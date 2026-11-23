#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# pd0l_mutants.sh -- negative controls for tests/physics0/verify/pd0l_parity.sh.
#
# Each mutant is one deliberate fault in the OM-2 ports the differential qualifies: the ladder checker
# (src/physics0/ladder/pd0_ladder.om: statistics, T1..T7, demotion, the ledger reader, claim, law and
# T8 verification), the scorer (src/physics0/score/pd0_score.om: structure, rollouts, the memoriser,
# the L6 reference and the reference solver) and the memoriser's stored-number count
# (src/physics0/controls/pd0_controls.om). The mutant is applied to a copy of the sources, the OM
# dumper is rebuilt, and the corpora of a passing parity run must show at least one difference from
# the committed C-reference goldens (tests/physics0/verify/ladder_golden, generated from the C at main
# commit 3f2c70dc5; the passing run leaves them unpacked in its work dir as out/<corpus>.c). A mutant that does not apply, does not build, or shows no difference fails this
# script.
#
# usage: PD0L_PARITY_WORK=<work dir of a passing pd0l_parity.sh run> tests/physics0/verify/pd0l_mutants.sh [OMC]
# score-onestep-bound-0 drops both one-step guards of pd0_score.om (the per-episode prediction and its
# count): guarding only the prediction is not observable, the OM sums it and then counts nothing.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
OMC=${1:-$ROOT/seed/out/omc}
case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
W=${PD0L_PARITY_WORK:?set PD0L_PARITY_WORK to the work dir of a passing pd0l_parity.sh run}
GOLD=$ROOT/tests/physics0/verify/ladder_golden
[ -x "$W/pd0l_dump_om" ] && [ -d "$W/corpus" ] && [ -d "$W/out" ] || { echo "MUTANTS FAIL no parity work dir"; exit 2; }
[ -f "$GOLD/MANIFEST" ] || { echo "MUTANTS FAIL missing $GOLD/MANIFEST"; exit 2; }
M=$W/mut
rm -rf "$M"; mkdir -p "$M"
L=src/physics0/ladder/pd0_ladder.om
S=src/physics0/score/pd0_score.om
K=src/physics0/controls/pd0_controls.om

