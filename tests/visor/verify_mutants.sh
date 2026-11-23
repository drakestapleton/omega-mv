#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# verify_mutants.sh -- negative controls for tests/visor/verify_parity.sh.
#
# Each mutant is one deliberate fault in the shipped OM-2 verify lane (src/visor/visor_verify.om:
# the six rows, the V0/V1 checks and the V1 interpreter it carries, the renderings). The mutant
# is applied to a copy of the sources, the OM dumper is rebuilt, and the corpora of a passing
# parity run must show at least one difference from the committed C-reference goldens
# (tests/visor/verify_golden, generated from the C at main commit 3f2c70dc5). A mutant that does
# not apply, does not build, or shows no difference fails this script.
#
# usage: VERIFY_PARITY_WORK=<work dir of a passing verify_parity.sh run> tests/visor/verify_mutants.sh [OMC]
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OMC=${1:-$ROOT/seed/out/omc}
case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
W=${VERIFY_PARITY_WORK:?set VERIFY_PARITY_WORK to the work dir of a passing verify_parity.sh run}
GOLD=$ROOT/tests/visor/verify_golden
[ -x "$W/verify_dump_om" ] && [ -d "$W/corpus" ] && [ -f "$W/test_helpers.om" ] || { echo "MUTANTS FAIL no parity work dir"; exit 2; }
[ -f "$GOLD/MANIFEST" ] || { echo "MUTANTS FAIL missing $GOLD/MANIFEST"; exit 2; }
M=$W/mut
rm -rf "$M"; mkdir -p "$M"

