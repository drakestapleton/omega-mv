#!/bin/sh
# mutate.sh -- each mutant breaks one round-4 rule in trit.om or the shared codebook.om; the fixture
# suite (test.sh) must kill every mutant, and the Lean differential test (difftest.sh, N=200 seed 3)
# must kill every mutant whose behaviour it models (read mode; see "ack" below).
# Usage from the repo root:  sh tools/trit/mutate.sh        (needs perl, python3, lean)
#   OMC   compiler, default <repo>/seed/out/omc (a relative path is made absolute)
#   LEAN  lean binary, default lean
#   W     work directory, default a fresh mktemp -d; per-mutant logs are kept under $W/logs
# Verdicts, one line per mutant, from three independent observations:
#   NOT APPLIED   the mutation expression changed nothing: the mutant is not a mutant
#   BUILD INVALID the mutant (or the baseline) did not compile
#   test.sh       killed only when it ran to its own "TOTAL pass=P fail=F skip=S" line with F>=1 and exit 1;
#                 exit 0 = survived; anything else (exit 2 "no binary", crash, timeout, no TOTAL line) =
#                 HARNESS ERROR, never counted as a kill
#   difftest      killed only on its own "DIFF disagree=" line with exit 1; "DIFF agree=" = survived;
#                 anything else (python3/lean failure, no output) = HARNESS ERROR
# The unmutated tree is built and must pass both first; otherwise no mutant is run.
# difftest models read mode only (no --ack, no fsync), so the "ack" mutants are judged by test.sh alone
# and the differential outcome is recorded, not required.
# Exit: 0 every mutant applied, built, killed by test.sh, and killed by difftest where modelled;
#       1 a mutant survived; 2 a prerequisite is missing; 3 a mutant is not applied or invalid;
#       4 a harness error; 5 the baseline did not build or did not pass.
# Precedence when several apply: 5, 2, 4, 3, 1.
set -u
R=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$R" || exit 2
OMC=${OMC:-$R/seed/out/omc}
case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
LEAN=${LEAN:-lean}
export OMC LEAN
for t in perl python3 cmp timeout; do
  command -v "$t" >/dev/null 2>&1 || { echo "mutate.sh: prerequisite missing: $t" >&2; exit 2; }
done
[ -f "$OMC" ] && [ -x "$OMC" ] || { echo "mutate.sh: prerequisite missing: compiler $OMC is not an executable file" >&2; exit 2; }
command -v "$LEAN" >/dev/null 2>&1 || { echo "mutate.sh: prerequisite missing: lean ($LEAN)" >&2; exit 2; }
if [ -z "${W:-}" ]; then W=$(mktemp -d "${TMPDIR:-/tmp}/trit-mut.XXXXXX") || exit 2; else
  if [ -e "$W" ] || [ -L "$W" ]; then echo "work directory already exists: $W (preserved)" >&2; exit 2; fi
  mkdir -p "$W" || exit 2
