#!/bin/sh
# tests/x86efi/run.sh [OMC]: compile the x86efi tests with OMC (default seed/out/omc) and run each
# image as \EFI\BOOT\BOOTX64.EFI on a fresh FAT disk under QEMU q35 + OVMF, serial console to a file.
# Every check prints PASS, FAIL or NOT_RUN. Exit 1 on any FAIL; exit 77 when nothing could run
# (qemu-system-x86_64, OVMF or mtools absent); else 0. Each QEMU boot is stopped after
# EFI_TIMEOUT seconds (default 60): the application has returned by then and OVMF sits in its menu.
# OVMF_CODE / OVMF_VARS override the firmware paths. Results are emulated, not hardware evidence.
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
omc=${1:-$root/seed/out/omc}
case $omc in /*) ;; *) omc=$PWD/$omc ;; esac
wait=${EFI_TIMEOUT:-60}
work=$(mktemp -d "${TMPDIR:-/tmp}/x86efi.XXXXXX")
trap 'rm -rf "$work"' EXIT
pass=0 fail=0 notrun=0
ok() { pass=$((pass + 1)); echo "PASS $*"; }
bad() { fail=$((fail + 1)); echo "FAIL $*"; }
nr() { notrun=$((notrun + 1)); echo "NOT_RUN $*"; }

code=${OVMF_CODE:-} vars=${OVMF_VARS:-}
for d in /usr/share/OVMF /usr/share/edk2/ovmf /usr/share/qemu; do
  [ -z "$code" ] && [ -f "$d/OVMF_CODE_4M.fd" ] && code=$d/OVMF_CODE_4M.fd && vars=$d/OVMF_VARS_4M.fd
  [ -z "$code" ] && [ -f "$d/OVMF_CODE.fd" ] && code=$d/OVMF_CODE.fd && vars=$d/OVMF_VARS.fd
done
efi=yes
command -v qemu-system-x86_64 > /dev/null 2>&1 || { efi=no; why="qemu-system-x86_64 not found"; }
command -v mformat > /dev/null 2>&1 || { efi=no; why="mtools not found"; }
command -v timeout > /dev/null 2>&1 || { efi=no; why="timeout not found"; }
{ [ -n "$code" ] && [ -f "$code" ] && [ -f "$vars" ]; } || { efi=no; why="OVMF firmware not found (set OVMF_CODE and OVMF_VARS)"; }

# block FILE: the lines after the first "==B" up to the next line starting with "==".
block() { tr -d '\r' < "$1" | awk '/^==B$/ { on = 1; next } on && /^==/ { exit } on { print }'; }

# boot NAME SOURCE...: compile the concatenated sources, boot the image; leaves $work/NAME/{serial.log,disk.img}.
boot() {
  name=$1; shift; d=$work/$name; mkdir -p "$d"
  cat "$@" > "$d/app.om"
  if ! "$omc" < "$d/app.om" > "$d/app.efi" 2> "$d/omc.err"; then bad "$name: omc refused it: $(cat "$d/omc.err")"; return 1; fi
  cp "$vars" "$d/vars.fd"
  dd if=/dev/zero of="$d/disk.img" bs=1048576 count=16 2> /dev/null
  mformat -i "$d/disk.img" :: && mmd -i "$d/disk.img" ::/EFI ::/EFI/BOOT && mcopy -i "$d/disk.img" "$d/app.efi" ::/EFI/BOOT/BOOTX64.EFI
  timeout "$wait" qemu-system-x86_64 -machine q35 -cpu max -m 512 -display none \
    -drive if=pflash,format=raw,readonly=on,file="$code" -drive if=pflash,format=raw,file="$d/vars.fd" \
    -device qemu-xhci,id=xhci -drive if=none,id=stick,format=raw,file="$d/disk.img" \
    -device usb-storage,bus=xhci.0,drive=stick -net none -serial file:"$d/serial.log" -no-reboot
  return 0
}
# trapped LOG: OVMF reports the image's EFI_STATUS 2^63|103 (trap 3) as "...: 00000067".
trapped() { tr -d '\r' < "$1" | grep -q 'failed to start .*: 00000067'; }
diskfile() { mtype -i "$1" "::/$2" 2> /dev/null; }

F=$here/float
# float: the same body gives the same bit patterns as x86efi, x86linux and AArch64.
if [ $efi = yes ]; then
  if boot float "$F/efi-pre.om" "$F/body.om" "$F/fexplog.om" "$F/main-efi.om"; then
    block "$work/float/serial.log" | cmp -s - "$F/expected.txt" && ok "float x86efi: $(wc -l < "$F/expected.txt") lines match" || bad "float x86efi differs"
  fi
else nr "float x86efi: $why"; fi
host() { # host LABEL PRE RUNNER...
  label=$1 pre=$2; shift 2; d=$work/$label; mkdir -p "$d"
  cat "$pre" "$F/body.om" "$F/fexplog.om" "$F/main-lin.om" > "$d/app.om"
  if ! "$omc" < "$d/app.om" > "$d/app" 2> "$d/omc.err"; then bad "$label: omc refused it"; return; fi
  chmod +x "$d/app"; "$@" "$d/app" > "$d/out.txt"
  printf '==E\n' >> "$d/out.txt"
  block "$d/out.txt" | cmp -s - "$F/expected.txt" && ok "$label: same lines as x86efi" || bad "$label differs"
}
case $(uname -m) in
  x86_64) host "float x86linux" "$F/lin-pre.om" env ;;
  *) if command -v qemu-x86_64 > /dev/null 2>&1; then host "float x86linux (qemu-x86_64)" "$F/lin-pre.om" qemu-x86_64
     else nr "float x86linux: not x86_64 and qemu-x86_64 not found"; fi ;;
esac
if [ "$(uname -m)" = aarch64 ]; then host "float aarch64" "$F/a64-pre.om" env; else nr "float aarch64: not an AArch64 host"; fi

[ $efi = yes ] || { nr "refusals, file, exit: $why"; echo "SUMMARY pass=$pass fail=$fail not_run=$notrun"; [ $fail = 0 ] || exit 1; [ $pass = 0 ] && exit 77; exit 0; }

# refusals: every efi 12 refusal code, then an OFF+N past the array traps 3.
if boot refusals "$here/refusals/g4.om"; then
  block "$work/refusals/serial.log" | cmp -s - "$here/refusals/expected.txt" && ok "refusals: $(wc -l < "$here/refusals/expected.txt") results match" || bad "refusals differ"
  trapped "$work/refusals/serial.log" && ok "refusals: OFF+N past the array ends in trap 3" || bad "refusals: no trap 3 status"
fi
# file: create, write, close, reopen, positioned write, read back.
if boot file "$here/file/t1.om"; then
  block "$work/file/serial.log" | cmp -s - "$here/file/expected.txt" && ok "file: round trip results match" || bad "file: results differ"
  [ "$(diskfile "$work/file/disk.img" T.TXT)" = abcd ] && ok "file: T.TXT on disk is abcd" || bad "file: T.TXT on disk is not abcd"
fi
# exit: a file left open is flushed and closed by return (e1) and by a trap (e2). The status check
# runs only for an image that booted, wrote a serial log and left the expected file on disk.
for e in e1 e2; do
  if boot "exit-$e" "$here/exit/$e.om"; then
    s=$work/exit-$e/serial.log got=$(diskfile "$work/exit-$e/disk.img" X.TXT)
    if [ "$got" = ABCDEFGHIJ ]; then ok "exit $e: X.TXT on disk is the 10 written bytes"; else bad "exit $e: X.TXT on disk is '$got'"; fi
    if [ ! -s "$s" ]; then bad "exit $e: no serial log at $s"
    elif [ "$got" != ABCDEFGHIJ ]; then bad "exit $e: status not checked, the disk check failed"
    elif [ $e = e1 ]; then
      if trapped "$s"; then bad "exit e1: unexpected trap"; else ok "exit e1: returned without a trap"; fi
    elif trapped "$s"; then ok "exit e2: ended in trap 3"
    else bad "exit e2: no trap 3 status"; fi
  fi
done
echo "SUMMARY pass=$pass fail=$fail not_run=$notrun"
[ $fail = 0 ]