# name|file|perl substitution (applied with perl -0pi, so \n spans lines)
cat > "$M/list" <<'EOF'
absent-text|src/visor/visor_verify.om|s/text vver_t_absent "absent"/text vver_t_absent "absen"/
rid-always-ok|src/visor/visor_verify.om|s/  ret vver_sha_eq_rid s\n/  ret true\n/
binding-ignored|src/visor/visor_verify.om|s/  bnd = vver_rsem_eq_q s/  bnd = true/
machine-profile-ignored|src/visor/visor_verify.om|s/  if ne rp mp\n/  if eq rp 999\n/
v1-mismatch-ignored|src/visor/visor_verify.om|s/    if ne ob ex\n/    if eq ob 999999\n/
finalize-any-ran|src/visor/visor_verify.om|s/  if and any_ran not any_fail/  if any_ran/
effect-not-counted|src/visor/visor_verify.om|s/    put vver_eff_cnt 0 add get vver_eff_cnt 0 1\n/    put vver_eff_cnt 0 get vver_eff_cnt 0\n/
dangling-ignored|src/visor/visor_verify.om|s/    if lt og_find_by_tmp 0\n      vver_sb_clear\n      vver_sb_t vver_e_dang/    if lt og_find_by_tmp -5\n      vver_sb_clear\n      vver_sb_t vver_e_dang/
text-no-bound|src/visor/visor_verify.om|s/  ob_reset sub n 1\n  for r ulong 6/  ob_reset 65535\n  for r ulong 6/
json-null|src/visor/visor_verify.om|s/failure\\":null"/failure\\":nil"/
decode-skipped|src/visor/visor_verify.om|s/  if lt vver_v0_code s 0\n/  if lt vver_v0_code s -5\n/
shift-ignored|src/visor/visor_verify.om|s/      b = vver_shift b ty amt sf\n/      b = and b 18446744073709551615\n/
na-text|src/visor/visor_verify.om|s/not applicable to op 0x/not applicabel to op 0x/
v2-text|src/visor/visor_verify.om|s/not object-specific"/not object specific"/
apply-kind-name|src/visor/visor_verify.om|s/text vver_k_app "OPERATION\(apply\)"/text vver_k_app "OPERATION"/
contract-post-unchecked|src/visor/visor_verify.om|s/  if or vver_id_zero32 0 vver_id_zero32 1\n/  if vver_id_zero32 0\n/
machine-id-unchecked|src/visor/visor_verify.om|s/    if not vver_mid_eq s g\n/    if not true\n/
cycle-ignored|src/visor/visor_verify.om|s/  if ne cy 0\n/  if lt cy -5\n/
violation-overwrite|src/visor/visor_verify.om|s/  if gt get vver_vlen 0 0\n    ret false\n/  if gt get vver_vlen 0 999\n    ret false\n/
triple-id-unused|src/visor/visor_verify.om|s/  if ne get vver_rhm s 0\n    vver_rid_triple s/  if ne get vver_rhm s 99\n    vver_rid_triple s/
asr-as-lsr|src/visor/visor_verify.om|s/    if eq and shr x sub wb 1 1 1\n      r = or r xor shr m amt m/    if eq and shr x sub wb 1 1 7\n      r = or r xor shr m amt m/
movk-clobber|src/visor/visor_verify.om|s/      res = or and vver_rd rg rd xor shl ulong 65535 sh 18446744073709551615 res/      res = or vver_rd rg rd res/
mneg32-refused|src/visor/visor_verify.om|s/    if and ne op 3 and eq sf 0 ge amt 32\n/    if and eq sf 0 ge amt 32\n/
subs-refused|src/visor/visor_verify.om|s/  if eq op 19\n    if eq and shr w 28 1 1\n/  if eq op 99\n    if eq and shr w 28 1 1\n/
subs-imm-11bit|src/visor/visor_verify.om|s/and shr w 10 4095\n/and shr w 10 2047\n/
subs-imm-no-mask32|src/visor/visor_verify.om|s/      res = sub vver_rd rg get d 3 and shr w 10 4095\n      if eq sf 0\n        res = and res 4294967295\n      end\n/      res = sub vver_rd rg get d 3 and shr w 10 4095\n/
ror-as-lsl|src/visor/visor_verify.om|s/  ret and or shr x amt shl x sub wb amt m\n/  ret and shl x amt m\n/
w32-no-mask|src/visor/visor_verify.om|s/  if eq sf 0\n    res = and res 4294967295\n  end\n  if lt rd 31\n/  if lt rd 31\n/
xzr-written|src/visor/visor_verify.om|s/  if lt rd 31\n    put rg rd res\n    if eq rd 30\n      put rg 31 1\n    end\n  end\n  ret 0\nend/  if le rd 31\n    put rg rd res\n    if eq rd 30\n      put rg 31 1\n    end\n  end\n  ret 0\nend/
mneg-as-mul|src/visor/visor_verify.om|s/    if eq and shr w 15 1 1\n      ret sub 0 p\n/    if eq and shr w 15 1 7\n      ret sub 0 p\n/
eor-as-orr|src/visor/visor_verify.om|s/  ret xor a b\nend/  ret or a b\nend/
movz-hw-ignored|src/visor/visor_verify.om|s/    sh = mul hw 16\n/    sh = mul hw 0\n/
type-tag-hex1|src/visor/visor_verify.om|s/    vver_sb_t vver_e_ttag\n    vver_sb_hex tag 2\n/    vver_sb_t vver_e_ttag\n    vver_sb_hex tag 1\n/
sint-range-as-uint|src/visor/visor_verify.om|s/    vver_sb_t vver_e_sw2\n/    vver_sb_t vver_e_uw2\n/
fp32-width-text|src/visor/visor_verify.om|s/text vver_e_fw2 " is not 32"/text vver_e_fw2 " is not 32 bits"/
bitvec-as-uint|src/visor/visor_verify.om|s/    vver_sb_t vver_e_bw\n/    vver_sb_t vver_e_uw\n/
value-expected-width|src/visor/visor_verify.om|s/    vver_sb_t vver_e_vbl3\n    vver_sb_u ulong r\n/    vver_sb_t vver_e_vbl3\n    vver_sb_u w\n/
value-short-98|src/visor/visor_verify.om|s/  if lt pl 98\n/  if lt pl 97\n/
type-short-44|src/visor/visor_verify.om|s/  if lt pl 44\n    vver_sb_clear\n    vver_sb_t vver_e_tlen\n/  if lt pl 43\n    vver_sb_clear\n    vver_sb_t vver_e_tlen\n/
apply-min-161|src/visor/visor_verify.om|s/  if lt pl 161\n    ret 0\n  end\n/  if lt pl 160\n    ret 0\n  end\n/
opcode-msg-hex1|src/visor/visor_verify.om|s/      vver_sb_t vver_e_opc\n      vver_sb_hex opc 2\n/      vver_sb_t vver_e_opc\n      vver_sb_hex opc 1\n/
overflow-unchecked|src/visor/visor_verify.om|s/    if eq r 2\n      vver_sb_clear\n      vver_sb_t vver_e_ovf\n/    if eq r 99\n      vver_sb_clear\n      vver_sb_t vver_e_ovf\n/
EOF

OMS="src/visor/visor.om src/visor/visor_machine.om om/aarch64/aarch64_om2.om om/visor/verify_om2.om
om/visor/validate_om2.om src/visor/visor_verify.om src/visor/visor_effect_request.om"
n=0; killed=0; bad=0
while IFS='|' read -r name f expr; do
  [ -n "$name" ] || continue
  n=$((n + 1))
  T=$M/t$n
  mkdir -p "$T"
  (cd "$ROOT" && tar -cf - $OMS) | tar -xf - -C "$T"
  file=$T/$f
  cp "$file" "$file.orig"
  perl -0pi -e "$expr" "$file"
  if cmp -s "$file" "$file.orig"; then
    echo "MUTANT $n $name NOT-APPLIED $expr"; bad=$((bad + 1)); continue
  fi
  if ! (cd "$T" && (printf 'om2\n'; sed -e '/^om2$/d' -e 's/^export fn /fn /' $OMS "$W/test_helpers.om" "$ROOT/tests/visor/verify_dump.om") | "$OMC" > "$T/dump" 2>"$T/omc.err"); then
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
echo "VERIFY_MUTANTS run=$n killed=$killed bad=$bad"
[ "$bad" -eq 0 ]
