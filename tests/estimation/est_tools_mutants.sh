#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# est_tools_mutants.sh -- negative controls for tests/estimation/est_tools_parity.sh.
#
# Each mutant is one deliberate fault in the shipped OM-2 est_fit or est_eval
# (tools/estimation/est_fit.om, tools/estimation/est_eval.om). The mutant is applied to a copy of
# the sources, the three tools are rebuilt as the parity run builds them, and the cases must
# show a difference from the committed C-reference goldens (tests/estimation/est_tools_golden,
# generated from the C at main commit 3f2c70dc5); each mutant run stops at its first differing
# case. A mutant that does not apply, does not build, or runs every case equal to the goldens
# fails this script.
# Not distinguished by any case: the 0.01-nat selection margin (the simpler of two calibrated
# models within 0.01 of the best is selected). The cases execute it, but no fixture found has two
# calibrated models within 0.01 with the later one ahead (a search over 3840 synthetic drift and
# parameter combinations found none), so a mutant of the margin would survive and is not listed.
#
# usage: EST_OM_LIB="<the ESTT_OM_LIB list>" [EST_MUTANT_JOBS=6] EST_PARITY_WORK=<work dir of a passing
#        est_tools_parity.sh run> tests/estimation/est_tools_mutants.sh [OMC]
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OMC=${1:-$ROOT/seed/out/omc}
case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
LIB=${EST_OM_LIB:?set EST_OM_LIB to the ESTT_OM_LIB list of mk/estimation_tools.mk}
W=${EST_PARITY_WORK:?set EST_PARITY_WORK to the work dir of a passing est_tools_parity.sh run}
GOLD=$ROOT/tests/estimation/est_tools_golden
[ -f "$W/om/toolid.om" ] && [ -f "$W/om/toolid_t.om" ] || { echo "MUTANTS FAIL no parity work dir"; exit 2; }
M=$W/mut
rm -rf "$M"; mkdir -p "$M"

# name|file|perl substitution (applied with perl -0pi, so \n spans lines)
cat > "$M/list" <<'EOF'
fit-loglik-2pi|tools/estimation/est_fit.om|s/est_log mul f64 6.283185307179586 sv/est_log mul f64 6.28318 sv/
fit-burn-in|tools/estimation/est_fit.om|s/    if lt get g_rps_L ki EST_BURN_IN\n      continue\n    end\n//
fit-include-coast|tools/estimation/est_fit.om|s/    if ne and fl 3 0\n      continue\n    end\n/    if ne and fl 1 0\n      continue\n    end\n/
fit-runA-only|tools/estimation/est_fit.om|s/if and eq synth 0 not er_eq view fsha 64 t_er_run_a_sha 64/if and eq synth 1 not er_eq view fsha 64 t_er_run_a_sha 64/
fit-m2-k|tools/estimation/est_fit.om|s/est_mix_fit_em nu EST_M2_K/est_mix_fit_em nu sub EST_M2_K 1/
eval-zc95|tools/estimation/est_eval.om|s/const EE_ZC95 f64 1.959964/const EE_ZC95 f64 1.96/
eval-zc50|tools/estimation/est_eval.om|s/const EE_ZC50 f64 0.674490/const EE_ZC50 f64 0.67/
eval-band50|tools/estimation/est_eval.om|s/SF_COV f64 0.46 f64 0.54/SF_COV f64 0.47 f64 0.54/
eval-band95|tools/estimation/est_eval.om|s/SF_COV 2 f64 0.93 f64 0.97/SF_COV 2 f64 0.93 f64 0.96/
eval-nis-band|tools/estimation/est_eval.om|s/SF_NIS f64 0.80 f64 1.25/SF_NIS f64 0.80 f64 1.05/
eval-bias|tools/estimation/est_eval.om|s/SF_BIAS f64 0.10/SF_BIAS f64 0.01/
eval-lag1|tools/estimation/est_eval.om|s/SF_LAG1 f64 0.20/SF_LAG1 f64 0.02/
eval-quarter-band|tools/estimation/est_eval.om|s/SF_QCOV q f64 0.90 f64 0.99/SF_QCOV q f64 0.95 f64 0.99/
eval-regime-gate|tools/estimation/est_eval.om|s/SU_RN g 100/SU_RN g 101/
eval-ten-step|tools/estimation/est_eval.om|s/long 10000000000/long 9000000000/
eval-select-m0-only|tools/estimation/est_eval.om|s/    for m ulong nm\n      if eq sel 0\n/    for m ulong 1\n      if eq sel 0\n/
eval-max-pairs|tools/estimation/est_eval.om|s/const EE_MAX_PAIRS ulong 512/const EE_MAX_PAIRS ulong 511/
eval-prefix-k|tools/estimation/est_eval.om|s/  put ks 1 500\n/  put ks 1 400\n/
eval-min-samples-stats|tools/estimation/est_eval.om|s/  if lt n 3\n/  if lt n 4\n/
eval-min-samples-rmse|tools/estimation/est_eval.om|s/  rle = ulong 0\n  if ge n 3\n/  rle = ulong 0\n  if ge n 4\n/
eval-ljung-lags|tools/estimation/est_eval.om|s/  for k1 ulong 10\n/  for k1 ulong 9\n/
eval-bias-dof|tools/estimation/est_eval.om|s/sdv = fsqrt div v sub dn f64 1.0/sdv = fsqrt div v dn/
eval-nested-begin|tools/estimation/est_eval.om|s/      put g_ee_mk_m 4 add get g_ee_mk_m 4 1\n      if ne ee_mk_push get st 0 tv 0\n        ret 1\n      end\n/      put g_ee_mk_m 4 add get g_ee_mk_m 4 1\n/
eval-stray-end|tools/estimation/est_eval.om|s/      put g_ee_mk_m 5 add get g_ee_mk_m 5 1\n      ret 0\n/      ret 0\n/
eval-unclosed|tools/estimation/est_eval.om|s/    put g_ee_mk_m 3 1\n//
eval-in-trial-edge|tools/estimation/est_eval.om|s/      if le t get g_ee_mk_e i\n/      if lt t get g_ee_mk_e i\n/
eval-wilson|tools/estimation/est_eval.om|s/  t2 = div z2 mul mul f64 4.0 dn dn\n/  t2 = div z2 mul mul f64 2.0 dn dn\n/
fit-long-data-usage|tools/estimation/est_fit.om|s/  if lt dl 0\n    ret ef_load_refuse idx\n  end\n  if lt ol 0\n/  if or lt dl 0 lt ol 0\n/
fit-empty-arg-usage|tools/estimation/est_fit.om|s/  if or lt v1l 0 lt ol 0\n/  if or le v1l 0 le ol 0\n/
lib-mismatch-want|tools/estimation/est_replay.om|s/    er_err_add view want 64\n//
EOF

