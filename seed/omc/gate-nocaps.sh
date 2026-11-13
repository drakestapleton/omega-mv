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
#  3. The arena grows (landing 2 of the run-time pools, docs/RUNTIME-POOLS.md s6 and s7 gate 13): a 512 MiB
#     input (note lines, then a program) and 1,500,000 globals (61 million arena words, the old arena held
#     16777216) compile and run. The control is omc 1e628c80 (d6840959, the static 128 MiB arena): it refuses
#     both with error 14 and full=1. Under prlimit --as=268435456 the host refuses the arena's growth on the
#     512 MiB input: error 14 on line 0 and the omc-use record with full=1 (the host refused), never a trap.
#  5. The memory ceiling (docs/RUNTIME-POOLS.md s6, "The memory ceiling"): a page unit shaped as cortex's
#     pageunit (671,088 text records of 100 bytes, about 87 MB; its artifact about 94 MB) is compiled with stdout
#     on a file, in a user cgroup scope (systemd-run --user --scope -p MemoryMax=C -p MemorySwapMax=0
#     -p OOMPolicy=continue) with OMC_MEMORY_MAX=C. C = 256 MiB and 448 MiB: error 14, full=1, ceiling=C,
#     memory.events oom_kill 0, under 30 s. C = 1 GiB: compiles, oom_kill 0, and the program writes the page
#     back byte for byte. Monotonic: C = 384 .. 640 MiB in 32 MiB steps, each 0 or 14 with oom_kill 0, no 14 above
#     a 0. An om2 diag unit (1,200,000 lines; omc-site records on stderr, a file) at 448 MiB and 640 MiB: 0 or 14,
#     oom_kill 0, and at 640 MiB compiled. A capped doubling that still fits: a 64 MiB input unit at
#     OMC_MEMORY_MAX=100 MiB compiles with a smaller arena than with no ceiling, through a file and a pipe.
#     Malformed values (12x, -5, " 5", "5 ", 20 digits, 2^63, a 70015-byte entry) are error 26 on line 0; empty
#     and 0 mean ceiling=0; an unrelated 100000-byte entry changes nothing. Mutants built from omc.om: the
#     ceiling ignored (killed or past 30 s at C = 448 MiB) and the margin dropped (a differential control: at
#     some C in 448 .. 512 MiB omc refuses and the mutant compiles; measured, it is not killed there, the kernel
#     reclaims the artifact's written pages). Without systemd-run --user the cgroup rows are NOT_RUN and the
#     variable is checked under prlimit --as.
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

# 3. the arena grows; the host is its bound
ARENA=1e628c80d5bd2ad0b08eb46d8abff66eff284a74e5a302e589c2d61cfe9f7347
git cat-file blob d6840959:seed/out/omc > $B/arena 2> /dev/null || bad "control: commit d6840959 is not in this clone's history"
[ "$(sha256sum $B/arena | cut -d' ' -f1)" = $ARENA ] || bad "control: d6840959:seed/out/omc is not omc $ARENA"
chmod +x $B/arena
{ yes 'note this line is ninety-nine bytes long, padding the input far past the old arena of 128 MiB....' | head -c 536870913 | sed '$d'
  printf 'fn main to int\nret 9\nend\n'; } > $B/a.om
awk 'BEGIN { for (i = 0; i < 1500000; i++) printf "global g%d uchar 1\n", i; print "fn main to int"; print "put g1499999 0 7"
  print "ret int get g1499999 0"; print "end" }' > $B/g.om