# name|file|perl substitution (applied with perl -0pi, so \n spans lines; the first match only)
cat > "$M/list" <<EOF
t1-records|$L|s/if lt ok get lp_min_t1_rec 0/if le ok get lp_min_t1_rec 0/
t1-episodes|$L|s/if lt eps get lp_min_t1_ep 0/if le eps get lp_min_t1_ep 0/
t2-r-tolerance|$L|s/r_mic long 1000\n/r_mic long 2000\n/
t2-weak|$L|s/if lt fabs r 0.3f64/if lt fabs r 0.2f64/
t2-p-bound|$L|s/gt p 0.01f64/gt p 0.02f64/
t2-p-claim|$L|s/gt p_mic long 10000/gt p_mic long 20000/
t2-npairs-zero|$L|s/npairs = ulong 1\n/npairs = ulong 2\n/
t2-shuffles|$L|s/if lt get np_ns_sd 1 ulong 2000/if lt get np_ns_sd 1 ulong 1999/
t2-claimed-n|$L|s/if or lt n ulong 100 ne n ulong n_cl/if lt n ulong 100/
t2-same-variable|$L|s/if eq va vb\n/if ne va va\n/
pearson-mean|$L|s/my = div sy f64 n/my = div sy f64 add n 1/
pearson-guard|$L|s/if or le sxx 0.0f64 le syy 0.0f64/if le sxx 0.0f64/
perm-plus-one|$L|s/ret div f64 add hits 1 f64 add n_shuf 1/ret div f64 hits f64 add n_shuf 1/
perm-ties|$L|s/if ge fabs lad_pearson_xy n 1 r0/if gt fabs lad_pearson_xy n 1 r0/
shuffle-range|$L|s/j = rem pd0_splitmix64 rng add i 1/j = rem pd0_splitmix64 rng i/
nrmse-empty|$L|s/to long\nif eq n ulong 0\nret long 9223372036854775807/to long\nif eq n ulong 0\nret long 0/
nrmse-variance|$L|s/var = sub div get acc add j 16 fn_cnt mul m m/var = div get acc add j 16 fn_cnt/
nrmse-sd-floor|$L|s/sd = fsqrt var\nend\nv = rmse\nif gt sd 0.000000001f64/sd = fsqrt var\nend\nv = rmse\nif gt sd 1.0f64/
pooled-sd-scale|$L|s/sd = div f64 get sd_mic j 1000000.0f64/sd = div f64 get sd_mic j 100000.0f64/
nrmse-cap|$L|s/if gt worst 9000000000000.0f64/if gt worst 9000000.0f64/
conf-numerator|$L|s/num = mul ulong 1000000 ulong add p uint 1/num = mul ulong 1000000 ulong add p uint 2/
conf-wrap|$L|s/ret uint and div num den ulong 0xffffffff/ret uint and div num den ulong 0x7fffffff/
param-rollout|$L|s/put lp_roll_steps 0 uint 20/put lp_roll_steps 0 uint 19/
param-channel|$L|s/put lp_cmin c long -2000000/put lp_cmin c long -2000001/
param-eps|$L|s/put lp_eps_bound 0 long 20000/put lp_eps_bound 0 long 20001/
state-name|$L|s/text LS_N7 "REPLICATED"/text LS_N7 "REPLICATE"/
t3-relation|$L|s/ne get vr_nch ridx get lp_n_ch 0/ne get vr_nch ridx get vr_nch ridx/
t3-degree|$L|s/if gt vr_rel_max_degree ridx 3/if gt vr_rel_max_degree ridx 4/
t3-size|$L|s/if gt vr_rel_size ridx get lp_size_bound 0/if ge vr_rel_size ridx get lp_size_bound 0/
t3-fit-error|$L|s/gt one long 50000/gt one long 60000/
t3-white|$L|s/if gt fabs ac 0.1f64/if gt fabs ac 0.2f64/
t4-no-rival|$L|s/if eq nriv ulong 0\nlc_set_code 4 PD0V_T4_NO_RIVAL/if eq nriv ulong 9\nlc_set_code 4 PD0V_T4_NO_RIVAL/
t4-eps-zero|$L|s/if or le eps long 0 gt eps get lp_eps_bound 0/if gt eps get lp_eps_bound 0/
t4-after-trial|$L|s/if ne lc_ep_is i TAG_TRIAL 0\nlc_set_code 4/if ne lc_ep_is i TAG_REP 0\nlc_set_code 4/
t5-hypotheses|$L|s/if ne ulong get ve_nhyp pslot add ulong 1 ulong get lc_fals_nriv 0/if lt ulong get ve_nhyp pslot add ulong 1 ulong get lc_fals_nriv 0/
t5-min-trials|$L|s/if gt get lc_fals_mint 0 need/if lt get lc_fals_mint 0 need/
t6-eps|$L|s/if gt err get lr_eps 0\nput lr_f 0 add get lr_f 0 uint 1\nlc_t6_record/if gt err mul long 2 get lr_eps 0\nput lr_f 0 add get lr_f 0 uint 1\nlc_t6_record/
t7-three-eps|$L|s/if gt e1 mul long 3 get lr_eps 0/if gt e1 mul long 4 get lr_eps 0/
t7-batch-eps|$L|s/if gt eb get lr_eps 0/if gt eb mul long 2 get lr_eps 0/
t7-origin|$L|s/if or lt add pln 1 rnd lt add rnd 1 pln/if or lt add pln 2 rnd lt add rnd 2 pln/
t7-void-batch|$L|s/if gt lc_batch_voids b uint 3\ncontinue/if gt lc_batch_voids b uint 4\ncontinue/
t7-too-small|$L|s/if or gt ready uint 0 gt nbat ulong 0/if gt ready uint 0/
demote-state|$L|s/put lr_state 0 LS_HYPOTHESIS\nput lr_demoted 0 1/put lr_state 0 LS_REPLICATED\nput lr_demoted 0 1/
demote-flag|$L|s/put lr_demoted 0 1\n/put lr_demoted 0 0\n/
ledger-chain|$L|s/if ne get vledg_buf add pb k get exp_prev k\nret 0/if ne get vledg_buf add pb k get vledg_buf add pb k\nret 0/
ledger-hash|$L|s/if eq lc_ledg_hash_ok o hlen view out_hash 0/if eq lc_ledg_hash_ok o hlen view out_hash 7/
ledger-version|$L|s/if ne pd0_get_u16 view hdr ulong 8 ushort 1/if eq pd0_get_u16 view hdr ulong 8 ushort 2/
ledger-size-order|$L|s/if eq lc_ledg_chain_ok add add o PD0_LEDG_HDR plen exp_prev 0\nret PD0V_CHAIN_BROKEN\nend\nif gt hlen ulong 16384\nret PD0V_TOO_LARGE\nend/if gt hlen ulong 16384\nret PD0V_TOO_LARGE\nend\nif eq lc_ledg_chain_ok add add o PD0_LEDG_HDR plen exp_prev 0\nret PD0V_CHAIN_BROKEN\nend/
claim-eps|$L|s/p = lad_buf_micro dst p cap get lr_eps 0/p = lad_buf_micro dst p cap get lp_eps_bound 0/
claim-fraction|$L|s/fp = rem ulong a ulong 1000000/fp = rem ulong a ulong 100000/
emit-refuted|$L|s/st = PD0_LAW_REFUTED/st = PD0_LAW_REJECTED/
verify-demoted|$L|s/if ne get lr_demoted 0 0\nret PD0V_LAW_DEMOTED/if ne get lr_demoted 0 7\nret PD0V_LAW_DEMOTED/
verify-hypothesis|$L|s/if and lt get lr_state 0 LS_HYPOTHESIS eq get lr_demoted 0 0/if lt get lr_state 0 LS_CANDIDATE/
verify-forbidden|$L|s/ret PD0V_T8_CLAIM_FORBIDDEN_WORD/ret PD0V_OK/
verify-rejected|$L|s/if ne lst PD0_LAW_REJECTED\nrc = lad_verify_rel_match ls/if ne lst PD0_LAW_REFUTED\nrc = lad_verify_rel_match ls/
verify-confidence|$L|s/if ne get vl_conf_ppm ls get lr_conf_ppm 0/if lt get vl_conf_ppm ls get lr_conf_ppm 0/
verify-chain-root|$L|s/if eq lad_chain_root_ok ls 0\nret PD0V_T8_CHAIN_ROOT_MISMATCH/if eq lad_chain_root_ok ls 7\nret PD0V_T8_CHAIN_ROOT_MISMATCH/
verify-refutations|$L|s/if ne uint get vr_nref lrslot get lr_n_refut 0\nret PD0V_T8_REFUTATION_COUNT_MISMATCH/if ne uint get vr_nref lrslot uint get vr_nref lrslot\nret PD0V_T8_REFUTATION_COUNT_MISMATCH/
score-first-code|$S|s/if eq get sr_code 0 0\nput sr_code 0 code/if ne code 0\nput sr_code 0 code/
score-empty-nrmse|$S|s/if eq n ulong 0\nret long 0\nend\nret lad_acc_nrmse/if eq n ulong 0\nret long 1\nend\nret lad_acc_nrmse/
score-exponent|$S|s/if ne get vr_ex add xb m get sp_t_ex add txb m/if lt get vr_ex add xb m get sp_t_ex add txb m/
score-zero-coef|$S|s/if ne get vr_coef ti long 0\nif ne sc_expo_eq/if ne get vr_coef ti long 7\nif ne sc_expo_eq/
score-tolerance|$S|s/if le d lim\nret 1/if lt d lim\nret 1/
score-constants-off|$S|s/if eq check_c 0\nret 1/if eq check_c 7\nret 1/
score-degree|$S|s/if gt vr_rel_max_degree rslot 3/if gt vr_rel_max_degree rslot 4/
score-size|$S|s/if gt get sr_size 0 get sp_size_bound 0/if ge get sr_size 0 get sp_size_bound 0/
score-stored-bits|$S|s/mul uint 24 stored/mul uint 23 stored/
score-latent|$S|s/if eq get vr_nlat rslot uchar 0\nsc_set_fail PD0V_SCORE_L6_LATENT_MISSING/if eq get vr_nlat rslot uchar 9\nsc_set_fail PD0V_SCORE_L6_LATENT_MISSING/
score-channels|$S|s/if ne get vr_nch rslot get sp_n_ch 0\nput sr_code 0 PD0V_BAD_FIELD/if ne get vr_nch rslot get vr_nch rslot\nput sr_code 0 PD0V_BAD_FIELD/
score-inbox-code|$S|s/sc_set_fail PD0V_SCORE_INBOX_NRMSE/sc_set_fail PD0V_SCORE_EXTRAP_NRMSE/
score-onestep-bound-0|$S|s/if ne get sp_onestep_bound 0 long 0\n/if ne get sp_onestep_bound 0 long 7\n/g
score-l6-factor|$S|s/if lt rn mul get sp_lat_ref_fac 0 get sp_inbox_bound 0/if lt rn get sp_inbox_bound 0/
score-l6-terms|$S|s/if eq mt uint 0\nmt = uint 1/if eq mt uint 0\nmt = uint 2/
ref-min-fit|$S|s/if or lt nfit uint 8 or gt/if or lt nfit uint 7 or gt/
ref-max-terms|$S|s/if gt mt ulong 16\nmt = ulong 16/if gt mt ulong 15\nmt = ulong 15/
ref-round|$S|s/if ge f 0.5f64\nret add t long 1\nend\n//
ref-ridge|$S|s/put a idx add get a idx 0.000000001f64/put a idx add get a idx 0.001f64/
memoriser-apply|$S|s/dd = sub av get sf_bef add bb j/dd = av/
memoriser-distance|$S|s/d = add d mul dv dv/d = add d dv/
memoriser-stored|$K|s/ret mul n add mul uint 2 uint n_obs uint 2/ret mul n add mul uint 2 uint n_obs uint 1/
EOF

