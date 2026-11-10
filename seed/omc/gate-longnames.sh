#!/bin/sh
# gate-longnames.sh -- names of up to 63 bytes (docs/one_layer/OMEGESE.md 9.2, error 13; 9.6, error 14).
# The compiler under test is seed/out/omc (OMC overrides it).
#  1. Every seed/omc/tests/longnames/NAME.om gives NAME.expect: "compile C", then "exit X" (the program's
#     status; NAME.stdout, when present, is its exact stdout) or "stderr LINE" (the exact refusal). Target
#     a64: compiled and run here (an AArch64 host). Target x86: the same compiler reads `target x86linux`,
#     a newline, then the unit, and the program runs under qemu-x86_64; the prepended line makes every
#     refusal line one higher (the om2 units carry their mode line after their notes, so they take it too).
#     Without qemu-x86_64 the x86 runs are NOT_RUN and the gate ends with status 3.
#  2. Capacity: 4096 distinct long globals compile and keep their values apart; the 4097th is error 14
#     on its own line.
#  3. Mutants: each one-line change of the interning in seed/omc/omc.om (a site that occurs exactly once)
#     must build a compiler (om4 cannot be asked, so the compiler under test builds it) that fails some
#     check of 1 or 2 on a64 (a wrong result, a refusal or a trap of the mutated compiler). A mutant that
#     does not build, does not change the compiler, or that no check notices, fails the gate.
# Last line: RC=0 when everything passed.
set -eu
R=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$R"
S=${OMC:-seed/out/omc}
D=seed/omc/tests/longnames
[ -x "$S" ] || { printf 'FAIL: %s missing; run sh seed/omega-from-seed.sh first\n' "$S" >&2; exit 1; }
mkdir -p build/seed
B=$(mktemp -d build/seed/longnames.XXXXXX)
trap 'rm -rf "$B"' EXIT HUP INT TERM
bad() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }
Q=$(command -v qemu-x86_64 || true)

# check COMPILER TARGET NAME -> prints nothing and returns 0 when NAME.expect holds, else prints why
check() {
  c=$1; t=$2; n=$3; f=$D/$n.om
  want=$(sed -n 1p $D/$n.expect); res=$(sed -n 2p $D/$n.expect)
  set +e
  if [ $t = a64 ]; then "$c" < $f > $B/p.bin 2> $B/p.err; else { printf 'target x86linux\n'; cat $f; } | "$c" > $B/p.bin 2> $B/p.err; fi
  rc=$?
  set -e
  [ "compile $rc" = "$want" ] || { echo "$t $n: compile $rc, wanted ${want#compile } ($(cat $B/p.err))"; return 1; }
  case $res in
  stderr*)
    exp=${res#stderr }
    if [ $t = x86 ]; then l=${exp#omc: line }; l=${l%%:*}; exp="omc: line $((l + 1)):${exp#omc: line *:}"; fi
    [ "$(cat $B/p.err)" = "$exp" ] || { echo "$t $n: stderr '$(cat $B/p.err)', wanted '$exp'"; return 1; } ;;
  exit*)
    chmod +x $B/p.bin
    set +e
    if [ $t = a64 ]; then $B/p.bin > $B/p.out 2>&1; else "$Q" $B/p.bin > $B/p.out 2>&1; fi
    x=$?
    set -e
    [ "exit $x" = "$res" ] || { echo "$t $n: exit $x, wanted ${res#exit }"; return 1; }
    if [ -f $D/$n.stdout ]; then cmp -s $B/p.out $D/$n.stdout || { echo "$t $n: stdout differs"; return 1; }; fi ;;
  *) echo "$n.expect: bad second line"; return 1 ;;
  esac
}
# capacity COMPILER -> 0 when 4096 long globals work and the 4097th is error 14
gen() { awk -v n=$1 'BEGIN { for (i = 1; i <= n; i++) printf "global long_global_name_%05d uint 1\n", i
  print "fn main to int"; print "put long_global_name_00001 0 uint 5"; printf "put long_global_name_%05d 0 uint 7\n", n
  printf "ret int add get long_global_name_00001 0 get long_global_name_%05d 0\nend\n", n }'; }
gen 4096 > $B/cap4096.om; gen 4097 > $B/cap4097.om
capacity() {
  set +e; "$1" < $B/cap4096.om > $B/c.bin 2> $B/c.err; rc=$?; set -e
  [ $rc = 0 ] || { echo "capacity: 4096 long globals: compile $rc ($(cat $B/c.err))"; return 1; }
  chmod +x $B/c.bin; set +e; $B/c.bin; x=$?; set -e
  [ $x = 12 ] || { echo "capacity: 4096 long globals: exit $x, wanted 12"; return 1; }
  set +e; "$1" < $B/cap4097.om > $B/c.bin 2> $B/c.err; rc=$?; set -e
  [ $rc = 14 ] && [ "$(cat $B/c.err)" = "omc: line 4097: error 14" ] || { echo "capacity: 4097 long globals: compile $rc ($(cat $B/c.err)), wanted line 4097 error 14"; return 1; }
}
names=$(ls $D/*.om | sed 's|.*/||; s|\.om$||')
nr=0; nx=0; skip=0
for n in $names; do
  check "$S" a64 $n > $B/why || bad "$(cat $B/why)"; nr=$((nr + 1))
  if [ -z "$Q" ] && grep -q '^exit' $D/$n.expect; then skip=$((skip + 1)); continue; fi
  check "$S" x86 $n > $B/why || bad "$(cat $B/why)"; nx=$((nx + 1))
done
say "PASS $nr long-name units on a64, $nx on x86${Q:+ (qemu-x86_64)}"
capacity "$S" > $B/why || bad "$(cat $B/why)"
say "PASS capacity: 4096 long globals keep their values apart (exit 12), the 4097th is line 4097 error 14"

# mutants: SITE|REPLACEMENT, each site exactly once in omc.om
k=0
while IFS='|' read -r site repl; do
  [ -n "$site" ] || continue
  k=$((k + 1))
  [ "$(grep -cxF "$site" seed/omc/omc.om)" = 1 ] || bad "mutant $k: site '$site' does not occur exactly once"
  awk -v s="$site" -v r="$repl" '$0 == s { print r; next } { print }' seed/omc/omc.om > $B/m.om
  set +e; "$S" < $B/m.om > $B/m.omc 2> $B/m.err; rc=$?; set -e
  [ $rc = 0 ] || bad "mutant $k ($repl): does not build ($(cat $B/m.err))"
  chmod +x $B/m.omc
  cmp -s $B/m.omc "$S" && bad "mutant $k ($repl): compiler unchanged"
  caught=""
  for n in $names; do check $B/m.omc a64 $n > $B/why || { caught=$n; break; }; done
  [ -n "$caught" ] || { capacity $B/m.omc > $B/why || caught=capacity; }
  [ -n "$caught" ] || bad "mutant $k ($repl): no check notices it"
  say "  killed mutant $k ($repl) by $caught: $(cat $B/why)"
done <<'MUT'
i = add n 1|i = add i 1
if ne get ln_b add o i bt|if eq get ln_b add o i bt
put ln_l k uchar n|put ln_l k uchar 9
put tw 0 add 1 shl k 8|put tw 0 add 1 shl mul k 0 8
if and gt n 8 le n 63|if and gt n 8 le n 62
if ge k 4096|if ge k 4095
MUT
say "PASS $k interning mutants each fail a check"
[ $skip = 0 ] || { say "NOT_RUN $skip x86 runs (no qemu-x86_64)"; exit 3; }
say "RC=0"