for u in a:9 g:7; do f=$B/${u%:*}.om; want=${u#*:}
  set +e; "$S" < $f > $B/a.bin 2> $B/a.err; rc=$?; set -e
  [ $rc = 0 ] || bad "arena: $(basename $f) ($(stat -c %s $f) bytes) gave $rc ($(head -c 200 $B/a.err))"
  chmod +x $B/a.bin; set +e; $B/a.bin > /dev/null 2>&1; x=$?; set -e
  [ $x = $want ] || bad "arena: $(basename $f) ran to $x, wanted $want"
  rec=$({ printf 'usage\n'; cat $f; } | "$S" | cut -d' ' -f1-6)
  set +e; $B/arena < $f > /dev/null 2> $B/c.err; crc=$?; set -e
  [ $crc = 14 ] && sed -n 2p $B/c.err | grep -q '^omc-use 1 arena=16777216 .* full=1 ' ||
    bad "control: omc 1e628c80 gave $crc on $(basename $f) ($(head -c 200 $B/c.err)), wanted error 14 with full=1"
  say "PASS arena grows: $(basename $f) ($(stat -c %s $f) bytes) compiles and runs to $x ($rec); control 1e628c80: $(head -1 $B/c.err)"
done
rm -f $B/g.om
set +e; prlimit --as=268435456 "$S" < $B/a.om > $B/a.bin 2> $B/a.err; rc=$?; set -e
[ $rc = 14 ] || bad "arena: under prlimit --as=268435456 the 512 MiB unit gave $rc, wanted 14"
[ "$(sed -n 1p $B/a.err)" = "omc: line 0: error 14" ] || bad "arena: first line '$(sed -n 1p $B/a.err)'"
sed -n 2p $B/a.err | grep -q '^omc-use 1 arena=[0-9]* top=[0-9]* waste=[0-9]* full=1 inp=' ||
  bad "arena: no omc-use record with full=1 ('$(sed -n 2p $B/a.err | head -c 200)')"
[ ! -s $B/a.bin ] || bad "arena: a refusal wrote stdout"
say "PASS arena host refusal: under prlimit --as=268435456 the 512 MiB unit is error 14 with the omc-use record ($(sed -n 2p $B/a.err | cut -d' ' -f1-6))"
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
# 5. the memory ceiling
awk 'BEGIN { a = "abcdefghijklmnopqrstuvwxyz"; while (length(a) < 90) a = a a; a = substr(a, 1, 90)
  for (i = 0; i < 671088; i++) printf "%08d %s\n", i, a }' > $B/page.txt
awk -v n=671088 'BEGIN { a = "abcdefghijklmnopqrstuvwxyz"; while (length(a) < 90) a = a a; a = substr(a, 1, 90)
  print "om2"; for (i = 0; i < n; i++) printf "text t%d \"%08d %s\\n\"\n", i, i, a
  print "fn emit a view uchar * to void"; print "n = len a"; print "o = ulong 0"; print "while lt o n bound 1000000"
  print "k = write 1 a o sub n o"; print "if le k 0"; print "exit 1"; print "end"; print "o = add o ulong k"; print "end"; print "end"
  print "fn main to int"; for (i = 0; i < n; i++) printf "emit t%d\n", i; print "ret 0"; print "end" }' > $B/pu.om
