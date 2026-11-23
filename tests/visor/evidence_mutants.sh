#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# evidence_mutants.sh -- negative controls for tests/visor/evidence_parity.sh.
#
# Each mutant is one deliberate fault in the shipped OM-2 evidence lane
# (src/visor/visor_evidence.om: JSON scanner, record extraction, scope law, walk, cap heap, view,
# renderings). The mutant is applied to a copy of the sources, the OM dumper is rebuilt, and the
# corpora of a passing parity run (on their trees) must show at least one difference from the
# committed C-reference goldens (tests/visor/evidence_golden, generated from the C at main commit
# 3f2c70dc5). A mutant that does not apply, does not build, or shows no difference fails.
#
# usage: EVIDENCE_PARITY_WORK=<work dir of a passing evidence_parity.sh run> tests/visor/evidence_mutants.sh [OMC]
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OMC=${1:-$ROOT/seed/out/omc}
case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
W=${EVIDENCE_PARITY_WORK:?set EVIDENCE_PARITY_WORK to the work dir of a passing evidence_parity.sh run}
GOLD=$ROOT/tests/visor/evidence_golden
[ -x "$W/evidence_dump_om" ] && [ -d "$W/corpus" ] && [ -d "$W/tree" ] || { echo "MUTANTS FAIL no parity work dir"; exit 2; }
[ -f "$GOLD/MANIFEST" ] || { echo "MUTANTS FAIL missing $GOLD/MANIFEST"; exit 2; }
M=$W/mut
rm -rf "$M"; mkdir -p "$M"

# name|perl substitution on src/visor/visor_evidence.om (perl -0pi, so \n spans lines)
cat > "$M/list" <<'EOF'
scope-priority|s/if or eq get vev_shave 0 0 lt s get vev_scur 0/if or eq get vev_shave 0 0 gt s get vev_scur 0/
name-mismatch-as-match|s/      ret 0\n    end\n  end\n  ret 1\nend/      ret 1\n    end\n  end\n  ret 1\nend/
name-length-68|s/  if ne bl 69\n/  if ne bl 68\n/
sort-order|s/ret le vev_cmp_slot oa ob 0/ret ge vev_cmp_slot oa ob 0/
heap-keep-largest|s/if ge vev_cmp_pbuf_slot 0 0/if le vev_cmp_pbuf_slot 0 0/
claim-separator|s/vev_fpush r VEV_F_CLAIM uchar 58/vev_fpush r VEV_F_CLAIM uchar 59/
machine-separator|s/vev_fpush r VEV_F_MACH uchar 61/vev_fpush r VEV_F_MACH uchar 58/
tree-dirty-ignored|s/    if vev_is_lit td vev_l_true\n      vev_rs_set r VEV_S_DIRTY 1\n/    if vev_is_lit td vev_l_true\n      vev_rs_set r VEV_S_DIRTY 0\n/
trees-clean-ignored|s/    if vev_is_lit long add k 1 vev_l_false\n      vev_rs_set r VEV_S_DIRTY 1\n/    if vev_is_lit long add k 1 vev_l_false\n      vev_rs_set r VEV_S_DIRTY 0\n/
gates-pass-double|s/VEV_S_GPASS add vev_rs_get r VEV_S_GPASS 1/VEV_S_GPASS add vev_rs_get r VEV_S_GPASS 2/
view-not-truncated|s/(fn vev_view_add to void.*?)put vev_trunc 0 1/${1}put vev_trunc 0 0/s
short-file-mentions|s/  if lt n 64\n    ret false\n/  if lt n 64\n    ret true\n/
hidden-not-skipped|s/if eq get vev_dbuf noff 46/if eq get vev_dbuf noff 47/
escape-any|s/      if not vev_is_esc e\n/      if vev_isdig e\n/
unparsed-list-2|s/  if lt n VEV_MAX_UNPARSED/  if lt n 2/
commit-hex-41|s/vev_hexf VEV_F_COMMIT 40 0 vev_k_cc/vev_hexf VEV_F_COMMIT 41 0 vev_k_cc/
max-files-plus-1|s/    put vev_maxf 0 cap/    put vev_maxf 0 add cap 1/
depth-limit-7|s/    if le add depth 1 8/    if le add depth 1 7/
oversize-262143|s/  if gt tot VEV_MAX_FILE/  if gt tot 262143/
silicon-basis-text|s/text vev_b_sot "silicon_observed=true"/text vev_b_sot "silicon_observed"/
json-depth-63|s/      if gt sp 64\n/      if gt sp 63\n/
token-pool-32767|s/const VEV_MAX_TOK ulong 32768/const VEV_MAX_TOK ulong 32767/
path-limit-257|s/  total = add add dl sep nl\n  if ge total 256\n/  total = add add dl sep nl\n  if ge total 257\n/
long-root-refused|s/  if ge rl 256\n    vev_collect_long rl\n/  if ge rl 256\n    put vev_oom 0 1\n    vev_collect_long rl\n/
frac-needs-no-digit|s/    i = add i 1\n    if ge i n\n      ret -1\n    end\n    if not vev_isdig ulong get vev_fbuf i\n      ret -1\n    end\n    i = vev_digits_end i\n  end\n/    i = add i 1\n    i = vev_digits_end i\n  end\n/
leading-zero-digits|s/  if eq get vev_fbuf i 48\n    i = add i 1\n  else\n/  if eq get vev_fbuf i 49\n    i = add i 1\n  else\n/
control-char-ok|s/    if lt c 32\n      ret -1\n    end\n    if eq c 92\n/    if lt c 9\n      ret -1\n    end\n    if eq c 92\n/
name-match-text|s/text vev_t_nmatch " \(name = content hash\)"/text vev_t_nmatch " (name == content hash)"/
none-text|s/text vev_t_none "\(none\)"/text vev_t_none "(none )"/
more-text|s/text vev_t_more "UNPARSED     \(\+"/text vev_t_more "UNPARSED     (+ "/
EOF

OMS="src/visor/visor.om src/visor/visor_evidence.om tests/visor/evidence_dump.om"
n=0; killed=0; bad=0
while IFS='|' read -r name expr; do
  [ -n "$name" ] || continue
  n=$((n + 1))
  T=$M/t$n
  mkdir -p "$T"
  (cd "$ROOT" && tar -cf - $OMS) | tar -xf - -C "$T"
  file=$T/src/visor/visor_evidence.om
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
    (cd "$W/tree/$b" && "$T/dump" < "$c") > "$T/$b.om" 2>/dev/null || rc=$?
    if [ "$rc" -ne 0 ] || ! cmp -s "$T/$b.om" "$GOLD/$b.out"; then hit="$hit $b"; fi
  done
  rm -f "$T"/*.om "$T/dump"
  if [ -n "$hit" ]; then
    killed=$((killed + 1)); echo "MUTANT $n $name KILLED by$hit"
  else
    bad=$((bad + 1)); echo "MUTANT $n $name SURVIVED $expr"
  fi
done < "$M/list"
echo "EVIDENCE_MUTANTS run=$n killed=$killed bad=$bad"
[ "$bad" -eq 0 ]
