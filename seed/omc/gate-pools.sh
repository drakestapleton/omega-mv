#!/bin/sh
# gate-pools.sh [OMC] -- run-time pools (docs/RUNTIME-POOLS.md sections 3, 4, 5, 7 and 11). The compiler
# under test is the argument, else $OMC, else seed/out/omc. The control CTRL (environment) defaults to the
# historical compiler selected and checked by CTRL_REF and BASE below, with the pinned bool-field correction
# (BASEFIX) applied to its source. Cases: seed/omc/tests/pools
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
# 11. Compile every tracked unit outside the separately qualified pools directory with CTRL and S.
#     Both accept: exact bytes/status/diagnostics, and any new-keyword declaration is false. CTRL refuses/S accepts:
#     declaration + new-global token + owner that actually compiled these bytes with status 0 and exited 0.
#     S refuses with a new token: declared refusal test; owner must compile these bytes to that refusal and exit 0.
#     Both refuse without a token: exact status/stdout/stderr. New refusal without a token fails.
#     Declarations name owner=PATH; each owner runs once under a generated recording compiler, bound to this head
#     by absolute compiler path and a per-invocation compiler-binary hash. No source-pattern coverage guesses.
#     keyword-users.om is compiled directly here (no recursion). See docs/RUNTIME-POOLS.md section 7.11.
#     A custom CTRL without pinned source mapping, POOLS_SKIP_EQUIV=1, or a partial/zero POOLS_EQUIV_MAX gives
#     NOT_RUN/exit3; subsequent S/M sections still run and their failures return exit1. An empty exact set fails.
#     POOLS_WORKDIR=NEW_DIRECTORY retains raw owner records and probe sources outside the tracked tree.
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
if [ -n "${POOLS_WORKDIR:-}" ]; then
  B=$(readlink -m "$POOLS_WORKDIR") || exit 1
  mkdir "$B" || { echo "FAIL: evidence work directory must be new: $B" >&2; exit 1; }
else
  B=$(mktemp -d build/seed/pools.XXXXXX)
  B=$R/$B
  trap 'rm -rf "$B"' EXIT HUP INT TERM
fi
bad() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }
on() { [ -z "${POOLS_ONLY:-}" ] && return 0; case " $POOLS_ONLY " in *" $1 "*) return 0 ;; esac; return 1; }
for t in python3 objdump strace prlimit timeout; do command -v $t > /dev/null || bad "$t not found"; done
printf abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN > $B/letters
seq 1 200000 > $B/seqin
{ cat $B/seqin; wc -c < $B/seqin; echo "status 0"; } > $B/gr.want
FUZZOPS=400
say "compiler under test $S $(sha256sum "$S" | cut -c1-16)"

