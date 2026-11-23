#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# pd0p_mutants.sh -- negative controls for tests/physics0/planner/pd0p_parity.sh.
#
# Each mutant is one deliberate fault in the shipped OM-2 planner (src/physics0/planner/pd0_planner.om),
# one per behaviour of each public function and of the helpers they rest on. The mutant is applied to a
# copy of the sources, the OM dumper is rebuilt, and the corpora of a passing parity run must show at
# least one difference from the committed C-reference goldens (tests/physics0/planner/parity_golden,
# generated from the C at main commit 3f2c70dc5). A mutant that does not apply, does not build, or shows
# no difference fails this script.
#
# usage: PD0P_PARITY_WORK=<work dir of a passing pd0p_parity.sh run> tests/physics0/planner/pd0p_mutants.sh [OMC]
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
OMC=${1:-$ROOT/seed/out/omc}
case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
W=${PD0P_PARITY_WORK:?set PD0P_PARITY_WORK to the work dir of a passing pd0p_parity.sh run}
GOLD=$ROOT/tests/physics0/planner/parity_golden
[ -x "$W/pd0p_dump_om" ] && [ -d "$W/corpus" ] || { echo "MUTANTS FAIL no parity work dir"; exit 2; }
[ -f "$GOLD/MANIFEST" ] || { echo "MUTANTS FAIL missing $GOLD/MANIFEST"; exit 2; }
M=$W/mut
rm -rf "$M"; mkdir -p "$M"

