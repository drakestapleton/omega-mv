#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# tools/spark-boot/tests/test_stage_bootnext.sh: offline safety tests for stage_bootnext.sh.
# Every external effect is stubbed on PATH (ssh, scp, sudo, efibootmgr, findmnt, df); the stub ssh only
# accepts the fake host "stub-spark-not-real" and runs the "remote" script locally against a temp fake
# /boot/efi. Nothing here can reach a Spark, an ESP or NVRAM.
#   STAGE_SCRIPT=/path/to/stage_bootnext.sh overrides the script under test.
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
STAGE="${STAGE_SCRIPT:-$HERE/../stage_bootnext.sh}"
T=$(mktemp -d "${TMPDIR:-/tmp}/stage-bootnext-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
B="$T/bin"
mkdir -p "$B" "$T/root/boot/efi/EFI/ubuntu"
: > "$T/root/boot/efi/EFI/ubuntu/shimaa64.efi"
HOST=stub-spark-not-real

cat > "$B/ssh" <<'S'
#!/bin/sh
while [ $# -gt 0 ]; do
  case "$1" in -o) shift 2 ;; -*) shift ;; *) break ;; esac
done
host=$1; shift
[ "$host" = "stub-spark-not-real" ] || { echo "stub ssh: refusing real host '$host'" >&2; exit 97; }
echo "ssh $*" >> "$STUB_LOG"
cmd="$*"
sed "s#/boot/efi#$STUB_ROOT/boot/efi#g" | sh -c "$cmd"
S
cat > "$B/scp" <<'S'
#!/bin/sh
for a in "$@"; do src=$dst; dst=$a; done
case "$dst" in stub-spark-not-real:*) ;; *) echo "stub scp: refusing '$dst'" >&2; exit 97 ;; esac
echo "scp $src $dst" >> "$STUB_LOG"
cp "$src" "${dst#stub-spark-not-real:}"
S
cat > "$B/sudo" <<'S'
#!/bin/sh
echo "sudo $*" >> "$STUB_LOG"
[ "${1:-}" = "-n" ] && shift
case "$*" in *"/proc/"*) exit 0 ;; esac
exec "$@"
S
cat > "$B/efibootmgr" <<'S'
#!/bin/sh
ORDER=0001,0000; NEXT=; HAS=0
[ -f "$STUB_ROOT/efi.state" ] && . "$STUB_ROOT/efi.state"
echo "efibootmgr $*" >> "$STUB_LOG"
case "${1:-}" in
  --create-only) HAS=1 ;;
  --bootnext) NEXT=$2; [ "${STUB_MUTATE_ORDER:-0}" = 1 ] && ORDER="0002,$ORDER" ;;
  -N) [ "${STUB_FAIL_CLEAR:-0}" = 1 ] && { echo "stub: -N refused" >&2; exit 1; }; NEXT= ;;
  -o) ORDER=$2 ;;
esac
printf 'ORDER=%s\nNEXT=%s\nHAS=%s\n' "$ORDER" "$NEXT" "$HAS" > "$STUB_ROOT/efi.state"
case "${1:-}" in
  -v|"")
    printf '%s\n' "BootCurrent: 0001"
    [ -n "$NEXT" ] && printf 'BootNext: %s\n' "$NEXT"
    printf 'BootOrder: %s\n' "$ORDER"
    printf '%s\n' 'Boot0000* UEFI PXE	PciRoot(0x0)/Pci(0x1,0x0)'
    printf '%s\n' 'Boot0001* ubuntu	HD(1,GPT,0,0x800,0x100000)/File(\EFI\ubuntu\shimaa64.efi)'
    [ "$HAS" = 1 ] && printf '%s\n' 'Boot0002* AIENOS Spark	HD(1,GPT,0,0x800,0x100000)/File(\EFI\AIENOS\SPARK.EFI)'
    ;;
esac
exit 0
S
cat > "$B/findmnt" <<'S'
#!/bin/sh
case "$*" in *SOURCE*) echo /dev/nvme0n1p1 ;; *FSTYPE*) echo vfat ;; esac
S
cat > "$B/df" <<'S'
#!/bin/sh
echo "Filesystem 1B-blocks Used Available Use% Mounted on"
echo "/dev/nvme0n1p1 536870912 1048576 ${STUB_ESP_AVAIL} 1% /boot/efi"
S
if ! command -v sha256sum >/dev/null 2>&1; then
  printf '#!/bin/sh\nexec shasum -a 256 "$@"\n' > "$B/sha256sum"