cg() { # compiler memmax var out -> "rc wall_ms oom_kill" in $B/cg.res, stderr in $B/cg.err (OMC_MEMORY_MAX unset when var is -)
  cat > $B/cg.sh << CG
g=/sys/fs/cgroup\$(sed -n "s/^0:://p" /proc/self/cgroup)
[ "\$(cat \$g/memory.max)" = $2 ] && [ "\$(cat \$g/memory.swap.max)" = 0 ] || { echo "noscope 0 0" > $B/cg.res; exit 0; }
s=\$(date +%s%N)
if [ "$3" = - ]; then timeout -s KILL 30 $1 < $B/pu.om > $4 2> $B/cg.err; else OMC_MEMORY_MAX=$3 timeout -s KILL 30 $1 < $B/pu.om > $4 2> $B/cg.err; fi
rc=\$?; e=\$(date +%s%N)
echo "\$rc \$(( (e - s) / 1000000 )) \$(awk '\$1 == "oom_kill" { print \$2 }' \$g/memory.events)" > $B/cg.res
CG
  systemd-run --user --scope -q -p MemoryMax=$2 -p MemorySwapMax=0 -p OOMPolicy=continue sh $B/cg.sh 2> /dev/null || echo "noscope 0 0" > $B/cg.res
}
if systemd-run --user --scope -q -p MemoryMax=268435456 -p MemorySwapMax=0 true 2> /dev/null; then
  for C in 268435456 469762048; do
    cg "$S" $C $C $B/pu.bin; read rc ms ok < $B/cg.res
    [ "$rc" != noscope ] || bad "ceiling: the scope did not carry MemoryMax=$C and swap 0"
    [ $rc = 14 ] && [ "$ok" = 0 ] && [ $ms -lt 30000 ] && sed -n 2p $B/cg.err | grep -q " full=1 .* ceiling=$C\$" ||
      bad "ceiling: MemoryMax=$C OMC_MEMORY_MAX=$C gave rc=$rc ${ms} ms oom_kill=$ok ($(head -c 200 $B/cg.err))"
    say "PASS ceiling $C: error 14 full=1 ceiling=$C in $ms ms, oom_kill 0 ($(head -1 $B/cg.err))"
  done
  C=1073741824; cg "$S" $C $C $B/pu.bin; read rc ms ok < $B/cg.res
  [ $rc = 0 ] && [ "$ok" = 0 ] || bad "ceiling: MemoryMax=$C OMC_MEMORY_MAX=$C gave rc=$rc oom_kill=$ok ($(head -c 200 $B/cg.err))"
  chmod +x $B/pu.bin; $B/pu.bin > $B/pu.out || bad "ceiling: the page program exited $?"
  cmp -s $B/pu.out $B/page.txt || bad "ceiling: the page program's output differs from the page"
  say "PASS ceiling $C: compiles in $ms ms, oom_kill 0, the program writes the $(stat -c %s $B/page.txt)-byte page back (cmp)"
  sed 's/^put a_cel 0 v$/put a_cel 0 0/' seed/omc/omc.om > $B/m1.om; grep -cx 'put a_cel 0 v' seed/omc/omc.om | grep -qx 1 || bad "mutant: no put a_cel 0 v"
  "$S" < $B/m1.om > $B/m1 && chmod +x $B/m1 || bad "mutant ceiling-ignored does not build"
  C=469762048; cg $B/m1 $C $C $B/pu.bin; read rc ms ok < $B/cg.res
  [ $rc != 14 ] && { [ "$ok" != 0 ] || [ $ms -ge 29000 ]; } || bad "mutant ceiling-ignored not caught: rc=$rc ${ms} ms oom_kill=$ok"
  say "PASS mutant ceiling ignored caught at $C: rc=$rc after $ms ms, oom_kill $ok"
  # the margin as a differential control: tables that never grow past the budget make a page-unit compile fit
  # somewhere below 512 MiB only when the margin (16 MiB + 1/128) is dropped; measured on the Spark, the dropped
  # margin is not killed there either (the kernel writes the artifact back and reclaims it), so the control is
  # that the margin, and only it, refuses (docs/RUNTIME-POOLS.md s7 item 13)
  grep -cx 'ret add add b shr b 7 16777216' seed/omc/omc.om | grep -qx 1 || bad "mutant margin: the margin line of a_marg is not there once"
  sed 's/^ret add add b shr b 7 16777216$/ret b/' seed/omc/omc.om > $B/m2.om
  "$S" < $B/m2.om > $B/m2 && chmod +x $B/m2 || bad "mutant margin does not build"
  dc=""
  for m in 448 464 480 496 512; do C=$((m * 1048576))
    set +e; OMC_MEMORY_MAX=$C "$S" < $B/pu.om > /dev/null 2>&1; r1=$?; OMC_MEMORY_MAX=$C $B/m2 < $B/pu.om > /dev/null 2>&1; r2=$?; set -e
    { [ $r1 = 0 ] || [ $r1 = 14 ]; } && { [ $r2 = 0 ] || [ $r2 = 14 ]; } || bad "margin: omc $r1, mutant $r2 at $m MiB"
    [ $r1 = 0 ] && [ $r2 != 0 ] && bad "margin: the mutant refused at $m MiB where omc compiles"
    [ $r1 = 14 ] && [ $r2 = 0 ] && dc="$dc $m"
  done
  [ -n "$dc" ] || bad "mutant margin not caught: no ceiling in 448..512 MiB where omc refuses and the margin-dropped mutant compiles"
  say "PASS mutant margin dropped caught (differential): omc refuses and the mutant compiles at$dc MiB"
  # monotonic in C: one unit over 384..640 MiB, every result 0 or 14 with oom_kill 0, and none 14 above a 0
  seen=0; row=""
  for m in 384 416 448 480 512 544 576 608 640; do C=$((m * 1048576))
    cg "$S" $C $C $B/pu.bin; read rc ms ok < $B/cg.res
    { [ "$rc" = 0 ] || [ "$rc" = 14 ]; } && [ "$ok" = 0 ] && [ $ms -lt 30000 ] || bad "sweep: $m MiB gave rc=$rc ${ms} ms oom_kill=$ok"
    [ $rc = 0 ] && seen=1; [ $seen = 1 ] && [ $rc = 14 ] && bad "sweep: refused at $m MiB above a ceiling that compiled"
    row="$row $m:$rc"
  done
  say "PASS sweep monotonic, oom_kill 0:$row"
  # an om2 diag unit: its omc-site records go to stderr (a file) after the artifact; both are page cache of the scope
  awk 'BEGIN { print "om2 diag"; print "global G ulong 1024"; print "fn main to int"; print "i = ulong 5"
    for (k = 0; k < 1200000; k++) print "put G i add get G i 1"; print "ret 0"; print "end" }' > $B/dg.om
  for C in 469762048 671088640; do
    cat > $B/cg2.sh << CG
