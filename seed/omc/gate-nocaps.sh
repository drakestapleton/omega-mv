#!/bin/sh
# gate-nocaps.sh -- omc has no table capacities of its own (OMEGESE 9.6, decision 23 as amended
# 2026-11-11). The compiler under test is seed/out/omc (OMC overrides it). The control is omc
# f4fa7951, the last compiler with fixed tables, read from this repository's history (commit b2ad967e).
#  1. Units far past every old capacity (seed/omc/tests/nocaps/gen.sh: 100,000 texts, 100,000 globals,
#     100,000 calls in one OM-2 function, the view uchar * call shape that stopped at 6553 and the same
#     shape 100,000 times, 100,000 trap sites in one function and two that trap through them, 50,000
#     functions, blocks nested 5,000 deep, 3,000 breaks, a value nested 30,000 deep, calls nested 10,000
#     deep, 20,000 long names, a 64 MiB input, 65, 1,000 and 22,000 inline edges): each compiles, runs and
#     gives its NAME.want status, and the checked twin (below) compiles it to the same bytes. The control
#     refuses each with error 14, except view6552, the last count it accepted (the boundary), and the units
#     with a NAME.old status (inline65 and inline1000 fit its 16384 inline edges). The inline units' omc-use
#     record shows exactly NAME.ie edges, and a second control, omc 1e628c80 (commit d6840959), stops each
#     with trap 3 (exit 103): its inline-cycle check read the calls table at the edges' indices.
#  2. Value nesting is bounded by omc's own 8 MiB stack (32768 levels): for every recursive shape measured
#     (nested calls, conversions, parentheses, get, and, OM-2 view calls, contract clauses, IR mode)
#     32767 levels are not a trap of omc (a status of 100 or more) and 32768 is exactly error 14 on its
#     line. A frame that grows past the 256 bytes per level allowed would trap 6 here first.
#  4. Every arena group past its first room (seed/omc/tests/nocaps/groups.sh: names, long names, functions,
#     calls, trap sites, blocks, breaks, continues, inline rets, inline edges, value depth, x86 address
#     fixups, x86 exits, diag sites, the Kahn tables of function mode, and the output and input): the
#     omc-use record shows each group asked for more than its first room, omc compiles the unit (never a
#     status of 100 or more), the program gives NAME.want (x86 under qemu-x86_64: EMULATED), and the checked
#     twin compiles it to the same bytes. The checked twin is seed/omc/omc.om with every inline table access
#     (get/put a_ar add get a_rb R I) made the region-checked call (a_g/a_p R I), built by the compiler under
#     test: an index past its region is trap 3 there, where omc itself would read or write a neighbour. Its
#     control: the twin of omc 1e628c80's source (d6840959) stops on inline1000 with trap 3.
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
OLD2=1e628c80d5bd2ad0b08eb46d8abff66eff284a74e5a302e589c2d61cfe9f7347
git cat-file blob d68409596f7b9f5756557621c385376e55f3ef17:seed/out/omc > $B/old2 2> /dev/null ||
  bad "control: commit d6840959 is not in this clone's history (a full clone is needed)"
[ "$(sha256sum $B/old2 | cut -d' ' -f1)" = $OLD2 ] || bad "control: d6840959:seed/out/omc is not omc $OLD2"
chmod +x $B/old2
# the checked twin of seed/omc/omc.om, built by the compiler under test (step 4 says what it is)
twin() { sed -e 's/get a_ar add get a_rb \([0-9]*\) /a_g \1 /g' -e 's/put a_ar add get a_rb \([0-9]*\) /a_p \1 /g'; }
twin < seed/omc/omc.om > $B/twin.om
set +e; "$S" < $B/twin.om > $B/twin 2> $B/twin.err; rc=$?; set -e
[ $rc = 0 ] || bad "twin: the checked twin of seed/omc/omc.om did not compile: $rc ($(head -c 300 $B/twin.err))"
chmod +x $B/twin
rm -f $B/twin.om
# the usage record of a unit (the usage line goes after a first target line)
rec() {
  if head -1 "$1" | grep -q '^target '; then sed '1a usage' "$1"; else { printf 'usage\n'; cat "$1"; }; fi > $B/r.om
  set +e; "$S" < $B/r.om 2> /dev/null | tr ' ' '\n' > $B/r.rec; set -e
}
recn() { sed -n "s/^$1=\([0-9]*\)\/.*/\1/p" $B/r.rec; }

