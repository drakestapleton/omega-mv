#!/bin/sh
# test-mutate.sh -- regression for the mutation driver tools/trit/mutate.sh itself (external shell
# verification tool, not Omega production code). The defect it guards: the driver once exited 0 with
# every mutant "build failed", unapplied, or surviving, and counted a crashed test runner as a kill.
# Each scenario runs a scratch copy of the driver (the real mutants, real seed omc unless the scenario
# is about the compiler) and checks the exit status AND the verdict text. Stubs replace test.sh or
# difftest.sh only inside the scratch copy, and only to produce one exact failure shape.
# Usage from the repo root:  sh tools/trit/test-mutate.sh      (W=dir keeps all logs; OMC optional)
set -u
R=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd); cd "$R" || exit 2
OMC=${OMC:-$R/seed/out/omc}; case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
if [ -z "${W:-}" ]; then W=$(mktemp -d "${TMPDIR:-/tmp}/trit-mutate-test.XXXXXX") || exit 2; else
  if [ -e "$W" ] || [ -L "$W" ]; then echo "work directory already exists: $W (preserved)" >&2; exit 2; fi
  mkdir -p "$W" || exit 2
fi
case $W in /*) ;; *) W=$(pwd)/$W ;; esac
[ -x "$OMC" ] || { echo "test-mutate.sh: compiler $OMC missing" >&2; exit 2; }
pass=0; fail=0
ok() { pass=$((pass+1)); printf 'PASS %s\n' "$1"; }
no() { fail=$((fail+1)); printf 'FAIL %s: %s\n' "$1" "$2"; }

# scratch NAME "mutant names kept": a repo copy whose driver runs only those mutants.
scratch() {
  S=$W/$1; rm -rf "$S"; mkdir -p "$S/tools" "$S/seed/trace" "$S/seed/out"
  cp -r tools/trit tools/codebook "$S/tools/"; cp seed/trace/sha256.om "$S/seed/trace/"
  rm -f "$S/tools/trit/trit.bin" "$S/tools/codebook/codebook.bin"
  ln -s "$OMC" "$S/seed/out/omc"
  keep=$2
  awk -v keep="$keep" 'BEGIN{n=split(keep,a," "); for(i=1;i<=n;i++)k[a[i]]=1} /^m /{ if(!($3 in k)) next } {print}' tools/trit/mutate.sh > "$S/tools/trit/mutate.sh"
}
# drive NAME [VAR=value ...]: run the scratch driver; sets RC and OUT (log path).
drive() {
  d=$1; shift
  OUT=$W/$d.log
  env "$@" W="$W/$d.work" REF_TRIT_OM="$R/tools/trit/trit.om" sh "$W/$d/tools/trit/mutate.sh" > "$OUT" 2>&1; RC=$?
}
# expect NAME RC PATTERN...: exit status and every grep pattern present in the log.
expect() {
  n=$1; rc=$2; shift 2
  if [ "$RC" != "$rc" ]; then no "$n" "exit $RC, want $rc (see $OUT)"; return; fi
  for p in "$@"; do grep -q -- "$p" "$OUT" || { no "$n" "pattern '$p' missing (see $OUT)"; return; }; done
  ok "$n"
}

# 1. normal subset with an explicit compiler, then the unset-OMC default and ack-only scope
scratch ok-read "lvl-ignores-3xx verify-disabled"
drive ok-read OMC="$OMC"
expect read-mutants-accepted 0 'BASELINE test.sh survived, difftest survived' 'MUTANT 1 lvl-ignores-3xx \[read\]: test.sh killed, difftest killed => ok' 'mutate.sh: PASS 2/2'
scratch ok-default "stale-allows-equal"
env -u OMC W="$W/ok-default.work" sh "$W/ok-default/tools/trit/mutate.sh" > "$W/ok-default.log" 2>&1; RC=$?; OUT=$W/ok-default.log
expect default-omc-is-seed-omc 0 'mutate.sh: PASS 1/1'
# an ack mutant is outside the differential model: test.sh kills it, difftest survives, still accepted
scratch ok-ack "ack-no-counter-advance"
drive ok-ack OMC="$OMC"
expect ack-mutant-judged-by-test-sh 0 'ack-no-counter-advance \[ack\]: test.sh killed, difftest survived => ok' 'mutate.sh: PASS 1/1'

# 2. invalid compilers are rejected before any mutant "result"
scratch bad-omc "lvl-ignores-3xx"
drive bad-omc OMC=/nonexistent/omc
expect compiler-missing 2 'prerequisite missing: compiler'
printf '#!/bin/sh\nexit 1\n' > "$W/failing-omc"; chmod 755 "$W/failing-omc"
scratch bad-omc2 "lvl-ignores-3xx"
drive bad-omc2 OMC="$W/failing-omc"
expect compiler-fails-baseline-build 5 'BASELINE build failed'
if grep -q '^MUTANT ' "$OUT"; then no compiler-fails-no-mutant-line "mutant lines printed with a failing compiler"; else ok compiler-fails-no-mutant-line; fi
printf 'not a program\n' > "$W/text-omc"; chmod 644 "$W/text-omc"
scratch bad-omc3 "lvl-ignores-3xx"
drive bad-omc3 OMC="$W/text-omc"
expect compiler-not-executable 2 'prerequisite missing: compiler'

# 3. a mutation that does not change the source is not a mutant
scratch unapplied "lvl-ignores-3xx"
sed 's|^m trit/trit.om lvl-ignores-3xx .*|m trit/trit.om lvl-ignores-3xx '"'"'s/NO SUCH TEXT IN trit.om/x/'"'"' read|' "$W/unapplied/tools/trit/mutate.sh" > "$W/unapplied/m" && cp "$W/unapplied/m" "$W/unapplied/tools/trit/mutate.sh"
drive unapplied OMC="$OMC"
expect mutation-not-applied 3 'MUTANT 1 lvl-ignores-3xx: NOT APPLIED' 'mutant not applied or invalid'

# 4. a mutant that does not compile is invalid, not killed
scratch invalid "lvl-ignores-3xx"
sed 's|^m trit/trit.om lvl-ignores-3xx .*|m trit/trit.om lvl-ignores-3xx '"'"'s/\\z/\\n@@@ not omega\\n/'"'"' read|' "$W/invalid/tools/trit/mutate.sh" > "$W/invalid/m" && cp "$W/invalid/m" "$W/invalid/tools/trit/mutate.sh"
drive invalid OMC="$OMC"
expect mutant-build-invalid 3 'MUTANT 1 lvl-ignores-3xx: BUILD INVALID' 'mutant not applied or invalid'

# 5. a surviving mutant fails the run: test.sh that always passes
STUBPASS='#!/bin/sh
echo "TOTAL pass=1 fail=0 skip=0"
exit 0
'
scratch survivor "lvl-ignores-3xx"
printf '%s' "$STUBPASS" > "$W/survivor/tools/trit/test.sh"
drive survivor OMC="$OMC"
expect survivor-fails-run 1 'test.sh survived' 'SURVIVED' 'mutate.sh: FAIL survivor'

# 6. a test runner that dies is a harness error, never a kill: baseline passes, mutants make it exit 2
STUBDIE='#!/bin/sh
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
if cmp -s "$HERE/trit.om" "$REF_TRIT_OM"; then echo "TOTAL pass=1 fail=0 skip=0"; exit 0; fi
echo "test.sh: no trit binary" >&2; exit 2
'
scratch harness-dies "lvl-ignores-3xx"
printf '%s' "$STUBDIE" > "$W/harness-dies/tools/trit/test.sh"
drive harness-dies OMC="$OMC"
expect test-runner-crash-not-a-kill 4 'test.sh harness-error' 'HARNESS ERROR (test.sh)' 'mutate.sh: FAIL harness error'
if grep -q 'test.sh killed' "$OUT"; then no crash-not-counted-killed "a crash was counted as killed"; else ok crash-not-counted-killed; fi
# exit 1 without any FAIL line or with fail=0 is also not a kill
STUBEXIT1='#!/bin/sh
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
if cmp -s "$HERE/trit.om" "$REF_TRIT_OM"; then echo "TOTAL pass=1 fail=0 skip=0"; exit 0; fi
echo "TOTAL pass=1 fail=0 skip=0"; exit 1
'
scratch harness-exit1 "lvl-ignores-3xx"
printf '%s' "$STUBEXIT1" > "$W/harness-exit1/tools/trit/test.sh"
drive harness-exit1 OMC="$OMC"
expect exit1-without-fail-not-a-kill 4 'test.sh harness-error'

# 7. difftest that dies (no DIFF verdict) is a harness error, not a kill
STUBDIFF='#!/bin/sh
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
if cmp -s "$HERE/../trit.om" "$REF_TRIT_OM"; then echo "DIFF agree=200/200 seed=3"; exit 0; fi
exit 1
'
scratch diff-dies "lvl-ignores-3xx"
printf '%s' "$STUBDIFF" > "$W/diff-dies/tools/trit/proof/difftest.sh"
drive diff-dies OMC="$OMC"
expect difftest-crash-not-a-kill 4 'difftest harness-error' 'HARNESS ERROR (difftest)'

# 8. a failing baseline stops the run before any mutant
STUBFAIL='#!/bin/sh
echo "FAIL x: broken"; echo "TOTAL pass=0 fail=1 skip=0"; exit 1
'
scratch base-fails "lvl-ignores-3xx"
printf '%s' "$STUBFAIL" > "$W/base-fails/tools/trit/test.sh"
drive base-fails OMC="$OMC"
expect baseline-failure-stops 5 'BASELINE did not pass'
if grep -q '^MUTANT ' "$OUT"; then no baseline-failure-runs-no-mutants "mutants ran after a failed baseline"; else ok baseline-failure-runs-no-mutants; fi

printf 'TOTAL pass=%d fail=%d logs=%s\n' "$pass" "$fail" "$W"
[ "$fail" = 0 ]
