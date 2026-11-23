#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# sem_mutants.sh -- negative controls for tests/visor/sem_parity.sh.
#
# Each mutant is one deliberate fault in the shipped OM-2 semantic lane
# (src/visor/visor_semantic.om): at least one per function the C lane exported (the name
# helpers, inspect, the text and JSON renderings, type_of, apply_parts, value_u64, eval_u64 and
# graph_text) and per check they make. The mutant is applied to a copy of the sources, the OM
# dumper is rebuilt, and the corpora of a passing parity run must show at least one difference
# from the committed C-reference goldens (tests/visor/sem_golden, generated from the C at main
# commit 3f2c70dc5). A mutant that does not apply, does not build, or shows no difference
# fails this script.
#
# usage: SEM_PARITY_WORK=<work dir of a passing sem_parity.sh run> tests/visor/sem_mutants.sh [OMC]
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OMC=${1:-$ROOT/seed/out/omc}
case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
W=${SEM_PARITY_WORK:?set SEM_PARITY_WORK to the work dir of a passing sem_parity.sh run}
GOLD=$ROOT/tests/visor/sem_golden
[ -x "$W/sem_dump_om" ] && [ -d "$W/corpus" ] || { echo "MUTANTS FAIL no parity work dir"; exit 2; }
[ -f "$GOLD/MANIFEST" ] || { echo "MUTANTS FAIL missing $GOLD/MANIFEST"; exit 2; }
M=$W/mut
rm -rf "$M"; mkdir -p "$M"

