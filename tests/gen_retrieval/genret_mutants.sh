#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# genret_mutants.sh -- negative controls for tests/gen_retrieval/genret_parity.sh.
#
# Each mutant is one deliberate fault in the shipped OM-2 genret (tools/gen/retrieval/genret.om). It is applied
# to a copy of the source, both bindings are rebuilt (as genret_parity.sh builds them), and the parity corpora
# must show at least one difference from the committed C-reference goldens (tests/gen_retrieval/golden,
# generated from the C genret at main commit 3f2c70dc5). The corpora run cheapest first and stop at the first
# difference. A mutant that does not apply, does not build, or shows no difference fails this script.
#
# usage: GENRET_PARITY_WORK=<work dir of a passing genret_parity.sh run> tests/gen_retrieval/genret_mutants.sh [OMC]
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OMC=${1:-$ROOT/seed/out/omc}
case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
W=${GENRET_PARITY_WORK:?set GENRET_PARITY_WORK to the work dir of a passing genret_parity.sh run}
[ -f "$W/bind_any.om" ] && [ -f "$W/bind_prod.om" ] || { echo "MUTANTS FAIL no parity work dir"; exit 2; }
M=$W/mut
rm -rf "$M"; mkdir -p "$M"

# name|perl substitution on genret.om (applied with perl -0pi, so \n spans lines)
cat > "$M/list" <<'EOF'
bm25-k1|s/acc_mul 44\n/acc_mul 45\n/
idf-df|s/add mul 2 df 1/add mul 2 df 2/
tie-order|s/if gt sa sb/if lt sa sb/
cap-strict|s/if le add get gstat 3 a cap/if lt add get gstat 3 a cap/
heading-every|s/a = block_len add ns 1 r\nif eq ns 0\n/a = block_len add ns 1 r\nif eq ns 1\n/
no-bin-pin|s/if not hex_eq_pin/if false/
no-query-dedup|s/ret ne cmpx get gsa sub nu 1 t 0/ret true/
no-extra-check|s/rc_bin_fail tm_extra/note x/
no-hidden-check|s/if has_hidden ulong rl/if false/
no-recheck-again|s/\nrecheck_again\n/\nnote recheck_again\n/
rename-replaces|s/on 1\n/on 0\n/
leading-zero|s/if and eq get gav o 48 gt n 1/if false/
num-no-low|s/if or lt v lo gt v hi\n/if gt v hi\n/
fence-one-tick|s/if and eq c1 96 eq c2 96/if eq c1 96/
no-desc-fence|s/ has_fence get r_fo sd get r_fl sd/ false/
family-first-only|s/s = add e 1\nend\nret 9999/s = add fl 1\nend\nret 9999/
no-validity|s/if not fld_is r 4 tg_verified/if false/
no-split|s/if not fld_is r 2 tg_corpus/if false/
lower-z|s/if and ge c 65 le c 90/if and ge c 65 le c 89/
pad-not-shorter-gt|s/if ge get gstat 3 tgt\nput gstat 6 3/if gt get gstat 3 tgt\nput gstat 6 3/
pad-beyond-k-only|s/if or eq c 7 eq c 8/if eq c 7/
reason-cap|s/text tr_cap "cap_bytes"/text tr_cap "cap_byte"/
dup-path-msg|s/text tm_dup_path "duplicate path "/text tm_dup_path "duplicate path"/
body-empty-msg|s/text tm_body_empty ": body empty or not ending in a newline"/text tm_body_empty ": body empty"/
select-cap-ge|s/if gt add tot a ulong get gnum 1/if ge add tot a ulong get gnum 1/
k-one-more|s/if eq get gstat 2 ulong get gnum 0/if gt get gstat 2 ulong get gnum 0/
keep-no-match|s/if and ne md 1 eq get r_sc rr 0/if false/
status-msg|s/text tm_not_clean " did not run cleanly \(status "/text tm_not_clean " did not run cleanly (code "/
EOF

n=0; killed=0; bad=0
while IFS='|' read -r name expr; do
  [ -n "$name" ] || continue
  n=$((n + 1))
  T=$M/t$n
  mkdir -p "$T"
  f=$T/genret.om
  cp "$ROOT/tools/gen/retrieval/genret.om" "$f.orig"
  cp "$f.orig" "$f"
  perl -0pi -e "$expr" "$f"
  if cmp -s "$f" "$f.orig"; then
    echo "MUTANT $n $name NOT-APPLIED $expr"; bad=$((bad + 1)); continue
  fi
  ok=1
  for v in any prod; do
    (printf 'om2\n'; sed '/^om2$/d' "$ROOT/seed/ng/sha256.om" "$W/bind_$v.om" "$f") | "$OMC" > "$T/genret_$v" 2> "$T/omc.err" || ok=0
    chmod +x "$T/genret_$v"
  done
  if [ "$ok" -eq 0 ]; then echo "MUTANT $n $name NO-BUILD $(head -1 "$T/omc.err") $expr"; bad=$((bad + 1)); continue; fi
  if GENRET_PARITY_WORK=$T/w GENRET_PARITY_STOP=1 GENRET_PARITY_ONLY=$T/genret_any,$T/genret_prod \
       sh "$ROOT/tests/gen_retrieval/genret_parity.sh" "$OMC" > "$T/parity.out" 2>&1; then
    bad=$((bad + 1)); echo "MUTANT $n $name SURVIVED $expr"
  elif grep -q '^PARITY .* DIFF' "$T/parity.out"; then
    killed=$((killed + 1)); echo "MUTANT $n $name KILLED by $(grep '^PARITY .* DIFF' "$T/parity.out" | head -1 | cut -d' ' -f2)"
  else
    bad=$((bad + 1)); echo "MUTANT $n $name ERROR $(tail -1 "$T/parity.out")"
  fi
  rm -rf "$T/w"
done < "$M/list"
echo "GENRET_MUTANTS run=$n killed=$killed bad=$bad"
[ "$bad" -eq 0 ]
