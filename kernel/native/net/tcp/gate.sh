#!/bin/sh
# gate.sh: L232 QEMU gate for the Omega TCP stack (verification rig, not product code).
# Usage: gate.sh OMC IMAGE BUSYBOX OUTDIR [PROFILES] [SCENARIOS]
#   OMC      pinned seeded omc (sha256 checked against omega-mv's seed/out/omc.sha256)
#   IMAGE    arm64 Linux Image for the guest (needs virtio-net, AF_PACKET)
#   BUSYBOX  static aarch64 busybox (guest init, sha256sum, and the g2h payload)
#   PROFILES default "clean loss reorder hostile"; SCENARIOS default "echo h2g g2h"
# Each run boots a fresh guest whose only TCP/IP stack is tcpd (tcp.om + tcpd.om),
# routes its NIC through link.om (seeded drop / reorder / duplicate / hostile
# injection) to QEMU slirp, and talks to peer.om on the host. Exit 0 only when
# every run passes every check. Requires qemu-system-aarch64 with KVM.
set -u
OMC=$1 IMAGE=$2 BUSYBOX=$3 OUT=$4
PROFILES=${5:-clean loss reorder hostile}
SCEN=${6:-echo h2g g2h}
HERE=$(cd "$(dirname "$0")" && pwd)
# The compiler pin is omega-mv's own (kernel/ is folded into omega-mv): seed/out/omc.sha256 at its root.
PINFILE=$HERE/../../../../seed/out/omc.sha256
PIN=$(cut -c1-64 "$PINFILE" 2>/dev/null)
printf '%s\n' "$PIN" | grep -qxE '[0-9a-f]{64}' || { echo "GATE_FAIL no sha256 in $PINFILE"; exit 2; }
mkdir -p "$OUT" || exit 2
OUT=$(cd "$OUT" && pwd)
have=$(sha256sum "$OMC" | cut -d' ' -f1)
if [ "$have" != "$PIN" ]; then echo "GATE_FAIL omc sha256 $have is not the pin $PIN"; exit 2; fi
B=$OUT/bin; mkdir -p "$B"
cat "$HERE/tcp.om" "$HERE/tcpd.om" | "$OMC" > "$B/tcpd" || { echo "GATE_FAIL build tcpd"; exit 2; }
"$OMC" < "$HERE/link.om" > "$B/link" || { echo "GATE_FAIL build link"; exit 2; }
"$OMC" < "$HERE/peer.om" > "$B/peer" || { echo "GATE_FAIL build peer"; exit 2; }
cat "$HERE/tcp.om" "$HERE/corpus.om" | "$OMC" > "$B/corpus" || { echo "GATE_FAIL build corpus"; exit 2; }
chmod +x "$B/tcpd" "$B/link" "$B/peer" "$B/corpus"
sha256sum "$OMC" "$IMAGE" "$BUSYBOX" "$B/tcpd" "$B/link" "$B/peer" "$B/corpus" > "$OUT/inputs.sha256"
# Hosted hostile corpus first: exact-state cases plus FUZZ seeded mutated frames.
FUZZ=${FUZZ:-2000000}
"$B/corpus" "$FUZZ" > "$OUT/corpus.log" 2>&1
CS=$?
if [ $CS -ne 0 ] || ! grep -q '^CORPUS_PASS' "$OUT/corpus.log"; then
  echo "CORPUS_FAIL rc=$CS $(head -3 "$OUT/corpus.log" | tr '\n' ' ')"; corpus_ok=0
else
  echo "CORPUS_OK $(grep '^CORPUS_PASS' "$OUT/corpus.log")"; corpus_ok=1
