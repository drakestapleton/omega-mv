#!/bin/sh
# tests/x86efi/machine/mutants.sh [OMC]: negative controls for efi 15..21. Each mutant is seed/omc/omc.om
# with one emitter line of xmach changed (sed, checked to change exactly one line), compiled by OMC
# (default seed/out/omc) into a compiler of its own under a temporary directory; nothing in seed/ is
# written. The machine section of ../run.sh must FAIL with every mutant compiler and PASS with OMC itself.
# Prints PASS, FAIL or NOT_RUN per case; exit 1 on any FAIL, 77 when QEMU, OVMF or mtools are absent.
# Each case boots QEMU once for EFI_TIMEOUT seconds (default 60). Emulated, not hardware evidence.
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
omc=${1:-$root/seed/out/omc}
case $omc in /*) ;; *) omc=$PWD/$omc ;; esac
src=$root/seed/omc/omc.om
work=$(mktemp -d "${TMPDIR:-/tmp}/x86efi-mut.XXXXXX")
trap 'rm -rf "$work"' EXIT
pass=0 fail=0
ok() { pass=$((pass + 1)); echo "PASS $*"; }
bad() { fail=$((fail + 1)); echo "FAIL $*"; }

# The mutant compiler runs on this host: x86-64 needs the target line, AArch64 is omc's default output.
pre=; [ "$(uname -m)" = x86_64 ] && pre='target x86linux'
# run COMPILER LOG: the machine section only; its status is the function's status.
run() { X86EFI_ONLY=machine sh "$here/../run.sh" "$1" > "$2" 2>&1; }

run "$omc" "$work/base.log"; rc=$?
if [ $rc = 77 ] || grep -q '^NOT_RUN' "$work/base.log"; then
  echo "NOT_RUN machine mutants: $(grep '^NOT_RUN' "$work/base.log" | head -n 1)"; exit 77
fi
if [ $rc = 0 ]; then ok "control: the machine section passes with the unchanged compiler ($(tail -n 1 "$work/base.log"))"
else bad "control: the machine section fails with the unchanged compiler"; cat "$work/base.log"; fi

# mutant NAME WHAT SED-SCRIPT: WHAT says which check should notice.
mutant() {
  name=$1 what=$2 script=$3 m=$work/$name.om
  sed "$script" "$src" > "$m"
  n=$(diff "$src" "$m" | grep -c '^[<>]')
  if [ "$n" != 2 ]; then bad "mutant $name: sed changed $((n / 2)) lines of omc.om, want exactly one"; return; fi
  if ! { [ -n "$pre" ] && echo "$pre"; cat "$m"; } | "$omc" > "$work/$name.omc" 2> "$work/$name.err"; then
    bad "mutant $name: did not compile: $(cat "$work/$name.err")"; return
  fi
  chmod +x "$work/$name.omc"
  if run "$work/$name.omc" "$work/$name.log"; then bad "mutant $name survived ($what)"
  else ok "mutant $name killed ($what): $(tail -n 1 "$work/$name.log")"; grep '^FAIL\|^  [<>]' "$work/$name.log" | sed 's/^/    /'; fi
}

# X: the lines of xmach, from its note to its last line (the MOVSB opcode byte).
X='/^note efi 15\.\.21 machine access/,/^emitb 164$/'
mutant m-in 'efi 16 emits IN where OUT belongs: nothing reaches COM1' \
  "${X}s/^io = add 236 mul sub op 15 2\$/io = ulong 236/"
mutant m-w16 'no 0x66 prefix, a 16-bit port access is 32 bits wide' \
  "${X}s/^emitb 102\$/emitb 144/"
mutant m-msrhi 'RDMSR drops EDX, the high half of the value' \
  "${X}s/^xrr 9 0 2\$/xrr 137 2 2/"
mutant m-cr0 'every control register read is CR0' \
  "${X}s/^xb 15 32 add 194 mul n 8\$/xb 15 32 194/"
mutant m-dir 'efi 21 copies in the direction of efi 20' \
  "${X}s/^if eq op 21\$/if eq op 22/"
mutant m-movsb 'N = 4 and 8 go through REP MOVSB: a device register needs one 32-bit read' \
  "${X}s/^while le s 8\$/while le s 2/"
mutant m-nochk 'efi 15 and 16 skip the width check, a refused write goes out' \
  "${X}s/^xer 0 8 45\$/xrr 133 1 1/"

echo "SUMMARY pass=$pass fail=$fail"
[ $fail = 0 ]