# name|perl substitution on src/physics0/planner/pd0_planner.om (perl -0pi, so \n spans lines)
cat > "$M/list" <<'EOF'
prior-has-never|s/fn pd0p_prior_has pr ulong h view uchar 32 to bool\nif eq pr ulong 0\nret false\nend\n/fn pd0p_prior_has pr ulong h view uchar 32 to bool\nif ne pr ulong 99\nret false\nend\n/
prior-cap-4095|s/const PD0P_MAX_PRIOR uint 4096/const PD0P_MAX_PRIOR uint 4095/
prior-add-no-count|s/put pp_prior_n 0 add n uint 1/put pp_prior_n 0 n/
prior-clear-noop|s/fn pd0p_prior_clear to void\nput pp_prior_n 0 uint 0\n/fn pd0p_prior_clear to void\n/
bounds-reset-equal-refused|s/if gt get b reset_min i get b reset_max i/if ge get b reset_min i get b reset_max i/
bounds-chan-unchecked|s/if gt get b chan_min i get b chan_max i\nret false/if false\nret false/
bounds-nobs-9|s/if or eq no ulong 0 gt no V_MAX_OBS/if or eq no ulong 0 gt no ulong 9/
bounds-nch-zero-ok|s/if or eq nc ulong 0 gt nc V_MAX_CHAN/if gt nc V_MAX_CHAN/
step-chan-max-open|s/ret le v get b chan_max ulong c/ret lt v get b chan_max ulong c/
step-chan-min-open|s/if lt v get b chan_min ulong c\nret false/if le v get b chan_min ulong c\nret false/
step-channel-range|s/if ge c get b n_channels\nret false/if gt c get b n_channels\nret false/
reset-max-unchecked|s/if gt v get b reset_max i\nret false/if false\nret false/
reset-min-unchecked|s/if lt v get b reset_min i\nret false/if false\nret false/
episode-cap-ignored|s/if gt ns em\nret false/if gt ns add em 1\nret false/
zero-steps-ok|s/if or eq ns ulong 0 gt ns V_MAX_STEPS/if gt ns V_MAX_STEPS/
steps-for-budget|s/if lt ulong budget n\nn = ulong budget/if lt add ulong budget 1 n\nn = ulong budget/
steps-for-cap|s/if and ne em ulong 0 lt em n\nn = em/if and ne em ulong 0 lt em n\nn = add em 1/
random-channel|s/c = rem pd0_splitmix64 r nc/c = rem pd0_splitmix64 r add nc 1/
random-reset-swap|s/put pc_reset add rb i pd0_const r get b reset_min i get b reset_max i/put pc_reset add rb i pd0_const r get b reset_max i get b reset_min i/
info-scale|s/pp_wdiv edit sq ulong 1000000/pp_wdiv edit sq ulong 1000001/
info-no-clamp|s/if gt get info 0 ulong 9223372036854775807\nret vmax\nend/if gt get info 0 ulong 9223372036854775807\nret long 1\nend/
d-scale|s/pp_wmul ulong x ulong 1000000 edit dq/pp_wmul ulong x ulong 999999 edit dq/
cost-signed|s/cost = add cost pp_abs64 get pc_val add sb s/cost = add cost get pc_val add sb s/
stepmax-last-pair|s/if gt d m\nm = d\nend/m = d/
better-d-flipped|s/ret gt da db/ret lt da db/
better-cost-flipped|s/ret lt ca cb/ret gt ca cb/
better-hash-flipped|s/ret lt x y/ret gt x y/
better-eligible-flipped|s/ret gt ea eb/ret lt ea eb/
no-refinement|s/pp_refine edit rng b edit cnt\n//
refine-rounds-7|s/const PD0P_REFINE_ROUNDS ulong 8/const PD0P_REFINE_ROUNDS ulong 7/
refine-top-15|s/const PD0P_REFINE_TOP ulong 16/const PD0P_REFINE_TOP ulong 15/
refine-count|s/pp_cand_copy ci PC_MUT\nput cnt 0 add get cnt 0 uint 1/pp_cand_copy ci PC_MUT/
skip-count-refine|s/put cnt 1 add get cnt 1 uint 1\ncontinue/continue/
skip-count-candidates|s/e = uchar 0\nskipped = add skipped uint 1/e = uchar 0/
mutate-steps-only|s/pos = rem pd0_splitmix64 rng add no ns/pos = add no rem pd0_splitmix64 rng ns/
no-final-sort|s/pp_sort PD0P_REFINE_TOP\n//
min-d-zero|s/const PD0P_MIN_D_MICRO long 3000000/const PD0P_MIN_D_MICRO long 0/
middle-third|s/q = div sub hi lo long 4/q = div sub hi lo long 3/
middle-reset-only|s/v = get ve_expected vr_exp_idx slot ulong 0 s i/v = r/
middle-empty-box|s/if le hi lo\nret false/if lt hi lo\nret false/
middle-traj-hyp1|s/v = get ve_expected vr_exp_idx slot ulong 0 s i/v = get ve_expected vr_exp_idx slot ulong 1 s i/
validate-no-hash|s/if ne get h k get ve_shash add hb k\nret PD0P_ERR_INPUT/if false\nret PD0P_ERR_INPUT/
validate-no-nobs|s/if ne get ve_nobs slot get b n_obs\nret PD0P_ERR_INPUT\nend\nh = new/h = new/
validate-no-bounds-input|s/fn pd0p_validate b view Pd0pBounds pr ulong slot ulong to int\nif not pp_bounds_ok b\nret PD0P_ERR_INPUT/fn pd0p_validate b view Pd0pBounds pr ulong slot ulong to int\nif false\nret PD0P_ERR_INPUT/
validate-no-duplicate|s/if pp_prior_has_ve pr slot\nret PD0P_ERR_DUPLICATE/if false\nret PD0P_ERR_DUPLICATE/
hyps-rsd-zero-ok|s/if le get h residual_sd_micro long 0/if lt get h residual_sd_micro long 0/
hyps-one-ok|s/if or lt nh ulong 2 gt nh V_MAX_HYP/if or lt nh ulong 1 gt nh V_MAX_HYP/
hyps-nvars-unchecked|s/if lt get vr_nvars s get b n_obs\nret false/if false\nret false/
hyps-nch-unchecked|s/if lt get vr_nch s get b n_channels\nret false/if false\nret false/
budget-one-ok|s/if lt budget uint 2\nput o status PD0P_ERR_BUDGET/if lt budget uint 1\nput o status PD0P_ERR_BUDGET/
finish-dup-ignored|s/if eq get pc_elig best uchar 0\nput o status PD0P_ERR_DUPLICATE/if eq get pc_elig best uchar 2\nput o status PD0P_ERR_DUPLICATE/
finish-nhyp|s/put ve_nhyp slot uchar get pp_nh 0/put ve_nhyp slot uchar 1/
finish-div|s/put ve_div slot get pc_d best/put ve_div slot long 0/
prereg-any-status|s/if ne get o status PD0P_OK\nret ulong 0\nend\nslot = get o exp_slot/slot = get o exp_slot/
prereg-refreshes-hash|s/n = vr_exp_write slot dst\nfor k ulong 32\nput ve_shash add hb k get keep k\nend/n = vr_exp_write slot dst/
plan-version-2|s/put dst 8 uchar 1\n/put dst 8 uchar 2\n/
plan-refined-field|s/pd0_put_u32 dst ulong 15 get o n_refined/pd0_put_u32 dst ulong 15 get o n_candidates/
plan-status-byte|s/put dst 10 uchar and get o status int 255/put dst 10 uchar and get o status int 127/
plan-parse-long-ok|s/if ne len src PD0P_PLAN_SIZE/if lt len src PD0P_PLAN_SIZE/
plan-parse-byte7|s/ ne get src 7 uchar 0/ false/
plan-parse-version-low|s/if or ne get src 8 uchar 1 ne get src 9 uchar 0/if ne get src 8 uchar 1/
plan-parse-sign|s/if gt st int 127/if gt st int 255/
plan-parse-flag|s/put o outside_middle get src 51/put o outside_middle get src 50/
passive-index-mix|s/mul ulong index ulong 0x9e3779b97f4a7c15/mul ulong index ulong 0x9e3779b97f4a7c17/
passive-tag|s/text PP_TAG_PASSIVE "passive"/text PP_TAG_PASSIVE "passivf"/
plan-tag|s/text PP_TAG_PLAN "plan"/text PP_TAG_PLAN "plao"/
passive-budget|s/if lt budget uint 2\nret PD0P_ERR_BUDGET/if lt budget uint 1\nret PD0P_ERR_BUDGET/
fraction-scale|s/ret uint div mul k ulong 1000000 ulong n/ret uint div mul k ulong 999999 ulong n/
fraction-flag-one|s/if ne get flags i uchar 0\nk = add k ulong 1/if eq get flags i uchar 1\nk = add k ulong 1/
EOF