fi
chmod +x "$B"/*

python3 - "$T/SPARK.EFI" <<'PY'
import struct, sys
d = bytearray(4096)
d[0:2] = b"MZ"; struct.pack_into("<I", d, 60, 64)
d[64:68] = b"PE\0\0"; struct.pack_into("<H", d, 68, 0xAA64)
struct.pack_into("<H", d, 88, 0x20B); struct.pack_into("<I", d, 144, 8192); struct.pack_into("<H", d, 156, 10)
open(sys.argv[1], "wb").write(d)
PY

export STUB_ROOT="$T/root" STUB_LOG="$T/log"
fails=0
run() { # name expect_exit esp_avail mutate args...
  name=$1; want=$2; esp=$3; mut=$4; shift 4
  rm -f "$STUB_ROOT/efi.state"; : > "$STUB_LOG"
  set +e
  PATH="$B:$PATH" STUB_ESP_AVAIL="$esp" STUB_MUTATE_ORDER="$mut" \
    sh "$STAGE" --spark-efi "$T/SPARK.EFI" --spark-host "$HOST" "$@" > "$T/out" 2>&1 </dev/null
  got=$?
  set -e
  if [ "$got" -ne "$want" ]; then
    echo "FAIL $name: exit $got (want $want)"; sed 's/^/    /' "$T/out"; fails=$((fails + 1)); return 1
  fi
  return 0
}
ok() { echo "PASS $1"; }
bad() { echo "FAIL $1: $2"; sed 's/^/    /' "$T/out"; fails=$((fails + 1)); }

if run t1_dryrun_no_sudo 0 536870912 0; then
  if grep -q '^sudo' "$STUB_LOG"; then bad t1_dryrun_no_sudo "dry-run invoked sudo"
  elif grep -q 'efibootmgr --bootnext\|efibootmgr -o\|efibootmgr --create-only' "$STUB_LOG"; then bad t1_dryrun_no_sudo "dry-run wrote NVRAM"
  elif ! grep -q 'DRY-RUN: zero changes' "$T/out"; then bad t1_dryrun_no_sudo "missing dry-run banner"
  else ok t1_dryrun_no_sudo; fi
fi
for v in 12abc - ' ' 1e9 0x4000000; do
  if run "t2_esp_avail_non_numeric($v)" 1 "$v" 0; then
    if grep -q 'not a number' "$T/out"; then ok "t2_esp_avail_non_numeric($v)"; else bad "t2_esp_avail_non_numeric($v)" "wrong refusal"; fi
  fi
done
if run t3_esp_avail_small 1 1048576 0; then
  if grep -q 'insufficient' "$T/out"; then ok t3_esp_avail_small; else bad t3_esp_avail_small "wrong refusal"; fi
fi
if run t4_apply_bootnext_only 0 536870912 0 --apply --i-am-at-the-console; then
  if grep -q 'efibootmgr -o' "$STUB_LOG"; then bad t4_apply_bootnext_only "BootOrder rewritten"
  elif ! grep -q 'efibootmgr --bootnext 0002' "$STUB_LOG"; then bad t4_apply_bootnext_only "BootNext not set"
  elif ! grep -q '^ORDER=0001,0000$' "$STUB_ROOT/efi.state"; then bad t4_apply_bootnext_only "BootOrder changed"
  elif [ ! -f "$STUB_ROOT/boot/efi/EFI/AIENOS/SPARK.EFI" ]; then bad t4_apply_bootnext_only "image not staged"
  else ok t4_apply_bootnext_only; fi
fi
if run t5_apply_order_changed_no_rewrite 1 536870912 1 --apply --i-am-at-the-console; then
  if grep -q 'efibootmgr -o' "$STUB_LOG"; then bad t5_apply_order_changed_no_rewrite "restore rewrote BootOrder"
  elif ! grep -q 'efibootmgr -N' "$STUB_LOG"; then bad t5_apply_order_changed_no_rewrite "BootNext not cleared"
  elif ! grep -q '^NEXT=$' "$STUB_ROOT/efi.state"; then bad t5_apply_order_changed_no_rewrite "BootNext still set"
  elif ! grep -q 'BootOrder was NOT rewritten' "$T/out"; then bad t5_apply_order_changed_no_rewrite "missing operator notice"
  elif ! grep -q 'BootNext cleared (efibootmgr -N succeeded)' "$T/out"; then bad t5_apply_order_changed_no_rewrite "clear result not reported"
  else ok t5_apply_order_changed_no_rewrite; fi
fi
if STUB_FAIL_CLEAR=1 run t7_apply_clear_failure_reported 1 536870912 1 --apply --i-am-at-the-console; then
  if grep -q 'efibootmgr -o' "$STUB_LOG"; then bad t7_apply_clear_failure_reported "BootOrder rewritten"
  elif grep -q 'BootNext cleared' "$T/out"; then bad t7_apply_clear_failure_reported "claimed a clear that failed"
  elif ! grep -q 'BootNext clear FAILED' "$T/out"; then bad t7_apply_clear_failure_reported "failure not reported"
  else ok t7_apply_clear_failure_reported; fi
fi
unset STUB_FAIL_CLEAR # POSIX sh may keep a prefix assignment on a function call
if run t6_apply_requires_console 2 536870912 0 --apply; then
  if [ -s "$STUB_LOG" ]; then bad t6_apply_requires_console "touched stubs"; else ok t6_apply_requires_console; fi
fi
if [ "$fails" -ne 0 ]; then echo "STAGE_BOOTNEXT_TEST_FAIL failed=$fails"; exit 1; fi
echo "STAGE_BOOTNEXT_TEST_PASS total=11 failed=0"
