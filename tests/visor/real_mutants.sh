#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# real_mutants.sh -- negative controls for tests/visor/real_parity.sh.
#
# Each mutant is one deliberate fault in the shipped OM-2 realization lab
# (src/visor/visor_realization.om) or in the program realizer it calls
# (src/visor/visor_program.om). The mutant is applied to a copy of the sources (its pattern must
# match exactly once), the OM dumper is rebuilt, and the corpora of a passing parity run must
# show at least one difference from the committed C-reference goldens (tests/visor/real_golden,
# generated from the C at main commit 3f2c70dc5). A mutant that does not apply, matches more than
# once, does not build, or shows no difference fails this script.
#
# usage: REAL_PARITY_WORK=<work dir of a passing real_parity.sh run> tests/visor/real_mutants.sh [OMC]
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OMC=${1:-$ROOT/seed/out/omc}
case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
W=${REAL_PARITY_WORK:?set REAL_PARITY_WORK to the work dir of a passing real_parity.sh run}
[ -x "$W/real_dump_om" ] && [ -d "$W/corpus" ] || { echo "MUTANTS FAIL no parity work dir"; exit 2; }
for c in "$W"/corpus/*.txt; do
  b=$(basename "$c" .txt)
  [ -f "$W/out/$b.gold" ] || { echo "MUTANTS FAIL no decompressed golden $b in $W/out"; exit 2; }
done
M=$W/mut
rm -rf "$M"; mkdir -p "$M"
L=src/visor/visor_realization.om
P=src/visor/visor_program.om

# name|file|perl substitution (applied with perl -0pi, so \n spans lines)
cat > "$M/list" <<EOF
dis-ror-as-asr|$L|s/  if eq sh 3\n    vsb_t vrl_m_ror\n/  if eq sh 3\n    vsb_t vrl_m_asr\n/
dis-cap-63|$L|s/    if ge cnt 64\n/    if ge cnt 63\n/
dis-wzr-as-xzr|$L|s/      vsb_t vrl_m_wzr\n/      vsb_t vrl_m_xzr\n/
dis-movk-shift-8|$L|s/    vsb_u mul hw 16\n/    vsb_u mul hw 8\n/
dis-bcond-text|$L|s/text vrl_m_bc "b.cond "/text vrl_m_bc "b.c "/
dis-cbz-no-reg|$L|s/    vsb_reg sf rd\n  end\n  vsb_t vrl_m_i19/  end\n  vsb_t vrl_m_i19/
dis-subs-as-str|$L|s/  if eq op 19\n    vsb_t vrl_m_subs/  if eq op 19\n    vsb_t vrl_m_str/
dis-mul-shift|$L|s/  if and ne op 3 ne i6 0\n/  if ne i6 0\n/
exec-add-as-sub|$L|s/    if eq op 1\n      res = add x z\n/    if eq op 1\n      res = sub x z\n/
exec-eor-as-orr|$L|s/    if eq op 6\n      res = xor x z\n/    if eq op 6\n      res = or x z\n/
exec-movk-clears|$L|s/    keep = xor shl 65535 sa 18446744073709551615\n/    keep = ulong 0\n/
exec-asr-as-lsr|$L|s/    if eq top 1\n      r = or r and xor shr m a m m\n    end\n//
exec-ror-as-lsr|$L|s/  ret and or shr x a shl x sub wb a m\n/  ret shr x a\n/
exec-w32-unmasked|$L|s/vrl_wreg rg get d 2 and res m/vrl_wreg rg get d 2 res/
run-argc-4|$L|s/  if gt argc 3\n    ret -3\n/  if gt argc 4\n    ret -3\n/
run-ignores-verdict|$L|s/  if and eq vre_g e VE_VK 1 eq vre_g e VE_COMPAT 0\n    ret -3\n  end\n//
run-profile-2|$L|s/  if ne pr 1\n    vsb_reset\n    vsb_t vrl_r_pr1/  if ne pr 2\n    vsb_reset\n    vsb_t vrl_r_pr1/
run-ret-position|$L|s/    last = eq add off 4 n\n/    last = eq add off 8 n\n/
run-entry-offset|$L|s/or gt n 4096 ne vro_g r VRO_EOFF 0/or gt n 4096 gt vro_g r VRO_EOFF 1/
run-bw-machine-id|$L|s/  if eq vre_g e VE_HASEM 1\n    u = vmch_blackwell_id/  if eq vre_g e VE_HASEM 2\n    u = vmch_blackwell_id/
view-bw-compatible|$L|s/  if vre_tn_is e vrl_t_bw\n    nbw = 0\n  end\n//
view-bound-not-ok|$L|s/        bok = 1\n        bd = 1\n/        bok = 0\n        bd = 1\n/
view-verdict-or|$L|s/  vrv_p v VW_COMPAT and and pok bok and nbw vok\n/  vrv_p v VW_COMPAT and and pok bok or nbw vok\n/
view-mismatch-text|$L|s/text vrl_v_mis " MISMATCH; "/text vrl_v_mis " mismatch; "/
view-reason-5|$L|s/    vsb_ir e 127\n/    vsb_ir e 5\n/
cost-no-recorded|$L|s/  if eq vre_g e VE_HASEST 1\n    vrl_cost_present v 1 vre_g e VE_EST ins by/  if eq vre_g e VE_HASEST 2\n    vrl_cost_present v 1 vre_g e VE_EST ins by/
cost-empty-text|$L|s/vrv_txt v VF_SRC vrl_c_empty/vrv_txt v VF_SRC vrl_c_nomg/
cost-pred-bytes|$L|s/    vrl_cost_present v 0 ins ins by\n/    vrl_cost_present v 0 by ins by\n/
cost-class-name|$L|s/text vrl_n_meas "measured"/text vrl_n_meas "measurd"/
base-no-estimate|$L|s/    vre_p e VE_HASEST 1\n  end\nend\n\nnote fail_view/    vre_p e VE_HASEST 0\n  end\nend\n\nnote fail_view/
apply-operands-3|$L|s/    if ne oc 2\n/    if ne oc 3\n/
apply-op-size-205|$L|s/  if ge pl 204\n    for i ulong 32\n      put vrl_opid i get vrl_aid i/  if ge pl 205\n    for i ulong 32\n      put vrl_opid i get vrl_aid i/
apply-type-short|$L|s/lt get v_og_plen t 44/lt get v_og_plen t 20/
apply-width-63|$L|s/if or ne tag V_TY_UINT ne wid 64/if or ne tag V_TY_UINT ne wid 63/
apply-overflow-sat|$L|s/if and ne ovf V_OVF_WRAP ne ovf V_OVF_DEFAULT/if and ne ovf V_OVF_WRAP ne ovf 2/
apply-opname|$L|s/text vrl_o_cnv "CONVERT"/text vrl_o_cnv "CONVERTS"/
fail-target-a64|$L|s/  vrv_txt v VF_TARGET vrl_t_none\n/  vrv_txt v VF_TARGET vrl_t_a64\n/
alt-other-label|$L|s/  put vrl_alt 1 vrl_target_kind VRL_MG_OT\n/  put vrl_alt 1 vrl_target_kind mg\n/
alt-max-gt|$L|s/    if ge n max\n      break\n/    if gt n max\n      break\n/
alt-custom-as-spark|$L|s/  ret 0\nend\n\nfn vsb_target_kind/  ret 1\nend\n\nfn vsb_target_kind/
synth-compare-eq|$L|s/    if ne get vrl_out 0 get vrl_ys i\n/    if eq get vrl_out 0 get vrl_ys i\n/
synth-schedule|$L|s/  if and ge vmch_gget m VMCH_K_ISSUE 4 ge vmch_gget m VMCH_K_GPRC 16\n/  if and ge vmch_gget m VMCH_K_ISSUE 5 ge vmch_gget m VMCH_K_GPRC 16\n/
latency-mul|$L|s/    if and eq rc 0 eq get d 0 3\n/    if and eq rc 0 eq get d 0 1\n/
latency-issue|$L|s/    if gt f tot\n/    if lt f tot\n/
compare-run-as-compat|$L|s/  ob_yn vrv_g a VW_RUN\n/  ob_yn vrv_g a VW_COMPAT\n/
why-buffer-size|$L|s/  ob_reset sub n 1\n  vrl_why_head v/  ob_reset n\n  vrl_why_head v/
format-text-buffer|$L|s/fn vrl_format_text v ulong n ulong to long\n  if eq n 0\n    ret -1\n  end\n  ob_reset sub n 1\n/fn vrl_format_text v ulong n ulong to long\n  if eq n 0\n    ret -1\n  end\n  ob_reset n\n/
format-no-overflow|$L|s/fn ob_done to long\n  if eq get v_ob_ovf 0 1\n    ret -1\n  end\n/fn ob_done to long\n/
prog-width-17|$P|s/  if and and ne iw 8 ne iw 16 and ne iw 32 ne iw 64\n    vsb_reset\n    vsb_t vpg_w_wd1/  if and and ne iw 8 ne iw 17 and ne iw 32 ne iw 64\n    vsb_reset\n    vsb_t vpg_w_wd1/
prog-sub-order|$P|s/  if eq op V_OP_SUB\n    r = sub x y\n/  if eq op V_OP_SUB\n    r = sub y x\n/
EOF

OMS="src/visor/visor.om om/aarch64/aarch64_om2.om om/visor/verify_om2.om om/visor/validate_om2.om
src/visor/visor_machine.om src/visor/visor_program.om src/visor/visor_realization.om tests/visor/real_dump.om"
n=0; killed=0; bad=0
while IFS='|' read -r name f expr; do
  [ -n "$name" ] || continue
  n=$((n + 1))
  T=$M/t$n
  mkdir -p "$T"
  (cd "$ROOT" && tar -cf - $OMS) | tar -xf - -C "$T"
  file=$T/$f
  pat=${expr#s/}; pat=${pat%%/*}
  cnt=$(perl -0ne "\$c = () = /$pat/g; print \$c" "$file")
  if [ "$cnt" != 1 ]; then
    echo "MUTANT $n $name BAD-PATTERN matches=$cnt"; bad=$((bad + 1)); continue
  fi
  cp "$file" "$file.orig"
  perl -0pi -e "$expr" "$file"
  if cmp -s "$file" "$file.orig"; then
    echo "MUTANT $n $name NOT-APPLIED"; bad=$((bad + 1)); continue
  fi
  if ! (cd "$T" && (printf 'om2\n'; sed -e '/^om2$/d' -e 's/^export fn /fn /' $OMS) | "$OMC" > "$T/dump" 2>"$T/omc.err"); then
    echo "MUTANT $n $name NO-BUILD $(head -1 "$T/omc.err")"; bad=$((bad + 1)); continue
  fi
  chmod +x "$T/dump"
  hit=""
  for c in "$W"/corpus/*.txt; do
    b=$(basename "$c" .txt)
    rc=0
    timeout 120 "$T/dump" < "$c" > "$T/$b.om" 2>/dev/null || rc=$?
    if [ "$rc" -ne 0 ] || ! cmp -s "$T/$b.om" "$W/out/$b.gold"; then hit="$hit $b"; fi
    rm -f "$T/$b.om"
  done
  rm -f "$T/dump"
  if [ -n "$hit" ]; then
    killed=$((killed + 1)); echo "MUTANT $n $name KILLED by$hit"
  else
    bad=$((bad + 1)); echo "MUTANT $n $name SURVIVED $expr"
  fi
done < "$M/list"
echo "REAL_MUTANTS run=$n killed=$killed bad=$bad"
[ "$bad" -eq 0 ]
