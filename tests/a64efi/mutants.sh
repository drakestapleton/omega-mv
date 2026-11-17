#!/bin/sh
# tests/a64efi/mutants.sh [OMC]: negative controls for tests/a64efi/run.sh. Each mutant changes one
# line of a copy of seed/omc/omc.om, is compiled by OMC (default seed/out/omc) into a mutant compiler
# under a temporary directory, and must make the named group of run.sh fail at the named check.
# PASS: the mutant is killed there. FAIL: it survives, was killed elsewhere, or the edit did not
# apply to exactly one line. Exit 1 on any FAIL; 77 when run.sh cannot boot (NOT_RUN); else 0.
# Nothing under seed/ is written. Results are emulated, not hardware evidence.
# No em dash or en dash is used in this file.
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
omc=${1:-$root/seed/out/omc}
case $omc in /*) ;; *) omc=$PWD/$omc ;; esac
src=$root/seed/omc/omc.om
work=$(mktemp -d "${TMPDIR:-/tmp}/a64mut.XXXXXX")
trap 'rm -rf "$work"' EXIT
pass=0 fail=0 notrun=0

# mutant NAME GROUP 'FAIL line prefix' AWK-PROGRAM: the awk program rewrites the source.
mutant() {
  name=$1 group=$2 expect=$3 prog=$4
  awk "$prog" "$src" > "$work/$name.om"
  n=$(diff "$src" "$work/$name.om" | grep -c '^>')
  if [ "$n" != 1 ]; then fail=$((fail + 1)); echo "FAIL mutant $name: the edit changed $n lines, wanted 1"; return; fi
  if ! "$omc" < "$work/$name.om" > "$work/$name.omc" 2> "$work/$name.err"; then
    fail=$((fail + 1)); echo "FAIL mutant $name: the mutant compiler did not build: $(cat "$work/$name.err")"; return
  fi
  chmod +x "$work/$name.omc"
  A64EFI_ONLY=$group sh "$here/run.sh" "$work/$name.omc" > "$work/$name.log" 2>&1; rc=$?
  if [ $rc = 77 ]; then notrun=$((notrun + 1)); echo "NOT_RUN mutant $name: $(grep '^NOT_RUN' "$work/$name.log" | head -n 1)"; return; fi
  if [ $rc = 1 ] && grep -q "^FAIL $expect" "$work/$name.log"; then
    pass=$((pass + 1)); echo "PASS mutant $name: killed: $(grep "^FAIL $expect" "$work/$name.log" | head -n 1)"
  else
    fail=$((fail + 1)); echo "FAIL mutant $name: run.sh exit $rc without 'FAIL $expect'"; sed 's/^/    /' "$work/$name.log"
  fi
}

# trapbit: the trap stub leaves bit 63 clear (NOP for ORR X0, X0, #2^63): a trap returns a warning status.
mutant trapbit exit 'exit trap3: trap 3' \
  'p == 1 { print "emit 3573751839"; p = 0; next } /^note a64efi: ORR X0, X0, #0x8000000000000000/ { p = 1 } { print }'
# adrp0: a text address is taken with a page distance of 0: right only on the 4 KiB page of the text itself.
mutant adrp0 addr 'addr a1: texts' \
  '$0 == "d = and sub add shr t 12 2097152 shr get oc 0 12 2097151" { print "d = ulong 0"; next } { print }'
# mem4: efi 20 / 21 with N 4 goes a byte at a time (NOP for the B.EQ to the 32-bit access).
mutant mem4 pl011 'pl011: UARTDR' \
  '$0 == "emit 1409286880" { print "emit 3573751839"; next } { print }'
# nocr: efi 13 never inserts CR before LF (B for the B.NE that skips the CR).
mutant nocr con 'con: [0-9]* lines without CR' \
  '$0 == "emit 1409286273" { print "emit 335544324"; next } { print }'

echo "SUMMARY mutants killed=$pass failed=$fail not_run=$notrun"
[ $fail = 0 ] || exit 1
[ $notrun = 0 ] || exit 77
exit 0
