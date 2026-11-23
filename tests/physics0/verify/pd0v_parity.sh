#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# pd0v_parity.sh -- differential qualification of the OM-2 ports of the PD-0 verifier library
# (src/physics0/ladder/pd0_fmt.om, pd0_codes.om, src/physics0/controls/pd0_controls.om, pd0_receipt.om)
# against the live C library they port (src/physics0/ladder/pd0_fmt.c, pd0_codes.c,
# src/physics0/controls/pd0_controls.c, pd0_receipt.c; the learners and planner link the C), on the same
# bytes, relations, records and seeds.
#
# Every corpus runs through tests/physics0/verify/pd0v_dump.om (built from P0V_OM_VERIFY of
# mk/physics0-verify.mk, receipt commit text "parity") in a fresh directory with an empty receipts/, and
# is compared byte for byte with tests/physics0/verify/parity_golden/<corpus>.out: the little-endian
# helpers, pd0_mul, PD0REC1 / relationship block / PD0EXP1 / PDLAW1 / ledger / payload writers and every
# parser verdict and decoded field, relation size, bits, degree and one step, the code names, receipt
# names and bodies, the null world, shuffle, rechain, the M1/M2 relation mutants and the memoriser size.
# The goldens were generated ONCE from the C at main commit 3f2c70dc5 (identical to the live C) by the
# reference-only C dumper tests/physics0/verify/pd0v_dump.c (committed once, then removed);
# parity_golden/MANIFEST records the commit, the generator and the sha256 of every corpus and golden.
# This script needs no C compiler.
#
# Corpus commands (one per line, decimal numbers, '-' allowed, "..." one word; '#' and blank skipped):
#   H hex          the byte buffer     Y off v  set a byte     Z n  set its length (zero filled)   B  print it
#   R nv nl nc bits nref | Q tgt | T coef i e | X i e | G n coef   build the relation (G: n terms)
#   rs | rw cap | rp | rt ch v s...   show, write (to the buffer), parse the buffer, one step
#   m a b   pd0_mul      u v   the u16/u32/u64 helpers
#   w cap nobs st kind ch seq ep step t rq ap prevbyte b... a...   PD0REC1 into the buffer
#   e cap nobs nhyp nsteps seed      PD0EXP1 (fields from the seed) into the buffer
#   l seed state conf nexc nexp claim dom_nobs dom_nch cap   PDLAW1 (the relation, fields from the seed)
#   t ep tag batch origin | c a b n r p pairs shuffles seed | f seed nriv eps min | b id seed nep  payloads
#   pr | pe | pw | pt | pc | pf | pb   parse the buffer;  pg off prevbyte  walk it as a ledger
#   gr byte | ga kind cap | gb   ledger: reset (last hash byte), append the buffer, to the buffer
#   n code   the code name    k code hseed kind flag "extra" | kx ...  receipt (kx: unwritable directory)
#   N seed nobs neps steps rmin rmax cmin cmax cap | S seed | C | E i f v [j] | P   null world, shuffle,
#            rechain, edit a record (f 0 kind, 1 status, 2 episode, 3 after[j]), print the records
#   M tgt num den e...  M1 scale    D n tiny  M2 pad    K n nobs  memoriser stored numbers
# The OM ports hold less than the C: at most 4 observed variables in a record (C 8) and 32 terms in an
# equation (C 64). The output lines where that shows are listed in tests/physics0/verify/
# parity_divergences.txt; a corpus must equal its golden on every other line, and differ on exactly
# the listed ones. Capacities where the OM traps rather than answers stay out of the corpora (null
# worlds with more than 4 variables or 255 steps, ledger payloads above 8192 bytes). Inputs stay where
# the C is defined: no product outside int64, no domain with more than 8 variables or 4 channels, no
# writer capacity above the dumper's 8192-byte buffer.
#
# usage: tests/physics0/verify/pd0v_parity.sh [OMC]
#        tests/physics0/verify/pd0v_parity.sh --generate <C dumper binary>
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
GOLD=$ROOT/tests/physics0/verify/parity_golden
GEN=""
if [ "${1:-}" = "--generate" ]; then
  GEN=${2:?usage: pd0v_parity.sh --generate <C dumper binary>}
  case $GEN in /*) ;; *) GEN=$(pwd)/$GEN ;; esac
  OMC=""
else
  OMC=${1:-$ROOT/seed/out/omc}
  case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
fi
W=${PD0V_PARITY_WORK:-$(mktemp -d)}
mkdir -p "$W/corpus" "$W/out"
sha() { sha256sum "$1" | cut -d' ' -f1; }
# run <dumper> <corpus> <out>: in a fresh directory with an empty receipts/
run() { rm -rf "$W/run"; mkdir -p "$W/run/receipts"; (cd "$W/run" && "$1" < "$2" > "$3"); }

# ---- corpora ----
cd "$ROOT"
C=$W/corpus
rm -f "$C"/*.txt
cp tests/physics0/verify/pd0v_corpus.txt "$C/hand.txt"
# PD0REC1: one to four variables, each kind and status; every byte set to 0 and 255; every length.
awk 'function rec(no, st, k, ch,   i, s) { s = "w 512 " no " " st " " k " " ch " " (no * 1000 + st) " " st " " k " " (no * 50000) " -" (no * 7) " " (no * 9) " " (st * 17);
       for (i = 0; i < 2 * no; i++) s = s " " ((i % 2 ? -1 : 1) * (i + 1) * 123457); print s }
     BEGIN { for (no = 1; no <= 4; no++) for (st = 0; st <= 4; st++) for (k = 0; k <= 1; k++) { rec(no, st, k, k ? 0 : 255); print "pr" }
       for (no = 1; no <= 4; no++) { n = 56 + 16 * no + 64;
         for (o = 0; o < n; o++) { rec(no, 1, 1, 0); print "Y " o " 0"; print "pr"; rec(no, 1, 1, 0); print "Y " o " 255"; print "pr" }
         for (z = 0; z <= n + 1; z++) { rec(no, 2, 1, 0); print "Z " z; print "pr" } } }' > "$C/gen-rec.txt"
# Relations: shapes over variables, latents, channels and equations, with terms of degree 0..3 and
# exponents up to 255 on inputs of magnitude 1; written, parsed back, stepped; then the parser on
# every byte set to 255 and on every length.
awk 'BEGIN { seed = 12345; rnd = 0;
       for (k = 0; k < 120; k++) {
         nv = 1 + k % 12; nl = (k % 3 == 0) ? 0 : (k % nv); nc = k % 5; ne = 1 + (k * 7) % 12; ni = nv + nc;
         print "R " nv " " nl " " nc " " (k * 97) " " (k * 3);
         for (e = 0; e < ne; e++) { print "Q " ((e * 5 + k) % nv); nt = (k + e) % 9;
           for (t = 0; t < nt; t++) { c = ((k * 31 + e * 7 + t * 13) % 2000001) - 1000000; print "T " c " " ((k + t) % ni) " " ((k + e + t) % 4);
             if (t % 3 == 1) print "X " ((k + 2 * t + 1) % ni) " " ((t + e) % 3) } }
         if (k % 10 == 0) print "G " (24 - (k % 9)) " " (k - 60);
         print "rs"; print "rw 8192"; print "rp";
         s = "rt " (k % 6) " " (((k * 37) % 4000001) - 2000000); for (i = 0; i < nv; i++) s = s " " ((((k + 3) * (i + 11) * 7919) % 4000001) - 2000000); print s }
       print "R 3 0 1 0 0"; print "Q 0"; print "T 1000000 0 9"; print "Q 1"; print "T -1000000 1 255"; print "X 3 200"; print "Q 2"; print "T 999999 2 128";
       print "rt 0 1000000 1000000 -1000000 999999"; print "rt 0 1000001 1000000 -1000000 0"; print "rt 3 5 0 0 1000001";
       print "R 2 1 1 7 9"; print "Q 0"; print "T 100000 1 1"; print "T -3 2 2"; print "Q 1"; print "T 5 0 3"; print "X 1 1";
       print "rw 8192"; n = 10 + 3 + 2 * 11 + 3 + 11;
       for (o = 0; o < n; o++) { print "rw 8192"; print "Y " o " 255"; print "rp" }
       for (z = 0; z <= n + 1; z++) { print "rw 8192"; print "Z " z; print "rp" }
       for (z = 0; z <= n + 1; z++) print "rw " z }' > "$C/gen-rel.txt"
# PD0EXP1: shapes 1..8 x 1..8 x 1..20, the writer at each capacity edge; the parser on every byte set
# to 0 and 255 and on every length of a small one.
awk 'BEGIN { for (no = 1; no <= 8; no++) for (nh = 1; nh <= 8; nh += 3) for (ns = 1; ns <= 20; ns += 6) { print "e 8192 " no " " nh " " ns " " (no * 100 + nh * 10 + ns); print "pe";
         need = 56 + 8 * no + 9 * ns + 8 * nh * ns * no; if (need <= 8192) { print "e " (need - 1) " " no " " nh " " ns " 3"; print "e " need " " no " " nh " " ns " 3" } }
       n = 56 + 16 + 18 + 8 * 2 * 2 * 2;
       for (o = 0; o < n; o++) { print "e 8192 2 2 2 77"; print "Y " o " 0"; print "pe"; print "e 8192 2 2 2 77"; print "Y " o " 255"; print "pe" }
       for (z = 0; z <= n + 1; z++) { print "e 8192 2 2 2 77"; print "Z " z; print "pe" } }' > "$C/gen-exp.txt"
# PDLAW1: states, confidences, exception / experiment / claim counts, domains; the writer at each
# capacity edge; the parser on every byte set to 0 and 255 and on every length of a small law.
awk 'BEGIN { print "R 2 0 1 0 0"; print "Q 0"; print "T 100000 1 1"; print "Q 1"; print "T -100000 0 1"; print "T 100000 2 1";
       for (s = 0; s <= 4; s++) for (k = 0; k < 6; k++) { ne = (k * 13) % 65; nx = (k * 29) % 65; cl = (k * 101) % 513;
         print "l " (s * 10 + k) " " s " " ((k * 250000) % 1000002) " " ne " " nx " " cl " " (1 + k % 8) " " (k % 5) " 8192"; print "pw" }
       for (c = 0; c <= 520; c += 13) print "l 3 2 5 1 1 2 2 1 " c;
       for (c = 480; c <= 520; c++) print "l 3 2 5 0 0 0 1 1 " c;
       for (c = 680; c <= 700; c++) print "l 3 2 5 3 2 40 2 1 " c;
       print "l 9 2 700000 1 1 3 2 1 8192"; n = 11 + 32 + 49 + 98 + 6 + 64 + 2 + 115 + 32 + 2 + 3;
       for (o = 0; o < n; o++) { print "l 9 2 700000 1 1 3 2 1 8192"; print "Y " o " 0"; print "pw"; print "l 9 2 700000 1 1 3 2 1 8192"; print "Y " o " 255"; print "pw" }
       for (z = 0; z <= n + 1; z++) { print "l 9 2 700000 1 1 3 2 1 8192"; print "Z " z; print "pw" }
       print "R 3 1 2 0 0"; print "Q 2"; print "G 32 5"; print "l 4 3 1000000 64 64 512 8 4 8192"; print "pw" }' > "$C/gen-law.txt"
# Ledger and payloads: chains of every kind, appends at each capacity edge; the walk on every byte set
# to 0 and 255 and on every length; payload codecs over field values and lengths.
awk 'function chain() { print "gr 9"; print "t 1 2 3 1"; print "ga 1 16384"; print "b 4 5 6"; print "ga 6 16384"; print "H 0102"; print "ga 0 16384"; print "gb" }
     BEGIN { chain(); print "pg 0 9"; n = 3 * 80 + 10 + 16 + 2;
       for (o = 0; o < n; o++) { chain(); print "Y " o " 0"; print "pg 0 9"; chain(); print "Y " o " 255"; print "pg 0 9" }
       for (z = 0; z <= n + 1; z++) { chain(); print "Z " z; print "pg 0 9" }
       for (c = 80; c <= 100; c++) { print "gr 1"; print "H 0102030405060708090a0b0c0d0e0f1011"; print "ga 3 " c }
       for (k = 0; k <= 8; k++) { print "gr " k; print "H 00"; print "ga " k " 16384"; print "gb"; print "pg 0 " k }
       for (k = 0; k < 40; k++) { print "t " (k * 104729) " " (k % 7) " " (k * 7) " " (k % 3); print "pt"; print "Z " (8 + k % 4); print "pt";
         print "c " (k % 256) " " ((k * 3) % 256) " " (k * 65537) " " (k * 1000 - 20000) " " (-k * 999) " " (k * 11) " " (k * 13) " " (k * 1000003); print "pc"; print "Z " (36 + k % 4); print "pc";
         print "f " k " " (k % 9) " " (k * 7 - 100) " " (k * 3); print "pf"; print "Z " (32 + k % 3 + (k % 9) * 32 + 12 - 1 + k % 3); print "pf";
         print "b " (k * 3) " " (k * 1000000007) " " k; print "pb"; print "Z " (14 + k % 4); print "pb" } }' > "$C/gen-ledg.txt"
# Controls: null worlds over seeds, 1..4 variables, episodes, steps up to 255, boxes and caps;
# shuffles and rechains, with records edited between them; M1 and M2 over relation shapes.
awk 'BEGIN { for (k = 0; k < 24; k++) { no = 1 + k % 4; ne = 1 + k % 5; st = (k * 7) % 12; cap = (k % 6 == 5) ? (k * 3) : 4096;
         print "N " (k * 7919) " " no " " ne " " st " " (-k * 100000) " " (k * 100000) " " (-k * 50000) " " (k * 70000) " " cap; print "P";
         print "S " k; print "P"; if (k % 3 == 0) { print "E 1 1 2"; print "E 2 0 0"; print "E 3 2 9"; print "E 1 3 5 0"; print "S " (k + 1); print "P" } print "C"; print "P" }
       print "N 5 2 1 255 -1000 1000 -2000 2000 4096"; print "S 8"; print "C"; print "P";
       for (k = 0; k < 30; k++) { nv = 1 + k % 6; nc = k % 3; ni = nv + nc; print "R " nv " 0 " nc " 0 0";
         for (e = 0; e < nv; e++) { print "Q " e; for (t = 0; t < 1 + (k + e) % 4; t++) { print "T " ((k + 1) * (t + 1) * 9973 - 50000) " " ((e + t) % ni) " " (1 + t % 2) } }
         s = "M " (k % nv) " " (k - 15) " " (1 + k % 7); for (i = 0; i < ni; i++) s = s " " (i == k % ni ? 1 + (k % 2) : 0); print s; print "rs";
         print "D " (k % 11) " " (k - 9); print "rs" }
       for (k = 0; k < 10; k++) print "K " (k * 429496729) " " (k * 28) }' > "$C/gen-ctrl.txt"

# ---- generate mode: write the goldens from the C dumper, keep the MANIFEST header line ----
if [ -n "$GEN" ]; then
  [ -x "$GEN" ] || { echo "PD0V_PARITY FAIL $GEN is not an executable C dumper"; exit 2; }
  mkdir -p "$GOLD"
  hdr=$(head -n 1 "$GOLD/MANIFEST" 2>/dev/null | grep '^# generated once ' || true)
  [ -n "$hdr" ] || { echo "PD0V_PARITY FAIL write the MANIFEST header line (commit, generator command) first"; exit 2; }
  rm -f "$GOLD"/*.out
  for c in "$C"/*.txt; do
    b=$(basename "$c" .txt)
    run "$GEN" "$c" "$GOLD/$b.out" || { echo "PD0V_PARITY FAIL the C dumper failed on $b"; exit 2; }
    [ -s "$GOLD/$b.out" ] || { echo "PD0V_PARITY FAIL empty C output for $b"; exit 2; }
    printf 'corpus %s %s\n' "$b" "$(sha "$c")"
    printf 'golden %s %s\n' "$b" "$(sha "$GOLD/$b.out")"
  done > "$W/MANIFEST.body"
  { printf '%s\n' "$hdr"
    printf '# goldens sha256 (of the corpus and golden lines below) %s\n' "$(sha "$W/MANIFEST.body")"
    cat "$W/MANIFEST.body"; } > "$GOLD/MANIFEST"
  echo "PD0V_PARITY generated $(grep -c '^golden ' "$GOLD/MANIFEST") goldens in $GOLD"
  exit 0
fi

# ---- the corpora and goldens must be the ones the MANIFEST records ----
M=$GOLD/MANIFEST
[ -f "$M" ] || { echo "PD0V_PARITY FAIL missing $M"; exit 2; }
grep -q '^# generated once from the C at main commit 3f2c70dc5' "$M" \
  || { echo "PD0V_PARITY FAIL $M header line does not name the C reference commit"; exit 2; }
grep -v '^#' "$M" > "$W/MANIFEST.body"
[ "$(sed -n 2p "$M")" = "# goldens sha256 (of the corpus and golden lines below) $(sha "$W/MANIFEST.body")" ] \
  || { echo "PD0V_PARITY FAIL $M body does not match its recorded sha256"; exit 2; }
bad=0
nc=$(ls "$C"/*.txt | wc -l | tr -d ' ')
[ "$nc" -eq "$(grep -c '^corpus ' "$M")" ] || { echo "PD0V_PARITY FAIL $nc corpora built, $(grep -c '^corpus ' "$M") in the MANIFEST"; bad=1; }
for c in "$C"/*.txt; do
  b=$(basename "$c" .txt)
  want=$(awk -v b="$b" '$1 == "corpus" && $2 == b { print $3 }' "$M")
  [ "$want" = "$(sha "$c")" ] || { echo "PD0V_PARITY FAIL corpus $b is not the one the goldens were generated from (regenerate: --generate)"; bad=1; }
  want=$(awk -v b="$b" '$1 == "golden" && $2 == b { print $3 }' "$M")
  [ -f "$GOLD/$b.out" ] && [ "$want" = "$(sha "$GOLD/$b.out")" ] || { echo "PD0V_PARITY FAIL golden $b.out missing or not the recorded sha256"; bad=1; }
done
[ "$bad" -eq 0 ] || exit 2

# ---- the OM-2 dumper, from the OM verifier units (P0V_OM_VERIFY of mk/physics0-verify.mk) ----
OMS="src/physics0/pd0_types.om src/physics0/pd0_rng.om src/physics0/pd0_wire.om src/physics0/ladder/pd0_codes.om
src/physics0/ladder/pd0_fmt.om src/physics0/controls/pd0_receipt.om src/physics0/ladder/pd0_ladder.om
src/physics0/score/pd0_score.om src/physics0/controls/pd0_controls.om tests/physics0/verify/pd0v_dump.om"
(printf 'om2\n'; echo 'text PD0_VERIFIER_COMMIT "parity"'; sed -e '/^om2$/d' -e 's/^export fn /fn /' $OMS) | "$OMC" > "$W/pd0v_dump_om"
chmod +x "$W/pd0v_dump_om"

# ---- compare (a corpus may differ only on the output lines tests/physics0/verify/parity_divergences.txt lists) ----
DV=$ROOT/tests/physics0/verify/parity_divergences.txt
[ -f "$DV" ] || { echo "PD0V_PARITY FAIL missing $DV"; exit 2; }
files=0; lines=0; diff=0; ndiv=0
for c in "$C"/*.txt; do
  b=$(basename "$c" .txt)
  rc=0
  run "$W/pd0v_dump_om" "$c" "$W/out/$b.om" || rc=$?
  n=$(wc -l < "$c" | tr -d ' ')
  files=$((files + 1)); lines=$((lines + n))
  awk -F'\t' -v b="$b" '!/^#/ && $1 == b { print $2 }' "$DV" | sort -n > "$W/div.want"
  if [ "$rc" -eq 0 ] && cmp -s "$GOLD/$b.out" "$W/out/$b.om" && [ ! -s "$W/div.want" ]; then
    echo "PARITY $b lines=$n same"
  elif [ "$rc" -eq 0 ] && [ "$(wc -l < "$GOLD/$b.out")" -eq "$(wc -l < "$W/out/$b.om")" ] \
       && awk 'NR == FNR { g[FNR] = $0; next } g[FNR] != $0 { print FNR }' "$GOLD/$b.out" "$W/out/$b.om" > "$W/div.got" \
       && cmp -s "$W/div.want" "$W/div.got"; then
    k=$(grep -c . "$W/div.got"); ndiv=$((ndiv + k))
    echo "PARITY $b lines=$n same except the $k listed capacity divergences (lines $(tr '\n' ' ' < "$W/div.got"| sed 's/ $//'))"
  else
    diff=$((diff + 1))
    echo "PARITY $b lines=$n DIFF exit=$rc (listed divergences: $(tr '\n' ' ' < "$W/div.want"))"
    diff "$GOLD/$b.out" "$W/out/$b.om" | head -20 || true
  fi
done
echo "PD0V_PARITY files=$files lines=$lines diff=$diff divergences=$ndiv reference=C@3f2c70dc5 (goldens) work=$W"
[ "$diff" -eq 0 ]
