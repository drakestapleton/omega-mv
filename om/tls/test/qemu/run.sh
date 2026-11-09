#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# The om/tls client inside a QEMU aarch64 guest, against a reference TLS 1.3 server (OpenSSL
# `s_server`) on the host. Ledger L233: "TLS handshake against a reference implementation in QEMU".
# usage: sh om/tls/test/qemu/run.sh OMC KERNEL
#   OMC    the seeded compiler (seed/out/omc; its sha256 is printed and checked against
#          seed/out/omc.sha256 when OMC is that file)
#   KERNEL an arm64 Linux image whose modules are installed under /lib/modules/KV on this host;
#          KV is taken from the file name (vmlinuz-KV) or from $KV. On the Spark:
#          apt-get download linux-image-$(uname -r) && dpkg-deb -x linux-image-*.deb img
#          (the image under /boot is root-only).
# Environment: ACCEL=tcg (default, -cpu max: every guest instruction is emulated) or ACCEL=kvm
#          (-cpu host -enable-kvm); TIMEOUT (seconds, default 600) bounds the guest run;
#          QEMU_CPUS (taskset list, default 0-19) pins QEMU and the servers.
# What runs where:
#   host   builds client.om (test/tls/client.om after every om/tls unit, om/tls/build.sh) and a
#          key-schedule mutant of it, makes a throwaway PKI with the openssl CLI, and starts one
#          `openssl s_server -www -naccept 1` per row on 127.0.0.1 only;
#   guest  QEMU virt (aarch64), the host's Ubuntu kernel, a busybox initramfs holding both
#          client binaries and the root certificate; virtio-net with QEMU user networking, so the
#          guest reaches the host loopback servers only through QEMU at 10.0.2.2. The guest sets its
#          clock from its own PL031 RTC (certificate validity is checked against it), prints the
#          sha256 of each binary it runs, then runs every row and powers off.
# A row passes when the outcome matches: OK rows need exit 0, the server's own `-www` status page
# (`HTTP/1.0 200 ok`, `New, TLSv1.3, Cipher is SUITE`, `Shared groups: GROUP`) decrypted by the
# client; the hrr row also needs two ClientHellos in the server's `-msg` log (a real
# HelloRetryRequest); refusal rows need the exact TLSERR line. The mutant row (label "c hs traffic"
# changed, so only the server can notice) must end with the server's bad_record_mac alert (20).
# Exit 0 only when every row passes,
# the guest ran the binaries the host built (sha256), on the given kernel, with its RTC clock and
# virtio-net address.
set -u
omc=${1:?usage: run.sh OMC KERNEL}; kernel=${2:?usage: run.sh OMC KERNEL}
here=$(cd "$(dirname "$0")" && pwd)
tls=$(cd "$here/../.." && pwd)
root=$(cd "$tls/../.." && pwd)
omc=$(cd "$(dirname "$omc")" && pwd)/$(basename "$omc")
kernel=$(cd "$(dirname "$kernel")" && pwd)/$(basename "$kernel")
[ -f "$kernel" ] || { echo "SETUP FAIL: no kernel $kernel"; exit 2; }
kv=${KV:-$(basename "$kernel" | sed -n 's/^vmlinuz-//p')}
mod=/lib/modules/$kv/kernel/drivers/rtc/rtc-pl031.ko.zst
[ -n "$kv" ] && [ -f "$mod" ] || { echo "SETUP FAIL: no $mod (set KV)"; exit 2; }
accel=${ACCEL:-tcg}
case $accel in
tcg) qaccel="-cpu max" ;;
kvm) qaccel="-cpu host -enable-kvm" ;;
*) echo "SETUP FAIL: ACCEL=$accel (tcg or kvm)"; exit 2 ;;
esac
cpus=${QEMU_CPUS:-0-19}
out="$root/build/tls/qemu"
rm -rf "$out"; mkdir -p "$out"; cd "$out" || exit 2
q() { "$@" > /dev/null 2>&1 || { echo "SETUP FAIL: $*"; exit 2; }; }
for t in openssl busybox zstd cpio gzip qemu-system-aarch64 ss; do command -v $t > /dev/null || { echo "SETUP FAIL: $t not found"; exit 2; }; done
bb=$(command -v busybox)
file -L "$bb" | grep -q 'statically linked' || { echo "SETUP FAIL: $bb is not static"; exit 2; }

