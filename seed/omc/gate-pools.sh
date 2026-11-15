#!/bin/sh
# gate-pools.sh [OMC] -- run-time pools (docs/RUNTIME-POOLS.md sections 3, 4, 5, 7 and 11). The compiler
# under test is the argument, else $OMC, else seed/out/omc. The control CTRL (environment) defaults to the
# base omc 1e628c80..., read from history (f615b139), with the pinned bool-field correction below. Cases: seed/omc/tests/pools
# (NAME.om, NAME.want: stdout, then `status N`). One line per check; last line RC=0 when all passed.
#  0. Controls: CTRL refuses `global P ulong *` (error 16) and `enlarge` (error 3), and every pools case.
#     The cases are generated: `python3 seed/omc/tests/pools/mk.py DIR` gives every committed NAME.om and
#     NAME.want byte for byte (fuzz.py writes the fuzz units at run time).
#  1. Growth and contents (g1): 0 -> 1 .. 4096 -> 2^20 -> 2^27 elements, a uchar pool past 16777216; old
#     values kept, new elements 0, an enlarge at or below the length changes nothing. gf: an f64 and an
#     f32 pool grown and moved, values read back across every grow, len, index = length traps 3.
#  2. Range (g2a-d): index = length traps 3 (exit 103) with no write past it; length + 1 is in range after
#     a grow; a number index past the length compiles (no error 21) and traps 3; a write slice past it.
#  3. Stale base (g3, g3i as OM-2 inline bodies): enlarge inside the value of put, the index of get and
#     the counts of read and write; strace shows mremap moved the regions and their addresses reused.
#     gr: a uchar pool filled by `read 0 P off n` from a pipe (seq 1 200000), n enlarging P every read.
#  4. Pinning (g4): an OM-2 unit whose first global is a pool; objdump shows the same set of X18..X26
#     written as the unit without the pool (g4base), so no pinned register holds the pool.
#  5. Contracts (g5a, g5b): `requires eq len P 0` and `invariant le i len P` are reported
#     `omc-check 1 kept ... rule=runtime` by om2 diag and evaluated at run time (exit 109, 110); a constant
#     index under unroll (g5c) and inline (g5d) keeps its run-time check. Control: len of a sized global
#     folds (g5ctl: erased rule=constant-true).
#  7. Fuzz differential: fuzz.py seeds $POOLS_FUZZ_SEEDS (default 1..8), 400 operations each, against a
#     Python list model, compared at every step (first differing step named).
#  8. Host refusal: under prlimit --as=268435456 enlarge returns -12 exactly, the pool is unchanged and the
#     program ends with its own status 7 (g8a; control: without the limit the same enlarge gives 0);
#     n * element size at or past 2^63 gives -22 (g8b). Recorded only: g8c touching 128 MiB under
#     systemd-run --user --scope -p MemoryMax=64M (expected 137), NOT_RUN without a user manager.
#  9. Untouched pages (g9): a 2 GiB pool with one page touched adds at most 16 kB of VmRSS; control:
#     touching 1024 more pages adds at least 3584 kB.
# 10. Refusals (err-*.om, exact `omc: line N: error K`, N `*` = any line); for the host-word and target
#     cases, the same unit with a sized global compiles (the pool is what is refused).
# 11. Byte identity: `git grep -nw enlarge` names no tracked unit outside tests/pools except in `note`
#     lines (comments, listed: omc.om documents its own keyword); every other tracked
#     .om gives the same status, stdout and stderr under OMC and CTRL, except the units
#     named in seed/omc/cabi/introduced.txt. Each line is the source sha256 and the path.
#     seed/omc/cabi/golden.sha256 is the stdout sha256, the stderr sha256, and the exit
#     from the compiler that wrote it (seed/omc/cabi/regen.sh, run by seed/units/regen.sh).
#     call.om and trap.om exit 0. The other six are refusals, pinned to that exit and to
#     the diagnostic bytes. The historical compiler must still refuse every one (error 16).
#     An unlisted file under seed/omc/cabi/, a missing file, a hash mismatch, or an extra
#     or unparseable line fails the gate. POOLS_SKIP_EQUIV=1 skips the comparison
#     (NOT_RUN); POOLS_EQUIV_MAX=N compares only the first N files.
#  S. Server (design 11, srv): 2000 requests of growing and shrinking size from one pool; enlarge calls
#     and growth syscalls (strace) equal the high-water marks of the model; VmRSS at the end is at most
#     the high-water VmRSS + 1024 kB. Control: the leak mode (stdin L) rises past it.
#  M. Mutants (mutants.tsv: NAME, CASE, MARKERS): omc.om with, for each marker m, the line after
#     `note POOLMUT m` replaced by the text after `note POOLMUT-ALT m ` (`note removed` deletes it),
#     compiled by OMC; it must compile g4base right and FAIL its CASE.
# POOLS_ONLY="1 3 M" runs only the named sections (0 always runs).
set -eu
O0=$(pwd)
R=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$R"
S=${1:-${OMC:-seed/out/omc}}
case $S in /*) ;; *) if [ -n "${1:-${OMC:-}}" ] && [ -x "$O0/$S" ]; then S=$O0/$S; else S=$R/$S; fi ;; esac
[ -x "$S" ] || { printf 'FAIL: %s missing\n' "$S" >&2; exit 1; }
T=seed/omc/tests/pools
mkdir -p build/seed
B=$(mktemp -d build/seed/pools.XXXXXX)
B=$R/$B
trap 'rm -rf "$B"' EXIT HUP INT TERM
bad() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }
on() { [ -z "${POOLS_ONLY:-}" ] && return 0; case " $POOLS_ONLY " in *" $1 "*) return 0 ;; esac; return 1; }
for t in python3 objdump strace prlimit timeout; do command -v $t > /dev/null || bad "$t not found"; done
printf abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN > $B/letters
seq 1 200000 > $B/seqin
{ cat $B/seqin; wc -c < $B/seqin; echo "status 0"; } > $B/gr.want
FUZZOPS=400
say "compiler under test $S $(sha256sum "$S" | cut -c1-16)"

BASE=1e628c80d5bd2ad0b08eb46d8abff66eff284a74e5a302e589c2d61cfe9f7347
if [ -n "${CTRL:-}" ]; then
  case $CTRL in /*) ;; *) CTRL=$O0/$CTRL ;; esac
  [ -x "$CTRL" ] || bad "control: $CTRL missing"
else
  git cat-file blob f615b139:seed/out/omc > $B/ctrl 2> /dev/null || bad "control: commit f615b139 is not in this clone"
  [ "$(sha256sum $B/ctrl | cut -d' ' -f1)" = $BASE ] || bad "control: f615b139:seed/out/omc is not omc $BASE"
  chmod +x $B/ctrl
  # Keep the historical no-pools implementation as the reference, with only the
  # independently reproduced bool-field opcode correction. No corpus row is skipped.
  mv "$B/ctrl" "$B/ctrl-raw"
  git cat-file blob f615b139:seed/omc/omc.om > "$B/ctrl-src.om"
  python3 - "$B/ctrl-raw" "$B/ctrl-src.om" "$B/ctrl" <<'PYBOOL'
from pathlib import Path
import hashlib, subprocess, sys
raw, source, out = map(Path, sys.argv[1:])
sha = lambda b: hashlib.sha256(b).hexdigest()
assert sha(raw.read_bytes()) == '1e628c80d5bd2ad0b08eb46d8abff66eff284a74e5a302e589c2d61cfe9f7347'
data = source.read_bytes()
assert sha(data) == 'de4099cad761a315d6bf9898bc29eb18b9eedddb568594d41e80d0de462f4199'
s = data.decode()
for fn, old, new in [
    ('ldop', 'if eq t 2', 'if or eq t 1 eq t 2'),
    ('stop', 'if or eq t 2 eq t 6', 'if or or eq t 1 eq t 2 eq t 6'),
]:
    start = s.index('fn '+fn+' t ulong to ulong\n')
    end = s.index('\nfn ', start + 1)
    part = s[start:end]
    assert part.count(old+'\n') == 1
    s = s[:start] + part.replace(old+'\n', new+'\n') + s[end:]
assert sha(s.encode()) == '33e993b566c5dbd36fa9d3a063584019485777841d4e4252655503bd9374b418'
image = subprocess.run([raw], input=s.encode(), capture_output=True, check=True, timeout=60).stdout
assert sha(image) == 'a0db6165a56811f1315cb445b037568a13bd40d82a155636a53550d123db8748'
out.write_bytes(image); out.chmod(0o700)
probe = b'struct W a uint f bool end\nfn main to int\nw = new W 1 false\nput w f true\nif get w f\nret 7\nend\nret 1\nend\n'
for compiler, want, suffix in [(raw, -4, 'raw'), (out, 7, 'corrected')]:
    p = subprocess.run([compiler], input=probe, capture_output=True, check=True, timeout=60)
    exe = out.with_name('bool-probe-'+suffix)
    exe.write_bytes(p.stdout); exe.chmod(0o700)
    result = subprocess.run([exe], capture_output=True, timeout=10)
    assert result.returncode == want, (suffix, result.returncode, want)
print('PASS historical control bool correction: original SIGILL, corrected exit 7; source and image pins match')
PYBOOL
  CTRL=$B/ctrl
fi
say "control $CTRL $(sha256sum "$CTRL" | cut -c1-16)"

firstdiff() { # firstdiff GOT WANT -> the first differing line (the step), on stdout
  awk 'NR == FNR { g[FNR] = $0; n = FNR; next }
       { m = FNR; if (!(FNR in g) || g[FNR] != $0) { printf "step %d: got \"%s\", wanted \"%s\"", FNR, (FNR in g) ? g[FNR] : "(nothing)", $0; f = 1; exit } }
       END { if (!f && n > m) printf "step %d: got \"%s\", wanted nothing", m + 1, g[m + 1] }' "$1" "$2"
}
regs() { # regs BIN -> the sorted set of X18..X26 that the code writes (ELF headers skipped)
  ph=$(od -An -j56 -N2 -tu2 "$1" | tr -d ' ')
  objdump -D -b binary -m aarch64 --start-address=$((64 + 56 * ph)) "$1" | awk -F'\t' 'NF >= 4 {
    m = $3; gsub(/ /, "", m)
    if (m ~ /^(st.*|cmp|cmn|tst|cbn?z|tbn?z|b|b\..*|bl|ret|br|blr|prfm)$/) next
    n = split($4, o, ","); k = (m ~ /^ldp/) ? 2 : 1
    for (j = 1; j <= k && j <= n; j++) { r = o[j]; gsub(/[ \t]/, "", r); sub(/^w/, "x", r)
      if (r ~ /^x(1[89]|2[0-6])$/) s[r] = 1 } }
    END { for (r in s) print r }' | sort | tr '\n' ' '
}
dline() { grep -nxF "$2" "$T/$1.om" | cut -d: -f1; }
ck() { # ck CC NAME: compile and run case NAME with compiler CC; 0 when it gives NAME.want, else 1 and $B/why
  cc=$1; n=$2; src=$T/$n.om; want=$T/$n.want; pre=; inp=/dev/null
  case $n in fuzz:*)
    s=${n#fuzz:}; src=$B/fz$s.om; want=$B/fz$s.want
    [ -f $src ] || python3 $T/fuzz.py $s $FUZZOPS $src $want ;;
  esac
  case $n in g3|g3i) inp=$B/letters ;; gr) inp=$B/seqin; want=$B/gr.want ;; g8a) pre="prlimit --as=268435456" ;; esac
  "$cc" < $src > $B/c.bin 2> $B/c.err; rc=$?
  [ $rc = 0 ] || { echo "$n: compile $rc ($(head -c 200 $B/c.err))" > $B/why; return 1; }
  chmod +x $B/c.bin
  if [ $n = gr ]; then cat $inp | $pre timeout ${TO:-300} $B/c.bin > $B/c.out 2> /dev/null; x=$?
  else $pre timeout ${TO:-300} $B/c.bin < $inp > $B/c.out 2> /dev/null; x=$?; fi
  echo "status $x" >> $B/c.out
  cmp -s $B/c.out $want || { echo "$n: $(firstdiff $B/c.out $want)" > $B/why; return 1; }
  case $n in
    g4) r1=$(regs $B/c.bin)
        "$cc" < $T/g4base.om > $B/c.base 2> /dev/null || { echo "g4base: compile failed" > $B/why; return 1; }
        r0=$(regs $B/c.base)
        [ "$r1" = "$r0" ] || { echo "g4: X18..X26 written {$r1}, without the pool {$r0}" > $B/why; return 1; }
        echo "$r1" > $B/regs ;;
    g5a|g5b)
        if [ $n = g5a ]; then L=$(dline g5a 'requires eq len P 0'); k=requires; else L=$(dline g5b 'invariant le i len P'); k=invariant; fi
        w="omc-check 1 kept line=$L rule=runtime kind=$k"
        grep -qxF "$w" $B/c.err || { echo "$n: no '$w' in om2 diag ($(grep omc-check $B/c.err | head -2 | tr '\n' ';'))" > $B/why; return 1; } ;;
  esac
  return 0
}
run() { # run NAME: ck with the compiler under test, or fail the gate
  ck "$S" $1 || bad "$(cat $B/why)"
}

# 0. controls: the base compiler does not know the new words
printf 'global P ulong *\nfn main to int\nret 0\nend\n' > $B/w.om
"$CTRL" < $B/w.om > /dev/null 2> $B/w.err && bad "control: CTRL accepted 'global P ulong *'"
[ "$(head -1 $B/w.err)" = "omc: line 1: error 16" ] || bad "control: CTRL on 'global P ulong *': $(head -1 $B/w.err)"
printf 'global P ulong 4\nfn main to int\nr = enlarge P ulong 8\nret 0\nend\n' > $B/w.om
"$CTRL" < $B/w.om > /dev/null 2> $B/w.err && bad "control: CTRL accepted enlarge"
[ "$(head -1 $B/w.err)" = "omc: line 3: error 3" ] || bad "control: CTRL on enlarge: $(head -1 $B/w.err)"
say "PASS control: CTRL refuses 'global P ulong *' (error 16) and enlarge (error 3)"
set +e; python3 $T/mk.py $B/regen > $B/regen.log 2>&1; rc=$?; set -e
[ $rc = 0 ] || bad "control: mk.py exit $rc ($(head -c 200 $B/regen.log))"
n=0
for f in $B/regen/*; do
  cmp -s $f $T/$(basename $f) || bad "control: mk.py output $(basename $f) differs from $T/$(basename $f)"
  n=$((n + 1))
done
for f in $T/*.om $T/*.want; do [ -f $B/regen/$(basename $f) ] || bad "control: $f is not written by mk.py"; done
say "PASS control: mk.py (exit 0) regenerates all $n committed case files byte for byte"
n=0
for f in $T/g*.om $T/srv.om; do
  c=$(basename $f .om); case $c in g4base|g5ctl) continue ;; esac
  "$CTRL" < $f > /dev/null 2> $B/w.err && bad "control: CTRL accepted $c"
  grep -q '^omc: line [0-9]*: error \(16\|3\)$' $B/w.err || bad "control: CTRL on $c: $(head -1 $B/w.err)"
  n=$((n + 1))
done
say "PASS control: CTRL refuses all $n pools cases (error 16 or 3)"

# 1. growth and contents
if on 1; then
  run g1; say "PASS 1 growth: g1 0..2^27 elements, uchar pool past 16777216, old kept, new 0"
  run gf; say "PASS 1 growth: gf f64 and f32 pools grown 40 times beside a blocker pool, values kept, len, index = len traps 3"
fi

# 2. range
if on 2; then
  for c in g2a g2b g2c g2d; do run $c; say "PASS 2 range: $c, $(sed -n '1s/^note gate-pools 2: //p' $T/$c.om | cut -c1-110)"; done
fi

# 3. stale base
if on 3; then
  for c in g3 g3i; do
    run $c
    strace -f -qq -e trace=mmap,mremap,munmap -o $B/st $B/c.bin < $B/letters > /dev/null 2>&1 || true
    mr=$(python3 - $B/st << 'EOF'
import re, sys
moves = reuse = 0; freed = []
def hit(a, l):
    return any(f < a + l and a < f + fl for f, fl in freed)
for line in open(sys.argv[1]):
    m = re.search(r"mremap\((0x[0-9a-f]+), (\d+), (\d+), [^)]*\) = (0x[0-9a-f]+)", line)
    if m:
        old, ol, nl, new = int(m[1], 16), int(m[2]), int(m[3]), int(m[4], 16)
        if new != old:
            reuse += hit(new, nl); moves += 1; freed.append((old, ol))
        continue
    m = re.search(r"mmap\(NULL, (\d+),.*\) = (0x[0-9a-f]+)", line)
    if m:
        reuse += hit(int(m[2], 16), int(m[1]))
print(moves, reuse)
EOF
)
    set -- $mr
    [ "$1" -gt 0 ] && [ "$2" -gt 0 ] || bad "3 $c: mremap moves $1, address reuses $2 (both must be above 0)"
    say "PASS 3 stale base: $c right after $1 moving mremaps and $2 reuses of a vacated address"
  done
  run gr
  say "PASS 3 stale base: gr read 0 P off n from a pipe, n enlarging P before each read: $(wc -c < $B/seqin) bytes back"
fi

# 4. pinning
if on 4; then run g4; say "PASS 4 pinning: g4 X18..X26 written {$(cat $B/regs | sed 's/ $//')} = g4base's; output right"; fi

# 5. contracts
if on 5; then
  run g5a; say "PASS 5 contracts: g5a requires eq len P 0 kept rule=runtime, false after the grow (109)"
  run g5b; say "PASS 5 contracts: g5b invariant le i len P kept rule=runtime, false at 9 (110)"
  run g5c; say "PASS 5 contracts: g5c constant index under unroll keeps its run-time check (103)"
  run g5d; say "PASS 5 contracts: g5d constant index in an inline body keeps its run-time check (103)"
  "$S" < $T/g5ctl.om > /dev/null 2> $B/w.err || bad "5 control: g5ctl does not compile"
  w="omc-check 1 erased line=$(dline g5ctl 'requires eq len G 8') rule=constant-true kind=requires"
  grep -qxF "$w" $B/w.err || bad "5 control: g5ctl has no '$w'"
  say "PASS 5 control: len of a sized global folds (g5ctl erased rule=constant-true)"
fi

# 7. fuzz differential
if on 7; then
  for s in ${POOLS_FUZZ_SEEDS:-1 2 3 4 5 6 7 8}; do
    run fuzz:$s
    say "PASS 7 fuzz seed $s: $(($(wc -l < $B/fz$s.want) - 1)) steps equal to the list model, $(tail -1 $B/fz$s.want)"
  done
fi

# 8. host refusal
if on 8; then
  run g8a; say "PASS 8 refusal: g8a under prlimit --as=268435456 enlarge gives -12, pool unchanged, own status 7"
  timeout 300 $B/c.bin > $B/c.out 2> /dev/null || true
  [ "$(sed -n 2p $B/c.out)" = 0 ] || bad "8 control: without the limit the 8 GiB enlarge gave '$(sed -n 2p $B/c.out)', wanted 0"
  say "PASS 8 control: without the limit the same 8 GiB enlarge gives 0"
  run g8b; say "PASS 8 overflow: g8b n * size at or past 2^63 gives -22, just below -12, pool unchanged"
  "$S" < $T/g8c.om > $B/g8c 2> $B/w.err || bad "8 g8c: compile failed ($(head -1 $B/w.err))"
  chmod +x $B/g8c
  if systemd-run --user --scope -q true > /dev/null 2>&1; then
    set +e; systemd-run --user --scope -q -p MemoryMax=64M $B/g8c > /dev/null 2>&1; x=$?; set -e
    say "RECORD 8 cgroup: g8c touching 128 MiB under systemd-run --user --scope -p MemoryMax=64M: exit $x (expected 137)"
  else
    say "NOT_RUN 8 cgroup: systemd-run --user is unavailable (g8c, MemoryMax=64M)"
  fi
fi

# 9. untouched pages
if on 9; then
  "$S" < $T/g9.om > $B/g9 2> $B/w.err || bad "9: compile failed ($(head -1 $B/w.err))"
  chmod +x $B/g9
  set +e; timeout 300 $B/g9 > $B/g9.out; x=$?; set -e
  [ $x = 0 ] || bad "9: g9 exit $x"
  set -- $(cat $B/g9.out)
  [ "$1" = 2147483648 ] || bad "9: len $1"
  [ $(($3 - $2)) -le 16 ] || bad "9: a 2 GiB pool with one page touched added $(($3 - $2)) kB of VmRSS (at most 16)"
  [ $(($4 - $3)) -ge 3584 ] || bad "9 control: 1024 pages touched added only $(($4 - $3)) kB"
  say "PASS 9 untouched pages: 2 GiB pool, one page touched: VmRSS +$(($3 - $2)) kB; control 1024 pages: +$(($4 - $3)) kB"
fi

# 10. refusals
if on 10; then
  n=0
  for f in $T/err-*.om; do
    c=$(basename $f .om); w=$(cat $T/$c.want)
    set +e; "$S" < $f > /dev/null 2> $B/w.err; rc=$?; set -e
    k=${w##* }; got=$(head -1 $B/w.err)
    [ $rc = $k ] || bad "10 $c: status $rc ($got), wanted error $k"
    case $w in
      *"line *:"*) case $got in "omc: line "*": error $k") ;; *) bad "10 $c: '$got'" ;; esac ;;
      *) [ "$got" = "$w" ] || bad "10 $c: '$got', wanted '$w'" ;;
    esac
    n=$((n + 1))
  done
  say "PASS 10 refusals: $n units refused with their exact code and line"
  for c in err-x86 err-devctl err-mapwrite; do
    sed 's/^global P \([a-z0-9]*\) \*$/global P \1 64/; s/^r = enlarge P .*/r = long 0/' $T/$c.om > $B/tw.om
    "$S" < $B/tw.om > /dev/null 2> $B/w.err || bad "10 control: $c with a sized global: $(head -1 $B/w.err)"
  done
  say "PASS 10 control: err-x86, err-devctl, err-mapwrite compile with a sized global in place of the pool"
