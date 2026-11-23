#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# real_parity.sh -- differential qualification of the pure OM-2 realization lab
# (src/visor/visor_realization.om: vrl_realize_apply, vrl_realize_program, vrl_view, vrl_cost,
# vrl_run_pure, vrl_alternatives_ex, vrl_compare, vrl_why, vrl_format_text, vrl_format_json,
# vrl_cost_format_text, vrl_cost_format_json and, through the view, the disassembler) against
# the C it replaced in the omega binary (src/visor/visor_realization.c), on the same inputs.
#
# Every corpus runs through tests/visor/real_dump.om and is compared byte for byte with
# tests/visor/real_golden/<corpus>.out.gz (gzip -9n of the C output). The goldens were generated
# ONCE from the C at main commit 3f2c70dc5 by the reference-only C dumper tests/visor/real_dump.c
# (committed once, then removed); tests/visor/real_golden/MANIFEST records the commit, the
# generator and the sha256 of every corpus and of every uncompressed golden. This script needs no
# C compiler.
#
# Corpus commands (one per line, decimal numbers, '#' and blank lines skipped):
#   matrix   A mi oi ov wi   binary apply of op oi (ADD SUB MUL DIV AND OR EQUAL NOT) with
#                            overflow ov at width 8<<wi on machine mi (0 dgx-spark, 1 qemu-virt,
#                            2 none; the entry commands also 3, a dgx-spark copy with another
#                            machine id), run over a fixed input grid (the wave 33 matrix)
#            P k             program case k (0..56): realize on each machine, run, alternatives
#   graph    R reset | O kind add object | L n payload_len | B o v byte | E o nb v big-endian |
#            W o nb v little-endian | F o j id of object j | X o v 32 bytes v | T k j relation |
#            I compute id | o s w opc ov  type (s: signed) w, values 7 and 11, operation, apply
#   entry    G j mi  realize object j into the current entry | H k mi  build program k, realize
#            n i target name i | q v profile | z n code_len | u v entry_offset | k off w code
#            word | m h has_machine_id | b machine_id = Blackwell | h v realization has_machine_id
#            | j known compatible reason | s has cycles estimate | v _ mi view | c _ mi cost |
#            x argc a b c run_pure | y truncation sizes of the current view
#   alts     w max mi  alternatives without entries | e max mi  alternatives with entries |
#            Q i  compare the current view with alternative view i
# Executed code (x) is only ever the realizer's own or the register-only subset run_check admits,
# writing x0..x15 or xzr and reading only defined registers (the C runs it natively); encodings the
# CPU rejects appear only in views, never executed.
#
# usage: tests/visor/real_parity.sh [OMC]
#          prints PARITY lines and REAL_PARITY ...; exit 0 iff every corpus equals its golden
#        tests/visor/real_parity.sh --generate <C dumper binary>
#          rewrites the goldens and the MANIFEST body from that binary (keeps the header line)
#        tests/visor/real_parity.sh --corpora <dir>   only writes the corpora into <dir>
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GOLD=$ROOT/tests/visor/real_golden
GEN=""; ONLY=""
case "${1:-}" in
  --generate) GEN=${2:?usage: real_parity.sh --generate <C dumper binary>}
    case $GEN in /*) ;; *) GEN=$(pwd)/$GEN ;; esac; OMC="" ;;
  --corpora) ONLY=${2:?usage: real_parity.sh --corpora <dir>}; OMC="" ;;
  *) OMC=${1:-$ROOT/seed/out/omc}; case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac ;;
esac
W=${REAL_PARITY_WORK:-$(mktemp -d)}
mkdir -p "$W/corpus" "$W/out"
sha() { sha256sum "$1" | cut -d' ' -f1; }

# ---- corpora ----
cd "$ROOT"
C=$W/corpus
[ -z "$ONLY" ] || C=$ONLY
mkdir -p "$C"
rm -f "$C"/*.txt
cp tests/visor/real_corpus.txt "$C/hand.txt"
# The wave 33 matrix: every binary apply case, then every program case.
awk 'BEGIN { for (m = 0; m < 3; m++) for (o = 0; o < 8; o++) for (v = 0; v < 4; v++) for (w = 0; w < 4; w++) print "A", m, o, v, w;
       for (k = 0; k < 57; k++) print "P", k }' > "$C/gen-matrix.txt"
# Operations: every opcode 0..18 and 255, 65536 (an opcode no name has), signed or unsigned,
# widths 8 12 32 64, overflow policies 0..3; the apply (object 4) and the operation itself (3).
awk 'BEGIN { split("8 12 32 64", ws, " "); n = 0;
       for (s = 0; s <= 1; s++) for (wi = 1; wi <= 4; wi++) for (opc = 0; opc <= 20; opc++) for (ov = 0; ov <= 3; ov++) {
         op = opc; if (opc == 19) op = 255; if (opc == 20) op = 65536;
         print "R"; print "o", s, ws[wi], op, ov; print "G 4", n % 3; if (ov == 1) print "G 3", n % 3; n++ } }' > "$C/gen-ops.txt"
# Executable code: register-only sequences of the run_check subset (ADD SUB AND ORR EOR shifted
# register, MUL, MOVZ, MOVK) ending in RET, written over a realized ADD apply and run natively
# (C) / interpreted (OM) on fixed arguments. A Park-Miller generator keeps the corpus identical
# under any awk.
awk 'function rnd(n) { seed = (seed * 48271) % 2147483647; return seed % n }
     function pick(   i, k) { k = rnd(nd + 1); if (k == nd) return 31; return def[k] }
     function setd(r,   i) { if (r == 31) return; for (i = 0; i < nd; i++) if (def[i] == r) return; def[nd++] = r }
     function insn(   kind, sf, rd, rn, rm, sh, im, hw, base) {
       kind = rnd(9); sf = rnd(4) ? 1 : 0; rd = rnd(17); if (rd == 16) rd = 31
       rn = pick(); rm = pick()
       if (kind <= 4) {
         split("11 75 10 42 74", bs, " "); base = bs[kind + 1] * 16777216
         sh = (kind <= 1) ? rnd(3) : rnd(4); im = rnd(sf ? 64 : 32); if (rnd(3) == 0) im = 0
         w = sf * 2147483648 + base + sh * 4194304 + rm * 65536 + im * 1024 + rn * 32 + rd
       } else if (kind == 5 || kind == 6) {
         w = sf * 2147483648 + 27 * 16777216 + rm * 65536 + 31 * 1024 + rn * 32 + rd
       } else {
         hw = rnd(sf ? 4 : 2); im = rnd(65536)
         if (kind == 8) { if (nd == 0) return 0; rd = def[rnd(nd)]; base = 114 * 16777216 + 8388608 }
         else base = 82 * 16777216 + 8388608
         w = sf * 2147483648 + base + hw * 2097152 + im * 32 + rd
       }
       setd(rd); return 1 }
     BEGIN { seed = 20261123;
       split("0 1 2 3 5 7 255 65535 4294967295 18446744073709551615 9223372036854775808 1311768467463790320", av, " ")
       print "R"; print "o 0 64 3 1"; print "G 4 0"
       for (t = 0; t < 400; t++) {
         nd = 0; def[nd++] = 0; def[nd++] = 1; def[nd++] = 2
         n = 1 + rnd(24); if (t % 50 == 49) n = 70 + rnd(60)
         off = 0
         for (i = 0; i < n; i++) { if (insn()) { print "k", off, w; off += 4 } }
         print "k", off, 3596551104; off += 4
         print "z", off
         for (r = 0; r < 4; r++) print "x 3", av[1 + rnd(12)], av[1 + rnd(12)], av[1 + rnd(12)]
         print "x 1", av[1 + rnd(12)]
         if (t % 8 == 0) print "v 0", t % 3
         if (t % 8 == 4) print "c 0", t % 3 } }' > "$C/gen-exec.txt"
# Disassembly and the run gate: words of every class the decoder knows (branches, compare and
# branch, ADR, loads and stores, SUBS, the pure subset with every shift type and the encodings the
# CPU rejects), random words, and a full 4096-byte buffer (the 64-line disassembly cap); viewed,
# never executed.
awk 'function rnd(n) { seed = (seed * 48271) % 2147483647; return seed % n }
     function r32() { return rnd(65536) * 65536 + rnd(65536) }
     function word(c,   sf) { sf = rnd(2) * 2147483648
       if (c == 0) return 5 * 67108864 + rnd(67108864)
       if (c == 1) return 37 * 67108864 + rnd(67108864)
       if (c == 2) return 84 * 16777216 + rnd(524288) * 32 + rnd(16)
       if (c == 3) return sf + 52 * 16777216 + rnd(524288) * 32 + rnd(32)
       if (c == 4) return sf + 53 * 16777216 + rnd(524288) * 32 + rnd(32)
       if (c == 5) return rnd(4) * 536870912 + 16 * 16777216 + rnd(524288) * 32 + rnd(32)
       if (c == 6) return 249 * 16777216 + 4194304 + rnd(4096) * 1024 + rnd(1024)
       if (c == 7) return 249 * 16777216 + rnd(4096) * 1024 + rnd(1024)
       if (c == 8) return 57 * 16777216 + 4194304 + rnd(4096) * 1024 + rnd(1024)
       if (c == 9) return 57 * 16777216 + rnd(4096) * 1024 + rnd(1024)
       if (c == 10) return 235 * 16777216 + rnd(4) * 4194304 + rnd(2097152)
       if (c == 11) return 241 * 16777216 + rnd(4194304)
       if (c == 12) return 145 * 16777216 + rnd(4194304)
       if (c == 13) return sf + (11 + 64 * rnd(2)) * 16777216 + 3 * 4194304 + rnd(2097152)
       if (c == 14) return sf + (10 + 32 * rnd(3)) * 16777216 + 2097152 + rnd(4) * 4194304 + rnd(2097152)
       if (c == 15) return 11 * 16777216 + rnd(4) * 4194304 + rnd(32) * 65536 + (32 + rnd(32)) * 1024 + rnd(1024)
       if (c == 16) return 82 * 16777216 + 8388608 + (2 + rnd(2)) * 2097152 + rnd(2097152)
       if (c == 17) return sf + 27 * 16777216 + rnd(2097152)
       if (c == 18) return 3596551104
       if (c == 19) return sf + (82 + 32 * rnd(2)) * 16777216 + 8388608 + rnd(8388608)
       return r32() }
     BEGIN { seed = 7340033
       print "R"; print "o 0 64 3 1"; print "G 4 0"
       for (c = 0; c <= 20; c++) for (g = 0; g < 6; g++) {
         n = 1 + rnd(16)
         for (i = 0; i < n; i++) print "k", 4 * i, word(c)
         if (rnd(2)) print "k", 4 * n, 3596551104
         print "z", 4 * n + 4 * rnd(2); print "v 0", rnd(3) }
       for (i = 0; i < 1024; i++) print "k", 4 * i, word(rnd(21))
       print "z 4096"; print "v 0 0"; print "x 2 1 2"
       for (i = 0; i < 1023; i++) print "k", 4 * i, 2332033024
       print "k 4092 3596551104"; print "v 0 1"; print "x 2 5 6"; print "z 4100"; print "x 2 5 6" }' > "$C/gen-disasm.txt"
# Entry edits: from a realized apply and realized programs on every machine, each field the run
# gate, the view and the cost read is changed alone, then viewed, costed and run.
awk 'function base(b) { if (b == 0) { print "R"; print "o 0 64 3 1"; print "G 4", bm } else print "H", b, bm }
     function look(   m) { for (m = 0; m < 4; m++) { print "v 0", m; print "c 0", m }
       print "x 2 3 4"; print "x 4 1 2 3"; print "x 0"; print "x 3 9 4 1" }
     BEGIN { split("0 9 44 52", bs, " ")
       for (bi = 1; bi <= 4; bi++) for (bm = 0; bm < 4; bm++) { b = bs[bi]
         base(b); look(); print "y"
         for (i = 0; i < 8; i++) { base(b); print "n", i; look() }
         split("0 2 255", ps, " "); for (i = 1; i <= 3; i++) { base(b); print "q", ps[i]; look() }
         split("0 2 6 4092", zs, " "); for (i = 1; i <= 4; i++) { base(b); print "z", zs[i]; look() }
         base(b); print "z 4100"; print "x 2 3 4"
         split("1 4 4294967295", us, " "); for (i = 1; i <= 3; i++) { base(b); print "u", us[i]; look() }
         base(b); print "b"; print "m 1"; look()
         base(b); print "b"; print "m 0"; look()
         base(b); print "m 0"; look()
         base(b); print "m 1"; look()
         base(b); print "h 1"; look()
         base(b); print "h 0"; look()
         base(b); print "j 0 0 0"; look()
         base(b); print "j 1 0 1"; look(); print "y"
         base(b); print "j 1 0 0"; look()
         base(b); print "j 1 1 1"; look()
         base(b); print "s 0 0"; look()
         base(b); print "s 1 77"; look()
         base(b); print "s 1 4294967295"; print "m 0"; look()
         base(b); print "k 0 335544320"; look()
         base(b); print "k 0 0"; look()
         base(b); print "k 0 3596551104"; look()
         base(b); print "k 0 4181721088"; look()
         base(b); print "z 4"; print "k 0 2332033024"; look()
         base(b); print "n 1"; print "s 1 5"; print "j 1 0 1"; print "b"; print "m 1"; look() } }' > "$C/gen-entry.txt"
# Alternatives: with and without entries, every max 0..4, on every machine.
awk 'BEGIN { split("0 8 23 41 42 44 46 47 48 49 50 51 52 53 54 55 56", ks, " ")
       for (i = 1; i <= 17; i++) for (m = 0; m < 4; m++) { print "H", ks[i], m
         for (x = 0; x <= 4; x++) { if (m == 0 || x == 4 || x == 1) print "w", x, m; if (x == 1 || x == 3) print "e", x, m } } }' > "$C/gen-alts.txt"
[ -z "$ONLY" ] || { echo "REAL_PARITY corpora in $C"; exit 0; }

# ---- generate mode: write the goldens from the C dumper, keep the MANIFEST header line ----
if [ -n "$GEN" ]; then
  [ -x "$GEN" ] || { echo "REAL_PARITY FAIL $GEN is not an executable C dumper"; exit 2; }
  mkdir -p "$GOLD"
  hdr=$(head -n 1 "$GOLD/MANIFEST" 2>/dev/null | grep '^# generated once ' || true)
  [ -n "$hdr" ] || { echo "REAL_PARITY FAIL write the MANIFEST header line (commit, generator command) first"; exit 2; }
  rm -f "$GOLD"/*.out.gz
  for c in "$C"/*.txt; do
    b=$(basename "$c" .txt)
    "$GEN" < "$c" > "$W/out/$b.c" || { echo "REAL_PARITY FAIL the C dumper failed on $b"; exit 2; }
    [ -s "$W/out/$b.c" ] || { echo "REAL_PARITY FAIL empty C output for $b"; exit 2; }
    gzip -9n < "$W/out/$b.c" > "$GOLD/$b.out.gz"
    printf 'corpus %s %s\n' "$b" "$(sha "$c")"
    printf 'golden %s %s\n' "$b" "$(sha "$W/out/$b.c")"
  done > "$W/MANIFEST.body"
  { printf '%s\n' "$hdr"
    printf '# goldens sha256 (of the corpus and golden lines below) %s\n' "$(sha "$W/MANIFEST.body")"
    cat "$W/MANIFEST.body"; } > "$GOLD/MANIFEST"
  echo "REAL_PARITY generated $(grep -c '^golden ' "$GOLD/MANIFEST") goldens in $GOLD"
  exit 0
fi

# ---- the corpora and goldens must be the ones the MANIFEST records ----
M=$GOLD/MANIFEST
[ -f "$M" ] || { echo "REAL_PARITY FAIL missing $M"; exit 2; }
grep -q '^# generated once from the C at main commit 3f2c70dc5' "$M" \
  || { echo "REAL_PARITY FAIL $M header line does not name the C reference commit"; exit 2; }
grep -v '^#' "$M" > "$W/MANIFEST.body"
[ "$(sed -n 2p "$M")" = "# goldens sha256 (of the corpus and golden lines below) $(sha "$W/MANIFEST.body")" ] \
  || { echo "REAL_PARITY FAIL $M body does not match its recorded sha256"; exit 2; }
bad=0
nc=$(ls "$C"/*.txt | wc -l | tr -d ' ')
[ "$nc" -eq "$(grep -c '^corpus ' "$M")" ] || { echo "REAL_PARITY FAIL $nc corpora built, $(grep -c '^corpus ' "$M") in the MANIFEST"; bad=1; }
for c in "$C"/*.txt; do
  b=$(basename "$c" .txt)
  want=$(awk -v b="$b" '$1 == "corpus" && $2 == b { print $3 }' "$M")
  [ "$want" = "$(sha "$c")" ] || { echo "REAL_PARITY FAIL corpus $b is not the one the goldens were generated from (regenerate: --generate)"; bad=1; }
  want=$(awk -v b="$b" '$1 == "golden" && $2 == b { print $3 }' "$M")
  if [ -f "$GOLD/$b.out.gz" ] && gzip -dc "$GOLD/$b.out.gz" > "$W/out/$b.gold" && [ "$want" = "$(sha "$W/out/$b.gold")" ]; then :; else
    echo "REAL_PARITY FAIL golden $b.out.gz missing or not the recorded sha256"; bad=1; fi
done
[ "$bad" -eq 0 ] || exit 2

# ---- the OM-2 dumper, from the shipped modules (as mk/visor-machine.mk joins them) ----
OMS="src/visor/visor.om om/aarch64/aarch64_om2.om om/visor/verify_om2.om om/visor/validate_om2.om
src/visor/visor_machine.om src/visor/visor_program.om src/visor/visor_realization.om tests/visor/real_dump.om"
(printf 'om2\n'; sed -e '/^om2$/d' -e 's/^export fn /fn /' $OMS) | "$OMC" > "$W/real_dump_om"
chmod +x "$W/real_dump_om"

# ---- compare ----
files=0; lines=0; diff=0
for c in "$C"/*.txt; do
  b=$(basename "$c" .txt)
  rc=0
  "$W/real_dump_om" < "$c" > "$W/out/$b.om" || rc=$?
  n=$(wc -l < "$c" | tr -d ' ')
  files=$((files + 1)); lines=$((lines + n))
  if [ "$rc" -eq 0 ] && cmp -s "$W/out/$b.gold" "$W/out/$b.om"; then
    echo "PARITY $b lines=$n same"
  else
    diff=$((diff + 1))
    echo "PARITY $b lines=$n DIFF exit=$rc"
    diff "$W/out/$b.gold" "$W/out/$b.om" | head -20 || true
  fi
done
echo "REAL_PARITY files=$files lines=$lines diff=$diff reference=C@3f2c70dc5 (goldens) work=$W"
[ "$diff" -eq 0 ]
