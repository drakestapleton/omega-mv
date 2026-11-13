#!/bin/sh
# gate12.sh -- documented capacities (OMEGESE 9.6, decision 23 as amended 2026-11-11). omc's tables live in
# one arena, which itself grows at run time (a run-time pool, landing 2 of docs/RUNTIME-POOLS.md); what is
# left are the host's refusal of that growth, the depth omc's own stack can hold, and the program's own pool limits (OMEGESE 9.4, error 23). Each case is generated, compiled by seed/out/omc, and
# checked for the documented accept/refuse boundary. The units one past each old table size (8192 names,
# 4096 functions, 512 blocks, 8 MiB input) are accepted; seed/omc/gate-nocaps.sh takes them far past.
# RC=0 only when all pass.
set -eu
R=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$R"
S=seed/out/omc
[ -x "$S" ] || { printf 'FAIL: %s missing; run sh seed/omega-from-seed.sh first\n' "$S" >&2; exit 1; }
mkdir -p build/seed/r12
T=$(mktemp -d build/seed/r12/cap.XXXXXX)
trap 'rm -rf "$T"' EXIT HUP INT TERM
bad() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }

accept() { # name file
    set +e
    "$S" < "$2" > "$T/$1.out" 2> "$T/$1.err"
    rc=$?
    set -e
    [ "$rc" = 0 ] || bad "$1: exit $rc ($(head -1 "$T/$1.err"))"
    [ -s "$T/$1.out" ] || bad "$1: empty output"
    say "PASS $1 accepted"
}
refuse() { # name file code
    set +e
    "$S" < "$2" > "$T/$1.out" 2> "$T/$1.err"
    rc=$?
    set -e
    [ "$rc" = "$3" ] || bad "$1: exit $rc, wanted $3 ($(head -1 "$T/$1.err"))"
    grep -q "error $3" "$T/$1.err" || bad "$1: diagnostic does not name error $3"
    say "PASS $1 error $3"
}

awk 'BEGIN{for(i=0;i<8193;i++)printf "global g%d uchar 1\n",i; print "fn main to int"; print "ret 0"; print "end"}' > "$T/g8193.om"
awk 'BEGIN{for(i=0;i<4096;i++)printf "fn q%d to int\nret 0\nend\n",i; print "fn main to int"; print "ret 0"; print "end"}' > "$T/f4096.om"
awk 'BEGIN{print "fn main to int"; print "x = ulong 1"; for(i=0;i<513;i++)print "if eq x 1"; print "ret 0"; for(i=0;i<513;i++)print "end"; print "ret 0"; print "end"}' > "$T/b513.om"
printf 'fn main to int\na = new uchar 4194305 0\nret 0\nend\n' > "$T/local.om"
printf 'fn main to int\na = new uchar 16777217 0\nret 0\nend\n' > "$T/arr.om"
awk 'BEGIN{for(i=0;i<64;i++)printf "global h%d uchar 16777216\n",i; print "global k uchar 1"; print "fn main to int"; print "ret 0"; print "end"}' > "$T/pools.om"
# a value nested 32768 deep: past what omc's own 8 MiB stack holds (32767 is accepted)
for d in 32767 32768; do
    { printf 'fn main to int\ny = ulong 7\nx = '; awk -v d=$d 'BEGIN { for (i = 0; i < d; i++) printf "ulong " }'; printf 'y\nret int rem x 256\nend\n'; } > "$T/v$d.om"
done
# an input one byte over the old 8 MiB buffer: a program after note lines
{ yes 'note padding' | head -c 8388609 | sed '$d'; printf 'fn main to int\nret 0\nend\n'; } > "$T/big.om"
# an input past the old static arena (16777216 words, 134217728 bytes), a program after note lines
{ yes 'note padding' | head -c 134217729 | sed '$d'; printf 'fn main to int\nret 0\nend\n'; } > "$T/arena.om"

accept g8193 "$T/g8193.om"
accept f4096 "$T/f4096.om"
accept b513 "$T/b513.om"
refuse local "$T/local.om" 23
refuse arr "$T/arr.om" 23
refuse pools "$T/pools.om" 23
accept v32767 "$T/v32767.om"
refuse v32768 "$T/v32768.om" 14
accept big "$T/big.om"
accept arena "$T/arena.om"
# the same input when the host refuses the arena's growth (prlimit --as=67108864): error 14, full=1
set +e; prlimit --as=67108864 "$S" < "$T/arena.om" > "$T/arenah.out" 2> "$T/arenah.err"; rc=$?; set -e
[ "$rc" = 14 ] || bad "arena under prlimit --as=67108864: exit $rc, wanted 14 ($(head -1 "$T/arenah.err"))"
grep -q '^omc-use 1 arena=[0-9]* .* full=1 ' "$T/arenah.err" || bad "arena under prlimit: no omc-use record with full=1"
say "PASS arena under prlimit --as=67108864 error 14 full=1"
rm -f "$T/arena.om" "$T/big.om"

say "PASS gate12 11 cases"
exit 0
