#!/bin/sh
# gate-nocaps.sh -- omc has no table capacities of its own (OMEGESE 9.6, decision 23 as amended
# 2026-11-11). The compiler under test is seed/out/omc (OMC overrides it). The control is omc
# f4fa7951, the last compiler with fixed tables, read from this repository's history (commit b2ad967e).
#  1. Units far past every old capacity (seed/omc/tests/nocaps/gen.sh: 100,000 texts, 100,000 globals,
#     100,000 calls in one OM-2 function, the view uchar * call shape that stopped at 6553 and the same
#     shape 100,000 times, 100,000 trap sites in one function and two that trap through them, 50,000
#     functions, blocks nested 5,000 deep, 3,000 breaks, a value nested 30,000 deep, calls nested 10,000
#     deep, 20,000 long names, a 64 MiB input): each compiles, runs and gives its NAME.want status. The
#     control refuses each with error 14, except view6552, the last count it accepted (the boundary).
#  2. Value nesting is bounded by omc's own 8 MiB stack (32768 levels): for every recursive shape measured
#     (nested calls, conversions, parentheses, get, and, OM-2 view calls, contract clauses, IR mode)
#     32767 levels are not a trap of omc (a status of 100 or more) and 32768 is exactly error 14 on its
#     line. A frame that grows past the 256 bytes per level allowed would trap 6 here first.
#     The IR row checks only that no depth is a trap of omc: IR mode refuses well before 32767 at its own
#     tables, so its depth site is shown reached by sitecov (seed/omc/sites/nesting-ir-32768.om).
#  3. A unit larger than the arena (134217728 bytes) is error 14 on line 0 followed by the omc-use record
#     with full=1, naming the arena (seed/omc/gate12.sh checks the same; here with the record's fields).
# Last line: RC=0 when everything passed.
set -eu
R=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$R"
S=${OMC:-seed/out/omc}
[ -x "$S" ] || { printf 'FAIL: %s missing; run sh seed/omega-from-seed.sh first\n' "$S" >&2; exit 1; }
mkdir -p build/seed
B=$(mktemp -d build/seed/nocaps.XXXXXX)
trap 'rm -rf "$B"' EXIT HUP INT TERM
bad() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }

OLD=f4fa7951816bbd09c5eaaae6692852a70c3c305164b365027c5b683dec7d63e9
git cat-file blob b2ad967e57146172c1bedf1eac98babb75baef65:seed/out/omc > $B/old 2> /dev/null ||
  bad "control: commit b2ad967e is not in this clone's history (a full clone is needed)"
[ "$(sha256sum $B/old | cut -d' ' -f1)" = $OLD ] || bad "control: b2ad967e:seed/out/omc is not omc $OLD"
chmod +x $B/old

