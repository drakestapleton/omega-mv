#!/bin/sh
# L836 regression run of the #748 OM-2 case lists on omega-mv main 1e3ecbba (seed/out/omc 6d1b1cf5),
# 2026-11-09. Usage (repository root): sh seed/qualification/om2/evidence/phaseB/main-1e3ecbba/run.sh OMC EVID
#   OMC   a seed-born compiler (sh seed/omega-from-seed.sh on a clean archive of the tree); its sha256 is the pin
#   EVID  new evidence directory (logs and summary.txt); scratch goes under build/l836
# Mutant lists get scratch copies of the current seed/omc/omc.om; no tracked file is edited.
set -u
OMC=$1; EVID=$2; Q=seed/qualification/om2; B=build/l836
[ -e "$EVID" ] && { echo "evidence dir exists: $EVID" >&2; exit 91; }
mkdir -p "$EVID" && rm -rf "$B" && mkdir -p "$B/scratch" || exit 9
H=$(sha256sum < "$OMC" | cut -c1-64)
"$OMC" < $Q/gate.om > "$B/gate" && chmod 700 "$B/gate" || exit 9
{ echo "omc $H (committed seed/out/omc $(cut -c1-64 seed/out/omc.sha256))"
  echo "gate $(sha256sum < "$B/gate" | cut -c1-64)"; } > "$EVID/summary.txt"
for s in s1 s2 s3 s4; do mkdir -p build/om2-qual/cand-$s; cp seed/omc/omc.om build/om2-qual/cand-$s/omc.om; done
run() { rc=0; "$B/gate" "$OMC" "$H" "$2" "$B/scratch/$1" > "$EVID/$1.log" 2>&1 || rc=$?
  echo "$1 rc=$rc $(tail -1 "$EVID/$1.log")" >> "$EVID/summary.txt"; }
run selftest-pass $Q/selftest/pass.cases
run selftest-fail $Q/selftest/fail.cases
run selftest-controls $Q/selftest/controls.cases
run selftest-emit $Q/selftest/emit.cases
run s0s2 $Q/sec/s0s2/candidate.cases
run s3s4 $Q/sec/s3s4/candidate.cases
run s4fuel $Q/sec/s4fuel/candidate.cases
run s5s7 $Q/sec/s5s7/candidate.cases
run s3s4-mutant-kills $Q/sec/s3s4/mutant-kills.cases
run leak $Q/leak/leak.cases
run leak-candidate $Q/leak/candidate.cases
run s1-mutants $Q/candidates/s1/s1-mutants.cases
run s1-lexmutants $Q/candidates/s1/s1-lexmutants.cases
run s2-mutants $Q/candidates/s2/s2-mutants.cases
run s3-mutants $Q/candidates/s3/s3-mutants.cases
run s4-mutants $Q/candidates/s4/s4-mutants.cases
run s4-part-mutants $Q/candidates/s4/s4-part-mutants.cases
# negative control: a wrong compiler pin makes the gate INVALID (exit 3) and runs no case
rc=0; "$B/gate" "$OMC" 0000000000000000000000000000000000000000000000000000000000000000 \
  $Q/selftest/pass.cases "$B/scratch/negpin" > "$EVID/neg-pin.log" 2>&1 || rc=$?
echo "neg-pin rc=$rc $(tail -1 "$EVID/neg-pin.log")" >> "$EVID/summary.txt"
rm -rf build/om2-qual