fi
case $W in /*) ;; *) W=$(pwd)/$W ;; esac
LOGS=$W/logs; mkdir -p "$LOGS"
echo "mutate.sh: omc=$OMC sha256=$(sha256sum < "$OMC" | cut -c1-64) logs=$LOGS"

# stage DIR: a private copy of the sources the build and both tests read.
stage() {
  rm -rf "$1"; mkdir -p "$1/tools" "$1/seed/trace"
  cp -r tools/trit tools/codebook "$1/tools/"; cp seed/trace/sha256.om "$1/seed/trace/"
  rm -rf "$1/tools/trit/trit.bin" "$1/tools/codebook/codebook.bin"
}
# build DIR TAG: both binaries with $OMC; logs kept.
build() { (cd "$1" && sh tools/trit/build.sh && sh tools/codebook/build.sh) > "$LOGS/$2.build.log" 2>&1; }
# run_test DIR TAG: prints killed|survived|harness-error.
run_test() {
  (cd "$1" && FIX="$W/fix-$2" timeout 300 sh tools/trit/test.sh) > "$LOGS/$2.test.log" 2>&1; rc=$?
  tot=$(grep '^TOTAL pass=[0-9]* fail=[0-9]* skip=[0-9]*$' "$LOGS/$2.test.log" | tail -1)
  f=${tot#*fail=}; f=${f%% *}
  case $tot in
    '') echo harness-error ;;
    *) if [ "$rc" = 0 ] && [ "$f" = 0 ]; then echo survived
       elif [ "$rc" = 1 ] && [ "$f" -ge 1 ] 2>/dev/null && grep -q '^FAIL ' "$LOGS/$2.test.log"; then echo killed
       else echo harness-error; fi ;;
  esac
}
run_diff() {
  (cd "$1" && N=200 SEED=3 W="$W/diff-$2" timeout 600 sh tools/trit/proof/difftest.sh) > "$LOGS/$2.diff.log" 2>&1; rc=$?
  if [ "$rc" = 0 ] && grep -q '^DIFF agree=' "$LOGS/$2.diff.log"; then echo survived
  elif [ "$rc" = 1 ] && grep -q '^DIFF disagree=' "$LOGS/$2.diff.log"; then echo killed
  else echo harness-error; fi
}

# Baseline: the unmutated tree must build and pass both, or a "kill" proves nothing.
stage "$W/base"
if ! build "$W/base" base; then echo "BASELINE build failed (see $LOGS/base.build.log)"; exit 5; fi
bt=$(run_test "$W/base" base); bd=$(run_diff "$W/base" base)
echo "BASELINE test.sh $bt, difftest $bd"
if [ "$bt" != survived ] || [ "$bd" != survived ]; then
  echo "BASELINE did not pass (test.sh $bt, difftest $bd); see $LOGS/base.*.log"; exit 5
fi

k1=0; k2=0; n=0; surv=0; inval=0; herr=0
# m FILE NAME EXPR SCOPE: SCOPE "read" = difftest must kill it; "ack" = outside the differential model.
m() {
  n=$((n+1)); f=$1; name=$2; expr=$3; scope=$4
  stage "$W/r"
  perl -0pi -e "$expr" "$W/r/tools/$f"
  if cmp -s "$W/r/tools/$f" "tools/$f"; then echo "MUTANT $n $name: NOT APPLIED"; inval=$((inval+1)); return; fi
  if ! build "$W/r" "m$n"; then echo "MUTANT $n $name: BUILD INVALID (see $LOGS/m$n.build.log)"; inval=$((inval+1)); return; fi
  t=$(run_test "$W/r" "m$n"); d=$(run_diff "$W/r" "m$n")
  verdict=ok
  case $t in
    killed) k1=$((k1+1)) ;;
    survived) verdict=SURVIVED; surv=$((surv+1)) ;;
    *) verdict="HARNESS ERROR (test.sh)"; herr=$((herr+1)) ;;
  esac
  case $d in
    killed) k2=$((k2+1)) ;;
    survived) if [ "$scope" = read ] && [ "$verdict" = ok ]; then verdict="SURVIVED (difftest)"; surv=$((surv+1)); fi ;;
    *) verdict="HARNESS ERROR (difftest)"; herr=$((herr+1)) ;;
  esac
  echo "MUTANT $n $name [$scope]: test.sh $t, difftest $d => $verdict"
}
m trit/trit.om lvl-ignores-3xx 's/if and eq get vf 0 1 eq get ve 0 1/if eq get vf 0 1/' read
m trit/trit.om verify-disabled 's/put vk 0 1\n/put vk 0 0\n/' read
m trit/trit.om quota-counts-forged 's/if eq get vm 0 0\nret true\nend\n//' read
m trit/trit.om quota-counts-replays 's/if seenc s n v\nret true\nend\n//' read
m trit/trit.om unsigned-emergency-jumps 's/if eq open te 2\nmktok 1/if gt open te 0\nmktok 1/' read
m trit/trit.om ack-no-counter-advance 's/ackv cur off\n//' ack
m trit/trit.om ack-advances-past-token 's/while lt p off bound BIG/while lt p get fbn 0 bound BIG/' ack
m trit/trit.om ack-no-lock 's/lk = lockst\n/lk = int 99\n/' ack
m trit/trit.om sig-not-stripped 's/ee = lp\nnf = sub nf 1\n//' read
m trit/trit.om cursor-no-dir-fsync 's/ptext tcur\nsyncdir\n/ptext tcur\n/' ack
m codebook/codebook.om no-batch-table 's/vtput s sn ctr\n//' read
m codebook/codebook.om counter-file-ignored 's/v = rdctf s n\n/v = ulong 0\n/' read
m codebook/codebook.om stale-allows-equal 's/if le ctr rdctr s sn/if lt ctr rdctr s sn/' read
m codebook/codebook.om counter-no-dir-fsync 's/ctrpath s n\nsyncdir\n//' ack
m codebook/codebook.om mac-not-checked 's/ret eq x 0\n/ret true\n/' read
m codebook/codebook.om 1xx-is-emergency 's/if and ge g 300 lt g 400\nret true/if and ge g 100 lt g 400\nret true/' read
echo "MUTANTS $n killed-by-test.sh=$k1 killed-by-difftest=$k2 survived=$surv invalid=$inval harness-errors=$herr"
if [ "$herr" -gt 0 ]; then echo "mutate.sh: FAIL harness error (not a kill); logs $LOGS"; exit 4; fi
if [ "$inval" -gt 0 ]; then echo "mutate.sh: FAIL mutant not applied or invalid; logs $LOGS"; exit 3; fi
if [ "$surv" -gt 0 ]; then echo "mutate.sh: FAIL survivor; logs $LOGS"; exit 1; fi
if [ "$n" -eq 0 ] || [ "$k1" -ne "$n" ]; then echo "mutate.sh: FAIL not every mutant killed by test.sh ($k1 of $n)"; exit 1; fi
echo "mutate.sh: PASS $k1/$n killed by test.sh; difftest killed $k2 (the ack mutants are outside its read-mode model)"
exit 0
