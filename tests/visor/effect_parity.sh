#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# effect_parity.sh -- differential qualification of the pure OM-2 effect-request lane
# (src/visor/visor_effect_request.om: verq_build, verq_classify, verq_format_text,
# verq_format_json) and the unattached World view (src/visor/visor_world.om: vwld_unattached,
# vwld_format_text, vwld_format_json) against the C they replace in the omega binary
# (src/visor/visor_effect_request.c, src/visor/visor_world.c), on the same graphs.
#
# Every corpus runs through tests/visor/effect_dump.om and is compared byte for byte with
# tests/visor/effect_golden/<corpus>.out: build return code, classify return code and result,
# both renderings, the object ids (D lines) and the world view. The goldens were generated ONCE
# from the C at main commit 3f2c70dc5 by the reference-only C dumper tests/visor/effect_dump.c
# (committed once, then removed); tests/visor/effect_golden/MANIFEST records the commit, the
# generator and the sha256 of every corpus and golden. This script needs no C compiler.
#
# Corpus commands (one per line, decimal numbers, '#' and blank lines skipped):
#   R reset the graph            O k   add an object of kind k (it becomes current)
#   L n payload_len              B o v payload byte o = v
#   E o nb v big-endian field    W o nb v little-endian field
#   F o j id of object j at o    X o v 32 bytes v at o (an id no object has, or zero)
#   T k j relation kind k to j   Y k v relation kind k to the id 32 x v
#   I compute the current id     D j print object j (kind, has_id, id)
#   C j classify object j        M j build object j and print both renderings
#   G the unattached world view (text and json)
#
# usage: tests/visor/effect_parity.sh [OMC]
#          prints PARITY lines and EFFECT_PARITY ...; exit 0 iff every corpus equals its golden
#        tests/visor/effect_parity.sh --generate <C dumper binary>
#          rewrites the goldens and the MANIFEST body from that binary (keeps the header line)
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GOLD=$ROOT/tests/visor/effect_golden
GEN=""
if [ "${1:-}" = "--generate" ]; then
  GEN=${2:?usage: effect_parity.sh --generate <C dumper binary>}
  case $GEN in /*) ;; *) GEN=$(pwd)/$GEN ;; esac
  OMC=""
else
  OMC=${1:-$ROOT/seed/out/omc}
  case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
fi
W=${EFFECT_PARITY_WORK:-$(mktemp -d)}
mkdir -p "$W/corpus" "$W/out"
sha() { sha256sum "$1" | cut -d' ' -f1; }

# ---- corpora ----
cd "$ROOT"
C=$W/corpus
rm -f "$C"/*.txt
cp tests/visor/effect_corpus.txt "$C/hand.txt"
# Applies: operand_count 0..6 and 255, the effect as op_id (0) or operand 1..4; then payload
# lengths 150..210 (an apply from 161, an OperationPayload from 204) with the effect as operand
# 3 and as operand 4. Objects: 0 u32 type, 1 value, 2 operation, 3 effect, 4 the apply.
awk 'function base() { print "R"; print "O 2"; print "L 44"; print "W 0 4 3"; print "W 4 2 32"; print "I";
       print "O 1"; print "L 98"; print "F 0 0"; print "W 32 2 4"; print "B 34 1"; print "I";
       print "O 3"; print "L 204"; print "W 0 4 3"; print "F 8 0"; print "B 40 2"; print "F 41 0"; print "F 73 0"; print "F 169 0"; print "I";
       print "O 8"; print "L 178"; print "E 0 2 1"; print "I" }
     function apply(len, n, pos,   i) { base(); print "O 3"; print "L " len; print "F 0 " (pos == 0 ? 3 : 2); print "B 32 " n;
       for (i = 1; i <= 4; i++) print "F " (33 + 32 * (i - 1)) " " (i == pos ? 3 : 1); print "I"; print "C 4"; print "C 2" }
     BEGIN { split("0 1 2 3 4 5 6 255", ns, " ");
       for (k = 1; k <= 8; k++) for (pos = 0; pos <= 4; pos++) apply(161, ns[k], pos);
       for (len = 150; len <= 210; len++) { apply(len, 4, 3); apply(len, 4, 4); apply(len, 2, 1) } }' > "$C/gen-apply.txt"
# Relations: 0..6, 32, 63, 64, 65, 66 relations to a bool type, or with the last one to a
# capability-ref type; then 64 relations with the capability ref in each position 1..64.
awk 'function base() { print "R"; print "O 2"; print "L 44"; print "W 0 4 2"; print "I"; print "O 2"; print "L 44"; print "W 0 4 11"; print "I";
       print "O 2"; print "L 44"; print "W 0 4 3"; print "W 4 2 8" }
     BEGIN { split("0 1 2 3 4 5 6 32 63 64 65 66", ns, " ");
       for (k = 1; k <= 12; k++) for (v = 0; v <= 1; v++) { n = ns[k]; base();
         for (i = 1; i <= n; i++) print "T 6 " ((v == 1 && i == n) ? 1 : 0); print "I"; print "C 2"; print "D 2" }
       for (p = 1; p <= 64; p++) { base(); for (i = 1; i <= 64; i++) print "T " (i == p ? 7 : 6) " " (i == p ? 1 : 0); print "I"; print "C 2" } }' > "$C/gen-rels.txt"
# Depth: chains of 30..40, 64, 128, 254 and 255 objects over relations and over sequence
# element types, ending in a capability ref or a bool; 255 fills the graph (256 objects), so a
# further object is refused.
awk 'BEGIN { split("30 31 32 33 34 35 36 37 38 39 40 64 128 254 255", ds, " ");
       for (k = 1; k <= 15; k++) for (via = 0; via <= 1; via++) for (cap = 0; cap <= 1; cap++) { d = ds[k];
         print "R"; print "O 2"; print "L 44"; print "W 0 4 " (cap ? 11 : 2); print "I";
         for (i = 1; i <= d; i++) { print "O 2"; print "L 44";
           if (via == 0) { print "W 0 4 3"; print "W 4 2 8"; print "W 8 4 " i; print "T 6 " (i - 1) }
           else { print "W 0 4 7"; print "W 8 4 " i; print "F 12 " (i - 1) }
           print "I" }
         print "C " d; print "C " int(d / 2); print "D " d;
         if (d == 255) { print "O 2"; print "C 255" } } }' > "$C/gen-depth.txt"
# Effect parameter padding: param_len 0, 1, 64, 127, 128; a non-zero byte at every offset of the
# parameter area (inside param_len: accepted; padding: refused); and payload lengths 0..200.
awk 'BEGIN { split("0 1 64 127 128", ps, " ");
       for (k = 1; k <= 5; k++) for (off = 50; off <= 177; off++) { p = ps[k];
         print "R"; print "O 8"; print "L 178"; print "E 0 2 2"; print "E 2 2 3"; print "E 48 2 " p; print "B " off " 1"; print "I"; print "M 0"; print "C 0" }
       for (len = 0; len <= 200; len++) { print "R"; print "O 8"; print "L " len; print "E 0 2 2"; print "I"; print "M 0"; print "C 0" } }' > "$C/gen-pad.txt"

# ---- generate mode: write the goldens from the C dumper, keep the MANIFEST header line ----
if [ -n "$GEN" ]; then
  [ -x "$GEN" ] || { echo "EFFECT_PARITY FAIL $GEN is not an executable C dumper"; exit 2; }
  mkdir -p "$GOLD"
  hdr=$(head -n 1 "$GOLD/MANIFEST" 2>/dev/null | grep '^# generated once ' || true)
  [ -n "$hdr" ] || { echo "EFFECT_PARITY FAIL write the MANIFEST header line (commit, generator command) first"; exit 2; }
  rm -f "$GOLD"/*.out
  for c in "$C"/*.txt; do
    b=$(basename "$c" .txt)
    "$GEN" < "$c" > "$GOLD/$b.out" || { echo "EFFECT_PARITY FAIL the C dumper failed on $b"; exit 2; }
    [ -s "$GOLD/$b.out" ] || { echo "EFFECT_PARITY FAIL empty C output for $b"; exit 2; }
    printf 'corpus %s %s\n' "$b" "$(sha "$c")"
    printf 'golden %s %s\n' "$b" "$(sha "$GOLD/$b.out")"
  done > "$W/MANIFEST.body"
  { printf '%s\n' "$hdr"
    printf '# goldens sha256 (of the corpus and golden lines below) %s\n' "$(sha "$W/MANIFEST.body")"
    cat "$W/MANIFEST.body"; } > "$GOLD/MANIFEST"
  echo "EFFECT_PARITY generated $(grep -c '^golden ' "$GOLD/MANIFEST") goldens in $GOLD"
  exit 0
fi

# ---- the corpora and goldens must be the ones the MANIFEST records ----
M=$GOLD/MANIFEST
[ -f "$M" ] || { echo "EFFECT_PARITY FAIL missing $M"; exit 2; }
grep -q '^# generated once from the C at main commit 3f2c70dc5' "$M" \
  || { echo "EFFECT_PARITY FAIL $M header line does not name the C reference commit"; exit 2; }
grep -v '^#' "$M" > "$W/MANIFEST.body"
[ "$(sed -n 2p "$M")" = "# goldens sha256 (of the corpus and golden lines below) $(sha "$W/MANIFEST.body")" ] \
  || { echo "EFFECT_PARITY FAIL $M body does not match its recorded sha256"; exit 2; }
bad=0
nc=$(ls "$C"/*.txt | wc -l | tr -d ' ')
[ "$nc" -eq "$(grep -c '^corpus ' "$M")" ] || { echo "EFFECT_PARITY FAIL $nc corpora built, $(grep -c '^corpus ' "$M") in the MANIFEST"; bad=1; }
for c in "$C"/*.txt; do
  b=$(basename "$c" .txt)
  want=$(awk -v b="$b" '$1 == "corpus" && $2 == b { print $3 }' "$M")
  [ "$want" = "$(sha "$c")" ] || { echo "EFFECT_PARITY FAIL corpus $b is not the one the goldens were generated from (regenerate: --generate)"; bad=1; }
  want=$(awk -v b="$b" '$1 == "golden" && $2 == b { print $3 }' "$M")
  [ -f "$GOLD/$b.out" ] && [ "$want" = "$(sha "$GOLD/$b.out")" ] || { echo "EFFECT_PARITY FAIL golden $b.out missing or not the recorded sha256"; bad=1; }
done
[ "$bad" -eq 0 ] || exit 2

# ---- the OM-2 dumper, from the shipped modules (as mk/00-visor-core.mk joins them) ----
OMS="src/visor/visor.om src/visor/visor_machine.om om/aarch64/aarch64_om2.om om/visor/verify_om2.om
om/visor/validate_om2.om src/visor/visor_verify.om src/visor/visor_world.om
src/visor/visor_effect_request.om tests/visor/effect_dump.om"
(printf 'om2\n'; sed -e '/^om2$/d' -e 's/^export fn /fn /' $OMS) | "$OMC" > "$W/effect_dump_om"
chmod +x "$W/effect_dump_om"

# ---- compare ----
files=0; lines=0; diff=0
for c in "$C"/*.txt; do
  b=$(basename "$c" .txt)
  rc=0
  "$W/effect_dump_om" < "$c" > "$W/out/$b.om" || rc=$?
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
echo "EFFECT_PARITY files=$files lines=$lines diff=$diff reference=C@3f2c70dc5 (goldens) work=$W"
[ "$diff" -eq 0 ]