g=/sys/fs/cgroup\$(sed -n "s/^0:://p" /proc/self/cgroup)
OMC_MEMORY_MAX=$C timeout -s KILL 30 "$S" < $B/dg.om > $B/dg.bin 2> $B/dg.err; rc=\$?
echo "\$rc \$(awk '\$1 == "oom_kill" { print \$2 }' \$g/memory.events)" > $B/cg.res
CG
    systemd-run --user --scope -q -p MemoryMax=$C -p MemorySwapMax=0 -p OOMPolicy=continue sh $B/cg2.sh 2> /dev/null || echo "noscope 0" > $B/cg.res
    read rc ok < $B/cg.res
    { [ "$rc" = 0 ] || [ "$rc" = 14 ]; } && [ "$ok" = 0 ] || bad "om2 diag unit at $C: rc=$rc oom_kill=$ok"
    [ $C = 671088640 ] && { [ $rc = 0 ] && [ $(stat -c %s $B/dg.err) -gt 60000000 ] || bad "om2 diag unit at $C: rc=$rc, site records $(stat -c %s $B/dg.err) bytes"; }
    say "PASS om2 diag unit (stderr on a file) at $C: rc=$rc, oom_kill 0, $(stat -c %s $B/dg.bin)-byte artifact, $(stat -c %s $B/dg.err) bytes on stderr"
  done
  rm -f $B/dg.om $B/dg.bin $B/dg.err
else
  say "NOT_RUN ceiling cgroup rows: systemd-run --user --scope cannot set MemoryMax here"
  set +e; OMC_MEMORY_MAX=268435456 prlimit --as=4294967296 "$S" < $B/pu.om > /dev/null 2> $B/cg.err; rc=$?; set -e
  ar=$(sed -n 2p $B/cg.err | sed 's/.* arena=\([0-9]*\) .*/\1/')
  [ $rc = 14 ] && sed -n 2p $B/cg.err | grep -q ' full=1 .* ceiling=268435456$' && [ $(( ar * 8 )) -le 268435456 ] ||
    bad "ceiling under prlimit: rc=$rc record '$(sed -n 2p $B/cg.err | cut -c1-120)'"
  say "PASS ceiling under prlimit --as=4294967296 with OMC_MEMORY_MAX=268435456: error 14, ceiling=268435456, arena $ar words within the cap"
fi
{ printf 'usage\n'; yes 'note padding past the first room of the input region, sixty-four MiB of it.....' | head -c 67108864 | sed '$d'
  printf 'fn main to int\nret 7\nend\n'; } > $B/in.om