omcsha=$(sha256sum "$omc" | cut -c1-64)
echo "omc $omcsha"
if [ "$omc" = "$root/seed/out/omc" ]; then
  [ "$omcsha" = "$(cut -c1-64 "$root/seed/out/omc.sha256")" ] || { echo "FAIL omc does not match seed/out/omc.sha256"; exit 1; }
fi
for u in sha2 hkdf drbg x25519 sha3 mlkem chacha aesgcm ec ecdh rsa x509 rev fips tls; do echo "$u.om $(sha256sum "$tls/$u.om" | cut -c1-64)"; done
echo "kernel $(sha256sum "$kernel" | cut -c1-64) KV $kv accel $accel"

# ---- the two clients: the real one and a key-schedule mutant (judged by the server alone) ----
sh "$tls/build.sh" "$omc" "$tls/test/tls/client.om" "$out/client" 2> build.err || { echo "FAIL build client: $(cat build.err)"; exit 1; }
mkdir mut
for u in sha2 hkdf drbg x25519 sha3 mlkem chacha aesgcm ec ecdh rsa x509 rev fips; do cp "$tls/$u.om" mut/; done
cp "$tls/build.sh" mut/
sed 's/^text TLLCHS "c hs traffic"/text TLLCHS "c hs traffie"/' "$tls/tls.om" > mut/tls.om
cmp -s mut/tls.om "$tls/tls.om" && { echo "FAIL mutant: the mutation did not apply"; exit 1; }
sh mut/build.sh "$omc" "$tls/test/tls/client.om" "$out/mclient" 2> build.err || { echo "FAIL build mutant: $(cat build.err)"; exit 1; }
csha=$(sha256sum client | cut -c1-64); msha=$(sha256sum mclient | cut -c1-64)
echo "client $csha"; echo "mclient $msha"

