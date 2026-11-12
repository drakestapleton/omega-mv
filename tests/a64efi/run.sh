#!/bin/sh
# tests/a64efi/run.sh [OMC]: the x86efi test programs (tests/x86efi) compiled for `target a64efi` with
# OMC (default seed/out/omc) and seed/a64efi/efirt.om, each booted as \EFI\BOOT\BOOTAA64.EFI on a fresh
# FAT disk under QEMU virt + EDK2. With KVM on an AArch64 host the CPU is the host's; elsewhere QEMU
# emulates one (-cpu max). Every check prints PASS, FAIL or NOT_RUN. Exit 1 on any FAIL; exit 77 when
# nothing could run (qemu-system-aarch64, the firmware or mtools absent); else 0. Each boot is stopped
# after EFI_TIMEOUT seconds (default 20): the application has returned by then and the firmware sits
# in its menu. A64EFI_CODE overrides the firmware path. Results are emulated, not hardware evidence.
# The sources are x86efi's with the first line changed and efirt.om placed after it: one set of test
# programs for both targets. file11 (efi 11) and the CPUID parts of ident are x86efi only.
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
X=$root/tests/x86efi
omc=${1:-$root/seed/out/omc}
case $omc in /*) ;; *) omc=$PWD/$omc ;; esac
wait=${EFI_TIMEOUT:-20}
work=$(mktemp -d "${TMPDIR:-/tmp}/a64efi.XXXXXX")
trap 'rm -rf "$work"' EXIT
pass=0 fail=0 notrun=0
ok() { pass=$((pass + 1)); echo "PASS $*"; }
bad() { fail=$((fail + 1)); echo "FAIL $*"; }
nr() { notrun=$((notrun + 1)); echo "NOT_RUN $*"; }

code=${A64EFI_CODE:-}
for f in /usr/share/qemu-efi-aarch64/QEMU_EFI.fd /usr/share/edk2/aarch64/QEMU_EFI.fd /usr/share/AAVMF/QEMU_EFI.fd; do
  [ -z "$code" ] && [ -f "$f" ] && code=$f
done
efi=yes why=
command -v qemu-system-aarch64 > /dev/null 2>&1 || { efi=no; why="qemu-system-aarch64 not found"; }
command -v mformat > /dev/null 2>&1 || { efi=no; why="mtools not found"; }
command -v timeout > /dev/null 2>&1 || { efi=no; why="timeout not found"; }
{ [ -n "$code" ] && [ -f "$code" ]; } || { efi=no; why="EDK2 AArch64 firmware not found (set A64EFI_CODE)"; }
accel="-cpu max"
[ "$(uname -m)" = aarch64 ] && [ -w /dev/kvm ] && accel="-cpu host -enable-kvm"

block() { tr -d '\r' < "$1" | sed 's/\x1b\[[0-9;?=]*[a-zA-Z]//g' | awk '/^==B$/ { on = 1; next } on && /^==/ { exit } on { print }'; }

# boot NAME SOURCE...: the sources concatenated, `target x86efi` on line 1 replaced by `target a64efi`
# and efirt.om inserted after it; leaves $work/NAME/{serial.log,disk.img}. $smb is the -smbios value.
smb=
boot() {
  name=$1; shift; d=$work/$name; mkdir -p "$d"
  cat "$@" > "$d/src.om"
  [ "$(sed -n 1p "$d/src.om")" = "target x86efi" ] || { bad "$name: first line is not target x86efi"; return 1; }
  { echo "target a64efi"; cat "$root/seed/a64efi/efirt.om"; sed 1d "$d/src.om"; } > "$d/app.om"
  if ! "$omc" < "$d/app.om" > "$d/app.efi" 2> "$d/omc.err"; then bad "$name: omc refused it: $(cat "$d/omc.err")"; return 1; fi
  dd if=/dev/zero of="$d/disk.img" bs=1048576 count=64 2> /dev/null
  mformat -i "$d/disk.img" -F :: && mmd -i "$d/disk.img" ::/EFI ::/EFI/BOOT && mcopy -i "$d/disk.img" "$d/app.efi" ::/EFI/BOOT/BOOTAA64.EFI
  # shellcheck disable=SC2086
  timeout -k 3 "$wait" qemu-system-aarch64 -M virt $accel -m 1024 -display none ${smb:+-smbios "$smb"} \
    -bios "$code" -drive if=none,id=d0,format=raw,file="$d/disk.img" -device virtio-blk-device,drive=d0 \
    -net none -serial file:"$d/serial.log" -monitor none -no-reboot < /dev/null > /dev/null 2>&1
  return 0
}
# trapped LOG: EDK2 reports the image's EFI_STATUS 2^63|103 (trap 3); the text is checked in `controls`.
trapped() { tr -d '\r' < "$1" | grep -q 'failed to start .*: 00000067\|Status = 8000000000000067\|8000000000000067'; }
diskfile() { mtype -i "$1" "::/$2" 2> /dev/null; }

# Compile-time refusals and the default target, no firmware needed. refuse NAME WANT SOURCE: omc must
# print exactly `omc: line L: error E` (WANT is "L E") and exit with status E.
refuse() {
  printf '%b' "$3" > "$work/r.om"
  got=$("$omc" < "$work/r.om" 2>&1 > /dev/null); rc=$?
  if [ $rc = "${2#* }" ] && [ "$got" = "omc: line ${2% *}: error ${2#* }" ]; then ok "refusal $1: $got"; else bad "refusal $1: exit $rc '$got', wanted line ${2% *} error ${2#* }"; fi
}
refuse "Linux host word" "3 25" 'target a64efi\nfn main to int\nx = getpid\nret 0\nend\n'
refuse "function mode" "1 25" 'target a64efi\nfn f a ulong to ulong\nret a\nend\n'
refuse "run-time pool" "2 25" 'target a64efi\nglobal p uchar *\nfn main to int\nret 0\nend\n'
refuse "efi without fn efirt" "4 16" 'target a64efi\nglobal b uchar 8\nfn main to int\nr = efi 13 0 b 0 1\nret 0\nend\n'
refuse "efi OP above 14" "7 25" 'target a64efi\nglobal b uchar 8\nfn efirt o ulong a ulong p ulong n ulong to ulong\nret 0\nend\nfn main to int\nr = efi 15 0 b 0 1\nret 0\nend\n'
refuse "unknown target" "1 25" 'target a64uefi\nfn main to int\nret 0\nend\n'
refuse "read" "4 25" 'target a64efi\nglobal b uchar 8\nfn main to int\nk = read 0 b 0 1\nret 0\nend\n'
refuse "write" "4 25" 'target a64efi\nglobal b uchar 8\nfn main to int\nk = write 1 b 0 1\nret 0\nend\n'
refuse "function named fwld" "2 16" 'target a64efi\nfn fwld to ulong\nret 7\nend\nfn main to int\nret 0\nend\n'
refuse "variable named fwld" "3 16" 'target a64efi\nfn main to int\nfwld = ulong 3\nret 0\nend\n'
refuse "global named efi" "2 16" 'target a64efi\nglobal efi uchar 8\nfn main to int\nret 0\nend\n'
refuse "parameter named fwadr" "2 16" 'target a64efi\nfn f fwadr ulong to ulong\nret 0\nend\nfn main to int\nret 0\nend\n'
refuse "efirt without parameters" "7 9" 'target a64efi\nglobal b uchar 8\nfn efirt to ulong\nret 0\nend\nfn main to int\nr = efi 13 0 b 0 1\nret 0\nend\n'
refuse "efirt giving int" "7 9" 'target a64efi\nglobal b uchar 8\nfn efirt o ulong a ulong p ulong n ulong to int\nret 0\nend\nfn main to int\nr = efi 13 0 b 0 1\nret 0\nend\n'
refuse "efirt with a uchar parameter" "7 9" 'target a64efi\nglobal b uchar 8\nfn efirt o ulong a uchar p ulong n ulong to ulong\nret 0\nend\nfn main to int\nr = efi 13 0 b 0 1\nret 0\nend\n'
refuse "efirt with an array parameter" "7 9" 'target a64efi\nglobal b uchar 8\nfn efirt o ulong a ulong p view uchar 8 n ulong to ulong\nret 0\nend\nfn main to int\nr = efi 13 0 b 0 1\nret 0\nend\n'
refuse "efiexit with parameters" "7 9" 'target a64efi\nfn efiexit a ulong b ulong to void\nend\nfn main to int\nret 0\nend\n'
refuse "efiexit giving a value" "8 9" 'target a64efi\nfn efiexit to ulong\nret 99\nend\nfn main to int\nret 0\nend\n'
# Without the target line the six words are ordinary names: a program may define fwld and a variable efi.
printf '%b' 'fn fwld a ulong b ulong to ulong\nefi = add a b\nret efi\nend\nfn main to int\nret int fwld 40 2\nend\n' > "$work/n.om"
if "$omc" < "$work/n.om" > "$work/n" 2> /dev/null && chmod +x "$work/n"; then
  if [ "$(uname -m)" = aarch64 ]; then "$work/n"; r=$?; [ $r = 42 ] && ok "default target: fwld and efi are ordinary names (exit 42)" || bad "default target: fwld program exit $r"
  else nr "default target fwld program: not an AArch64 host"; fi
else bad "default target: a program defining fwld was refused"; fi

[ $efi = yes ] || { nr "all: $why"; echo "SUMMARY pass=$pass fail=$fail not_run=$notrun"; exit 77; }

# float: the body of tests/x86efi/float gives the bit patterns of x86efi, x86linux and AArch64 Linux.
F=$X/float
if boot float "$F/efi-pre.om" "$F/body.om" "$F/fexplog.om" "$F/main-efi.om"; then
  block "$work/float/serial.log" | cmp -s - "$F/expected.txt" && ok "float a64efi: $(wc -l < "$F/expected.txt") lines match x86efi's expected.txt" || bad "float a64efi differs"
fi
# refusals: every efi 12 refusal code, then an OFF+N past the array traps 3.
if boot refusals "$X/refusals/g4.om"; then
  block "$work/refusals/serial.log" | cmp -s - "$X/refusals/expected.txt" && ok "refusals: $(wc -l < "$X/refusals/expected.txt") results match" || bad "refusals differ"
  trapped "$work/refusals/serial.log" && ok "refusals: OFF+N past the array ends in trap 3" || bad "refusals: no trap 3 status"
fi
# file: create, write, close, reopen, positioned write, read back.
if boot file "$X/file/t1.om"; then
  block "$work/file/serial.log" | cmp -s - "$X/file/expected.txt" && ok "file: round trip results match" || bad "file: results differ"
  [ "$(diskfile "$work/file/disk.img" T.TXT)" = abcd ] && ok "file: T.TXT on disk is abcd" || bad "file: T.TXT on disk is not abcd"
fi
# exit: a file left open is flushed and closed by return (e1) and by a trap (e2), through fn efiexit.
for e in e1 e2; do
  if boot "exit-$e" "$X/exit/$e.om"; then
    s=$work/exit-$e/serial.log got=$(diskfile "$work/exit-$e/disk.img" X.TXT)
    if [ "$got" = ABCDEFGHIJ ]; then ok "exit $e: X.TXT on disk is the 10 written bytes"; else bad "exit $e: X.TXT on disk is '$got'"; fi
    if [ ! -s "$s" ]; then bad "exit $e: no serial log"
    elif [ $e = e1 ]; then
      if trapped "$s"; then bad "exit e1: unexpected trap"; else ok "exit e1: returned without a trap"; fi
    elif trapped "$s"; then ok "exit e2: ended in trap 3"
    else bad "exit e2: no trap 3 status"; fi
  fi
done
# ident: efi 14 sub 3 reads the SMBIOS type 1 strings the firmware was given and never the serial or the
# UUID. The brand line (CPUID) is x86 only and is not compared. Negative control: another manufacturer.
I=$X/ident
smb=type=1,manufacturer=OmegaTest,product=IdentBox,version=7.1,serial=SECRET123,uuid=12345678-1234-1234-1234-123456789abc
if boot ident "$I/id.om"; then
  block "$work/ident/serial.log" | grep -qx 'sm=OmegaTest/IdentBox/7.1' && ok "ident: SMBIOS type 1 strings read (sm=OmegaTest/IdentBox/7.1)" || bad "ident: no line sm=OmegaTest/IdentBox/7.1"
  tr -d '\r' < "$work/ident/serial.log" | grep -q 'SECRET123\|12345678' && bad "ident: serial or UUID printed" || ok "ident: no serial or UUID in the output"
fi
smb=type=1,manufacturer=OtherMaker,product=IdentBox,version=7.1
if boot ident-neg "$I/id.om"; then
  block "$work/ident-neg/serial.log" | grep -qx 'sm=OtherMaker/IdentBox/7.1' && ok "ident negative control: OtherMaker is reported" || bad "ident negative control: OtherMaker not reported"
fi
smb=
nr "file11: efi 11 is x86efi only"
echo "SUMMARY pass=$pass fail=$fail not_run=$notrun"
[ $fail = 0 ]
