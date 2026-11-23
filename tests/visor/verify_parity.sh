#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# verify_parity.sh -- differential qualification of the pure OM-2 verify lane
# (src/visor/visor_verify.om: vver_verify_object, vver_verify_program, vver_format_text,
# vver_format_json, and the V0/V1 execution it carries) against the C it replaced in the omega
# binary (src/visor/visor_verify.c, retired at main commit 3f2c70dc5), on the same graphs,
# realizations, machine models and programs.
#
# Every corpus runs through tests/visor/verify_dump.om and is compared byte for byte with
# tests/visor/verify_golden/<corpus>.out: report return code, both renderings, their lengths at
# the exact buffer size and around it, the V0 structure of a realization and its execution. The
# goldens were generated ONCE from the C at main commit 3f2c70dc5 by the reference-only C dumper
# tests/visor/verify_dump.c (committed once, then removed); tests/visor/verify_golden/MANIFEST
# records the commit, the generator and the sha256 of every corpus and golden. No C compiler
# is needed.
#
# Corpus commands: see the header of tests/visor/verify_dump.om.
#   hand      the hand scenario S (every report shape of the C test, lies, programs, effects)
#   gen-ops   every opcode 0..17 as the graph's operation: verify each object without and with a
#             realization and the machine model
#   gen-fields  opcode, overflow, type tag, width, value byte length and the payload lengths of the
#             value, type, apply and operation mutated one at a time, each object verified
#   gen-code  1200 generated AArch64 programs of the realizable subset (ADD SUB AND ORR EOR with
#             shifts, MUL/MADD/MSUB, MOVZ MOVK MOVN, SUBS register and immediate, RET) bound to
#             the ADD op (words the decoder refuses included): V0 + V1 run
#             through the verify report, and each program run on three inputs (native in the C,
#             the interpreter in the OM)
#
# usage: tests/visor/verify_parity.sh [OMC]
#          prints PARITY lines and VERIFY_PARITY ...; exit 0 iff every corpus equals its golden
#        tests/visor/verify_parity.sh --generate <C dumper binary>
#          rewrites the goldens and the MANIFEST body from that binary (keeps the header line)
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GOLD=$ROOT/tests/visor/verify_golden
GEN=""
if [ "${1:-}" = "--generate" ]; then
  GEN=${2:?usage: verify_parity.sh --generate <C dumper binary>}
  case $GEN in /*) ;; *) GEN=$(pwd)/$GEN ;; esac
  OMC=""
else
  OMC=${1:-$ROOT/seed/out/omc}
  case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
fi
W=${VERIFY_PARITY_WORK:-$(mktemp -d)}
mkdir -p "$W/corpus" "$W/out"
sha() { sha256sum "$1" | cut -d' ' -f1; }

# ---- corpora ----
cd "$ROOT"
C=$W/corpus
rm -f "$C"/*.txt
printf 'S\n' > "$C/hand.txt"
awk 'BEGIN { for (op = 0; op <= 17; op++) {
       print "G " op; print "K";
       for (q = 0; q <= 4; q++) { print "Q " q; print "V -1 -1" }
       print "P"; print "Q 4"; print "V 0 0"; print "Q 3"; print "V 0 -1"; print "Q 1"; print "V 0 0" } }' > "$C/gen-ops.txt"
awk 'BEGIN { split("0 1 2 3 4 5 6 9 10 11 12 15 16 17 32 51 255", opc, " ");
       print "G 3"; print "K"; print "P";
       for (k = 1; k <= 17; k++) { print "O 1 " opc[k]; print "Q 3"; print "V -1 -1"; print "Q 4"; print "V 0 0"; print "O 1 3" }
       for (v = 0; v <= 5; v++) { print "O 2 " v; print "Q 4"; print "V -1 -1"; print "Q 3"; print "V 0 0" } print "O 2 1";
       split("0 1 2 7 8 16 31 32 33 63 64 65 128 255 256 257 4096 65535", ws, " ");
       for (tag = 0; tag <= 16; tag++) for (k = 1; k <= 18; k++) {
         print "O 5 " tag; print "O 3 " ws[k]; print "Q 0"; print "V -1 -1"; print "Q 1"; print "V -1 -1" }
       print "O 5 3"; print "O 3 64";
       for (b = 0; b <= 70; b++) { print "O 4 " b; print "Q 1"; print "V -1 -1"; print "Q 4"; print "V 0 0" }
       print "O 4 8";
       for (f = 6; f <= 9; f++) { full = (f == 6) ? 98 : (f == 7) ? 44 : (f == 8) ? 161 : 204;
         for (l = 0; l <= 210; l++) if (l <= 8 || (l >= 40 && l <= 48) || (l >= 94 && l <= 100) || (l >= 157 && l <= 165) || (l >= 200)) {
           print "O " f " " l; print "Q " ((f == 6) ? 1 : (f == 7) ? 0 : (f == 8) ? 4 : 3); print "V -1 -1"; print "Q 4"; print "V -1 -1" }
         print "O " f " " full }
       print "Q 9"; print "V -1 -1"; print "V 0 0" }' > "$C/gen-fields.txt"
# gen-code: a 32-bit LCG (x = x * 69069 + 1 mod 2^32, exact in double arithmetic); registers read
# and written are X0..X2 or XZR (native code must not read an uninitialised register or touch
# X30/SP); shifts stay architecturally defined (no ROR on ADD/SUB/SUBS, no 32-bit shift above 31,
# no MOVZ/MOVK/MOVN hw above 1 in 32-bit form), so the C can run every program natively. Branches,
# ADR, loads and stores, which the V0 decoder accepts but no realizer emits, are not generated:
# native execution of arbitrary ones is undefined in the C (the OM refuses them with rc=-3).
awk 'function r(n) { x = (x * 69069 + 1) % 4294967296; return int(x / 65536) % n }
     function reg() { k = r(5); return k == 4 ? 31 : (k == 3 ? r(3) : k) }
     function insn(   f, sf, ty, amt, w, hw) {
       f = r(13); sf = r(4) ? 1 : 0
       if (f <= 4) {                       # ADD SUB AND ORR EOR (shifted register)
         ty = (f <= 1) ? r(3) : r(4)
         amt = sf ? r(64) : r(32)
         if (r(6) == 0) amt = 0
         base = (f == 0) ? 184549376 : (f == 1) ? 1258291200 : (f == 2) ? 167772160 : (f == 3) ? 704643072 : 1241513984
         w = sf * 2147483648 + base + ty * 4194304 + reg() * 65536 + amt * 1024 + reg() * 32 + reg()
         if (f >= 2 && r(8) == 0) w += 2097152   # BIC ORN EON (N bit)
         return w }
       if (f <= 6) {                       # MADD/MSUB, Ra = XZR (MUL/MNEG) or X0..X2
         return sf * 2147483648 + 452984832 + reg() * 65536 + r(2) * 32768 + (r(2) ? 31 : r(3)) * 1024 + reg() * 32 + reg() }
       if (f <= 10) {                      # MOVZ MOVK MOVN
         hw = sf ? r(4) : r(2)
         base = (f <= 8) ? 1384120320 : (f == 9) ? 1920991232 : 310378496
         return sf * 2147483648 + base + hw * 2097152 + r(65536) * 32 + reg() }
       if (f == 11) {                      # SUBS (shifted register; Rd = XZR is CMP)
         amt = sf ? r(64) : r(32)
         return sf * 2147483648 + 1795162112 + r(3) * 4194304 + reg() * 65536 + amt * 1024 + reg() * 32 + reg() }
       return sf * 2147483648 + 1895825408 + r(4096) * 1024 + r(3) * 32 + reg() }   # SUBS (immediate), Rn = X0..X2
     BEGIN { x = 20261123; split("0 0 0 1 2 3 7 11 0 18446744073709551615 1 0 4294967295 4294967297 2 9223372036854775808 5 9", ins, " ");
       print "G 3"; print "K"; print "Q 4";
       for (p = 0; p < 1200; p++) {
         n = 1 + r(4); line = "W " (n + 1)
         for (i = 0; i < n; i++) line = line " " insn()
         print line " 3596551104"
         if (p % 4 == 0) print "V 4 0"
         for (k = 0; k < 3; k++) { j = r(6) * 3; print "X " ins[j + 1] " " ins[j + 2] " " ins[j + 3] } }
       print "W 2 2332098560 3596551104"; print "V 4 0"; print "X 7 11 0"
       print "W 1 0"; print "V 4 0"; print "X 1 2 3" }' > "$C/gen-code.txt"

# ---- generate mode: write the goldens from the C dumper, keep the MANIFEST header line ----
if [ -n "$GEN" ]; then
  [ -x "$GEN" ] || { echo "VERIFY_PARITY FAIL $GEN is not an executable C dumper"; exit 2; }
  mkdir -p "$GOLD"
  hdr=$(head -n 1 "$GOLD/MANIFEST" 2>/dev/null | grep '^# generated once ' || true)
  [ -n "$hdr" ] || { echo "VERIFY_PARITY FAIL write the MANIFEST header line (commit, generator command) first"; exit 2; }
  rm -f "$GOLD"/*.out
  for c in "$C"/*.txt; do
    b=$(basename "$c" .txt)
    "$GEN" < "$c" > "$GOLD/$b.out" || { echo "VERIFY_PARITY FAIL the C dumper failed on $b"; exit 2; }
    [ -s "$GOLD/$b.out" ] || { echo "VERIFY_PARITY FAIL empty C output for $b"; exit 2; }
    printf 'corpus %s %s\n' "$b" "$(sha "$c")"
    printf 'golden %s %s\n' "$b" "$(sha "$GOLD/$b.out")"
  done > "$W/MANIFEST.body"
  { printf '%s\n' "$hdr"
    printf '# goldens sha256 (of the corpus and golden lines below) %s\n' "$(sha "$W/MANIFEST.body")"
    cat "$W/MANIFEST.body"; } > "$GOLD/MANIFEST"
  echo "VERIFY_PARITY generated $(grep -c '^golden ' "$GOLD/MANIFEST") goldens in $GOLD"
  exit 0
fi

# ---- the corpora and goldens must be the ones the MANIFEST records ----
M=$GOLD/MANIFEST
[ -f "$M" ] || { echo "VERIFY_PARITY FAIL missing $M"; exit 2; }
grep -q '^# generated once from the C at main commit 3f2c70dc5' "$M" \
  || { echo "VERIFY_PARITY FAIL $M header line does not name the C reference commit"; exit 2; }
grep -v '^#' "$M" > "$W/MANIFEST.body"
[ "$(sed -n 2p "$M")" = "# goldens sha256 (of the corpus and golden lines below) $(sha "$W/MANIFEST.body")" ] \
  || { echo "VERIFY_PARITY FAIL $M body does not match its recorded sha256"; exit 2; }
bad=0
nc=$(ls "$C"/*.txt | wc -l | tr -d ' ')
[ "$nc" -eq "$(grep -c '^corpus ' "$M")" ] || { echo "VERIFY_PARITY FAIL $nc corpora built, $(grep -c '^corpus ' "$M") in the MANIFEST"; bad=1; }
for c in "$C"/*.txt; do
  b=$(basename "$c" .txt)
  want=$(awk -v b="$b" '$1 == "corpus" && $2 == b { print $3 }' "$M")
  [ "$want" = "$(sha "$c")" ] || { echo "VERIFY_PARITY FAIL corpus $b is not the one the goldens were generated from (regenerate: --generate)"; bad=1; }
  want=$(awk -v b="$b" '$1 == "golden" && $2 == b { print $3 }' "$M")
  [ -f "$GOLD/$b.out" ] && [ "$want" = "$(sha "$GOLD/$b.out")" ] || { echo "VERIFY_PARITY FAIL golden $b.out missing or not the recorded sha256"; bad=1; }
done
[ "$bad" -eq 0 ] || exit 2

# ---- the OM-2 dumper: the shipped verify modules (mk/visor-verify.mk VISOR_VERIFY_OM_SRCS),
#      the graph and realization helpers of tests/visor/test_visor_verify.om without its main,
#      and tests/visor/verify_dump.om ----
OMS="src/visor/visor.om src/visor/visor_machine.om om/aarch64/aarch64_om2.om om/visor/verify_om2.om
om/visor/validate_om2.om src/visor/visor_verify.om src/visor/visor_effect_request.om"
sed '/^fn main/,$d' tests/visor/test_visor_verify.om > "$W/test_helpers.om"
(printf 'om2\n'; sed -e '/^om2$/d' -e 's/^export fn /fn /' $OMS "$W/test_helpers.om" tests/visor/verify_dump.om) | "$OMC" > "$W/verify_dump_om"
chmod +x "$W/verify_dump_om"

# ---- compare ----
files=0; lines=0; diff=0
for c in "$C"/*.txt; do
  b=$(basename "$c" .txt)
  rc=0
  "$W/verify_dump_om" < "$c" > "$W/out/$b.om" || rc=$?
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
echo "VERIFY_PARITY files=$files lines=$lines diff=$diff reference=C@3f2c70dc5 (goldens) work=$W"
[ "$diff" -eq 0 ]
