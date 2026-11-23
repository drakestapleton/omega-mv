#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# effect_mutants.sh -- negative controls for tests/visor/effect_parity.sh.
#
# Each mutant is one deliberate fault in the shipped OM-2 effect-request lane
# (src/visor/visor_effect_request.om), in the strict effect decode it reuses
# (src/visor/visor_verify.om vver_eff_code) or in the World view (src/visor/visor_world.om).
# The mutant is applied to a copy of the sources, the OM dumper is rebuilt, and the corpora of
# a passing parity run must show at least one difference from the committed C-reference goldens
# (tests/visor/effect_golden, generated from the C at main commit 3f2c70dc5). A mutant that
# does not apply, does not build, or shows no difference fails this script.
#
# usage: EFFECT_PARITY_WORK=<work dir of a passing effect_parity.sh run> tests/visor/effect_mutants.sh [OMC]
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OMC=${1:-$ROOT/seed/out/omc}
case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
W=${EFFECT_PARITY_WORK:?set EFFECT_PARITY_WORK to the work dir of a passing effect_parity.sh run}
GOLD=$ROOT/tests/visor/effect_golden
[ -x "$W/effect_dump_om" ] && [ -d "$W/corpus" ] || { echo "MUTANTS FAIL no parity work dir"; exit 2; }
[ -f "$GOLD/MANIFEST" ] || { echo "MUTANTS FAIL missing $GOLD/MANIFEST"; exit 2; }
M=$W/mut
rm -rf "$M"; mkdir -p "$M"

# name|file|perl substitution (applied with perl -0pi, so \n spans lines)
cat > "$M/list" <<'EOF'
drop-operand-3|src/visor/visor_effect_request.om|s/      for i ulong n bound 4\n        verq_push_pay pb add 33 mul i 32\n/      for i ulong n bound 4\n        if ne i 2\n          verq_push_pay pb add 33 mul i 32\n        end\n/
drop-elem-type|src/visor/visor_effect_request.om|s/    if ge pl 44\n      verq_push_pay pb 12\n    end\n//
accept-nonzero-padding|src/visor/visor_verify.om|s/        ret 5\n/        ret 0\n/
relations-bound-4|src/visor/visor_effect_request.om|s/for r ulong nrel bound V_MAX_RELS/for r ulong nrel bound 4/
apply-only-161|src/visor/visor_effect_request.om|s/    if ge pl 161\n/    if eq pl 161\n/
operation-as-apply|src/visor/visor_effect_request.om|s/    if ge pl 204\n      verq_push_pay pb 8\n/    if ge pl 205\n      verq_push_pay pb 8\n/
op-three-inputs|src/visor/visor_effect_request.om|s/      for i ulong 4\n        verq_push_pay pb add 41 mul i 32/      for i ulong 3\n        verq_push_pay pb add 41 mul i 32/
drop-output-type|src/visor/visor_effect_request.om|s/      verq_push_pay pb 169\n//
drop-op-type-id|src/visor/visor_effect_request.om|s/      verq_push_pay pb 8\n//
drop-apply-op-id|src/visor/visor_effect_request.om|s/    if ge pl 161\n      verq_push_pay pb 0\n/    if ge pl 161\n/
drop-capability-ref|src/visor/visor_effect_request.om|s/      verq_push_pay pb 16\n//
operand-clamp-3|src/visor/visor_effect_request.om|s/if gt n 4\n        n = 4/if gt n 3\n        n = 3/
type-size-43|src/visor/visor_effect_request.om|s/ge get v_og_plen o 44/ge get v_og_plen o 43/
value-size-97|src/visor/visor_effect_request.om|s/    if ge pl 98\n/    if ge pl 97\n/
zero-id-is-missing|src/visor/visor_effect_request.om|s/  if verq_is_zero_tmp\n    ret\n  end\n  ti = og_find_by_tmp/  ti = og_find_by_tmp/
ignore-missing|src/visor/visor_effect_request.om|s/    put verq_missing 0 1\n    ret\n/    ret\n/
drop-receipt-ref|src/visor/visor_effect_request.om|s/ eq tag V_TY_EFF_RECEIPT_REF/ eq tag V_TY_CAP_REF/
depth-limit-32|src/visor/visor_effect_request.om|s/  sp = get verq_sp 0\n  put verq_stack sp t\n/  sp = get verq_sp 0\n  if gt sp 32\n    put verq_missing 0 1\n    ret\n  end\n  put verq_stack sp t\n/
no-visited-set|src/visor/visor_effect_request.om|s/  if ne get verq_seen t uchar 0\n    ret\n  end\n//
build-skips-validate|src/visor/visor_effect_request.om|s/  if ne vver_validate_object o 0\n    ret -1\n  end\n//
build-skips-digest|src/visor/visor_effect_request.om|s/  if not og_id_eq_sha o\n    ret -1\n  end\n//
build-no-first-match|src/visor/visor_effect_request.om|s/  og_tmp_from_obj idx\n  ret og_find_by_tmp/  ret long idx/
build-param-129|src/visor/visor_verify.om|s/  if gt plen 128\n    ret 4\n/  if gt plen 129\n    ret 4\n/
format-gen-32bit|src/visor/visor_effect_request.om|s/put verq_cap_gen 0 verq_be pb 8 8/put verq_cap_gen 0 verq_be pb 12 4/
world-gap-text|src/visor/visor_world.om|s/nothing here is observed/nothing is observed/
world-authority|src/visor/visor_world.om|s/,\\"authority\\":false}/,\\"authority\\":null}/
EOF

OMS="src/visor/visor.om src/visor/visor_machine.om om/aarch64/aarch64_om2.om om/visor/verify_om2.om
om/visor/validate_om2.om src/visor/visor_verify.om src/visor/visor_world.om
src/visor/visor_effect_request.om tests/visor/effect_dump.om"
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
  if [ -n "$hit" ]; then
    killed=$((killed + 1)); echo "MUTANT $n $name KILLED by$hit"
  else
    bad=$((bad + 1)); echo "MUTANT $n $name SURVIVED $expr"
  fi
done < "$M/list"
echo "EFFECT_MUTANTS run=$n killed=$killed bad=$bad"
[ "$bad" -eq 0 ]
