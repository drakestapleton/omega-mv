#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# pd0v_mutants.sh -- negative controls for tests/physics0/verify/pd0v_parity.sh.
#
# Each mutant is one deliberate fault in an OM-2 port of the PD-0 verifier library (pd0_fmt.om,
# pd0_codes.om, pd0_controls.om, pd0_receipt.om, and the record codec of pd0_wire.om they use), one per
# behaviour. The mutant is applied to a copy of the sources, the OM dumper is rebuilt, and the corpora of
# a passing parity run must show at least one difference from that run's OM output (which equals the
# committed C-reference goldens of tests/physics0/verify/parity_golden, generated from the C at main
# commit 3f2c70dc5, except on the capacity lines parity_divergences.txt lists; comparing with the
# goldens themselves would count those lines as a kill). A mutant that does not apply, does not build,
# or shows no difference fails this script.
#
# usage: PD0V_PARITY_WORK=<work dir of a passing pd0v_parity.sh run> tests/physics0/verify/pd0v_mutants.sh [OMC]
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
OMC=${1:-$ROOT/seed/out/omc}
case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
W=${PD0V_PARITY_WORK:?set PD0V_PARITY_WORK to the work dir of a passing pd0v_parity.sh run}
GOLD=$ROOT/tests/physics0/verify/parity_golden
[ -x "$W/pd0v_dump_om" ] && [ -d "$W/corpus" ] || { echo "MUTANTS FAIL no parity work dir"; exit 2; }
[ -f "$GOLD/MANIFEST" ] || { echo "MUTANTS FAIL missing $GOLD/MANIFEST"; exit 2; }
M=$W/mut
rm -rf "$M"; mkdir -p "$M"