fi
qemu-system-aarch64 --version | head -1 >> "$OUT/inputs.sha256"
# Payloads: a fixed pseudo-random file (derived from the busybox bytes, so it is
# reproducible) for echo and host-to-guest, the busybox binary for guest-to-host.
P1=$OUT/payload1
{ cat "$BUSYBOX"; cat "$BUSYBOX"; } | gzip -9 -n | head -c 1048576 > "$P1"
cat "$P1" "$P1" | head -c 2000000 > "$OUT/payload2"
P2=$OUT/payload2
# Initramfs
R=$OUT/rd; rm -rf "$R"; mkdir -p "$R/bin" "$R/proc" "$R/sys" "$R/dev" "$R/tmp"
cp "$BUSYBOX" "$R/bin/busybox"; cp "$B/tcpd" "$R/tcpd"
cat > "$R/init" <<'EOF'
#!/bin/busybox sh
B=/bin/busybox
$B mount -t proc p /proc
$B mount -t sysfs s /sys
$B mount -t devtmpfs d /dev
A=$($B sed -n 's/.*tcpdargs=\([^ ]*\).*/\1/p' /proc/cmdline | $B tr , ' ')
/tcpd $A
echo "TCPD_EXIT=$?"
[ -f /tmp/rx ] && $B sha256sum /tmp/rx
# Give the serial console time to drain; poweroff -f can cut the last lines.
$B sleep 1
$B poweroff -f
EOF
chmod +x "$R/init"
(cd "$R" && find . | cpio -o -H newc 2>/dev/null | gzip -1 > "$OUT/rd.cpio.gz")
fails=0; runs=0; n=0
num() { v=$(grep -a "^$1 " "$2" | head -1 | cut -d' ' -f"$3"); echo "${v:-0}"; }
# Host ports sit below the Linux ephemeral range (32768-60999) so an unrelated
# outgoing connection cannot already hold one when slirp binds its forward.
PORTBASE=${PORTBASE:-21100}
for prof in $PROFILES; do
  case $prof in
    clean)   RATES="0 0 0 0" ;;
    loss)    RATES="30 0 0 0" ;;
    reorder) RATES="0 150 0 0" ;;
    hostile) RATES="20 100 20 200" ;;
    *) echo "GATE_FAIL unknown profile $prof"; exit 2 ;;
  esac
  for sc in $SCEN; do
    n=$((n + 1)); runs=$((runs + 1))
    HP=$((PORTBASE + n)); SEED=$((7919 * n + 17))
    D=$OUT/run-$prof-$sc; rm -rf "$D"; mkdir -p "$D"; : > "$D/console.log"
    T=$(mktemp -d /tmp/l232g.XXXXXX)
    case $sc in
      echo) ARGS="e,7,-,-,150"; FWD=",hostfwd=tcp:127.0.0.1:$HP-10.0.2.15:7"; WANT=$P1 ;;
      h2g)  ARGS="r,9,-,/tmp/rx,150"; FWD=",hostfwd=tcp:127.0.0.1:$HP-10.0.2.15:9"; WANT=$P2 ;;
      g2h)  ARGS="s,$HP,10.0.2.2,/bin/busybox,150"; FWD=""; WANT=$BUSYBOX ;;
    esac
    # link.om stops on its own when the guest goes quiet; timeout bounds it if traffic never stops.
    timeout 230 "$B/link" "$T/l1" "$T/g" "$T/l2" "$T/s" $SEED $RATES 8 > "$D/link.log" 2>&1 &
    LP=$!
    if [ "$sc" = g2h ]; then
      "$B/peer" r $HP "$WANT" 170 "$D/received" > "$D/peer.log" 2>&1 &
      PP=$!
    fi
    sleep 0.2
    timeout 200 qemu-system-aarch64 -M virt -accel kvm -cpu host -m 512 -smp 1 -nographic -no-reboot \
      -kernel "$IMAGE" -initrd "$OUT/rd.cpio.gz" \
      -append "console=ttyAMA0 quiet panic=-1 ipv6.disable=1 tcpdargs=$ARGS" \
      -netdev dgram,id=n0,local.type=unix,local.path=$T/g,remote.type=unix,remote.path=$T/l1 \
      -device virtio-net-pci,netdev=n0,romfile= \
      -netdev dgram,id=d1,local.type=unix,local.path=$T/s,remote.type=unix,remote.path=$T/l2 \
      -netdev user,id=u0$FWD \
      -netdev hubport,id=hp0,hubid=1,netdev=u0 -netdev hubport,id=hp1,hubid=1,netdev=d1 \
      > "$D/console.log" 2>&1 &
    QP=$!
    if [ "$sc" != g2h ]; then
      i=0; while [ $i -lt 300 ] && ! grep -aq TCPD_READY "$D/console.log"; do sleep 0.1; i=$((i + 1)); done
      MODE=e; [ "$sc" = h2g ] && MODE=s
      "$B/peer" $MODE $HP "$WANT" 170 > "$D/peer.log" 2>&1
      PS=$?
    else
      wait $PP; PS=$?
    fi
    wait $QP; QS=$?
    wait $LP; LS=$?
    rm -rf "$T"
    ok=1; why=""
    [ $PS -eq 0 ] && grep -aq '^PEER_PASS' "$D/peer.log" || { ok=0; why="$why peer"; }
    grep -aq '^TCPD_PASS' "$D/console.log" && grep -aq 'TCPD_EXIT=0' "$D/console.log" || { ok=0; why="$why tcpd"; }
    [ $LS -eq 0 ] || { ok=0; why="$why link"; }
    [ $QS -eq 0 ] || { ok=0; why="$why qemu"; }
    want=$(sha256sum "$WANT" | cut -d' ' -f1)
    # Echo bytes are compared one by one by peer.om; the two transfers are compared by digest.
    case $sc in
      h2g) got=$(grep -a ' /tmp/rx' "$D/console.log" | cut -d' ' -f1) ;;
      g2h) got=$(sha256sum "$D/received" | cut -d' ' -f1) ;;
      echo) got=peer-compared ;;
    esac
    [ "$sc" = echo ] || [ "$got" = "$want" ] || { ok=0; why="$why digest"; }
    # The profile must really have impaired this run (LINK fields: 2 in 3 out 4 drop 5 held 6 dup, +8 for B to A; 18 hostile).
    drop=$(( $(num LINK "$D/link.log" 4) + $(num LINK "$D/link.log" 12) ))
    held=$(( $(num LINK "$D/link.log" 5) + $(num LINK "$D/link.log" 13) ))
    dup=$(( $(num LINK "$D/link.log" 6) + $(num LINK "$D/link.log" 14) ))
    host=$(num LINK "$D/link.log" 18)
    set -- $RATES
    [ "$1" -eq 0 ] || [ $drop -gt 0 ] || { ok=0; why="$why nodrop"; }
    [ "$2" -eq 0 ] || [ $held -gt 0 ] || { ok=0; why="$why noreorder"; }
    [ "$3" -eq 0 ] || [ $dup -gt 0 ] || { ok=0; why="$why nodup"; }
    [ "$4" -eq 0 ] || [ $host -gt 0 ] || { ok=0; why="$why nohostile"; }
    # Every one of the 15 hostile kinds (LINKH fields 2..16) must have been injected.
    kinds=0; k=2; while [ $k -le 16 ]; do [ $(num LINKH "$D/link.log" $k) -gt 0 ] && kinds=$((kinds + 1)); k=$((k + 1)); done
    [ "$4" -eq 0 ] || [ $kinds -eq 15 ] || { ok=0; why="$why kinds=$kinds"; }
    [ "$1$2$3$4" != 0000 ] || [ $((drop + held + dup + host)) -eq 0 ] || { ok=0; why="$why notclean"; }
    line="$prof $sc sha=$got drop=$drop held=$held dup=$dup hostile=$host qemu=$QS $(grep -a '^TCPD_PASS\|^TCPD_FAIL' "$D/console.log" | head -1)"
    if [ $ok -eq 1 ]; then echo "RUN_PASS $line"; else echo "RUN_FAIL$why $line"; fails=$((fails + 1)); fi
  done
done
if [ $fails -eq 0 ] && [ $corpus_ok -eq 1 ]; then echo "GATE_PASS runs=$runs corpus=pass"; exit 0; fi
echo "GATE_FAIL failed=$fails runs=$runs corpus_ok=$corpus_ok"; exit 1