OMS="src/physics0/pd0_types.om src/physics0/pd0_rng.om src/physics0/pd0_wire.om src/physics0/ladder/pd0_codes.om
src/physics0/ladder/pd0_fmt.om src/physics0/controls/pd0_receipt.om src/physics0/ladder/pd0_ladder.om
src/physics0/score/pd0_score.om src/physics0/controls/pd0_controls.om tests/physics0/verify/pd0_bundle.om
tests/physics0/verify/pd0l_dump.om"
# cheapest corpora first: a mutant stops at the first corpus that differs
ORDER="hand gen-stats gen-score gen-crafted gen-ledgers gen-damage gen-opts gen-params"
for b in $ORDER; do [ -f "$W/corpus/$b.txt" ] || { echo "MUTANTS FAIL corpus $b missing"; exit 2; }; done
[ "$(ls "$W"/corpus/*.txt | wc -l | tr -d ' ')" -eq 8 ] || { echo "MUTANTS FAIL the corpus list changed; update ORDER"; exit 2; }

# one mutant: writes its verdict line to $T/verdict
one() {
  n=$1; name=$2; f=$3; expr=$4
  T=$M/t$n
  mkdir -p "$T"
  (cd "$ROOT" && tar -cf - $OMS) | tar -xf - -C "$T"
  file=$T/$f
  cp "$file" "$file.orig"
  perl -0pi -e "$expr" "$file"
  if cmp -s "$file" "$file.orig"; then
    echo "MUTANT $n $name NOT-APPLIED $expr" > "$T/verdict"; return
  fi
  if ! (cd "$T" && { echo om2; echo 'text PD0_VERIFIER_COMMIT "parity"'; cat $OMS; } | "$OMC" > "$T/dump" 2>"$T/omc.err"); then
    echo "MUTANT $n $name NO-BUILD $(head -1 "$T/omc.err") $expr" > "$T/verdict"; return
  fi
  chmod +x "$T/dump"
  hit=""
  for b in $ORDER; do
    rc=0
    "$T/dump" < "$W/corpus/$b.txt" > "$T/$b.om" 2>/dev/null || rc=$?
    if [ "$rc" -ne 0 ] || ! cmp -s "$T/$b.om" "$W/out/$b.c"; then hit=" $b"; break; fi
  done
  rm -f "$T"/*.om "$T/dump"
  if [ -n "$hit" ]; then echo "MUTANT $n $name KILLED by$hit" > "$T/verdict"
  else echo "MUTANT $n $name SURVIVED $expr" > "$T/verdict"; fi
}

# PD0L_MUTANT_JOBS mutants at a time (default 8; CPU only)
J=${PD0L_MUTANT_JOBS:-8}
n=0
while IFS='|' read -r name f expr; do
  [ -n "$name" ] || continue
  n=$((n + 1))
  one "$n" "$name" "$f" "$expr" &
  [ $((n % J)) -ne 0 ] || wait
done < "$M/list"
wait
killed=0; bad=0
i=1
while [ "$i" -le "$n" ]; do
  v=$(cat "$M/t$i/verdict" 2>/dev/null || echo "MUTANT $i NO-VERDICT")
  echo "$v"
  case $v in *" KILLED by "*) killed=$((killed + 1)) ;; *) bad=$((bad + 1)) ;; esac
  i=$((i + 1))
done
echo "PD0L_MUTANTS run=$n killed=$killed bad=$bad"
[ "$bad" -eq 0 ]