CTRL_REF=f615b139
BASE=1e628c80d5bd2ad0b08eb46d8abff66eff284a74e5a302e589c2d61cfe9f7347
BASEFIX=a0db6165a56811f1315cb445b037568a13bd40d82a155636a53550d123db8748
if [ -n "${CTRL:-}" ]; then
  case $CTRL in /*) ;; *) CTRL=$O0/$CTRL ;; esac
  [ -x "$CTRL" ] || bad "control: $CTRL missing"
else
  if ! git cat-file blob "$CTRL_REF:seed/out/omc" > $B/ctrl 2> /dev/null; then
    # A shallow clone lacks the history this gate reads; that is NOT_RUN with the reason, not a failure of the head.
    [ "$(git rev-parse --is-shallow-repository 2> /dev/null || echo unknown)" = true ] || bad "control: commit $CTRL_REF is not in this clone"
    say "NOT_RUN gate-pools: shallow clone: control commit $CTRL_REF is not in this clone; no section was run (a full clone is needed)"
    say 'RC=3'
    exit 3
  fi
  [ "$(sha256sum $B/ctrl | cut -d' ' -f1)" = $BASE ] || bad "control: $CTRL_REF:seed/out/omc is not omc $BASE"
  chmod +x $B/ctrl
  # Keep the historical no-pools implementation as the reference, with only the
  # independently reproduced bool-field opcode correction. No corpus row is skipped.
  mv "$B/ctrl" "$B/ctrl-raw"
  git cat-file blob "$CTRL_REF:seed/omc/omc.om" > "$B/ctrl-src.om"
  python3 - "$B/ctrl-raw" "$B/ctrl-src.om" "$B/ctrl" "$BASE" "$BASEFIX" <<'PYBOOL'
from pathlib import Path
import hashlib, subprocess, sys
raw, source, out = map(Path, sys.argv[1:4])
base_pin, fixed_pin = sys.argv[4:6]
sha = lambda b: hashlib.sha256(b).hexdigest()
def need(ok, what):
    # Explicit checks, not assert: python3 -O (or PYTHONOPTIMIZE) must not turn these pins into no-ops.
    if not ok:
        sys.exit('historical control: ' + what)
need(sha(raw.read_bytes()) == base_pin, 'raw compiler sha256 differs from BASE')
data = source.read_bytes()
need(sha(data) == 'de4099cad761a315d6bf9898bc29eb18b9eedddb568594d41e80d0de462f4199', 'source sha256 differs from the pinned control source')
s = data.decode()
for fn, old, new in [
    ('ldop', 'if eq t 2', 'if or eq t 1 eq t 2'),
    ('stop', 'if or eq t 2 eq t 6', 'if or or eq t 1 eq t 2 eq t 6'),
]:
    start = s.index('fn '+fn+' t ulong to ulong\n')
    end = s.index('\nfn ', start + 1)
    part = s[start:end]
    need(part.count(old+'\n') == 1, 'correction site in fn ' + fn + ' is not exactly one line')
    s = s[:start] + part.replace(old+'\n', new+'\n') + s[end:]
need(sha(s.encode()) == '33e993b566c5dbd36fa9d3a063584019485777841d4e4252655503bd9374b418', 'corrected source sha256 differs')
image = subprocess.run([raw], input=s.encode(), capture_output=True, check=True, timeout=60).stdout
need(sha(image) == fixed_pin, 'corrected image sha256 differs from BASEFIX')
out.write_bytes(image); out.chmod(0o700)
probe = b'struct W a uint f bool end\nfn main to int\nw = new W 1 false\nput w f true\nif get w f\nret 7\nend\nret 1\nend\n'
for compiler, want, suffix in [(raw, -4, 'raw'), (out, 7, 'corrected')]:
    p = subprocess.run([compiler], input=probe, capture_output=True, check=True, timeout=60)
    exe = out.with_name('bool-probe-'+suffix)
    exe.write_bytes(p.stdout); exe.chmod(0o700)
    result = subprocess.run([exe], capture_output=True, timeout=10)
    need(result.returncode == want, f'bool probe {suffix} exit {result.returncode}, wanted {want}')
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

# 11. byte identity and new-keyword acceptance/refusal qualification.
# Classification is the pair of actual compiler outcomes, never a source-based exclusion list.
OMCMAXCODE11=$(awk -F'|' '$1=="omc" && $2 ~ /^[0-9]+$/ {if ($2+0>m) m=$2+0} END {print m+0}' seed/omc/error-codes.reg) || bad '11 instrument: reading the error-code registry failed'
[ "$OMCMAXCODE11" -gt 0 ] || bad '11 instrument: no omc exit codes in seed/omc/error-codes.reg'
lexer11() {
  K11=seed/omc/keyword-users.om
  git log --format=%H --diff-filter=A -- "$K11" > "$B/lexer-introductions"
  nk=$(wc -l < "$B/lexer-introductions")
  if [ "$nk" = 1 ]; then kr=$(cat "$B/lexer-introductions");
  elif [ "$nk" = 0 ] && ! git cat-file -e "HEAD:$K11" 2>/dev/null; then kr=HEAD;
  else bad "11 keywords: cannot establish lexer seed provenance"; fi
  git show "$kr:seed/out/omc" > "$B/lexer-cc" || bad "11 keywords: lexer seed compiler unavailable"
  chmod +x "$B/lexer-cc"
  "$B/lexer-cc" < "$K11" > "$B/keyword-tool" 2> "$B/keyword-build.err" || bad "11 keywords: lexer build: $(cat "$B/keyword-build.err")"
  chmod +x "$B/keyword-tool"
  printf 'enlarge\n' > "$B/enlarge-word"
}
words11() {
  git show "$CTRL_REF:seed/omc/genkw.awk" > "$B/control-genkw.awk" || bad "11 keywords: historical control generator unavailable"
  awk -f "$B/control-genkw.awk" > "$B/control-kw.body" || bad "11 keywords: control generator failed"
  awk -f seed/omc/genkw.awk > "$B/current-kw.body" || bad "11 keywords: current generator failed"
  printf 'fn kw w ulong to ulong\n' > "$B/control-kw.om" || bad '11 instrument: keyword unit header failed'
  cat "$B/control-kw.body" >> "$B/control-kw.om" || bad '11 instrument: keyword body read failed'
  printf 'ret 0\nend\n' >> "$B/control-kw.om" || bad '11 instrument: keyword unit footer failed'
  printf 'fn kw w ulong to ulong\n' > "$B/current-kw.om" || bad '11 instrument: keyword unit header failed'
  cat "$B/current-kw.body" >> "$B/current-kw.om" || bad '11 instrument: keyword body read failed'
  printf 'ret 0\nend\n' >> "$B/current-kw.om" || bad '11 instrument: keyword unit footer failed'
  frame11 D "$B/derive-input" "$B/control-kw.om" "$B/current-kw.om"
  "$B/keyword-tool" < "$B/derive-input" > "$B/new-keywords.u" || bad "11 keywords: derivation failed"
  sort -u "$B/new-keywords.u" > "$B/new-keywords"
  say "KEYWORDS 11 control-source=$CTRL_REF generator=$(sha256sum "$B/control-genkw.awk" | cut -d' ' -f1) current-generator=$(sha256sum seed/omc/genkw.awk | cut -d' ' -f1) lexer-seed=$kr lexer-source=$(sha256sum "$K11" | cut -d' ' -f1) lexer-binary=$(sha256sum "$B/keyword-tool" | cut -d' ' -f1)"
  sed 's/^/NEWGLOBAL /' "$B/new-keywords"
}

frame11() { # MODE OUTPUT INPUT...: construct the whole frame with every producer checked before invoking the lexer.
  fm=$1; fo=$2; shift 2
  printf '%s\n' "$fm" > "$fo" || bad '11 instrument: creating frame failed'
  firstframe=1
  for fi in "$@"; do
    if [ "$firstframe" = 0 ]; then printf '\000' >> "$fo" || bad '11 instrument: framing separator failed'; fi
    cat "$fi" >> "$fo" || bad "11 instrument: unreadable frame input $fi"
    firstframe=0
  done
}
uses11() { # SOURCE WORDS OUT: 0 token found, 1 absent; I/O or instrument errors fail, never mean absence.
  ui=$B/use-input
  printf 'U\n' > "$ui" || bad "11 instrument: cannot construct input for $1"
  cat "$2" >> "$ui" || bad "11 instrument: unreadable word list $2 for $1"
  printf '\000' >> "$ui" || bad "11 instrument: cannot frame input for $1"
  cat "$1" >> "$ui" || bad "11 instrument: unreadable source $1"
  if "$B/keyword-tool" < "$ui" > "$3"; then ur=0; else ur=$?; fi
  [ "$ur" -le 1 ] || bad "11 instrument: token checker exit $ur on $1"
  return "$ur"
}
pooluses11() { # SOURCE: lexical line-start global NAME TYPE * shape, with real compiler-token boundaries.
  [ -r "$1" ] || bad "11 instrument: unreadable pool declaration source $1"
  printf 'P\n\000' > "$B/pool-input" || bad '11 instrument: framing pool declaration input failed'
  cat "$1" >> "$B/pool-input" || bad '11 instrument: reading pool declaration source failed'
  if "$B/keyword-tool" < "$B/pool-input" > "$B/pool-output"; then pr=0; else pr=$?; fi
  [ "$pr" -le 1 ] || bad "11 instrument: pool declaration lexer exit $pr"
  return "$pr"
}
compile11() { # COMPILER SOURCE PREFIX
  [ -r "$2" ] || bad "11 instrument: unreadable compile source $2"
  if timeout 60 "$1" < "$2" > "$3.bin" 2> "$3.err"; then cr=0; else cr=$?; fi
  # The ceiling is the largest omc exit code in seed/omc/error-codes.reg, not a typed number.
  [ "$cr" -le "$OMCMAXCODE11" ] || bad "11 instrument: compiler exit $cr on $2 (registry maximum $OMCMAXCODE11)"
  printf '%s\n' "$cr" > "$3.exit" || bad "11 instrument: recording compiler status failed"
}
strict11() { # SOURCE OLD NEW: identical status, stdout and stderr (also covers refusal/refusal).
  sa=$(cat "$2.exit") || bad "11 instrument: reading status failed"
  sb=$(cat "$3.exit") || bad "11 instrument: reading status failed"
  if [ "$sa" != "$sb" ] || ! cmp -s "$2.bin" "$3.bin" || ! cmp -s "$2.err" "$3.err"; then
    echo "DIFF $1 status=$sa/$sb (exact status stdout stderr comparison)"; return 1
  fi
  return 0
}
declaration11() { # UNIT: WORD<TAB>OWNER rows using valid compiler blanks; malformed/duplicate intent markers fail.
  awk '
    { line=$0; gsub(/[ \t\r]+/, " ", line); sub(/^ +/, "", line)
      if (line ~ /gate-pools: *uses/) {
        nf=split(line,a," ")
        if (a[1]!="note" || a[2]!="gate-pools:" || a[3]!="uses" || a[4] !~ /^[A-Za-z_][A-Za-z0-9_]*$/ ||
            a[5]!="on" || a[6]!="purpose:" || a[7] !~ /^owner=[A-Za-z0-9_.\/-]+$/ || nf<8 || seen[a[4]]++) bad=1
        else print a[4] "\t" substr(a[7],7)
      }
    }
    END {if(bad) exit 2}' "$1"
}
makerecorder11() { # OUTPUT REAL LOG: bind compiler and recording path in the generated script (execprog clears env).
  { printf '#!/bin/sh\n';
    for binding in real log; do
      if [ "$binding" = real ]; then name=OMC_RECORD_REAL; value=$2; else name=OMC_RECORD_LOG; value=$3; fi
      printf '%s=' "$name"
      printf "'"; printf '%s' "$value" | sed "s/'/'\"'\"'/g"; printf "'\n"
    done
    cat "$R/seed/omc/tests/pools/record-compiler.sh";
  } > "$1" || bad '11 coverage: generating recording compiler failed'
  chmod +x "$1" || bad '11 coverage: recorder not executable'
}
recordsetup11() {
  REAL11=$S
  RUNREAL11=$S
  HEADHASH11=$(sha256sum "$REAL11") || bad '11 coverage: real compiler hash failed'
  HEADHASH11=${HEADHASH11%% *}
  mkdir "$B/owners" || bad '11 coverage: creating log directory failed'
}
coverage11() { # ROOT UNIT OWNER EXPECTED_STATUS (head compiler result); run each distinct owner once.
  covroot=$1; covunit=$2; covowner=$3; covwant=$4
  [ -n "$covowner" ] || { echo "11 coverage: $covunit has no declared owner" >&2; return 1; }
  case /$covowner/ in */../*|*/./*) echo "11 coverage: $covunit has invalid owner $covowner" >&2; return 1;; esac
  case $covowner in /*) echo "11 coverage: $covunit has absolute owner $covowner" >&2; return 1;; esac
  [ -f "$covroot/$covowner" ] || { echo "11 coverage: $covunit owner missing: $covowner" >&2; return 1; }
  key=$(printf '%s\n%s\n' "$covroot" "$covowner" | sha256sum) || return 1
  key=${key%% *}
  covlog=$B/owners/$key
  if [ ! -f "$covlog.exit" ]; then
    : > "$covlog.record" || return 1
    covrunner=$covlog.runner
    makerecorder11 "$covrunner" "$RUNREAL11" "$covlog.record"
    if [ "$covroot" = "$R" ] && [ "$covowner" = seed/omc/gate-pools.sh ]; then
      # This gate owns its lexer: compile the helper directly, never recurse into gate-pools.
      if "$covrunner" < "$R/$K11" > "$covlog.helper" 2> "$covlog.log"; then covr=0; else covr=$?; fi
      echo "OWNER 11 $covowner direct helper compilation (no recursion), exit=$covr"
    else
      if (cd "$covroot" && env OMC="$covrunner" OMC_BINARY="$REAL11" /usr/bin/time -p sh "$covowner" "$covrunner") > "$covlog.log" 2>&1; then covr=0; else covr=$?; fi
      echo "OWNER 11 $covowner executed once, exit=$covr record=$covlog.record"
    fi
    printf '%s\n' "$covr" > "$covlog.exit" || return 1
  fi
  covr=$(cat "$covlog.exit") || return 1
  [ "$covr" = 0 ] || { echo "11 coverage: $covunit owner $covowner failed exit=$covr (log $covlog.log)" >&2; return 1; }
  if ! awk -F '\t' 'NF!=4 || $4 !~ /^[1-9][0-9]*$/ {bad=1} END {exit bad}' "$covlog.record"; then
    echo "11 coverage: $covunit owner $covowner supplied a malformed record or wrapper PID" >&2
    return 1
  fi
  if ! awk -F '\t' -v h="$HEADHASH11" '$3!=h {bad=1} END {exit bad}' "$covlog.record"; then
    echo "11 coverage: $covunit owner $covowner executed a different compiler binary (expected $HEADHASH11)" >&2
    return 1
  fi
  if [ "$covowner" = seed/effects/check.sh ] && ! grep -Eqx 'WRAPPED-EFFECTS-RESULT ok checks=[0-9]+ runner=[0-9a-f]+ artifact=[0-9a-f]+' "$covlog.log"; then
    echo "11 coverage: $covunit owner $covowner did not report wrapped qualification" >&2
    return 1
  fi
  if [ "$covowner" = seed/effects/check.sh ] && grep -q 'SEMANTIC EFFECTS PASS' "$covlog.log"; then
    echo "11 coverage: $covunit owner $covowner printed the ordinary qualification phrase in a recording run" >&2
    return 1
  fi
  covhash=$(sha256sum "$covroot/$covunit") || return 1
  covhash=${covhash%% *}
  if ! awk -F '\t' -v h="$covhash" -v s="$covwant" '$1==h && $2==s {found=1} END {exit !found}' "$covlog.record"; then
    echo "11 coverage: $covunit owner $covowner did not compile these exact bytes with status $covwant (sha256=$covhash record=$covlog.record)" >&2
    return 1
  fi
  echo "COVERED 11 $covunit head-status=$covwant owner=$covowner source-sha256=$covhash"
}
classify11() { # UNIT OLD_PREFIX NEW_PREFIX WORDS; use precompiled outcomes and token proof.
  cu=$1; co=$2; cn=$3; cw=$4
  ca=$(cat "$co.exit") || bad "11 instrument: old status missing"
  cb=$(cat "$cn.exit") || bad "11 instrument: head status missing"
  if uses11 "$cu" "$cw" "$B/class-words"; then ct=1; else ct=0; fi
  # Pool-only syntax predates enlarge use in several current units. It is not a new keyword.
  # Only use this fallback when no added keyword was present; the original strict both-accept rule remains first.
  if [ "$ct" = 0 ] && pooluses11 "$cu"; then
    printf 'pool\n' > "$B/class-words" || bad '11 instrument: recording pool syntax feature failed'
    ct=1
  fi
  if declaration11 "$cu" > "$B/unit-declarations"; then :; else bad "11 declaration: malformed declaration for $cu (uses WORD on purpose: owner=PATH REASON)"; fi
  cut -f2 "$B/unit-declarations" > "$B/unit-owners" || bad '11 instrument: deriving owners failed'
  sort -u "$B/unit-owners" > "$B/unit-owners-sorted" || bad '11 instrument: sorting owners failed'
  cowner=$(tr '\n' ' ' < "$B/unit-owners-sorted") || bad '11 instrument: reading owners failed'
  if [ "$ca" = 0 ] && [ "$cb" = 0 ]; then
    [ -z "$cowner" ] || { echo "11 classification: false declaration: $cu both compilers accept" >&2; return 1; }
    strict11 "$cu" "$co" "$cn" || return 1
    CLASS11=exact
  elif [ "$ct" = 1 ]; then
    cut -f1 "$B/unit-declarations" > "$B/declared-words" || bad '11 instrument: deriving declaration words failed'
    sort -u "$B/declared-words" > "$B/declared-sorted" || bad '11 instrument: sorting declarations failed'
    sort -u "$B/class-words" > "$B/used-new-sorted" || bad '11 instrument: sorting token proof failed'
    while IFS="$(printf '\t')" read -r dw downer; do
      if [ "$dw" != pool ]; then
        grep -qxF -- "$dw" "$cw" || { echo "11 classification: false declaration for $cu: $dw is not a keyword absent from the control" >&2; return 1; }
      fi
      grep -qxF -- "$dw" "$B/used-new-sorted" || { echo "11 classification: false declaration for $cu: $dw is not used as a token" >&2; return 1; }
    done < "$B/unit-declarations"
    comm -23 "$B/used-new-sorted" "$B/declared-sorted" > "$B/missing-declarations" || bad '11 instrument: comparing declared/used words failed'
    [ ! -s "$B/missing-declarations" ] || { echo "11 classification: $cu missing declarations for $(tr '\n' ' ' < "$B/missing-declarations")" >&2; return 1; }
    if [ "$cb" = 0 ]; then CLASS11=accepted; else CLASS11=refusal; fi
  elif [ "$ca" != 0 ] && [ "$cb" = 0 ]; then
    [ "$ct" = 1 ] && [ -n "$cowner" ] || { echo "11 classification: $cu newly accepted without a declared new keyword and owner" >&2; return 1; }
    CLASS11=accepted
  else
    [ -z "$cowner" ] || { echo "11 classification: false declaration: $cu has no new-keyword token" >&2; return 1; }
    strict11 "$cu" "$co" "$cn" || return 1
    CLASS11=exact
  fi
  OWNER11=$cowner; OLDSTATUS11=$ca; HEADSTATUS11=$cb
}
poolcontrols11() {
  # A pool declaration is a new syntax feature, not a newly added spelling in genkw.awk.
  printf 'global P ulong *\nfn main to int\nret 0\nend\n' > "$B/pool-only.om"
  pooluses11 "$B/pool-only.om" || bad '11 pool control: real declaration shape missing'
  for kind in note string fixed cross-line; do
    case $kind in
      note) printf 'note global P ulong *\nfn main to int\nret 0\nend\n';;
      string) printf 'text t "global P ulong *"\nfn main to int\nret 0\nend\n';;
      fixed) printf 'global P ulong 1\nfn main to int\nret 0\nend\n';;
      cross-line) printf 'global P ulong\n*\nfn main to int\nret 0\nend\n';;
    esac > "$B/pool-$kind.om"
    if pooluses11 "$B/pool-$kind.om"; then bad "11 pool control: $kind text admitted as declaration shape"; fi
  done
  compile11 "$CTRL" "$B/pool-only.om" "$B/pool-old"
  compile11 "$S" "$B/pool-only.om" "$B/pool-head"
  [ "$(cat "$B/pool-head.exit")" = 0 ] || bad '11 pool control: head refuses genuine pool-only unit'
  if [ "$(cat "$B/pool-old.exit")" = 0 ]; then
    say 'LIMIT 11 pool-only classification control: custom reference already accepts pools; no refusal/acceptance contrast'
  else
    if classify11 "$B/pool-only.om" "$B/pool-old" "$B/pool-head" "$B/new-keywords" > "$B/pool-missing.why" 2>&1; then
      bad '11 pool control: undeclared newly accepted syntax was exempted'
    fi
    grep -q 'missing declarations for pool' "$B/pool-missing.why" || bad '11 pool control: missing declaration failed for wrong reason'
    printf 'note gate-pools: uses pool on purpose: owner=seed/x/accepts.sh pool-only control\n' >> "$B/pool-only.om"
    compile11 "$CTRL" "$B/pool-only.om" "$B/pool-old"
    compile11 "$S" "$B/pool-only.om" "$B/pool-head"
    classify11 "$B/pool-only.om" "$B/pool-old" "$B/pool-head" "$B/new-keywords" || bad '11 pool control: declared real feature refused'
    [ "$CLASS11" = accepted ] || bad '11 pool control: genuine syntax classification wrong'
  fi
  cp "$B/pool-fixed.om" "$B/pool-false.om"
  printf 'note gate-pools: uses pool on purpose: owner=seed/x/accepts.sh false declaration\n' >> "$B/pool-false.om"
  compile11 "$CTRL" "$B/pool-false.om" "$B/pool-false-old"
  compile11 "$S" "$B/pool-false.om" "$B/pool-false-head"
  if classify11 "$B/pool-false.om" "$B/pool-false-old" "$B/pool-false-head" "$B/new-keywords" > "$B/pool-false.why" 2>&1; then
    bad '11 pool control: false syntax declaration accepted on fixed array'
  fi
  grep -q 'false declaration' "$B/pool-false.why" || bad '11 pool control: false syntax declaration failed for wrong reason'
  say 'PASS 11 pool controls: real line-start syntax detected; notes/strings/fixed arrays/cross-line lookalikes rejected; declarations do not waive both-accept byte identity'
}
wordcontrols11() {
  # A real compiler mutant changes a CONTROL-KNOWN statement, so no future keyword can excuse it.
  printf 'emit 3573751871\n' > "$B/wordmut.from" # existing cpurelax YIELD emission
  printf 'emit 3573759903\n' > "$B/wordmut.to"   # existing cpufence DSB SY emission
  frame11 M "$B/mutation-input" "$B/wordmut.from" "$B/wordmut.to" seed/omc/omc.om
  "$B/keyword-tool" < "$B/mutation-input" > "$B/wordmut.om" || bad "11 control: mutant anchor not unique or no-op"
  "$B/lexer-cc" < "$B/wordmut.om" > "$B/wordmut-cc" 2> "$B/wordmut.err" || bad "11 control: known-word mutant compiler build failed: $(cat "$B/wordmut.err")"
  chmod +x "$B/wordmut-cc"
  w=$(head -1 "$B/new-keywords")
  [ -n "$w" ] || w=gate_pools_future_keyword
  printf '%s\n' "$w" > "$B/control-words"
  for variant in plain note string; do
    { [ "$variant" != note ] || printf 'note %s\n' "$w";
      [ "$variant" != string ] || printf 'text t "%s"\n' "$w";
      printf 'fn main to int\ncpurelax\nret 0\nend\n'; } > "$B/word-$variant.om"
    if uses11 "$B/word-$variant.om" "$B/control-words" "$B/word-use"; then bad "11 control: $variant data excluded a control-known unit"; fi
    compile11 "$CTRL" "$B/word-$variant.om" "$B/word-old"
    compile11 "$B/wordmut-cc" "$B/word-$variant.om" "$B/word-new"
    if strict11 "$B/word-$variant.om" "$B/word-old" "$B/word-new" > "$B/word-$variant.why"; then bad "11 control: control-known lowering mutation accepted ($variant)"; fi
    say "PASS 11 control: known-word byte mutation rejected ($variant; notes/strings do not exclude)"
  done
  # Real target-conditional firmware spelling is absent from the global generator: fail loudly.
  printf 'target a64efi\nfn main to ulong\nret fwsys 1\nend\n' > "$B/conditional.om"
  if uses11 "$B/conditional.om" "$B/new-keywords" "$B/word-use"; then bad "11 control: target-conditional word silently treated as a new global"; fi
  compile11 "$CTRL" "$B/conditional.om" "$B/conditional-old"
  compile11 "$B/lexer-cc" "$B/conditional.om" "$B/conditional-new"
  if strict11 "$B/conditional.om" "$B/conditional-old" "$B/conditional-new" > "$B/conditional.why"; then bad "11 control: unknown target-conditional feature not detected"; fi
  say "PASS 11 boundary: standalone target-conditional word fails exact comparison loudly: $(cat "$B/conditional.why")"
  frame11 D "$B/empty-derive-input" "$B/control-kw.om" "$B/control-kw.om"
  "$B/keyword-tool" < "$B/empty-derive-input" > "$B/empty-words" || bad "11 control: empty word derivation failed"
  [ ! -s "$B/empty-words" ] || bad "11 control: same keyword table produced additions"
  if uses11 "$B/word-plain.om" "$B/empty-words" "$B/word-use"; then bad "11 control: empty set excluded unit"; fi
  say "PASS 11 control: empty added-global set excludes no unit; exact comparison unchanged"
}

controls11() {
  # Compiler token boundaries: note( is a note, not a keyword use; parentheses delimit real source tokens.
  for variant in string note-paren; do
    if [ "$variant" = string ]; then
      printf 'text t "enlarge"\nfn main to int\nret 0\nend\n' > "$B/probe.om"
    else
      printf 'fn main to int\nnote( enlarge\nret 0\nend\n' > "$B/probe.om"
    fi
    if uses11 "$B/probe.om" "$B/enlarge-word" "$B/probe.words"; then bad "11 control: $variant data counted as a token"; fi
    compile11 "$CTRL" "$B/probe.om" "$B/probe-old"
    compile11 "$S" "$B/probe.om" "$B/probe-new"
    [ "$(cat "$B/probe-old.exit")" = 0 ] && [ "$(cat "$B/probe-new.exit")" = 0 ] || bad "11 control: $variant should compile under both compilers"
    strict11 "$B/probe.om" "$B/probe-old" "$B/probe-new" || bad "11 control: $variant bytes differ"
    # Classifier case 1 ignores source appearances and compares both-accept units; a declaration is false.
    classify11 "$B/probe.om" "$B/probe-old" "$B/probe-new" "$B/enlarge-word" || bad "11 control: undeclared $variant refused"
    [ "$CLASS11" = exact ] || bad "11 control: $variant left the exact comparison"
    printf 'note gate-pools: uses enlarge on purpose: owner=seed/omc/gate-pools.sh false-data\n' >> "$B/probe.om"
    # Recompile the declared bytes, not the earlier source.
    compile11 "$S" "$B/probe.om" "$B/probe-new"
    compile11 "$CTRL" "$B/probe.om" "$B/probe-old"
    if classify11 "$B/probe.om" "$B/probe-old" "$B/probe-new" "$B/enlarge-word" > "$B/probe-$variant.why" 2>&1; then bad "11 control: declared $variant accepted"; fi
    grep -q 'false declaration: .* both compilers accept' "$B/probe-$variant.why" || bad "11 control: wrong declared $variant reason"
    say "PASS 11 control: $variant undeclared stays exact and equal; declared is refused as false"
  done
  for adjacent in '(enlarge' 'enlarge)' '(enlarge)'; do
    printf '%s\n' "$adjacent" > "$B/adjacent.om"
    uses11 "$B/adjacent.om" "$B/enlarge-word" "$B/probe.words" || bad "11 control: parentheses hide a real token: $adjacent"
  done
  say 'PASS 11 control: parenthesis-adjacent real enlarge tokens are found'
  # Checked producers: no cat failure can turn an unreadable input into absence. A directory exists but cannot
  # be read as source bytes, even under root; a missing path tests the other input producer.
  mkdir "$B/io-directory"
  if (uses11 "$B/io-directory" "$B/enlarge-word" "$B/probe.words") > "$B/unreadable-source.log" 2>&1; then bad "11 control: unreadable source accepted"; fi
  grep -q '11 instrument: unreadable source' "$B/unreadable-source.log" || bad "11 control: source failure became absence"
  if (uses11 "$B/adjacent.om" "$B/missing-words" "$B/probe.words") > "$B/unreadable-words.log" 2>&1; then bad "11 control: unreadable word list accepted"; fi
  grep -q '11 instrument: unreadable word list' "$B/unreadable-words.log" || bad "11 control: word-list failure became absence"
  if (frame11 D "$B/failed-frame" "$B/missing-frame-input" "$B/adjacent.om") > "$B/unreadable-frame.log" 2>&1; then bad '11 control: unreadable derivation producer accepted'; fi
  grep -q '11 instrument: unreadable frame input' "$B/unreadable-frame.log" || bad '11 control: derivation producer failure became empty input'
  say 'PASS 11 control: unreadable source, word-list and derivation producers fail as instrument errors'
  # Execution, not registration text, proves coverage. Every misleading shell/manifest input the reviewers
  # named is retained here; these owners all exit zero but do not compile the source bytes.
  cr11=$B/coverage-controls
  mkdir -p "$cr11/seed/x"
  printf 'fn main to int\nret 0\nend\n' > "$cr11/seed/x/new.om"
  for mode in inert inline-comment quoted heredoc wrong-command dead-branch uncalled reassignment unused-manifest suffix; do
    co11=$cr11/seed/x/$mode.sh
    printf '#!/bin/sh\n# TEST INSTRUMENT: executed coverage negative control\n' > "$co11"
    case $mode in
      inert) printf 'echo seed/x/new.om\n' >> "$co11";;
      inline-comment) printf ': # < seed/x/new.om\n' >> "$co11";;
      quoted) printf "echo '< seed/x/new.om '\n" >> "$co11";;
      heredoc) printf 'cat <<EOF\n< seed/x/new.om\nEOF\n' >> "$co11";;
      wrong-command) printf ': < seed/x/new.om\n' >> "$co11";;
      dead-branch) printf 'if false; then "$1" < seed/x/new.om > /dev/null; fi\n' >> "$co11";;
      uncalled) printf 'never() { "$1" < seed/x/new.om > /dev/null; }\n' >> "$co11";;
      reassignment) printf 'U=seed/x/new.om\nU=/dev/null\n"$1" < "$U" > /dev/null\nexit 0\n' >> "$co11";;
      unused-manifest) printf 'new seed/x/new.om\n' > "$cr11/seed/x/cases-fake.txt"; printf 'fn main to int\nret 0\nend\n' > "$cr11/seed/x/gate-fake.om"; printf 'echo cases-fake.txt\n' >> "$co11";;
      suffix) printf 'x|@new.om.extra\n' > "$cr11/seed/x/probes.txt"; printf 'echo probes.txt\n' >> "$co11";;
    esac
    if coverage11 "$cr11" seed/x/new.om "seed/x/$mode.sh" 0 > "$B/coverage-$mode.log" 2>&1; then bad "11 control: $mode falsely covered seed/x/new.om"; fi
    grep -q '11 coverage: seed/x/new.om .*did not compile these exact bytes' "$B/coverage-$mode.log" || bad "11 control: wrong $mode coverage reason: $(cat "$B/coverage-$mode.log")"
    say "PASS 11 control: $mode owner does not cover seed/x/new.om (nothing compiled its exact bytes)"
  done
  printf '#!/bin/sh\n"$1" < seed/x/new.om > /dev/null\nexit 7\n' > "$cr11/seed/x/fails.sh"
  if coverage11 "$cr11" seed/x/new.om seed/x/fails.sh 0 > "$B/coverage-fails.log" 2>&1; then bad '11 control: failing owner accepted'; fi
  grep -q '11 coverage: seed/x/new.om owner .* failed exit=7' "$B/coverage-fails.log" || bad '11 control: wrong owner failure reason'
  if coverage11 "$cr11" seed/x/new.om seed/x/missing.sh 0 > "$B/coverage-missing.log" 2>&1; then bad '11 control: missing owner accepted'; fi
  grep -q '11 coverage: seed/x/new.om owner missing' "$B/coverage-missing.log" || bad '11 control: wrong missing-owner reason'
  printf '#!/bin/sh\n"$1" < seed/x/new.om > /dev/null\n' > "$cr11/seed/x/accepts.sh"
  if coverage11 "$cr11" seed/x/new.om seed/x/accepts.sh 9 > "$B/coverage-wrong-status.log" 2>&1; then bad '11 control: accepted compilation counted as refusal coverage'; fi
  grep -q '11 coverage: seed/x/new.om .*did not compile these exact bytes with status 9' "$B/coverage-wrong-status.log" || bad '11 control: wrong refusal-coverage mismatch reason'
  coverage11 "$cr11" seed/x/new.om seed/x/accepts.sh 0 || bad '11 control: successful exact-byte compilation not covered'
  say 'PASS 11 control: missing owner, failing owner, and successful compilation offered as refusal coverage are rejected by unit name; successful exact-byte coverage works'
  # A wrapper that executes another real compiler cannot establish coverage of this head.
  savedreal=$RUNREAL11
  RUNREAL11=$CTRL
  cp "$cr11/seed/x/accepts.sh" "$cr11/seed/x/wrong-compiler.sh"
  if coverage11 "$cr11" seed/x/new.om seed/x/wrong-compiler.sh 0 > "$B/coverage-wrong-compiler.log" 2>&1; then bad '11 control: wrapper executing another compiler accepted'; fi
  grep -q '11 coverage: seed/x/new.om .*executed a different compiler binary' "$B/coverage-wrong-compiler.log" || bad '11 control: wrong different-compiler refusal reason'
  RUNREAL11=$savedreal
  say 'PASS 11 control: a wrapper running the historical compiler instead of this head is refused by the executed-binary hash'
  # Case-2 boundary using a genuinely new accepted program, not an inert-data approximation.
  printf 'global P uchar *\nfn main to int\nr = enlarge P ulong 4\nret 0\nend\nnote gate-pools: uses enlarge on purpose: owner=seed/x/inert.sh accepted-boundary\n' > "$cr11/seed/x/new-accept.om"
  compile11 "$CTRL" "$cr11/seed/x/new-accept.om" "$B/new-accept-old"
  compile11 "$S" "$cr11/seed/x/new-accept.om" "$B/new-accept-head"
  classify11 "$cr11/seed/x/new-accept.om" "$B/new-accept-old" "$B/new-accept-head" "$B/enlarge-word" || bad '11 control: new accepted program misclassified'
  [ "$CLASS11" = accepted ] || bad '11 control: newly accepted boundary did not reach case 2'
  if coverage11 "$cr11" seed/x/new-accept.om seed/x/inert.sh 0 > "$B/coverage-new-accept.log" 2>&1; then bad '11 control: new accepted program with inert owner qualified'; fi
  grep -q '11 coverage: seed/x/new-accept.om .*did not compile these exact bytes' "$B/coverage-new-accept.log" || bad '11 control: wrong case-2 coverage reason'
  say 'PASS 11 control: case-2 newly accepted unit whose owner never compiles it fails by unit name'
  # Newly refusing a unit without a new token cannot be excused: feed observed refusal/acceptance pairs from
  # real compilers to the same classifier, with an empty token set.
  printf 'fn main to int\nret 0\nend\n' > "$B/no-token.om"
  compile11 "$S" "$B/no-token.om" "$B/no-token-old"
  printf '#!/bin/sh\n# TEST INSTRUMENT: inject a compiler refusal for a no-token unit\necho "injected head refusal" >&2\nexit 1\n' > "$B/refusing-compiler"
  chmod +x "$B/refusing-compiler"
  compile11 "$B/refusing-compiler" "$B/no-token.om" "$B/no-token-new"
  : > "$B/empty-words"
  if classify11 "$B/no-token.om" "$B/no-token-old" "$B/no-token-new" "$B/empty-words" > "$B/new-refusal.why" 2>&1; then bad '11 control: newly refusing a no-token unit accepted'; fi
  grep -q 'DIFF .*no-token.om status=0/1' "$B/new-refusal.why" || bad '11 control: wrong newly-refused-unit reason'
  say 'PASS 11 control: newly refusing a no-token unit fails exact comparison'
}

reviewthreecontrols11() {
  # Quote is special only at token start; inside a word it is part of that name (compiler tok2).
  printf 'fn main to int\nenlarge" = long 0\nret 0\nend\n' > "$B/embedded-quote.om"
  if uses11 "$B/embedded-quote.om" "$B/enlarge-word" "$B/probe.words"; then bad '11 control: mid-word quote created a false enlarge token'; fi
  compile11 "$CTRL" "$B/embedded-quote.om" "$B/embedded-old"
  compile11 "$S" "$B/embedded-quote.om" "$B/embedded-head"
  [ "$(cat "$B/embedded-old.exit")" = 0 ] && [ "$(cat "$B/embedded-head.exit")" = 0 ] || bad '11 control: embedded-quote local must compile under both'
  classify11 "$B/embedded-quote.om" "$B/embedded-old" "$B/embedded-head" "$B/enlarge-word" || bad '11 control: embedded-quote local not exact'
  [ "$CLASS11" = exact ] || bad '11 control: embedded-quote local left exact comparison'
  printf 'global P ulong *\nfn main to int\nenlarge" = long 0\nret 0\nend\nnote gate-pools: uses enlarge on purpose: owner=seed/omc/gate-pools.sh false-quote-token\n' > "$B/pool-only-quote.om"
  compile11 "$CTRL" "$B/pool-only-quote.om" "$B/pool-only-old"
  compile11 "$S" "$B/pool-only-quote.om" "$B/pool-only-head"
  [ "$(cat "$B/pool-only-old.exit")" != 0 ] && [ "$(cat "$B/pool-only-head.exit")" = 0 ] || bad '11 control: pool-only form did not exercise case 2'
  if classify11 "$B/pool-only-quote.om" "$B/pool-only-old" "$B/pool-only-head" "$B/enlarge-word" > "$B/pool-only-quote.why" 2>&1; then bad '11 control: pool-only form with no real keyword accepted'; fi
  # The pool declaration is now a witnessed syntax feature, so the quoted lookalike fails as a false enlarge declaration.
  grep -q 'false declaration for .*: enlarge is not used as a token' "$B/pool-only-quote.why" || bad '11 control: wrong pool-only quote reason'
  say 'PASS 11 control: embedded quote stays inside a name; both-accepted local is exact, pool-only case2 without a keyword fails'
  # Invalid text stops lexical scanning where tok_text fails; bytes on later lines cannot become false tokens.
  printf 'text x "invalid\nenlarge\n"\nfn main to int\nret 0\nend\n' > "$B/invalid-text.om"
  if uses11 "$B/invalid-text.om" "$B/enlarge-word" "$B/probe.words"; then bad '11 control: lexer crossed a newline inside text'; fi
  compile11 "$S" "$B/invalid-text.om" "$B/invalid-text-head"
  [ "$(cat "$B/invalid-text-head.exit")" = 22 ] || bad '11 control: invalid text did not reach compiler error22'
  printf 'text x "x"enlarge\nfn main to int\nret 0\nend\n' > "$B/text-follower.om"
  if uses11 "$B/text-follower.om" "$B/enlarge-word" "$B/probe.words"; then bad '11 control: lexer scanned past invalid text follower'; fi
  compile11 "$S" "$B/text-follower.om" "$B/text-follower-head"
  [ "$(cat "$B/text-follower-head.exit")" = 22 ] || bad '11 control: invalid text follower not error22'
  say 'PASS 11 control: newline inside text and nonblank text follower stop the token scan at the compiler lexical error'
  printf 'fn main to int\n\001enlarge\nret 0\nend\n' > "$B/invalid-blank.om"
  if uses11 "$B/invalid-blank.om" "$B/enlarge-word" "$B/probe.words"; then bad '11 control: invalid control byte treated as compiler blank'; fi
  compile11 "$S" "$B/invalid-blank.om" "$B/invalid-blank-head"
  [ "$(cat "$B/invalid-blank-head.exit")" = 16 ] || bad '11 control: invalid blank did not reach compiler error16'
  say 'PASS 11 control: token-start blanks are space/tab/CR; other control bytes stop at compiler error16'
  printf 'fn main to int\n  note gate-pools: uses enlarge on purpose: owner=seed/omc/gate-pools.sh false-indented-intent\nret 0\nend\n' > "$B/indented-intent.om"
  compile11 "$CTRL" "$B/indented-intent.om" "$B/indented-old"
  compile11 "$S" "$B/indented-intent.om" "$B/indented-head"
  if classify11 "$B/indented-intent.om" "$B/indented-old" "$B/indented-head" "$B/enlarge-word" > "$B/indented-intent.why" 2>&1; then bad '11 control: indented false declaration ignored'; fi
  grep -q 'false declaration: .* both compilers accept' "$B/indented-intent.why" || bad '11 control: wrong indented intent refusal'
  printf 'fn main to int\n  note gate-pools: uses enlarge on purpose: missing-owner\nret 0\nend\n' > "$B/malformed-intent.om"
  compile11 "$CTRL" "$B/malformed-intent.om" "$B/malformed-old"
  compile11 "$S" "$B/malformed-intent.om" "$B/malformed-head"
  if (classify11 "$B/malformed-intent.om" "$B/malformed-old" "$B/malformed-head" "$B/enlarge-word") > "$B/malformed-intent.why" 2>&1; then bad '11 control: malformed intent marker ignored'; fi
  grep -q '11 declaration: malformed declaration' "$B/malformed-intent.why" || bad '11 control: wrong malformed-marker refusal'
  say 'PASS 11 control: indented false declarations and malformed intent-marker lines are refused'
  # Deliberately forging tracked code is outside this same-user test instrument's trust boundary.
  # Demonstrate, rather than claim to prevent, the reviewer's forgery. This is NOT a passing security control.
  fdemo=$B/forging-demonstration
  mkdir -p "$fdemo/seed/x"
  printf 'global P uchar *\nfn main to int\nr = enlarge P ulong 4\nret 0\nend\nnote gate-pools: uses enlarge on purpose: owner=seed/x/forge.sh deliberate-limit-demonstration\n' > "$fdemo/seed/x/forge.om"
  cat > "$fdemo/seed/x/forge.sh" <<'FORGE'
#!/bin/sh
# TEST INSTRUMENT: deliberate same-user record forgery; never runs the supplied compiler.
log=$(sed -n "s/^OMC_RECORD_LOG='\(.*\)'$/\1/p" "$1") || exit 1
h=$(sha256sum seed/x/forge.om) || exit 1; h=${h%% *}
b=$(sha256sum "$OMC_BINARY") || exit 1; b=${b%% *}
printf '%s\t0\t%s\t%s\n' "$h" "$b" "$$" >> "$log"
FORGE
  # The raw demonstration output is prefixed so that its COVERED line can never be read as real coverage.
  if coverage11 "$fdemo" seed/x/forge.om seed/x/forge.sh 0 > "$B/forging-demonstration.raw" 2>&1; then observed_forgery=0; else observed_forgery=$?; fi
  sed 's/^/DEMONSTRATION-NOT-COVERAGE /' "$B/forging-demonstration.raw" > "$B/forging-demonstration.log" || bad '11 instrument: labelling the forging demonstration failed'
  rm -f "$B/forging-demonstration.raw"
  ! grep -q '^COVERED 11' "$B/forging-demonstration.log" || bad '11 instrument: unlabelled demonstration coverage line'
  say "LIMIT 11 demonstration (not a security control): forging owner ran no compiler; trusted-record coverage returned $observed_forgery; wrapper PID shape is not independently authenticated ancestry"
}

# Container-word landing controls for the generalized declaration schema; production lowering is not changed here.
multiwordcontrols11() {
  cat > "$B/multiple-base.om" <<'OM'
note TEST INSTRUMENT: actual two-new-word compiler admission, never a product workload.
global P uchar *
fn main to int
r = enlarge P ulong 128
r = fstatfs 0 P 0 128
cpurelax
ret 0
end
OM
  printf 'note gate-pools: uses enlarge on purpose: owner=seed/host/fstatfs/check.sh declaration-schema-control\n' > "$B/decl-enlarge"
  printf 'note gate-pools: uses fstatfs on purpose: owner=seed/host/fstatfs/check.sh declaration-schema-control\n' > "$B/decl-fstatfs"
  for fault in unused known missing-one complete; do
    cat "$B/multiple-base.om" "$B/decl-enlarge" > "$B/multiple-$fault.om" || bad '11 control: writing multiword input failed'
    [ "$fault" = missing-one ] || cat "$B/decl-fstatfs" >> "$B/multiple-$fault.om" || bad '11 control: appending fstatfs intent failed'
    case "$fault" in
      unused) printf 'note gate-pools: uses mount on purpose: owner=seed/host/fstatfs/check.sh false-unused-word\n' >> "$B/multiple-$fault.om";;
      known) printf 'note gate-pools: uses cpurelax on purpose: owner=seed/host/fstatfs/check.sh false-control-known-word\n' >> "$B/multiple-$fault.om";;
    esac
    compile11 "$CTRL" "$B/multiple-$fault.om" "$B/multiple-old"
    compile11 "$S" "$B/multiple-$fault.om" "$B/multiple-head"
    if [ "$fault" = complete ]; then
      classify11 "$B/multiple-$fault.om" "$B/multiple-old" "$B/multiple-head" "$B/new-keywords" || bad '11 control: complete multiword declarations refused'
      [ "$CLASS11" = accepted ] || bad '11 control: multiword input not newly accepted'
      say 'PASS 11 control: a unit using enlarge and fstatfs declares both actual new tokens'
    else
      if classify11 "$B/multiple-$fault.om" "$B/multiple-old" "$B/multiple-head" "$B/new-keywords" > "$B/multiple-$fault.why" 2>&1; then bad "11 control: $fault declaration accepted"; fi
      case "$fault" in
        unused) grep -q 'false declaration .*mount is not used as a token' "$B/multiple-$fault.why" || bad '11 control: wrong unused-word reason';;
        known) grep -q 'false declaration .*cpurelax is not a keyword absent from the control' "$B/multiple-$fault.why" || bad '11 control: wrong control-known-word reason';;
        missing-one) grep -q 'missing declarations for fstatfs' "$B/multiple-$fault.why" || bad '11 control: wrong missing-word reason';;
      esac
      say "PASS 11 control: $fault declaration rejected by unit and word: $(cat "$B/multiple-$fault.why")"
    fi
  done
}

notrun11=
if on 11 && [ "$(git rev-parse --is-shallow-repository 2> /dev/null || echo unknown)" != false ]; then
  # lexer11 builds the lexer with the compiler of the one commit that introduced keyword-users.om. A shallow
  # clone cannot name that commit (its boundary commit shows every file as added), so section 11 is not run.
  notrun11="shallow clone: the commit that introduced seed/omc/keyword-users.om cannot be established; section 11 not run (a full clone is needed)"
  say "NOT_RUN 11: $notrun11"
elif on 11; then
  lexer11
  recordsetup11
  controls11
  reviewthreecontrols11
  if [ "$(sha256sum "$CTRL" | cut -d' ' -f1)" != "$BASEFIX" ]; then
    notrun11="custom CTRL has no pinned source mapping for the keyword derivation; compiler-outcome comparison not run"
    say "NOT_RUN 11: $notrun11"
  else
    words11
    wordcontrols11
    poolcontrols11
    multiwordcontrols11
    git ls-files '*.om' > "$B/corpus-all" || bad '11 instrument: listing tracked units failed'
    # The original pool fixtures have their separate sections above; no other path list or declaration excludes a unit.
    if grep -v "^$T/" "$B/corpus-all" > "$B/files"; then :; else lr=$?; [ "$lr" = 1 ] || bad '11 instrument: filtering pool fixtures failed'; fi
    total11=$(wc -l < "$B/files") || bad '11 instrument: counting corpus failed'
    [ "$total11" -gt 0 ] || bad '11 comparison: empty corpus/exact set'
    max11=${POOLS_EQUIV_MAX:-$total11}
    case "$max11" in ''|*[!0-9]*) bad '11 comparison: POOLS_EQUIV_MAX must be a nonnegative integer';; esac
    if [ "${POOLS_SKIP_EQUIV:-0}" = 1 ] || [ "$max11" = 0 ]; then
      notrun11="comparison skipped (POOLS_SKIP_EQUIV=${POOLS_SKIP_EQUIV:-0}, POOLS_EQUIV_MAX=$max11)"
      say "NOT_RUN 11: $notrun11"
    else
      n11=0; exact11=0; accepts11=0; refuses11=0
      while IFS= read -r f; do
        [ "$n11" -lt "$max11" ] || break
        n11=$((n11+1))
        compile11 "$CTRL" "$f" "$B/old"
        compile11 "$S" "$f" "$B/head"
        if classify11 "$f" "$B/old" "$B/head" "$B/new-keywords"; then :; else bad "11 classification failed for $f"; fi
        case "$CLASS11" in
          exact) exact11=$((exact11+1)); say "EXACT 11 $f status=$OLDSTATUS11/$HEADSTATUS11";;
          accepted|refusal)
            if [ "$CLASS11" = accepted ]; then accepts11=$((accepts11+1)); else refuses11=$((refuses11+1)); fi
            for declared_owner in $OWNER11; do
              coverage11 "$R" "$f" "$declared_owner" "$HEADSTATUS11" || bad "11 executed coverage failed for $f"
            done
            say "QUALIFIED 11 $CLASS11 $f status=$OLDSTATUS11/$HEADSTATUS11 new-token=$(tr '\n' ',' < "$B/class-words") owner=$OWNER11"
            ;;
          *) bad "11 instrument: unknown classification $CLASS11 for $f";;
        esac
      done < "$B/files"
      [ "$exact11" -gt 0 ] || bad '11 comparison: empty exact set'
      say "CORPUS 11 measured=$n11 total=$total11 exact=$exact11 new-accepted=$accepts11 new-refusals=$refuses11; classification by compiler outcomes"
      if [ "$n11" -lt "$total11" ]; then
        notrun11="partial compiler-outcome comparison: $n11 of $total11 units"
        say "NOT_RUN 11: $notrun11"
      else
        say "PASS 11: both-accepted bytes identical; token-qualified acceptance/refusal units have successful executed owners; both-refused no-token units identical in status/stdout/stderr"
      fi
    fi
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

if [ -n "$notrun11" ]; then
  say "NOT_RUN gate-pools${POOLS_ONLY:+ (sections 0 $POOLS_ONLY only)}: $notrun11; every other section run passed"
  say 'RC=3'
  exit 3
fi
say "PASS gate-pools${POOLS_ONLY:+ (sections 0 $POOLS_ONLY only)}"
say 'RC=0'