OMS="src/physics0/planner/pd0_planner_types.om src/physics0/pd0_types.om src/physics0/pd0_rng.om src/physics0/pd0_wire.om
src/physics0/ladder/pd0_codes.om src/physics0/ladder/pd0_fmt.om src/physics0/planner/pd0_planner.om
tests/physics0/planner/pd0p_dump.om"
f=src/physics0/planner/pd0_planner.om
n=0; killed=0; bad=0
while IFS='|' read -r name expr; do
  [ -n "$name" ] || continue
  n=$((n + 1))
  T=$M/t$n
  mkdir -p "$T"
  (cd "$ROOT" && tar -cf - $OMS) | tar -xf - -C "$T"
  cp "$T/$f" "$T/$f.orig"
  perl -0pi -e "$expr" "$T/$f"
  if cmp -s "$T/$f" "$T/$f.orig"; then
    echo "MUTANT $n $name NOT-APPLIED $expr"; bad=$((bad + 1)); continue
  fi
  if ! (cd "$T" && (printf 'om2\n'; sed -e '/^om2$/d' -e 's/^export fn /fn /' $OMS) | "$OMC" > "$T/dump" 2>"$T/omc.err"); then
    echo "MUTANT $n $name NO-BUILD $(head -1 "$T/omc.err") $expr"; bad=$((bad + 1)); continue
  fi
  chmod +x "$T/dump"
  hit=""
  for c in "$W"/corpus/*.txt; do
    b=$(basename "$c" .txt)
    rc=0
    "$T/dump" < "$c" > "$T/$b.om" 2>/dev/null || rc=$?
    if [ "$rc" -ne 0 ] || ! cmp -s "$T/$b.om" "$GOLD/$b.out"; then hit="$hit $b"; fi
  done
  rm -f "$T"/*.om "$T/dump"
  if [ -n "$hit" ]; then
    killed=$((killed + 1)); echo "MUTANT $n $name KILLED by$hit"
  else
    bad=$((bad + 1)); echo "MUTANT $n $name SURVIVED $expr"
  fi
done < "$M/list"
echo "PD0P_MUTANTS run=$n killed=$killed bad=$bad"
[ "$bad" -eq 0 ]