F=src/physics0/ladder/pd0_fmt.om
# name|file|perl substitution (perl -0pi, so \n spans lines; the first match only)
cat > "$M/list" <<EOF
u32-get-off3|src/physics0/pd0_wire.om|s/fn pd0_get_u32 buf view uchar \* off ulong to uint\n/fn pd0_get_u32 buf view uchar * off ulong to uint\nif eq off ulong 3\nret uint 0\nend\n/
rec-body-step|src/physics0/pd0_wire.om|s/pd0_put_u32 dst ulong 28 get r step_in_episode/pd0_put_u32 dst ulong 28 get r episode/
rec-parse-short|$F|s/need = pd0_rec_size nobs\nif lt slen need\nret PD0V_TRUNCATED/need = pd0_rec_size nobs\nif lt slen sub need 1\nret PD0V_TRUNCATED/
rec-parse-status|$F|s/if or gt get src 11 PD0_BUDGET_EXHAUSTED gt get src 12 uchar 1/if gt get src 12 uchar 1/
rec-parse-kind|$F|s/if or gt get src 11 PD0_BUDGET_EXHAUSTED gt get src 12 uchar 1/if gt get src 11 PD0_BUDGET_EXHAUSTED/
rel-parse-nvars|$F|s/if or eq nv ulong 0 gt nv V_MAX_VARS\nret PD0V_BAD_FIELD/if or eq nv ulong 0 gt nv ulong 13\nret PD0V_BAD_FIELD/
rel-parse-latent|$F|s/ge ulong get src 1 nv\nret PD0V_BAD_FIELD/gt ulong get src 1 nv\nret PD0V_BAD_FIELD/
rel-parse-neq|$F|s/if gt ulong get src 9 V_MAX_EQ/if gt ulong get src 9 ulong 13/
rel-parse-target|$F|s/if ge tgt ulong get vr_nvars slot/if gt tgt ulong get vr_nvars slot/
rel-parse-short-terms|$F|s/if lt len src add o mul nt add ulong 8 ne_ex/if lt len src add o mul nt add ulong 7 ne_ex/
rel-parse-refs|$F|s/put vr_nref slot pd0_get_u16 src ulong 7/put vr_nref slot pd0_get_u16 src ulong 6/
rel-write-latent|$F|s/if or gt nc V_MAX_CHAN ge ulong get vr_nlat slot nv\nret ulong 0/if gt nc V_MAX_CHAN\nret ulong 0/
rel-write-cap|$F|s/if lt len dst ulong 10\nret ulong 0/if lt len dst ulong 9\nret ulong 0/
rel-size-zero-coef|$F|s/if ne get vr_coef vr_term_idx slot e t long 0\ns = add s uint 1/if ne get vr_coef vr_term_idx slot e t long 1\ns = add s uint 1/
rel-bits-per-term|$F|s/per = add mul uint 8 ne_ex uint 24/per = add mul uint 8 ne_ex uint 23/
rel-degree|$F|s/s = add s int get vr_ex add xb i/s = add s int 1/
ipow-one|$F|s/fn vr_ipow_micro base long ex ulong to long\nacc = PD0_MICRO/fn vr_ipow_micro base long ex ulong to long\nacc = long 999999/
step-channel|$F|s/if eq ulong ch c\nput inp add nv c val/if ne ulong ch c\nput inp add nv c val/
step-from-next|$F|s/put nxt tgt add get st tgt d/put nxt tgt add get nxt tgt d/
schedule-hash-channel|$F|s/put buf o get ve_step_ch add sb s/put buf o uchar 0/
exp-write-need|$F|s/need = add need mul ulong 9 ns/need = add need mul ulong 8 ns/
exp-parse-magic7|$F|s/V_MAGIC_EXP1 ulong 7 1 ne get src 7 uchar 0/V_MAGIC_EXP1 ulong 7 1 false/
exp-parse-nhyp|$F|s/if or eq nh ulong 0 gt nh V_MAX_HYP\nret PD0V_BAD_FIELD/if gt nh V_MAX_HYP\nret PD0V_BAD_FIELD/
exp-parse-hash|$F|s/if ne get sh k get src add o k\nret PD0V_HASH_MISMATCH/if false\nret PD0V_HASH_MISMATCH/
exp-parse-div|$F|s/put ve_div slot bitcast long pd0_get_u64 src o\n/put ve_div slot long 0\n/
ledg-kind|$F|s/len buf gt kind LEDG_BATCH/len buf gt kind uchar 7/
ledg-next-kind|$F|s/if gt get buf add o 10 LEDG_BATCH/if gt get buf add o 10 uchar 7/
ledg-chain|$F|s/if ne get buf add poff k get exp_prev k\nret PD0V_CHAIN_BROKEN/if false\nret PD0V_CHAIN_BROKEN/
ledg-hash|$F|s/if ne get h k get buf add add poff PD0_HASH k\nret PD0V_HASH_MISMATCH/if false\nret PD0V_HASH_MISMATCH/
tag-origin|$F|s/gt og uchar 1/gt og uchar 2/
tag-write-origin|$F|s/put dst 9 orig/put dst 9 tag/
corr-len|$F|s/if ne len src ulong 38/if ne len src ulong 37/
corr-write-p|$F|s/pd0_put_u64 dst ulong 14 bitcast ulong get m 4/pd0_put_u64 dst ulong 14 bitcast ulong get m 3/
fals-rivals|$F|s/if gt nr ulong 7/if gt nr ulong 8/
fals-min|$F|s/put out_meta 2 long pd0_get_u32 src p/put out_meta 2 long 0/
batch-len|$F|s/if ne len src ulong 16\nret PD0V_TRUNCATED\nend\nput out_b/if ne len src ulong 17\nret PD0V_TRUNCATED\nend\nput out_b/
batch-write-nep|$F|s/pd0_put_u32 dst ulong 12 nep/pd0_put_u32 dst ulong 12 bid/
law-id|$F|s/if ne get h k get vl_law_id add hb k\nret PD0V_LAW_ID_MISMATCH/if false\nret PD0V_LAW_ID_MISMATCH/
law-state|$F|s/if gt st PD0_LAW_PROVISIONAL\nret PD0V_BAD_FIELD/if gt st uchar 4\nret PD0V_BAD_FIELD/
law-conf|$F|s/if gt conf uint 1000000/if gt conf uint 1000001/
law-exp-kind|$F|s/if or gt kd uchar 1 gt rs uchar 1/if gt rs uchar 1/
law-write-400|$F|s/if lt cap add o ulong 400/if lt cap add o ulong 399/
law-write-tail|$F|s/mul nexp ulong 115 ulong 42 clen/mul nexp ulong 115 ulong 41 clen/
dom-latent|$F|s/pd0_put_u64 dst o bitcast ulong get vl_dom_latr slot/pd0_put_u64 dst o bitcast ulong get vl_dom_rmax slot/
claim-max|$F|s/if gt clen VL_MAX_CLAIM\nret PD0V_TOO_LARGE/if gt clen ulong 511\nret PD0V_TOO_LARGE/
name-receipt-io|src/physics0/ladder/pd0_codes.om|s/text PD0VN_RECEIPT_IO "PD0V_RECEIPT_IO"/text PD0VN_RECEIPT_IO "PD0V_RECEIPT_I0"/
name-unknown|src/physics0/ladder/pd0_codes.om|s/"PD0V_UNKNOWN"/"PD0V_UNKNOWM"/
name-t5-reused|src/physics0/ladder/pd0_codes.om|s/if eq code PD0V_T5_SCHEDULE_REUSED\n/if eq code PD0V_T5_OUT_OF_BOUNDS\n/
receipt-lines|src/physics0/controls/pd0_receipt.om|s/recorder: STAND_IN/recorder: STAND-IN/
receipt-newline|src/physics0/controls/pd0_receipt.om|s/if ne get extra sub el 1 uchar 10/if eq get extra sub el 1 uchar 10/
receipt-no-retry|src/physics0/controls/pd0_receipt.om|s/if ne fd long -17\nret PD0V_RECEIPT_IO/if ne fd long -2\nret PD0V_RECEIPT_IO/
receipt-name-hex|src/physics0/controls/pd0_receipt.om|s/for i ulong 16\np = pd0_buf_ch edit path p ulong 1023 get rc_hex i/for i ulong 15\np = pd0_buf_ch edit path p ulong 1023 get rc_hex i/
null-time|src/physics0/controls/pd0_controls.om|s/put cr_time n mul long s long 50000/put cr_time n mul long s long 49999/
null-noise|src/physics0/controls/pd0_controls.om|s/nv = pd0_noise edit nz long 500000/nv = pd0_noise edit nz long 499999/
null-end|src/physics0/controls/pd0_controls.om|s/put cr_st n PD0_EPISODE_END/put cr_st n PD0_OK/
null-reset-box|src/physics0/controls/pd0_controls.om|s/put st j add get box 0 pd0_mul sub get box 1 get box 0 pd0_uniform edit sch/put st j add get box 0 pd0_mul sub get box 1 get box 0 sub pd0_uniform edit sch long 1/
null-cap|src/physics0/controls/pd0_controls.om|s/if ge n and sc ulong 65535/if gt n and sc ulong 65535/
shuffle-status|src/physics0/controls/pd0_controls.om|s/if eq get cr_st i PD0_OK/if le get cr_st i PD0_EPISODE_END/
shuffle-tag|src/physics0/controls/pd0_controls.om|s/text CTRL_TAG_SHUF "shuffle"/text CTRL_TAG_SHUF "shufflf"/
shuffle-episode|src/physics0/controls/pd0_controls.om|s/if eq get cr_ep k get cr_ep sub k 1\ncr_copy_before k/cr_copy_before k\nif false/
rechain-first|src/physics0/controls/pd0_controls.om|s/put cr_prev add hb k uchar 0/put cr_prev add hb k uchar 1/
scale-target|src/physics0/controls/pd0_controls.om|s/if eq get vr_eq_tgt vr_eq_idx rslot e tgt/if ne get vr_eq_tgt vr_eq_idx rslot e tgt/
scale-expo|src/physics0/controls/pd0_controls.om|s/if ne get vr_ex add xb m get ex m\nret 0/if false\nret 0/
pad-dup|src/physics0/controls/pd0_controls.om|s/if ne ctrl_has_term rslot e view ex ne_ex 0\nret ulong 0/if false\nret ulong 0/
stored|src/physics0/controls/pd0_controls.om|s/ret mul n add mul uint 2 uint n_obs uint 2/ret mul n add mul uint 2 uint n_obs uint 1/
EOF

