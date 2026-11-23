#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# pd0p_parity.sh -- differential qualification of the pure OM-2 PD-0 experiment planner
# (src/physics0/planner/pd0_planner.om: pd0p_propose, pd0p_validate, pd0p_prereg_bytes, pd0p_plan_write,
# pd0p_plan_parse, pd0p_passive, pd0p_prior_add, pd0p_prior_has, pd0p_outside_fraction_ppm) against the
# retired C planner it replaced (src/physics0/planner/pd0_planner.c, deleted in wave 36b), on the same
# hypotheses, bounds, domains, priors and seeds.
#
# Every corpus runs through tests/physics0/planner/pd0p_dump.om (built from the shipped planner units, as
# mk/physics0-planner.mk joins P0P_OM_LIB) and is compared byte for byte with
# tests/physics0/planner/parity_golden/<corpus>.out: status, D, info proxy, cost, counters, the behaviour-5
# flag, seed, the whole PD0EXP1 (resets, steps, hash, every expected trajectory), the preregistration
# bytes, the PD0PLN1 bytes and their parse, validation codes, passive schedules and the outside fraction.
# The goldens were generated ONCE from the C at main commit 3f2c70dc5 by the reference-only C dumper
# tests/physics0/planner/pd0p_dump.c (committed once, then removed); parity_golden/MANIFEST records the
# commit, the generator and the sha256 of every corpus and golden. This script needs no C compiler.
#
# Corpus commands (one per line, decimal numbers, '-' allowed; '#' and blank lines skipped):
#   R s nv nl nc   relation slot s (1..8): n_vars, n_latent, n_channels, no equation
#   Q s tgt        a new equation with target tgt     T s coef i e  a term: coef, exponent e at input i
#   X s i e        exponent e at input i of the last term
#   B no nc em     bounds (all ranges 0)   C c lo hi  channel range   Z i lo hi  reset range
#   D i lo hi      visited domain of variable i (the first D after N zeroes the others)   N  no domain
#   U / Y          no prior set (C NULL) / the prior set     K  clear the prior set
#   A              add the current PD0EXP1's stored hash to the prior set
#   H n rsd s...   hypotheses: n_hyp, residual sd, slots (a slot not given is missing, the C NULL)
#   P budget seed  propose (prints the proposal and its PD0EXP1)
#   G              preregistration bytes      W  PD0PLN1 bytes
#   L n off v      parse the first n of the PD0PLN1 bytes (zero padded to 128) with byte off = v
#   V              validate the current PD0EXP1
#   M 0 i v | M 1 s ch v | M 2 n | M 3 n | M 4   change reset i, step s, n_steps, n_obs; recompute the hash
#   S budget seed index   passive schedule into the current PD0EXP1
#   F n f...       outside fraction of n flags
# Inputs stay where the C is defined: no n_steps above 20 or n_obs above 8 into the schedule hash (the
# C buffer is 244 bytes), no product or sum outside int64 in a rollout, no reset or channel span
# above INT64_MAX.
#
# usage: tests/physics0/planner/pd0p_parity.sh [OMC]
#          prints PARITY lines and PD0P_PARITY ...; exit 0 iff every corpus equals its golden
#        tests/physics0/planner/pd0p_parity.sh --generate <C dumper binary>
#          rewrites the goldens and the MANIFEST body from that binary (keeps the header line)
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
GOLD=$ROOT/tests/physics0/planner/parity_golden
GEN=""
if [ "${1:-}" = "--generate" ]; then
  GEN=${2:?usage: pd0p_parity.sh --generate <C dumper binary>}
  case $GEN in /*) ;; *) GEN=$(pwd)/$GEN ;; esac
  OMC=""
else
  OMC=${1:-$ROOT/seed/out/omc}
  case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
fi
W=${PD0P_PARITY_WORK:-$(mktemp -d)}
mkdir -p "$W/corpus" "$W/out"
sha() { sha256sum "$1" | cut -d' ' -f1; }

# ---- corpora ----
cd "$ROOT"
C=$W/corpus
rm -f "$C"/*.txt
cp tests/physics0/planner/pd0p_corpus.txt "$C/hand.txt"
# the relation set of the hand corpus (slots 1..8), the head of every generated corpus
sed -n '/^R 1 /,/^# the base bounds/p' tests/physics0/planner/pd0p_corpus.txt | sed '$d' > "$W/rels"
# Seeds, budgets and episode caps over seven hypothesis sets (two to eight hypotheses, latent, two
# channels, nonlinear), with the preregistration, the plan bytes and the validation of each proposal.
awk 'function bounds(nc, em) { print "B 2 " nc " " em; print "C 0 -2000000 2000000"; if (nc == 2) print "C 1 -500000 1500000";
       print "Z 0 -2000000 2000000"; print "Z 1 -1500000 2500000" }
     BEGIN { n = split("2 10000 1 2|2 7000 1 8|2 20000 4 1|2 10000 2 1|3 15000 1 2 8|2 10000 5 1|8 30000 1 2 3 4 8 1 2 3", hs, "|");
       split("2 3 20 57", bs, " "); split("0 1 4 100", es, " ");
       print "D 0 -2000000 2000000"; print "D 1 -1500000 2500000";
       for (k = 1; k <= n; k++) for (e = 1; e <= 4; e++) {
         bounds(k == 6 ? 2 : 1, es[e]); print "H " hs[k];
         for (b = 1; b <= 4; b++) for (s = 1; s <= 12; s++) { print "P " bs[b] " " (s * 7919 + k); print "G"; print "W"; print "V" } } }' > "$W/gen.tail"
cat "$W/rels" "$W/gen.tail" > "$C/gen-seeds.txt"
# Behaviour 5: visited boxes of six widths around three centres per variable, and boxes with hi <= lo.
awk 'BEGIN { print "B 2 1 100"; print "C 0 -2000000 2000000"; print "Z 0 -2000000 2000000"; print "Z 1 -2000000 2000000"; print "H 2 10000 1 2";
       split("100000 500000 1000000 2000000 4000000 100000000", ws, " "); split("-1000000 0 1000000", cs, " ");
       for (w = 1; w <= 6; w++) for (a = 1; a <= 3; a++) for (b = 1; b <= 3; b++) {
         print "N"; print "D 0 " (cs[a] - ws[w]) " " (cs[a] + ws[w]); print "D 1 " (cs[b] - ws[w]) " " (cs[b] + ws[w]);
         print "P 20 " (w * 9 + a * 3 + b) }
       for (w = 1; w <= 6; w++) { print "N"; print "D 0 -9000000000 9000000000"; print "D 1 " ws[w] " " (ws[w] * 3); print "P 20 41";
         print "N"; print "D 0 " (-ws[w] * 3) " " (-ws[w]); print "D 1 -9000000000 9000000000"; print "P 20 42" }
       print "N"; print "D 0 3 3"; print "D 1 -5 -6"; print "P 20 43"; print "N"; print "P 20 44";
       # one fixed schedule (reset 0.3, -0.2; no input), short budgets, boxes on a grid: the quarter
       # margins, the reset and each hypothesis trajectory fall on both sides
       print "B 2 1 100"; print "C 0 0 0"; print "Z 0 300000 300000"; print "Z 1 -200000 -200000";
       split("1 2|2 1|1 4|8 1", ps, "|");
       for (k = 1; k <= 4; k++) for (b = 2; b <= 5; b += 3) { print "H 2 1000 " ps[k];
         for (lo = -10; lo <= 2; lo++) for (hi = 3; hi <= 14; hi++) { print "N"; print "D 0 " (lo * 100000) " " (hi * 100000); print "P " b " 51" }
         for (lo = -14; lo <= -3; lo++) for (hi = -2; hi <= 10; hi++) { print "N"; print "D 0 -9000000000 9000000000"; print "D 1 " (lo * 50000) " " (hi * 50000); print "P " b " 52" } } }' > "$W/gen.tail"
cat "$W/rels" "$W/gen.tail" > "$C/gen-domains.txt"
# Duplicates: a box with four schedules in all (resets 0 or 1, channel value 0); each proposal joins the
# prior set until every schedule is a duplicate; then the usual box with each best schedule added.
awk 'BEGIN { print "Y"; print "K"; print "B 2 1 100"; print "C 0 0 0"; print "Z 0 0 1"; print "Z 1 0 1"; print "H 2 10000 1 2";
       for (i = 1; i <= 6; i++) { print "P 20 5"; print "V"; print "A"; print "V" }
       print "K"; print "B 2 1 100"; print "C 0 0 1"; print "Z 0 0 0"; print "Z 1 0 0";
       for (i = 1; i <= 10; i++) { print "P 3 9"; print "A" }
       print "K"; print "B 2 1 100"; print "C 0 -2000000 2000000"; print "Z 0 -2000000 2000000"; print "Z 1 -2000000 2000000";
       for (i = 1; i <= 12; i++) { print "P 20 7"; print "A"; print "P 20 7"; print "S 20 7 " i; print "A"; print "V" }
       print "U"; print "P 20 7"; print "V" }' > "$W/gen.tail"
cat "$W/rels" "$W/gen.tail" > "$C/gen-dup.txt"
# The prior set at its 4096 cap: further adds are dropped; the set still answers.
awk 'BEGIN { print "Y"; print "K"; print "B 2 1 100"; print "C 0 -2000000 2000000"; print "Z 0 -2000000 2000000"; print "Z 1 -2000000 2000000";
       print "H 2 10000 1 2"; print "S 20 1 1"; print "A"; print "V";
       for (i = 2; i <= 4100; i++) { print "S 20 1 " i; print "A" }
       print "V"; print "S 20 1 4095"; print "V"; print "S 20 1 4096"; print "V"; print "S 20 1 4097"; print "V"; print "S 20 1 1"; print "V";
       print "P 20 7"; print "V" }' > "$W/gen.tail"
cat "$W/rels" "$W/gen.tail" > "$C/gen-prior.txt"
# PD0PLN1 parse: every byte of a plan set to 0, 1, 128 and 255, and the lengths 0..90.
awk 'BEGIN { print "B 2 1 100"; print "C 0 -2000000 2000000"; print "Z 0 -2000000 2000000"; print "Z 1 -2000000 2000000"; print "H 2 10000 1 2";
       print "P 20 7"; split("0 1 128 255", vs, " ");
       for (o = 0; o < 84; o++) for (v = 1; v <= 4; v++) print "L 84 " o " " vs[v];
       for (n = 0; n <= 90; n++) print "L " n " 255 0";
       print "H 2 10000 1 3"; print "P 20 7"; print "W"; print "L 84 255 0" }' > "$W/gen.tail"
cat "$W/rels" "$W/gen.tail" > "$C/gen-plan.txt"
# Passive baselines and the residual sd: budgets, stream seeds and indices; sd from 1 (info clamped) up.
awk 'BEGIN { print "B 2 1 100"; print "C 0 -1000000000000 1000000000000"; print "Z 0 -4000000000000 4000000000000"; print "Z 1 -1 1";
       for (b = 0; b <= 22; b++) for (s = 0; s < 3; s++) { print "S " b " " (s * 1000003) " " (b * 31 + s); print "V" }
       print "S 20 18446744073709551615 4294967295"; print "V";
       print "B 2 1 100"; print "C 0 -2000000 2000000"; print "Z 0 -2000000 2000000"; print "Z 1 -2000000 2000000";
       split("1 2 3 5 10 100 999 1000 3163 10000 316228 1000000 100000000 9000000000000", rs, " ");
       for (r = 1; r <= 14; r++) { print "H 2 " rs[r] " 1 2"; print "P 20 " r; print "W"; print "H 2 " rs[r] " 1 8"; print "P 9 " r }
       print "H 2 10000 1 2"; print "B 2 1 100"; print "C 0 -1000000000000 1000000000000"; print "Z 0 -1000000000000 1000000000000"; print "Z 1 -1000000000000 1000000000000";
       for (s = 1; s <= 6; s++) { print "P 20 " s; print "G"; print "V" } }' > "$W/gen.tail"
cat "$W/rels" "$W/gen.tail" > "$C/gen-passive.txt"
rm -f "$W/gen.tail" "$W/rels"

# ---- generate mode: write the goldens from the C dumper, keep the MANIFEST header line ----
if [ -n "$GEN" ]; then
  [ -x "$GEN" ] || { echo "PD0P_PARITY FAIL $GEN is not an executable C dumper"; exit 2; }
  mkdir -p "$GOLD"
  hdr=$(head -n 1 "$GOLD/MANIFEST" 2>/dev/null | grep '^# generated once ' || true)
  [ -n "$hdr" ] || { echo "PD0P_PARITY FAIL write the MANIFEST header line (commit, generator command) first"; exit 2; }
  rm -f "$GOLD"/*.out
  for c in "$C"/*.txt; do
    b=$(basename "$c" .txt)
    "$GEN" < "$c" > "$GOLD/$b.out" || { echo "PD0P_PARITY FAIL the C dumper failed on $b"; exit 2; }
    [ -s "$GOLD/$b.out" ] || { echo "PD0P_PARITY FAIL empty C output for $b"; exit 2; }
    printf 'corpus %s %s\n' "$b" "$(sha "$c")"
    printf 'golden %s %s\n' "$b" "$(sha "$GOLD/$b.out")"
  done > "$W/MANIFEST.body"
  { printf '%s\n' "$hdr"
    printf '# goldens sha256 (of the corpus and golden lines below) %s\n' "$(sha "$W/MANIFEST.body")"
    cat "$W/MANIFEST.body"; } > "$GOLD/MANIFEST"
  echo "PD0P_PARITY generated $(grep -c '^golden ' "$GOLD/MANIFEST") goldens in $GOLD"
  exit 0
fi

# ---- the corpora and goldens must be the ones the MANIFEST records ----
M=$GOLD/MANIFEST
[ -f "$M" ] || { echo "PD0P_PARITY FAIL missing $M"; exit 2; }
grep -q '^# generated once from the C at main commit 3f2c70dc5' "$M" \
  || { echo "PD0P_PARITY FAIL $M header line does not name the C reference commit"; exit 2; }
grep -v '^#' "$M" > "$W/MANIFEST.body"
[ "$(sed -n 2p "$M")" = "# goldens sha256 (of the corpus and golden lines below) $(sha "$W/MANIFEST.body")" ] \
  || { echo "PD0P_PARITY FAIL $M body does not match its recorded sha256"; exit 2; }
bad=0
nc=$(ls "$C"/*.txt | wc -l | tr -d ' ')
[ "$nc" -eq "$(grep -c '^corpus ' "$M")" ] || { echo "PD0P_PARITY FAIL $nc corpora built, $(grep -c '^corpus ' "$M") in the MANIFEST"; bad=1; }
for c in "$C"/*.txt; do
  b=$(basename "$c" .txt)
  want=$(awk -v b="$b" '$1 == "corpus" && $2 == b { print $3 }' "$M")
  [ "$want" = "$(sha "$c")" ] || { echo "PD0P_PARITY FAIL corpus $b is not the one the goldens were generated from (regenerate: --generate)"; bad=1; }
  want=$(awk -v b="$b" '$1 == "golden" && $2 == b { print $3 }' "$M")
  [ -f "$GOLD/$b.out" ] && [ "$want" = "$(sha "$GOLD/$b.out")" ] || { echo "PD0P_PARITY FAIL golden $b.out missing or not the recorded sha256"; bad=1; }
done
[ "$bad" -eq 0 ] || exit 2

# ---- the OM-2 dumper, from the shipped planner units (P0P_OM_LIB of mk/physics0-planner.mk) ----
OMS="src/physics0/planner/pd0_planner_types.om src/physics0/pd0_types.om src/physics0/pd0_rng.om src/physics0/pd0_wire.om
src/physics0/ladder/pd0_codes.om src/physics0/ladder/pd0_fmt.om src/physics0/planner/pd0_planner.om
tests/physics0/planner/pd0p_dump.om"
(printf 'om2\n'; sed -e '/^om2$/d' -e 's/^export fn /fn /' $OMS) | "$OMC" > "$W/pd0p_dump_om"
chmod +x "$W/pd0p_dump_om"

# ---- compare ----
files=0; lines=0; diff=0
for c in "$C"/*.txt; do
  b=$(basename "$c" .txt)
  rc=0
  "$W/pd0p_dump_om" < "$c" > "$W/out/$b.om" || rc=$?
  n=$(wc -l < "$c" | tr -d ' ')
  files=$((files + 1)); lines=$((lines + n))
  if [ "$rc" -eq 0 ] && cmp -s "$GOLD/$b.out" "$W/out/$b.om"; then
    echo "PARITY $b lines=$n same"
  else
    diff=$((diff + 1))
    echo "PARITY $b lines=$n DIFF exit=$rc"
    diff "$GOLD/$b.out" "$W/out/$b.om" | head -20 || true
  fi
done
echo "PD0P_PARITY files=$files lines=$lines diff=$diff reference=C@3f2c70dc5 (goldens) work=$W"
[ "$diff" -eq 0 ]