# ---- throwaway PKI: root -> intermediate -> P-256 and RSA leaves; an unrelated root ----
cat > ca.cnf <<'EOF'
[ca]
default_ca = d
[d]
database = index.txt
new_certs_dir = .
serial = serial
default_md = sha256
policy = p
copy_extensions = copy
unique_subject = no
[p]
commonName = supplied
[v3ca]
basicConstraints = critical,CA:true
keyUsage = critical,keyCertSign,cRLSign
[v3leaf]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = serverAuth
EOF
: > index.txt; echo 1000 > serial
ec() { q openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$1.key"; }
ec root
q openssl req -x509 -new -key root.key -subj /CN=omega-tls-qemu-root -days 30 -sha256 \
  -addext basicConstraints=critical,CA:true -addext keyUsage=critical,keyCertSign,cRLSign -out root.pem
ec int
q openssl req -new -key int.key -subj /CN=omega-tls-qemu-int -out int.csr
q openssl ca -batch -config ca.cnf -cert root.pem -keyfile root.key -extensions v3ca -days 30 -in int.csr -out int.pem -notext
leaf() { # NAME SAN: signed by the intermediate
  [ -f "$1.key" ] || ec "$1"
  q openssl req -new -key "$1.key" -subj "/CN=$1" -addext "subjectAltName=$2" -out "$1.csr"
  q openssl ca -batch -config ca.cnf -cert int.pem -keyfile int.key -extensions v3leaf -days 10 -in "$1.csr" -out "$1.pem" -notext
}
leaf good DNS:localhost
leaf wrongname DNS:other.example
q openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out rsa.key
leaf rsa DNS:localhost
ec other
q openssl req -x509 -new -key other.key -subj /CN=other-root -days 30 -addext basicConstraints=critical,CA:true -addext keyUsage=critical,keyCertSign -out other.pem
q openssl req -new -key good.key -subj /CN=localhost -addext subjectAltName=DNS:localhost -out stray.csr
q openssl x509 -req -in stray.csr -CA other.pem -CAkey other.key -CAcreateserial -days 10 -copy_extensions copy -out stray.pem
cp good.key stray.key

# ---- rows: NAME|BIN|OPTS|EXPECT|CERT|CHAIN|SERVER ARGS ----
# EXPECT: OK:SUITE:GROUP, or the client's exact TLSERR line
cat > rows <<'EOF'
mti-p256-aes128|client|0,0,0,0,1|OK:TLS_AES_128_GCM_SHA256:secp256r1|good|int.pem|-tls1_3 -groups P-256 -ciphersuites TLS_AES_128_GCM_SHA256
x25519-chacha|client|0|OK:TLS_CHACHA20_POLY1305_SHA256:x25519|good|int.pem|-tls1_3 -groups X25519 -ciphersuites TLS_CHACHA20_POLY1305_SHA256
rsa-pss-leaf|client|0|OK:TLS_AES_128_GCM_SHA256:x25519|rsa|int.pem|-tls1_3 -groups X25519 -ciphersuites TLS_AES_128_GCM_SHA256
hrr-x25519|client|0,0,0,0,2|OK:TLS_AES_128_GCM_SHA256:x25519|good|int.pem|-tls1_3 -groups X25519 -ciphersuites TLS_AES_128_GCM_SHA256 -msg
wrong-name|client|0|TLSERR TLS_ERR_CERTIFICATE detail 4 X509_ERR_NAME_MISMATCH|wrongname|int.pem|-tls1_3
unknown-issuer|client|0|TLSERR TLS_ERR_CERTIFICATE detail 5 X509_ERR_UNKNOWN_ISSUER|stray|-|-tls1_3
tls12-only|client|0|TLSERR TLS_ERR_ALERT_RECEIVED detail 70|good|int.pem|-tls1_2
mutant-c-hs-label|mclient|0|TLSERR TLS_ERR_ALERT_RECEIVED detail 20|good|int.pem|-tls1_3 -groups X25519 -ciphersuites TLS_AES_128_GCM_SHA256
EOF

nextport() { # a free 127.0.0.1 TCP port
  while :; do
    port=$((20000 + $(od -An -N2 -tu2 /dev/urandom | tr -d ' ') % 40000))
    ss -Hltn "sport = :$port" | grep -q . || return 0
  done
}
pids=
cleanup() { for p in $pids; do kill "$p" 2> /dev/null; done; }
trap cleanup EXIT INT TERM
: > cmds
while IFS='|' read -r name bin opts expect cert chain sargs; do
  if [ "$chain" = - ]; then ch=""; else ch="-cert_chain $chain"; fi
  n=0
  while :; do
    nextport
    # shellcheck disable=SC2086
    taskset -c "$cpus" openssl s_server -accept "127.0.0.1:$port" -naccept 1 -cert "$cert.pem" -key "$cert.key" $ch -www $sargs > "s-$name.log" 2>&1 &
    sp=$!
    i=0; while [ $i -lt 50 ] && ! ss -Hltnp "sport = :$port" | grep -q "pid=$sp,"; do kill -0 $sp 2> /dev/null || break; sleep 0.1; i=$((i + 1)); done
    ss -Hltnp "sport = :$port" | grep -q "pid=$sp," && break
    kill $sp 2> /dev/null; n=$((n + 1)); [ $n -lt 5 ] || { echo "SETUP FAIL: no port for $name"; exit 2; }
  done
  pids="$pids $sp"
  echo "$name|$bin|$port|$opts" >> cmds
done < rows

# ---- initramfs: static busybox, the PL031 RTC module, /init, both clients, the root cert ----
mkdir -p ir/bin ir/proc ir/sys ir/dev ir/tmp ir/lib
cp "$bb" ir/bin/busybox
for a in $("$bb" --list); do [ "$a" = busybox ] || ln -s busybox "ir/bin/$a"; done
zstd -q -d -c "$mod" > ir/lib/rtc-pl031.ko
cp client mclient ir/; cp root.pem cmds ir/
cat > ir/init <<'INIT'
#!/bin/sh
export PATH=/bin
mount -t proc proc /proc; mount -t sysfs sysfs /sys; mount -t devtmpfs devtmpfs /dev
echo "=== guest: $(uname -srm)"
echo "=== cpu: $(grep -m1 -E '^(CPU implementer|model name)' /proc/cpuinfo) $(grep -c ^processor /proc/cpuinfo) cpus"
insmod /lib/rtc-pl031.ko && hwclock -s -u && echo "=== clock from rtc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
nic=; for n in /sys/class/net/*; do [ "${n##*/}" = lo ] || { nic=${n##*/}; break; }; done
ip link set lo up; ip link set "$nic" up
ip addr add 10.0.2.15/24 dev "$nic"; ip route add default via 10.0.2.2
echo "=== net: $nic $(cat /sys/class/net/$nic/address) driver $(basename $(readlink /sys/class/net/$nic/device/driver)) $(ip -4 addr show $nic | sed -n 's/.*inet \([^ ]*\).*/\1/p')"
for b in client mclient; do echo "=== sha256 $(sha256sum /$b)"; done
while IFS='|' read -r name bin port opts; do
  echo "=== row $name"
  /$bin localhost "$port" get 10.0.2.2 /root.pem / "$opts" > /tmp/o 2> /tmp/e
  rc=$?
  grep -E '^HTTP/1.0 |^New, |^Shared groups: |^ *Protocol *: ' /tmp/o | sed 's/^/out: /'
  sed 's/^/err: /' /tmp/e
  echo "rc=$rc"