OMS="src/physics0/pd0_types.om src/physics0/pd0_rng.om src/physics0/pd0_wire.om src/physics0/ladder/pd0_codes.om
src/physics0/ladder/pd0_fmt.om src/physics0/controls/pd0_receipt.om src/physics0/ladder/pd0_ladder.om
src/physics0/score/pd0_score.om src/physics0/controls/pd0_controls.om tests/physics0/verify/pd0v_dump.om"
n=0; killed=0; bad=0
while IFS='|' read -r name f expr; do
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
  if ! (cd "$T" && (printf 'om2\n'; echo 'text PD0_VERIFIER_COMMIT "parity"'; sed -e '/^om2$/d' -e 's/^export fn /fn /' $OMS) | "$OMC" > "$T/dump" 2>"$T/omc.err"); then
    echo "MUTANT $n $name NO-BUILD $(head -1 "$T/omc.err") $expr"; bad=$((bad + 1)); continue
  fi
  chmod +x "$T/dump"
  hit=""
  for c in "$W"/corpus/*.txt; do
    b=$(basename "$c" .txt)
    rc=0
    rm -rf "$T/run"; mkdir -p "$T/run/receipts"
    (cd "$T/run" && "$T/dump" < "$c" > "$T/$b.out" 2>/dev/null) || rc=$?
    if [ "$rc" -ne 0 ] || ! cmp -s "$T/$b.out" "$W/out/$b.om"; then hit="$hit $b"; fi
  done
  rm -rf "$T/run" "$T"/*.out "$T/dump"
  if [ -n "$hit" ]; then
    killed=$((killed + 1)); echo "MUTANT $n $name KILLED by$hit"
  else
    bad=$((bad + 1)); echo "MUTANT $n $name SURVIVED $expr"
  fi
done < "$M/list"
echo "PD0V_MUTANTS run=$n killed=$killed bad=$bad"
[ "$bad" -eq 0 ]