# one mutant: its verdict line goes to $T/res
one() {
  n=$1; name=$2; f=$3; expr=$4; T=$M/t$n
  mkdir -p "$T"
  # shellcheck disable=SC2086
  (cd "$ROOT" && tar -cf - $LIB tools/estimation/est_fit.om tools/estimation/est_eval.om) | tar -xf - -C "$T"
  file=$T/$f
  cp "$file" "$file.orig"
  perl -0pi -e "$expr" "$file"
  if cmp -s "$file" "$file.orig"; then echo "MUTANT $n $name NOT-APPLIED $expr" > "$T/res"; return; fi
  rm -f "$file.orig"
  # shellcheck disable=SC2086
  if ! (cd "$T" && cat $LIB tools/estimation/est_fit.om | "$OMC" > "$T/est_fit" 2> "$T/omc.err" \
        && cat $LIB "$W/om/toolid.om" tools/estimation/est_eval.om | "$OMC" > "$T/est_eval" 2>> "$T/omc.err" \
        && cat $LIB "$W/om/toolid_t.om" tools/estimation/est_eval.om | "$OMC" > "$T/est_eval_t" 2>> "$T/omc.err"); then
    echo "MUTANT $n $name NO-BUILD $(head -1 "$T/omc.err") $expr" > "$T/res"; return
  fi
  chmod +x "$T/est_fit" "$T/est_eval" "$T/est_eval_t"
  EST_STOP_GOLD=$GOLD sh "$ROOT/tests/estimation/est_tools_parity.sh" --run "$T/est_fit" "$T/est_eval" "$T/est_eval_t" "$T/o" > "$T/run.log" 2>&1 || true
  if [ -f "$T/o/.stop" ]; then
    echo "MUTANT $n $name KILLED by $(cat "$T/o/.stop")" > "$T/res"
  else
    hit=""
    for g in "$GOLD"/*.out; do cmp -s "$g" "$T/o/$(basename "$g")" || hit="$hit $(basename "$g" .out)"; done
    if [ -n "$hit" ]; then echo "MUTANT $n $name KILLED by$hit" > "$T/res"
    else echo "MUTANT $n $name SURVIVED $expr" > "$T/res"; fi
  fi
  rm -rf "$T/o.fx"
}

# EST_MUTANT_JOBS mutants at a time (each runs the cases up to its first difference)
J=${EST_MUTANT_JOBS:-6}
n=0
while IFS='|' read -r name f expr; do
  [ -n "$name" ] || continue
  n=$((n + 1))
  one "$n" "$name" "$f" "$expr" &
  [ $((n % J)) -ne 0 ] || wait
done < "$M/list"
wait
killed=0; bad=0
i=0
while [ "$i" -lt "$n" ]; do
  i=$((i + 1))
  r=$(cat "$M/t$i/res" 2>/dev/null || echo "MUTANT $i NO-RESULT")
  echo "$r"
  case $r in *" KILLED by"*) killed=$((killed + 1)) ;; *) bad=$((bad + 1)) ;; esac
done
echo "EST_TOOLS_MUTANTS run=$n killed=$killed bad=$bad"
[ "$bad" -eq 0 ]