# 1. the units
sh seed/omc/tests/nocaps/gen.sh $B/u
n=0
for f in $B/u/*.om; do
  u=$(basename $f .om); want=$(cat $B/u/$u.want)
  set +e; "$S" < $f > $B/p.bin 2> $B/p.err; rc=$?; set -e
  [ $rc = 0 ] || bad "$u: compile $rc ($(head -c 300 $B/p.err))"
  chmod +x $B/p.bin; set +e; $B/p.bin > /dev/null 2>&1; x=$?; set -e
  [ $x = $want ] || bad "$u: exit $x, wanted $want"
  set +e; $B/old < $f > /dev/null 2> $B/o.err; orc=$?; set -e
  if [ $u = view6552 ]; then
    [ $orc = 0 ] || bad "control $u: omc f4fa7951 gave $orc, wanted 0 (the last count it accepted)"
  else
    [ $orc = 14 ] || bad "control $u: omc f4fa7951 gave $orc ($(cat $B/o.err)), wanted error 14"
  fi
  say "PASS $u: exit $x; control $(cat $B/o.err | head -1 | sed 's/^$/compiled/')"
  n=$((n + 1))
done

# 2. value nesting at the stack-derived depth
shape() { # shape NAME DEPTH -> the unit on stdout; the deep value is on line L (printed to fd 3)
  awk -v s=$1 -v d=$2 'BEGIN {
    if (s == "call") { print "fn inc a ulong to ulong\nret add a 1\nend\nfn main to int\ny = ulong 0"; printf "x = "; for (i = 0; i < d; i++) printf "inc "; print "y" }
    if (s == "conv") { print "fn main to int\ny = ulong 7"; printf "x = "; for (i = 0; i < d; i++) printf "ulong "; print "y" }
    if (s == "paren") { print "fn main to int\ny = ulong 7"; printf "x = "; for (i = 0; i < d; i++) printf "( "; printf "y"; for (i = 0; i < d; i++) printf " )"; print "" }
    if (s == "get") { print "global g ulong 4\nfn main to int"; printf "x = "; for (i = 0; i < d; i++) printf "get g "; print "ulong 0" }
    if (s == "and") { print "fn main to int\nb = true"; printf "c = "; for (i = 0; i < d; i++) printf "and b "; print "b"; print "x = ulong 0" }
    if (s == "om2view") { print "om2\ntext t \"hello\"\nfn vl a view uchar * b ulong to ulong\nret add len a b\nend\nfn main to int"; printf "x = "; for (i = 0; i < d; i++) printf "vl t "; print "ulong 0" }
    if (s == "contract") { print "om2\nfn f a ulong to ulong"; printf "requires "; for (i = 0; i < d; i++) printf "and true "; print "true\nret a\nend\nfn main to int\nx = f 1" }
    if (s == "ir") { print "ir\nfn f a ulong to ulong\nret a\nend\nfn main to int"; printf "x = "; for (i = 0; i < d; i++) printf "f "; print "ulong 0" }
    print "ret 0\nend" }'
}
line() { # the line of the deep value
  case $1 in call) echo 6 ;; conv|paren|get|and) echo 3 ;; om2view) echo 7 ;; contract) echo 3 ;; ir) echo 6 ;; esac
}
for s in call conv paren get and om2view contract ir; do
  shape $s 32767 > $B/s.om
  set +e; "$S" < $B/s.om > /dev/null 2> $B/s.err; rc=$?; set -e
  [ $rc -lt 100 ] || bad "depth $s 32767: omc stopped with status $rc (a trap of omc itself: a frame grew?)"
  if [ $rc = 0 ]; then first=compiled; else first="status $rc ($(head -1 $B/s.err))"; fi
  shape $s 32768 > $B/s.om
  set +e; "$S" < $B/s.om > /dev/null 2> $B/s.err; rc=$?; set -e
  want="omc: line $(line $s): error 14"
  [ $rc = 14 ] && [ "$(head -1 $B/s.err)" = "$want" ] || bad "depth $s 32768: $rc '$(head -1 $B/s.err)', wanted '$want'"
  say "PASS depth $s: 32767 levels $first; 32768 levels error 14"
done

# 3. the arena boundary
{ yes 'note this line is ninety-nine bytes long, padding the input past the arena of omc, which is 128 MiB...' | head -c 134217729; } > $B/a.om
set +e; "$S" < $B/a.om > $B/a.bin 2> $B/a.err; rc=$?; set -e
[ $rc = 14 ] || bad "arena: a 134217729-byte unit gave $rc, wanted 14"
[ "$(sed -n 1p $B/a.err)" = "omc: line 0: error 14" ] || bad "arena: first line '$(sed -n 1p $B/a.err)'"
sed -n 2p $B/a.err | grep -q '^omc-use 1 arena=16777216 top=[0-9]* waste=[0-9]* full=1 inp=' ||
  bad "arena: no omc-use record with full=1 ('$(sed -n 2p $B/a.err | head -c 200)')"
[ ! -s $B/a.bin ] || bad "arena: a refusal wrote stdout"
say "PASS arena: a unit past the arena is error 14 with the omc-use record ($(sed -n 2p $B/a.err | cut -d' ' -f1-8))"
rm -f $B/a.om
say "PASS gate-nocaps $n units past the old capacities, 8 nesting shapes, the arena boundary"
say "RC=0"
