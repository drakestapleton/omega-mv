#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# sat_mutants.sh -- negative controls for tests/checker2/sat_parity.sh.
#
# Each mutant is one deliberate fault in the shipped OM-2 solver src/checker2/untrusted/c2sat.om.
# It is applied to a copy, the solver is rebuilt with the seed omc as mk/checker2.mk builds it,
# and sat_parity.sh on that binary must report a difference from the committed C-reference
# goldens (tests/checker2/sat_golden, generated from the C at main commit 3f2c70dc5). A mutant
# that does not apply, does not build, or shows no difference fails this script.
#
# usage: tests/checker2/sat_mutants.sh [OMC]   env: SAT_PARITY_WORK (work dir; default a new one)
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OMC=${1:-$ROOT/seed/out/omc}
case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
W=${SAT_PARITY_WORK:-$(mktemp -d)}
case $W in /*) ;; *) W=$(pwd)/$W ;; esac
SRC=$ROOT/src/checker2/untrusted/c2sat.om
M=$W/mut
rm -rf "$M"; mkdir -p "$M"

# name|perl substitution on c2sat.om (applied with perl -0pi, so \n spans lines)
cat > "$M/list" <<'EOF'
no-reverse-hints|s/  reverse_hints nh\n//
no-conflict-hint|s/ret emit 1 nl add nh 1/ret emit 1 nl nh/
no-backjump|s/    if not mentions idx neg d\n/    if false\n/
unit-as-free|s/      if eq st 1\n        assign/      if eq st 2\n        assign/
model-sign|s/      ob_int neg long add i 1\n/      ob_int long add i 1\n/
negative-first|s/    d = v\n    if eq side 1\n      d = neg v/    d = neg v\n    if eq side 1\n      d = v/
limit-off-by-one|s/if gt dc sget 6/if ge dc sget 6/
default-limit|s/sset 6 2000000/sset 6 2000/
resolvent-no-dedup|s/n = rbuf_add bi n v true/n = rbuf_add bi n v false/
resolvent-keeps-pivot|s/n = rbuf_add ai 0 neg v false/n = rbuf_add ai 0 0 false/
resolve-hint-order|s/  put g_ahints 0 ida\n  put g_ahints 1 idb/  put g_ahints 0 idb\n  put g_ahints 1 ida/
clause-cap|s/if lt bn add mul unv 2 1/if lt bn mul unv 2/
no-count-check|s/  if ne sget 2 ncl\n    ret 2\n  end\n//
comment-byte|s/if ne ulong get g_in pos 99/if ne ulong get g_in pos 35/
scan-no-plus|s/    if eq c 43\n      pos = add pos 1\n/    if eq c 0\n      pos = add pos 1\n/
scan-int-range|s/    if gt m 2147483647\n      ret -1/    if gt m 2147483646\n      ret -1/
scan-int-neg-range|s/    if gt m 2147483648\n      ret -1/    if gt m 2147483647\n      ret -1/
atol-sign|s/  if neg_sign\n    ret neg long m\n/  if neg_sign\n    ret long m\n/
atol-saturate|s/    ret long 9223372036854775807\n/    ret long 0\n/
cr-not-space|s/    if le c 13\n/    if le c 12\n/
level0-no-unit|s/            assign l0 long add i 1\n//
level0-no-empty|s/    if eq cn 0\n      conflict = long add i 1/    if eq cn 99\n      conflict = long add i 1/
propagate-wrong-lit|s/s = ulong add neg t sget 0/s = ulong add t sget 0/
satisfied-is-free|s/    if lit_true lj\n      ret 3\n    end\n//
decide-from-2|s/      v = long add i 1\n      break/      v = long add i 1\n      if eq i 0\n        continue\n      end\n      break/
usage-arity|s/  if lt ac 3\n/  if lt ac 2\n/
unknown-text|s/s UNKNOWN \(decision limit\)/s UNKNOWN/
sat-tail|s/text t_tail " 0\\n"/text t_tail "\\n"/
ob-flush-drops|s/  if ge used OB_CAP\n    ob_flush\n    used = 0\n  end\n/  if ge used OB_CAP\n    sset 8 0\n    used = 0\n  end\n/
EOF

n=0; killed=0; bad=0
while IFS='|' read -r name expr; do
  [ -n "$name" ] || continue
  n=$((n + 1))
  T=$M/t$n
  mkdir -p "$T"
  cp "$SRC" "$T/c2sat.om"
  perl -0pi -e "$expr" "$T/c2sat.om"
  if cmp -s "$SRC" "$T/c2sat.om"; then
    echo "MUTANT $n $name NOT-APPLIED $expr"; bad=$((bad + 1)); continue
  fi
  if ! "$OMC" < "$T/c2sat.om" > "$T/c2sat" 2> "$T/omc.err"; then
    echo "MUTANT $n $name NO-BUILD $(head -1 "$T/omc.err") $expr"; bad=$((bad + 1)); continue
  fi
  chmod +x "$T/c2sat"
  if SAT_PARITY_WORK=$T/w sh "$ROOT/tests/checker2/sat_parity.sh" "$T/c2sat" > "$T/parity.out" 2>&1; then
    bad=$((bad + 1)); echo "MUTANT $n $name SURVIVED $expr"
  elif grep -q '^SAT_PARITY corpora=' "$T/parity.out"; then
    killed=$((killed + 1)); echo "MUTANT $n $name KILLED by $(grep '^PARITY .* DIFF' "$T/parity.out" | cut -d' ' -f2 | tr '\n' ' ')"
  else
    bad=$((bad + 1)); echo "MUTANT $n $name ERROR (parity did not run): $(tail -1 "$T/parity.out")"
  fi
  rm -rf "$T/w"
done < "$M/list"
echo "SAT_MUTANTS run=$n killed=$killed bad=$bad"
[ "$bad" -eq 0 ]