done < /cmds
echo "=== guest done"
poweroff -f
INIT
chmod +x ir/init
(cd ir && find . | cpio -o -H newc --quiet) | gzip -9 > initrd

# ---- boot ----
echo "### qemu-system-aarch64 $(qemu-system-aarch64 --version | head -n 1) accel $accel"
start=$(date +%s)
# shellcheck disable=SC2086
taskset -c "$cpus" timeout "${TIMEOUT:-600}" qemu-system-aarch64 -M virt $qaccel -smp 2 -m 1G \
  -nographic -no-reboot -kernel "$kernel" -initrd initrd -append 'console=ttyAMA0 rdinit=/init panic=-1 quiet' \
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0 > guest.log 2>&1
qrc=$?
echo "guest exit $qrc after $(($(date +%s) - start)) s (log $out/guest.log)"
tr -d '\r' < guest.log > g.log

# ---- judge ----
fail=0; rows=0; ok=0
grep -q '^=== guest done' g.log || { echo "FAIL guest did not finish"; fail=1; }
grep -q "^=== sha256 $csha  /client\$" g.log || { echo "FAIL guest client sha256 differs from the host build"; fail=1; }
grep -q "^=== sha256 $msha  /mclient\$" g.log || { echo "FAIL guest mclient sha256 differs from the host build"; fail=1; }
grep -q "^=== guest: Linux $kv aarch64" g.log || { echo "FAIL guest kernel is not $kv"; fail=1; }
grep -q '^=== clock from rtc: ' g.log || { echo "FAIL guest clock not set from its RTC"; fail=1; }
grep -q '^=== net: .* driver virtio_net 10.0.2.15/24' g.log || { echo "FAIL guest network is not virtio-net 10.0.2.15"; fail=1; }
sed -n '/^=== guest: /p;/^=== cpu: /p;/^=== clock /p;/^=== net: /p' g.log
while IFS='|' read -r name bin opts expect cert chain sargs; do
  rows=$((rows + 1))
  blk=$(sed -n "/^=== row $name\$/,/^rc=/p" g.log)
  rc=$(printf '%s\n' "$blk" | sed -n 's/^rc=//p')
  err=$(printf '%s\n' "$blk" | sed -n 's/^err: //p' | tr '\n' ' ' | sed 's/ $//')
  case $expect in
  OK:*)
    suite=$(echo "$expect" | cut -d: -f2); group=$(echo "$expect" | cut -d: -f3)
    if [ "$rc" = 0 ] && printf '%s\n' "$blk" | grep -q '^out: HTTP/1.0 200 ok$' \
      && printf '%s\n' "$blk" | grep -q "^out: New, TLSv1.3, Cipher is $suite\$" \
      && printf '%s\n' "$blk" | grep -q "^out: Shared groups: $group\$"; then got="OK $suite $group"; v=PASS
    else got="rc=$rc $err"; v=FAIL; fi
    case $name in hrr-*)
      h=$(grep -c 'Handshake .*, ClientHello$' "s-$name.log")
      [ "$h" = 2 ] && got="$got, server saw 2 ClientHellos (HRR)" || { got="$got, server saw $h ClientHellos, want 2"; v=FAIL; }
    esac ;;
  *)
    if [ -n "$rc" ] && [ "$rc" != 0 ] && [ "$err" = "$expect" ]; then got="$err (rc $rc)"; v=PASS
    else got="rc=$rc $err"; v=FAIL; fi ;;
  esac
  [ $v = PASS ] && ok=$((ok + 1)) || fail=1
  printf '%s %-18s expect %-52s got %s\n' "$v" "$name" "$expect" "$got"
done < rows
# stop any server whose row did not connect (-naccept 1 ends the others by themselves)
for p in $pids; do kill "$p" 2> /dev/null; done; wait 2> /dev/null; pids=
if [ $fail = 0 ]; then echo "TLS-QEMU PASS rows=$ok/$rows accel=$accel kernel=$kv client=$(echo "$csha" | cut -c1-16)"
else echo "TLS-QEMU FAIL rows=$ok/$rows accel=$accel"; fi
exit $fail