# 1. the units
sh seed/omc/tests/nocaps/gen.sh $B/u
n=0
for f in $B/u/*.om; do
  u=$(basename $f .om); want=$(cat $B/u/$u.want)
  set +e; "$S" < $f > $B/p.bin 2> $B/p.err; rc=$?; set -e
  [ $rc = 0 ] || bad "$u: compile $rc ($(head -c 300 $B/p.err))"
  chmod +x $B/p.bin; set +e; $B/p.bin > /dev/null 2>&1; x=$?; set -e
  [ $x = $want ] || bad "$u: exit $x, wanted $want"
  set +e; $B/twin < $f > $B/t.bin 2> $B/t.err; trc=$?; set -e
  [ $trc = 0 ] || bad "$u: the checked twin gave $trc ($(head -c 300 $B/t.err)): an index past its region"
  cmp -s $B/p.bin $B/t.bin || bad "$u: the checked twin's output differs from omc's"
  extra=""
  if [ -f $B/u/$u.ie ]; then
    rec $f; e=$(recn inledge)
    [ "$e" = "$(cat $B/u/$u.ie)" ] || bad "$u: omc-use inledge=$e, wanted $(cat $B/u/$u.ie)"
    extra="; $e inline edges"
  fi
  set +e; $B/old < $f > /dev/null 2> $B/o.err; orc=$?; set -e
  if [ $u = view6552 ]; then
    [ $orc = 0 ] || bad "control $u: omc f4fa7951 gave $orc, wanted 0 (the last count it accepted)"
  elif [ -f $B/u/$u.old ]; then
    [ $orc = $(cat $B/u/$u.old) ] || bad "control $u: omc f4fa7951 gave $orc ($(cat $B/o.err)), wanted $(cat $B/u/$u.old)"
  else
    [ $orc = 14 ] || bad "control $u: omc f4fa7951 gave $orc ($(cat $B/o.err)), wanted error 14"
  fi
  if [ -f $B/u/$u.c2 ]; then
    set +e; $B/old2 < $f > /dev/null 2> /dev/null; c2=$?; set -e
    [ $c2 = $(cat $B/u/$u.c2) ] || bad "control $u: omc 1e628c80 gave $c2, wanted $(cat $B/u/$u.c2)"
    extra="$extra; control 1e628c80 status $c2 (trap $((c2 - 100)))"
  fi
  if [ $orc = 0 ]; then octl=compiled; else octl=$(head -1 $B/o.err); fi
  say "PASS $u: exit $x$extra; control $octl"
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
# 4. every arena group past its first room, by omc and by the checked twin
git cat-file blob d68409596f7b9f5756557621c385376e55f3ef17:seed/omc/omc.om | twin > $B/twin2.om
set +e; "$S" < $B/twin2.om > $B/twin2 2> /dev/null; rc=$?; set -e
[ $rc = 0 ] || bad "twin control: the checked twin of d6840959's omc.om did not compile: $rc"
chmod +x $B/twin2; rm -f $B/twin2.om
sh seed/omc/tests/nocaps/groups.sh $B/g
set +e; $B/twin2 < $B/g/inledge.om > /dev/null 2> /dev/null; rc=$?; set -e
[ $rc = 103 ] || bad "twin control: the checked twin of omc 1e628c80 gave $rc on inledge, wanted 103 (trap 3)"
say "PASS twin control: the checked twin of omc 1e628c80's source stops on inledge with trap 3"
g=0
for f in $B/g/*.om; do
  u=$(basename $f .om)
  set +e; "$S" < $f > $B/p.bin 2> $B/p.err; rc=$?; set -e
  [ $rc -lt 100 ] || bad "group $u: omc stopped with status $rc (a trap of omc itself)"
  [ $rc = 0 ] || bad "group $u: compile $rc ($(head -c 300 $B/p.err))"
  set +e; $B/twin < $f > $B/t.bin 2> $B/t.err; trc=$?; set -e
  [ $trc = 0 ] || bad "group $u: the checked twin gave $trc ($(head -c 300 $B/t.err)): an index past its region"
  cmp -s $B/p.bin $B/t.bin || bad "group $u: the checked twin's output differs from omc's"
  rec $f; got=""
  while read k m; do
    v=$(recn $k)
    [ -n "$v" ] && [ "$v" -ge "$m" ] || bad "group $u: omc-use $k=$v, wanted at least $m (past its first room)"
    got="$got $k=$v"
  done < $B/g/$u.grp
  run="compiled only"
  if [ -f $B/g/$u.want ]; then
    chmod +x $B/p.bin
    if [ "$(cat $B/g/$u.run 2> /dev/null)" = x86 ]; then
      if command -v qemu-x86_64 > /dev/null; then
        set +e; qemu-x86_64 $B/p.bin > /dev/null 2>&1; x=$?; set -e; run="exit $x (qemu-x86_64, EMULATED)"
      else x=$(cat $B/g/$u.want); run="run NOT_RUN (no qemu-x86_64)"; fi
    else
      set +e; $B/p.bin > /dev/null 2>&1; x=$?; set -e; run="exit $x"
    fi
    [ $x = $(cat $B/g/$u.want) ] || bad "group $u: exit $x, wanted $(cat $B/g/$u.want)"
  fi
  say "PASS group $u:$got; $run; twin same bytes"
  g=$((g + 1))
done
say "PASS gate-nocaps $n units past the old capacities, 8 nesting shapes, the arena boundary, $g group units"
say "RC=0"