fi

# 11. byte identity
if on 11; then
  git grep -nw enlarge -- '*.om' '*.omegese' | grep -v "^$T/" > $B/scan || true
  grep -v '^[^:]*:[0-9]*:note ' $B/scan > $B/scanuse || true
  sed 's/^/SCAN /' $B/scan | cut -c1-160
  # Units that use the word on purpose are listed by name in $T/enlarge-users.txt (design 7.11: "except the files
  # that name enlarge, listed by name"); any other user fails, and the listed ones leave the byte identity list.
  cut -d: -f1 $B/scanuse | sort -u > $B/users
  grep -v '^#' $T/enlarge-users.txt | sort -u > $B/allowed
  # An exemption must name an actual tracked unit with the excluded feature.
  # This also prevents a future file being exempted outside its own change.
  while IFS= read -r unit; do
    [ -n "$unit" ] || bad "11 inventory: blank entry"
    case "$unit" in *.om) ;; *) bad "11 inventory: not an Omega unit: $unit" ;; esac
    [ -f "$unit" ] && git --literal-pathspecs ls-files --error-unmatch -- "$unit" > /dev/null 2>&1 ||
      bad "11 inventory: not a tracked file: $unit"
    grep -qxF "$unit" "$B/users" || grep -qE '^global [^ ]+ [^ ]+ \*$' "$unit" ||
      bad "11 inventory: no enlarge or run-time pool declaration: $unit"
  done < $B/allowed
  if [ -n "$(comm -23 $B/users $B/allowed)" ]; then bad "11 scan: units use enlarge outside $T and are not listed in $T/enlarge-users.txt: $(comm -23 $B/users $B/allowed | tr '\n' ' ')"; fi
  say "PASS 11 scan: git grep -nw enlarge outside $T: $(wc -l < $B/scan) lines; units using the word: $(tr '\n' ' ' < $B/users)(each listed in enlarge-users.txt); the rest are notes"
  # FR-7. The list is the lines of introduced.txt, not the directory.
  intro=seed/omc/cabi/introduced.txt
  gold=seed/omc/cabi/golden.sha256
  [ -f "$intro" ] || bad "11 FR-7: $intro is missing"
  [ -f "$gold" ] || bad "11 FR-7: $gold is missing"
  : > $B/fr7
  : > $B/fr7src
  nline=0
  while IFS= read -r line || [ -n "$line" ]; do
    nline=$((nline + 1))
    printf '%s\n' "$line" | grep -Eq '^[0-9a-f]{64} seed/omc/cabi/[A-Za-z0-9._-]+\.om$' \
      || bad "11 FR-7: unparseable line $nline in $intro"
    sum=${line%% *}
    path=${line#* }
    grep -qxF "$path" $B/fr7 && bad "11 FR-7: duplicate $path"
    printf '%s\n' "$path" >> $B/fr7
    printf '%s %s\n' "$sum" "$path" >> $B/fr7src
  done < "$intro"
  [ "$nline" = 8 ] || bad "11 FR-7: $intro has $nline lines, wanted the 8 units"
  : > $B/fr7g
  nline=0
  while IFS= read -r line || [ -n "$line" ]; do
    nline=$((nline + 1))
    printf '%s\n' "$line" | grep -Eq '^[0-9a-f]{64} [0-9a-f]{64} [0-9]+ seed/omc/cabi/[A-Za-z0-9._-]+\.om$' \
      || bad "11 FR-7: unparseable line $nline in $gold"
    rest=${line#* }
    errsum=${rest%% *}
    rest=${rest#* }
    gexit=${rest%% *}
    path=${rest#* }
    grep -qxF "$path" $B/fr7g && bad "11 FR-7: duplicate golden $path"
    printf '%s\n' "$path" >> $B/fr7g
    printf '%s %s %s %s\n' "${line%% *}" "$errsum" "$gexit" "$path" >> $B/fr7grow
  done < "$gold"
  [ "$nline" = 8 ] || bad "11 FR-7: $gold has $nline lines, wanted the 8 units"
  sort $B/fr7 > $B/fr7s
  sort $B/fr7g > $B/fr7gs
  cmp -s $B/fr7s $B/fr7gs || bad "11 FR-7: introduced.txt and golden.sha256 name different units"
  git ls-files 'seed/omc/cabi/*.om' | sort > $B/fr7tracked
  cmp -s $B/fr7s $B/fr7tracked || bad "11 FR-7: tracked units and introduced.txt differ: $(comm -3 $B/fr7s $B/fr7tracked | tr '\n' ' ')"
  git ls-files 'seed/omc/cabi' | sort > $B/cabiall
  printf '%s\n' \
    seed/omc/cabi/call.c \
    seed/omc/cabi/trap.c \
    seed/omc/cabi/introduced.txt \
    seed/omc/cabi/golden.sha256 \
    seed/omc/cabi/regen.sh \
    | sort > $B/cabiok
  sort -u $B/fr7s $B/cabiok > $B/cabiwant
  extra=$(comm -23 $B/cabiall $B/cabiwant || true)
  [ -z "$extra" ] || bad "11 FR-7: unlisted file under seed/omc/cabi/: $(printf '%s' "$extra" | tr '\n' ' ')"
  while read -r sum path; do
    [ -f "$path" ] || bad "11 FR-7: missing $path"
    have=$(sha256sum < "$path" | cut -c1-64)
    [ "$have" = "$sum" ] || bad "11 FR-7: source hash mismatch $path"
  done < $B/fr7src
  : > $B/fr7
  while read -r outsum errsum gexit path; do
    set +e
    timeout 60 "$S" < "$path" > $B/ea 2> $B/eae; a=$?
    timeout 60 "$CTRL" < "$path" > $B/eb 2> $B/ebe; b=$?
    set -e
    [ "$b" = 16 ] && grep -q 'error 16$' $B/ebe || bad "11 FR-7: historical compiler did not refuse $path (status $b)"
    [ "$a" = "$gexit" ] || bad "11 FR-7: $path status $a, golden $gexit"
    got=$(sha256sum < $B/ea | cut -c1-64)
    [ "$got" = "$outsum" ] || bad "11 FR-7: $path output hash $got, golden $outsum"
    got=$(sha256sum < $B/eae | cut -c1-64)
    [ "$got" = "$errsum" ] || bad "11 FR-7: $path diagnostic hash $got, golden $errsum"
    printf '%s\n' "$path" >> $B/fr7
  done < $B/fr7grow
  printf 'fn main to int\nret 0\nend\n' > $B/fr7mut.om
  set +e
  timeout 60 "$CTRL" < $B/fr7mut.om > $B/eb 2> $B/ebe; b=$?
  set -e
  if [ "$b" = 16 ] && grep -q 'error 16$' $B/ebe; then
    bad "11 FR-7 mutant: the historical compiler refused an ordinary program, so the refusal check cannot go red"
  fi
  say "PASS 11 FR-7: 8 units, source and output pinned; historical compiler refuses each (error 16)"
  if [ "${POOLS_SKIP_EQUIV:-0}" = 1 ]; then
    say "NOT_RUN 11 byte identity (POOLS_SKIP_EQUIV=1)"
  else
    git ls-files '*.om' | grep -v "^$T/" | grep -vxF -f $B/allowed | grep -vxF -f $B/fr7 > $B/files
    [ -z "${POOLS_EQUIV_MAX:-}" ] || { head -n "$POOLS_EQUIV_MAX" $B/files > $B/f2; mv $B/f2 $B/files; }
    n=0; d=0
    while read -r f; do
      n=$((n + 1))
      set +e
      timeout 60 "$S" < "$f" > $B/ea 2> $B/eae; a=$?
      timeout 60 "$CTRL" < "$f" > $B/eb 2> $B/ebe; b=$?
      set -e
      if [ $a != $b ] || ! cmp -s $B/ea $B/eb || ! cmp -s $B/eae $B/ebe; then d=$((d + 1)); say "DIFF $f $a $b"; fi
    done < $B/files
    [ $d = 0 ] || bad "11 byte identity: $d of $n units differ"
    "$S" < $T/g1.om > $B/ea 2> $B/eae || true; "$CTRL" < $T/g1.om > $B/eb 2> $B/ebe || true
    ! cmp -s $B/eae $B/ebe || bad "11 control: the comparison does not tell g1 apart"
    say "PASS 11 byte identity: $n tracked units, status stdout stderr equal under OMC and CTRL${POOLS_EQUIV_MAX:+ (first $POOLS_EQUIV_MAX only)}; control g1 differs"
  fi
fi

# S. server
if on S; then
  "$S" < $T/srv.om > $B/srv 2> $B/w.err || bad "S: compile failed ($(head -1 $B/w.err))"
  chmod +x $B/srv
  set +e; timeout 300 strace -f -qq -e trace=mmap,mremap -o $B/st $B/srv < /dev/null > $B/srv.out; x=$?; set -e
  [ $x = 0 ] || bad "S: srv exit $x"
  set -- $(cat $B/srv.out)
  w() { sed -n "s/^$1 //p" $T/srv.want; }
  [ "$1" = "$(w hw)" ] && [ "$2" = "$(w calls)" ] && [ "$3" = "$(w marks)" ] && [ "$6" = "$(w cs)" ] ||
    bad "S: hw $1 calls $2 marks $3 cs $6, wanted $(tr '\n' ' ' < $T/srv.want)"
  sc=$(grep -c 'm\(re\)\?map(' $B/st)
  [ "$sc" = "$3" ] || bad "S: $sc mmap/mremap calls, wanted one per high-water mark ($3)"
  [ "$4" -ge 65536 ] || bad "S: VmRSS at the high-water point $4 kB, below the 64 MiB served"
  [ "$5" -le $(($4 + 1024)) ] || bad "S: VmRSS $5 kB at the end, high-water $4 kB (+1024 allowed)"
  say "PASS S server: 2000 requests, $2 enlarge calls = $sc growth syscalls = $3 marks; VmRSS $4 kB at high-water, $5 kB at end"
  set +e; printf L | timeout 300 $B/srv > $B/leak.out; x=$?; set -e
  set -- $(cat $B/leak.out)
  [ $x = 0 ] && [ "$5" -gt $(($4 + 1024)) ] || bad "S control: the leak mode gave exit $x, VmRSS $4 -> $5 kB"
  say "PASS S control: enlarging per request raises VmRSS $4 -> $5 kB (the check trips)"
fi

# M. mutants
if on M; then
  fails=0
  while IFS='	' read -r name case marks; do
    [ -n "$name" ] || continue
    cp seed/omc/omc.om $B/m.om; why=
    for m in $(echo "$marks" | tr , ' '); do
      cnt=$(awk -v t="note POOLMUT $m" -v p="note POOLMUT-ALT $m " '$0 == t { c++ } index($0, p) == 1 { a++ } END { print c + 0, a + 0 }' $B/m.om)
      [ "$cnt" = "1 1" ] || { why="marker missing"; [ "$cnt" = "0 0" ] || why="marker $m found $cnt times (target, alt)"; break; }
      awk -v t="note POOLMUT $m" -v p="note POOLMUT-ALT $m " '
        NR == FNR { if (index($0, p) == 1) alt = substr($0, length(p) + 1); next }
        skip { skip = 0; if (alt != "note removed") print alt; next }
        { print } $0 == t { skip = 1 }' $B/m.om $B/m.om > $B/m2.om
      ! cmp -s $B/m.om $B/m2.om || { why="marker $m changes nothing"; break; }
      mv $B/m2.om $B/m.om
    done
    if [ -n "$why" ]; then say "MUTANT $name NOT_BUILT: $why"; fails=$((fails + 1)); continue; fi
    if ! "$S" < $B/m.om > $B/mutomc 2> $B/w.err; then
      say "MUTANT $name NOT_BUILT: omc refuses the mutated omc.om ($(head -1 $B/w.err))"; fails=$((fails + 1)); continue
    fi
    chmod +x $B/mutomc
    if ! TO=120 ck $B/mutomc g4base; then
      say "MUTANT $name NOT_BUILT: the mutant compiles g4base wrong ($(cat $B/why))"; fails=$((fails + 1)); continue
    fi
    if TO=120 ck $B/mutomc $case; then
      say "FAIL mutant $name ($marks): $case passed"; fails=$((fails + 1))
    else
      say "PASS mutant $name ($marks): caught by $case: $(cat $B/why | cut -c1-160)"
    fi
  done < $T/mutants.tsv
  [ $fails = 0 ] || bad "$fails mutants not built or not caught"
fi

say "PASS gate-pools${POOLS_ONLY:+ (sections 0 $POOLS_ONLY only)}"
say "RC=0"