a0=$("$S" < $B/in.om | sed 's/.* arena=\([0-9]*\) .*/\1/')
a1=$(OMC_MEMORY_MAX=104857600 "$S" < $B/in.om | sed 's/.* arena=\([0-9]*\) .*/\1/')
[ "$a1" -lt "$a0" ] && [ $(( a1 * 8 )) -lt 104857600 ] || bad "capped doubling: arena $a1 words with OMC_MEMORY_MAX=104857600, $a0 without"
sed 1d $B/in.om > $B/in2.om
set +e; OMC_MEMORY_MAX=104857600 "$S" < $B/in2.om > $B/in.bin 2> $B/in.err; rc=$?; set -e
[ $rc = 0 ] || bad "capped doubling: the 64 MiB unit does not compile under 100 MiB: rc=$rc $(head -c 300 $B/in.err)"
# the same through a pipe in 4096-byte writes, 5 times: reads cut differently must not change the outcome (a_hw is not
# followed while a_rdin reads; omc 81d608a1, which followed it, refused 4 of 5 such runs)
for i in 1 2 3 4 5; do
  set +e; dd if=$B/in2.om bs=4096 status=none | OMC_MEMORY_MAX=104857600 "$S" > /dev/null 2> $B/in.err; rc=$?; set -e
  [ $rc = 0 ] || bad "capped doubling through a pipe (run $i): rc=$rc $(head -c 300 $B/in.err)"
done
chmod +x $B/in.bin; set +e; $B/in.bin; x=$?; set -e; [ $x = 7 ] || bad "capped doubling: ran to $x"
say "PASS capped doubling: the 64 MiB unit compiles under OMC_MEMORY_MAX=104857600 with an arena of $a1 words ($a0 with no ceiling), runs to 7"
rm -f $B/in.om $B/in2.om $B/in.bin
printf 'fn main to int\nret 0\nend\n' > $B/t.om
for v in 12x -5 " 5" "5 " 12345678901234567890 9223372036854775808; do
  set +e; OMC_MEMORY_MAX="$v" "$S" < $B/t.om > $B/t.bin 2> $B/t.err; rc=$?; set -e
  [ $rc = 26 ] && [ "$(cat $B/t.err)" = "omc: line 0: error 26" ] && [ ! -s $B/t.bin ] || bad "malformed OMC_MEMORY_MAX '$v': rc=$rc $(cat $B/t.err)"
done
for v in "" 0; do
  { printf 'usage\n'; cat $B/t.om; } | OMC_MEMORY_MAX="$v" "$S" | grep -q ' ceiling=0$' || bad "OMC_MEMORY_MAX='$v' is not ceiling=0"
done
say "PASS ceiling values: 12x, -5, ' 5', '5 ', 20 digits and 2^63 are error 26 on line 0; empty and 0 are ceiling=0"
z=$(head -c 70000 /dev/zero | tr '\0' 0)
set +e; env "OMC_MEMORY_MAX=$z" "$S" < $B/t.om > /dev/null 2> $B/t.err; rc=$?; set -e
[ $rc = 26 ] || bad "a 70015-byte OMC_MEMORY_MAX entry gave $rc ($(cat $B/t.err)), wanted 26"
x=$(head -c 100000 /dev/zero | tr '\0' x)
{ printf 'usage\n'; cat $B/t.om; } | env -u OMC_MEMORY_MAX "BIG=$x" "$S" | grep -q ' ceiling=0$' || bad "an unrelated 100000-byte entry changed the ceiling"
say "PASS long entries: a 70015-byte OMC_MEMORY_MAX is error 26; an unrelated 100000-byte entry leaves ceiling=0"
rm -f $B/pu.om $B/pu.bin $B/pu.out $B/page.txt $B/m1 $B/m2 $B/m1.om $B/m2.om

say "PASS gate-nocaps $n units past the old capacities, 8 nesting shapes, the growing arena and its host refusal, $g group units, the memory ceiling"
say "RC=0"
