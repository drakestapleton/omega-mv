#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# lang_mutants.sh -- negative controls for tests/language/lang_parity.sh.
#
# Each mutant is one deliberate fault in src/language/*.om (a limit off by one, a dropped check,
# a wrong message, a lost rollback, ...). The mutant is applied to a copy of the tree, the OM
# dumper is rebuilt, and every parity corpus must show at least one difference from the C
# reference outputs of a passing parity run. A mutant that does not apply, does not build, or
# shows no difference fails this script.
#
# usage: LANG_PARITY_WORK=<work dir of a passing lang_parity.sh run> tests/language/lang_mutants.sh [OMC]
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OMC=${1:-$ROOT/seed/out/omc}
case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
W=${LANG_PARITY_WORK:?set LANG_PARITY_WORK to the work dir of a passing lang_parity.sh run}
[ -x "$W/lang_dump_c" ] && [ -d "$W/corpus" ] || { echo "MUTANTS FAIL no parity work dir"; exit 2; }
M=$W/mut
rm -rf "$M"; mkdir -p "$M"

# file|perl substitution (applied with perl -0pi, so \n spans lines)
cat > "$M/list" <<'EOF'
lex|s/const OLX_LINE_MAX ulong 1024/const OLX_LINE_MAX ulong 1025/
lex|s/const OLX_MAX_TOKENS ulong 256/const OLX_MAX_TOKENS ulong 257/
lex|s/if eq nx 120\n/if eq nx 121\n/
lex|s/olx_failt col olx_e_wide\n    ret -2/olx_failt col olx_e_wide\n    ret -1/
lex|s/if ge n 64\n    olx_failt add i 1 olx_e_name/if ge n 65\n    olx_failt add i 1 olx_e_name/
lex|s/    ret 117\n/    ret 113\n/
lex|s/olm_c add 87 d/olm_c add 55 d/
lex|s/if or or eq c 32 eq c 9 or eq c 13 eq c 10/if or or eq c 32 eq c 9 or eq c 11 eq c 10/
parse|s/ret or olx_tok_eq t opr_w_self olx_tok_eq t opr_w_rec/ret olx_tok_eq t opr_w_self/
parse|s/const OPR_MAX_DEPTH ulong 32/const OPR_MAX_DEPTH ulong 33/
parse|s/const OPR_MAX_NODES ulong 128/const OPR_MAX_NODES ulong 127/
parse|s/if and eq level 0 gt seen 0/if and eq level 0 gt seen 1/
parse|s/  if eq k 22\n    ret 1\n  end\n  if eq k 21\n    ret 2/  if eq k 22\n    ret 2\n  end\n  if eq k 21\n    ret 1/
parse|s/put opr_cl_plp 0 1/put opr_cl_plp 0 0/
parse|s/if ge add add ln sp pl 64/if ge add add ln sp pl 65/
parse|s/text opr_w_x "x"/text opr_w_x "y"/
parse|s/text opr_m_found " but found '"/text opr_m_found " but got '"/
parse|s/if eq opr_peek 14\n    olx_failt opr_peek_col opr_m_one/if eq opr_peek 99\n    olx_failt opr_peek_col opr_m_one/
lower|s/if and eq get olw_lit_ok 0 1 eq dv 0/if and eq get olw_lit_ok 0 1 eq dv 1/
lower|s/if ne shr v ewid 0/if gt shr v ewid 1/
lower|s/  if ne rc 0\n    put v_og_cnt 0 saved\n    ret rc/  if ne rc 0\n    ret rc/
lower|s/o = og_dedupe og_build_val_uint/o = og_build_val_uint/
lower|s/if gt imm 0xffffffff\n/if gt imm 0x1ffffffff\n/
lower|s/const OLW_MAX_STEPS ulong 32/const OLW_MAX_STEPS ulong 33/
lower|s/comm = or or eq opc V_OP_ADD eq opc V_OP_MUL or eq opc V_OP_AND eq opc V_OP_OR/comm = or or eq opc V_OP_ADD eq opc V_OP_MUL or eq opc V_OP_AND eq opc V_OP_ADD/
lower|s/  vsb_clause 1\n/  vsb_clause 0\n/
lower|s/ret lt get v_bind_cnt 0 V_MAX_BINDINGS/ret le get v_bind_cnt 0 V_MAX_BINDINGS/
lower|s/    if olw_pid_eq i\n/    if and false olw_pid_eq i\n/
lower|s/olx_failt col olw_m_full\n  ret -3/olx_failt col olw_m_full\n  ret -2/
lower|s/ret olw_infer ulong get opr_nrhs ni/ret olw_infer ulong get opr_nlhs ni/
EOF

OMS="src/visor/visor.om om/aarch64/aarch64_om2.om om/visor/verify_om2.om om/visor/validate_om2.om
src/visor/visor_program.om src/language/omega_lex.om src/language/omega_parse.om
src/language/omega_lower.om tests/language/lang_dump.om"
n=0; killed=0; bad=0
while IFS='|' read -r f expr; do
  [ -n "$f" ] || continue
  n=$((n + 1))
  T=$M/t$n
  mkdir -p "$T"
  (cd "$ROOT" && tar -cf - $OMS) | tar -xf - -C "$T"
  file=$T/src/language/omega_$f.om
  cp "$file" "$file.orig"
  perl -0pi -e "$expr" "$file"
  if cmp -s "$file" "$file.orig"; then
    echo "MUTANT $n $f NOT-APPLIED $expr"; bad=$((bad + 1)); continue
  fi
  if ! (cd "$T" && (printf 'om2\n'; sed -e '/^om2$/d' -e 's/^export fn /fn /' $OMS) | "$OMC" > "$T/dump" 2>"$T/omc.err"); then
    echo "MUTANT $n $f NO-BUILD $(head -1 "$T/omc.err") $expr"; bad=$((bad + 1)); continue
  fi
  chmod +x "$T/dump"
  hit=""
  for c in "$W"/corpus/*.txt; do
    b=$(basename "$c" .txt)
    "$T/dump" < "$c" > "$T/$b.om" 2>/dev/null || true
    if ! cmp -s "$T/$b.om" "$W/out/$b.c"; then hit="$hit $b"; fi
  done
  if [ -n "$hit" ]; then
    killed=$((killed + 1)); echo "MUTANT $n $f KILLED by$hit"
  else
    bad=$((bad + 1)); echo "MUTANT $n $f SURVIVED $expr"
  fi
done < "$M/list"
echo "LANG_MUTANTS run=$n killed=$killed bad=$bad"
[ "$bad" -eq 0 ]