# name|perl substitution on src/visor/visor_semantic.om (perl -0pi, so \n spans lines)
cat > "$M/list" <<'EOF'
opcode-name|s/text vsem_op14 "SLICE"/text vsem_op14 "SLIC"/
overflow-name|s/text vsem_ov2 "SATURATE"/text vsem_ov2 "SATURATED"/
relation-name|s/text vsem_rl8 "SATISFIES"/text vsem_rl8 "SATISFY"/
constraint-name|s/text vsem_c5 "LENGTH"/text vsem_c5 "LEN"/
shape-name-none|s/  ob_puts vsem_s_none\n/  ob_puts vsem_s_opaque\n/
kind-range|s/if or lt kind V_KIND_VALUE gt kind V_KIND_PROOF/if or lt kind V_KIND_VALUE gt kind V_KIND_EFFECT/
attr-count-bound|s/if gt ac V_MAX_ATTRS\n/if gt ac 33\n/
val-len-bound|s/    if gt vl 512\n      vsem_rs_clear/    if gt vl 513\n      vsem_rs_clear/
const-len-bound|s/    if gt cl 128\n      vsem_rs_clear/    if gt cl 127\n      vsem_rs_clear/
payload-bound|s/if gt pl V_MAX_PAYLOAD\n/if gt pl 1025\n/
type-payload-43|s/    if lt pl 44\n      vsem_rs_clear/    if lt pl 43\n      vsem_rs_clear/
type-tag-fp32|s/if or eq tag 0 gt tag V_TY_FP32/if or eq tag 0 gt tag V_TY_EFF_RECEIPT_REF/
value-bytelen-65|s/    if gt bl 64\n      vsem_rs_clear/    if gt bl 65\n      vsem_rs_clear/
op-arity-5|s/    if gt ar 4\n      vsem_rs_clear/    if gt ar 5\n      vsem_rs_clear/
apply-at-160|s/  if ge pl 161\n    oc = vsem_pay_u8 idx 32/  if ge pl 160\n    oc = vsem_pay_u8 idx 32/
skip-stored-id|s/  if not og_id_eq_sha idx\n    vsem_rs_clear\n    vsem_rs_txt vsem_r_stored\n    ret -2\n  end\n//
seq-depth-9|s/  if gt depth 8\n    vsem_tr_set r vsem_n_q cap/  if gt depth 9\n    vsem_tr_set r vsem_n_q cap/
bitvector-text|s/    vsem_tr_txt r vsem_tt_bv cap\n    vsem_tr_u64 r w cap\n    vsem_tr_push r uchar 62 cap/    vsem_tr_txt r vsem_tt_bv cap\n    vsem_tr_u64 r w cap/
byte-not-int|s/    if eq tag V_TY_BYTE\n      w = 8\n/    if eq tag V_TY_SEQ\n      w = 8\n/
decode-high-bits|s/    if ne shr v uw 0\n      ret -1\n    end\n//
bool-two|s/if or ne bl 1 gt b0 1/if or ne bl 1 gt b0 2/
dep-no-dedupe|s/    if same\n      ret\n    end\n//
dep-skip-output|s/    vsem_pay_to_tmp idx 169\n    vsem_dep_push lv 4 0\n//
apply-result-type|s/    ret vsem_rtid_from get vsem_lidx 0 169/    ret vsem_rtid_from get vsem_lidx 0 8/
utf8-del|s/    if or lt c 32 gt c 126\n      ret false/    if or lt c 32 gt c 127\n      ret false/
json-escape-high|s/  if or lt c 32 gt c 126\n    ob_putc uchar 92\n    ob_putc uchar 117/  if lt c 32\n    ob_putc uchar 92\n    ob_putc uchar 117/
text-dangling|s/text vsem_f_dangl " \(DANGLING\)"/text vsem_f_dangl " (dangling)"/
json-null-type|s/text vsem_j_null "null"/text vsem_j_null "nul"/
eval-depth-63|s/fn vsem_eval_rec depth ulong to long\n  if gt depth 64/fn vsem_eval_rec depth ulong to long\n  if gt depth 63/
eval-no-input-check|s/  if not vsem_input_eq_rtid opi i\n    ret -1\n  end\n//
eval-arity-any|s/  if or ne vsem_pay_u8 opi 40 2 ne vsem_pay_u8 idx 32 2\n    ret -1\n  end\n//
eval-bool-op|s/  if or lt w 0 eq get vsem_isb 0 1\n/  if lt w 0\n/
eval-refused-rc|s/  if ne rc 0\n    ret -3\n  end\n  ret 0\nend/  if ne rc 0\n    ret -2\n  end\n  ret 0\nend/
eval-saturate|s/    if eq ovf V_OVF_SATURATE\n      res = mask\n/    if eq ovf V_OVF_SATURATE\n      res = sub mask 1\n/
eval-mul-overflow|s/          if gt b div mask a\n/          if gt b mask\n/
eval-sub-borrow|s/      if lt a b\n        over = true/      if le a b\n        over = true/
eval-div-zero|s/    if eq b 0\n      put vsem_evv 0 1\n      ret 0\n    end\n    ret div a b/    if eq b 0\n      ret 0\n    end\n    ret div a b/
eval-lt-le|s/    if lt a b\n      put vsem_evv 0 1/    if le a b\n      put vsem_evv 0 1/
graph-depth-63|s/fn vsem_graph_rec depth ulong to long\n  if gt depth 64/fn vsem_graph_rec depth ulong to long\n  if gt depth 63/
graph-no-visited|s/    if eq get vsem_visited ulong oi 1\n      ret 0\n    end\n//
graph-follow-malformed|s/    ob_putc uchar 10\n    put vsem_visited idx 1\n    ret 0\n  end\n  v_put_kind_name/    ob_putc uchar 10\n    put vsem_visited idx 1\n  end\n  v_put_kind_name/
type-of-unresolved|s/  vsem_rtid_to_tmp\n  if ne vsem_type_text 40 96 0 0\n    ret -1\n  end\n  ret 0/  vsem_rtid_to_tmp\n  u = vsem_type_text 40 96 0\n  ret 0/
apply-parts-shape|s/  if ne sh long VSEM_SHAPE_APPLY\n    ret -1\n  end\n  idx = get vsem_lidx 0\n  pb = vsem_pb idx/  idx = get vsem_lidx 0\n  pb = vsem_pb idx/
value-u64-shape|s/  if ne sh long VSEM_SHAPE_VALUE\n    ret -1\n  end\n  if ne vsem_decode/  if ne vsem_decode/
format-text-zero|s/fn vsem_format_text n ulong to long\n  if eq n 0\n    ret -1/fn vsem_format_text n ulong to long\n  if eq n 0\n    ret 0/
format-json-zero|s/fn vsem_format_json n ulong to long\n  if eq n 0\n    ret -1/fn vsem_format_json n ulong to long\n  if eq n 0\n    ret 0/
EOF

OMS="src/visor/visor.om src/visor/visor_semantic.om tests/visor/sem_dump.om"
f=src/visor/visor_semantic.om
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
  if [ -n "$hit" ]; then
    killed=$((killed + 1)); echo "MUTANT $n $name KILLED by$hit"
  else
    bad=$((bad + 1)); echo "MUTANT $n $name SURVIVED $expr"
  fi
done < "$M/list"
echo "SEM_MUTANTS run=$n killed=$killed bad=$bad"
[ "$bad" -eq 0 ]
