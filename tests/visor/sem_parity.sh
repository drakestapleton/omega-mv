#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# sem_parity.sh -- differential qualification of the pure OM-2 semantic lane
# (src/visor/visor_semantic.om, run by the omega binary) against the C it replaced
# (src/visor/visor_semantic.c, retired), on the same graphs.
#
# Every corpus runs through tests/visor/sem_dump.om (built from the shipped visor.om and
# visor_semantic.om) and is compared byte for byte with tests/visor/sem_golden/<corpus>.out:
# inspect return code, the text and JSON renderings and their exact-size refusals, type_of,
# apply_parts, value_u64, eval_u64, graph_text (with small buffers) and the five name helpers.
# The goldens were generated ONCE from the C at main commit 3f2c70dc5 by the reference-only C
# dumper tests/visor/sem_dump.c (committed once, then removed); tests/visor/sem_golden/MANIFEST
# records the commit, the generator and the sha256 of every corpus and golden. This script
# needs no C compiler.
#
# Corpus commands: see the header of tests/visor/sem_dump.om.
#
# usage: tests/visor/sem_parity.sh [OMC]
#          prints PARITY lines and SEM_PARITY ...; exit 0 iff every corpus equals its golden
#        tests/visor/sem_parity.sh --generate <C dumper binary>
#          rewrites the goldens and the MANIFEST body from that binary (keeps the header line)
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GOLD=$ROOT/tests/visor/sem_golden
GEN=""
if [ "${1:-}" = "--generate" ]; then
  GEN=${2:?usage: sem_parity.sh --generate <C dumper binary>}
  case $GEN in /*) ;; *) GEN=$(pwd)/$GEN ;; esac
  OMC=""
else
  OMC=${1:-$ROOT/seed/out/omc}
  case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
fi
W=${SEM_PARITY_WORK:-$(mktemp -d)}
mkdir -p "$W/corpus" "$W/out"
sha() { sha256sum "$1" | cut -d' ' -f1; }

# ---- corpora ----
cd "$ROOT"
C=$W/corpus
rm -f "$C"/*.txt
cp tests/visor/sem_corpus.txt "$C/hand.txt"
# Shared object builders (awk): each prints the commands and returns the new object's index.
LIB='function ty(tag, w, l) { print "O 2"; print "L 44"; print "W 0 4 " tag; print "W 4 2 " w; print "W 8 4 " l; print "I"; return n++ }
function seq(e, l) { print "O 2"; print "L 44"; print "W 0 4 7"; print "W 8 4 " l; print "F 12 " e; print "I"; return n++ }
function val(t, bl, v,   i, b) { print "O 1"; print "L 98"; print "F 0 " t; print "W 32 2 " bl;
  b = v; for (i = bl - 1; i >= 0; i--) { if (i < 64) print "B " (34 + i) " " (b % 256); b = int(b / 256) } print "I"; return n++ }
function op(opc, ov, t, ar, i1, i2, o,   i) { print "O 3"; print "L 204"; print "W 0 4 " opc; print "W 4 4 " ov; print "F 8 " t; print "B 40 " ar;
  if (i1 >= 0) print "F 41 " i1; if (i2 >= 0) print "F 73 " i2; if (i1 >= 0 && ar > 2) { print "F 105 " i1; print "F 137 " i1 }
  if (o >= 0) print "F 169 " o; print "I"; return n++ }
function ap(o, c, a1, a2) { print "O 3"; print "L 161"; print "F 0 " o; print "B 32 " c; if (a1 >= 0) print "F 33 " a1; if (a2 >= 0) print "F 65 " a2;
  if (c > 2 && a1 >= 0) { print "F 97 " a1; print "F 129 " a1 } print "I"; return n++ }
function all(j) { print "S " j; print "U " j; print "H " j; print "Z " j; print "J " j; print "M " j " 0" }
function reset() { print "R"; n = 0 }'
# Types: every tag 0..16 and 255 with widths 0..65535 and lengths; payloads 43..45; sequences of
# sequences nested 1..12 deep (type text gives up past depth 8), over a missing, zero, non-type
# or malformed element.
awk "$LIB"'
BEGIN { split("0 1 7 8 32 64 65 255 65535", ws, " "); split("0 5 4294967295", ls, " ");
  for (tag = 0; tag <= 16; tag++) for (k = 1; k <= 9; k++) { reset(); j = ty(tag, ws[k], ls[(k % 3) + 1]); print "S " j; print "U " j; print "M " j " 0" }
  reset(); j = ty(255, 8, 0); print "S " j
  for (pl = 43; pl <= 45; pl++) { reset(); print "O 2"; print "L " pl; print "W 0 4 3"; print "W 4 2 8"; print "I"; print "S 0"; print "M 0 0" }
  for (d = 1; d <= 12; d++) for (base = 0; base <= 4; base++) { reset();
    if (base == 0) e = ty(3, 32, 0); else if (base == 1) e = ty(2, 1, 0);
    else if (base == 2) { print "O 1"; print "L 98"; print "I"; e = n++ } else if (base == 3) { print "O 2"; print "L 44"; print "W 0 4 99"; print "I"; e = n++ }
    else { print "O 2"; print "L 44"; print "W 0 4 7"; print "X 12 9"; print "I"; e = n++ }
    for (i = 1; i <= d; i++) e = seq(e, i * 3); print "S " e; print "U " e; print "M " e " 0" }
  reset(); print "O 2"; print "L 44"; print "W 0 4 7"; print "W 8 4 4"; print "I"; print "S 0"; print "M 0 0" }' > "$C/gen-types.txt"
# Values: integer, bitvector, byte, bool, signed, unit, fp32 and missing types; byte_len 0..9
# and 64, 65, 300; values at and over the width; payload 97..99.
awk "$LIB"'
BEGIN { split("1 7 8 9 16 31 32 63 64 65 0", ws, " ");
  for (k = 1; k <= 11; k++) for (tg = 1; tg <= 4; tg++) { tag = (tg == 1 ? 3 : (tg == 2 ? 5 : (tg == 3 ? 4 : 6))); w = ws[k];
    for (bl = 0; bl <= 9; bl++) for (vv = 0; vv <= 2; vv++) { reset(); t = ty(tag, w, 0);
      v = (vv == 0 ? 0 : (vv == 1 ? 2 ^ (w > 52 ? 52 : w) - 1 : 2 ^ (w > 52 ? 52 : w))); j = val(t, bl, v); nb = int((w + 7) / 8);
      if (bl == 0 || bl == nb || (bl == nb + 1 && vv == 1)) { print "S " j; print "M " j " 0" } print "Z " j; print "J " j; print "U " j } }
  for (bl = 0; bl <= 3; bl++) for (v = 0; v <= 3; v++) { reset(); t = ty(2, 1, 0); j = val(t, bl, v); print "S " j; print "Z " j; print "J " j; print "M " j " 0" }
  split("1 9 10 14 15 0", os, " ");
  for (k = 1; k <= 6; k++) { reset(); t = ty(os[k], 8, 0); j = val(t, 1, 5); print "S " j; print "Z " j; print "U " j; print "M " j " 0" }
  split("64 65 300 65535", bs, " ");
  for (k = 1; k <= 4; k++) { reset(); t = ty(3, 64, 0); j = val(t, bs[k], 1); print "S " j; print "Z " j; print "M " j " 0" }
  reset(); print "O 1"; print "L 98"; print "X 0 7"; print "W 32 2 1"; print "I"; print "S 0"; print "Z 0"; print "U 0"; print "J 0"; print "M 0 0"
  reset(); print "O 1"; print "L 98"; print "W 32 2 1"; print "I"; print "S 0"; print "Z 0"; print "U 0"; print "M 0 0"
  reset(); t = ty(3, 8, 0); print "O 1"; print "L 98"; print "F 0 " t; print "W 32 2 1"; print "B 34 9"; print "I"; print "O 1"; print "L 98"; print "F 0 1"; print "W 32 2 1"; print "I"; print "S 2"; print "Z 2"; print "U 2"; print "M 2 0"
  for (pl = 97; pl <= 99; pl++) { reset(); t = ty(3, 8, 0); print "O 1"; print "L " pl; print "F 0 " t; print "W 32 2 1"; print "B 34 3"; print "I"; print "S 1"; print "Z 1"; print "M 1 0" } }' > "$C/gen-values.txt"
# Operations: opcode 0..17 x overflow 0..4 x arity 0..5, with real, zero, missing and malformed
# input and output types; payload 203..205.
awk "$LIB"'
BEGIN { for (opc = 0; opc <= 17; opc++) for (ov = 0; ov <= 4; ov++) for (ar = 0; ar <= 5; ar++) { reset(); t = ty(3, 64, 0);
    j = op(opc, ov, t, ar, (ar % 2 ? t : -1), t, (opc % 3 ? t : -1)); print "S " j; print "U " j; print "H " j; print "M " j " 0" }
  for (k = 0; k <= 4; k++) { reset(); t = ty(3, 16, 0); b = ty(2, 1, 0); s = seq(t, 4);
    if (k == 0) j = op(3, 1, t, 4, b, s, b); else if (k == 1) { print "O 3"; print "L 204"; print "W 0 4 3"; print "W 4 4 1"; print "X 8 5"; print "B 40 2"; print "X 41 6"; print "X 73 7"; print "X 169 8"; print "I"; j = n++ }
    else if (k == 2) { print "O 2"; print "L 44"; print "W 0 4 99"; print "I"; m = n++; j = op(4, 2, m, 2, m, m, m) }
    else if (k == 3) j = op(5, 3, s, 3, s, t, s); else { j = op(8, 1, t, 2, t, t, b) }
    print "S " j; print "U " j; print "M " j " 0" }
  for (pl = 203; pl <= 205; pl++) { reset(); t = ty(3, 8, 0); print "O 3"; print "L " pl; print "W 0 4 3"; print "W 4 4 1"; print "F 8 " t; print "B 40 2"; print "F 41 " t; print "F 73 " t; print "F 169 " t; print "I"; print "S 1"; print "U 1"; print "M 1 0" } }' > "$C/gen-ops.txt"
# Applies: operand_count 0..6 and 255 over real, missing, non-operation and malformed ops;
# payload 159..162; apply_parts on every shape.
awk "$LIB"'
BEGIN { split("0 1 2 3 4 5 6 255", cs, " ");
  for (k = 1; k <= 8; k++) for (opk = 0; opk <= 4; opk++) { reset(); t = ty(3, 32, 0); v = val(t, 4, 9);
    if (opk == 0) o = op(3, 1, t, 2, t, t, t); else if (opk == 1) o = v; else if (opk == 2) o = op(5, 2, t, 2, t, t, -1);
    else if (opk == 3) { print "O 3"; print "L 204"; print "W 0 4 99"; print "W 4 4 1"; print "I"; o = n++ } else o = -1;
    print "O 3"; print "L 161"; if (o >= 0) print "F 0 " o; else print "X 0 3"; print "B 32 " cs[k];
    for (i = 0; i < 4; i++) print "F " (33 + 32 * i) " " (i % 2 ? t : v); print "I"; j = n++; all(j) }
  for (pl = 159; pl <= 162; pl++) { reset(); t = ty(3, 8, 0); v = val(t, 1, 3); o = op(3, 1, t, 2, t, t, t); print "O 3"; print "L " pl; print "F 0 " o; print "B 32 2"; print "F 33 " v; print "F 65 " v; print "I"; all(n) } }' > "$C/gen-apply.txt"
# Evaluation: every opcode x overflow at widths 1..64 over boundary operands; bool, signed and
# zero-width operation types; operand type mismatches; arity and operand_count other than 2;
# missing and malformed operands; nested chains 60..70 deep (refused past depth 64).
awk "$LIB"'
BEGIN { split("1 2 7 8 16 32 63 64", ws, " "); split("0 1 5 3 255 65535 4294967295 9007199254740991", vs, " ");
  for (k = 1; k <= 8; k++) for (opc = 1; opc <= 16; opc++) for (ov = 1; ov <= 3; ov++) { reset(); w = ws[k]; t = ty(3, w, 0); o = op(opc, ov, t, 2, t, t, t);
    nb = int((w + 7) / 8); m = (w > 52 ? 9007199254740991 : 2 ^ w - 1);
    for (x = 1; x <= 8; x += 3) for (y = 1; y <= 8; y++) { a = vs[x]; b = vs[y]; if (a > m) a = m; if (b > m) b = m;
      va = val(t, nb, a); vb = val(t, nb, b); j = ap(o, 2, va, vb); print "J " j } }
  for (tg = 1; tg <= 6; tg++) { reset(); t = ty(tg, 8, 0); u = ty(3, 8, 0); o = op(3, 1, t, 2, u, u, u); va = val(u, 1, 3); j = ap(o, 2, va, va); print "J " j; print "S " j; print "M " j " 0" }
  reset(); t = ty(3, 0, 0); u = ty(3, 8, 0); o = op(3, 1, t, 2, u, u, u); va = val(u, 1, 3); j = ap(o, 2, va, va); print "J " j
  reset(); t = ty(5, 8, 0); o = op(3, 1, t, 2, t, t, t); va = val(t, 1, 3); j = ap(o, 2, va, va); print "J " j
  reset(); t = ty(6, 8, 0); o = op(4, 1, t, 2, t, t, t); va = val(t, 1, 3); vb = val(t, 1, 5); j = ap(o, 2, va, vb); print "J " j
  reset(); t = ty(3, 8, 0); u = ty(3, 16, 0); o = op(3, 1, t, 2, t, t, t); va = val(t, 1, 3); vb = val(u, 2, 3); j = ap(o, 2, va, vb); print "J " j; j = ap(o, 2, vb, va); print "J " j
  for (ar = 0; ar <= 4; ar++) for (c = 0; c <= 4; c++) { reset(); t = ty(3, 8, 0); o = op(3, 1, t, ar, t, t, t); va = val(t, 1, 3); j = ap(o, c, va, va); print "J " j }
  reset(); t = ty(3, 8, 0); o = op(3, 1, t, 2, t, t, t); va = val(t, 1, 3); print "O 3"; print "L 161"; print "F 0 " o; print "B 32 2"; print "F 33 " va; print "X 65 4"; print "I"; print "J " n++
  reset(); t = ty(3, 8, 0); o = op(3, 1, t, 2, t, t, t); print "O 1"; print "L 98"; print "F 0 " t; print "W 32 2 3"; print "I"; m = n++; j = ap(o, 2, m, m); print "J " j
  reset(); t = ty(3, 8, 0); o = op(3, 1, t, 2, t, t, t); print "O 1"; print "L 98"; print "F 0 " t; print "W 32 2 1"; print "I"; print "B 34 1"; m = n++; j = ap(o, 2, m, m); print "J " j
  reset(); t = ty(3, 8, 0); o = op(3, 1, t, 2, t, t, t); print "O 1"; print "L 98"; print "F 0 " t; print "W 32 2 99"; print "I"; m = n++; j = ap(o, 2, m, m); print "J " j
  reset(); t = ty(3, 8, 0); print "O 3"; print "L 204"; print "W 0 4 3"; print "W 4 4 1"; print "F 8 " t; print "B 40 2"; print "F 41 " t; print "F 73 " t; print "F 169 " t; print "I"; print "B 0 4"; o = n++; va = val(t, 1, 3); j = ap(o, 2, va, va); print "J " j
  reset(); t = ty(3, 8, 0); v1 = val(t, 1, 1); o = op(1, 1, t, 2, t, t, t); j = ap(o, 2, v1, v1); print "J " j; o2 = op(3, 1, t, 2, t, t, t); j2 = ap(o2, 2, j, v1); print "J " j2
  for (d = 60; d <= 70; d++) for (side = 0; side <= 1; side++) { reset(); t = ty(3, 64, 0); o = op(3, 1, t, 2, t, t, t); v1 = val(t, 8, 1); e = v1;
    for (i = 0; i < d; i++) e = (side ? ap(o, 2, v1, e) : ap(o, 2, e, v1)); print "J " e; print "M " e " 0" } }' > "$C/gen-eval.txt"
# Attributes and constraints: printable, quoted, escaped and binary values; 0..33 of them; value
# lengths up to 513; constraint kinds 0..12 and payloads up to 129; counts and lengths poked past
# their bounds; an encoding past 4096 bytes; renderings past 65535 bytes.
awk "$LIB"'
function key(k,   i, s) { s = "K"; for (i = 0; i < k % 9 + 1; i++) s = s " " (97 + (k + i) % 26); print s }
BEGIN { for (a = 0; a <= 33; a++) { reset(); t = ty(3, 8, 0); print "O 1"; print "L 98"; print "F 0 " t; print "W 32 2 1"; print "B 34 2";
    for (i = 0; i < a; i++) { key(i); if (i % 4 == 0) print "V 104 105 34 92 32 126"; else if (i % 4 == 1) print "V 0 1 31 127 128 255"; else if (i % 4 == 2) print "G " (i * 3) " 32 1"; print "A" }
    print "I"; print "S 1"; print "M 1 0" }
  split("0 1 64 127 128 129 255 256 511 512 513", vl, " ");
  for (k = 1; k <= 11; k++) for (p = 0; p <= 1; p++) { reset(); t = ty(3, 8, 0); print "O 1"; print "L 98"; print "F 0 " t; print "W 32 2 1"; print "B 34 2";
    print "K 107"; print "G " vl[k] " " (p ? 65 : 7) " " (p ? 0 : 13); print "A"; print "I"; print "S 1" }
  for (kk = 0; kk <= 12; kk++) for (pl = 0; pl <= 129; pl += 43) { reset(); t = ty(3, 8, 0); print "O 1"; print "L 98"; print "F 0 " t; print "W 32 2 1";
    print "G " pl " " kk " 3"; print "Q " kk; print "G 3 1 1"; print "Q " (kk + 100); print "I"; print "S 1" }
  for (c = 30; c <= 33; c++) { reset(); print "O 4"; print "L 0"; for (i = 0; i < c; i++) { print "V " i; print "Q " (i % 12) } print "I"; print "S 0"; print "M 0 0" }
  split("33 64 65000", ps, " ");
  for (f = 0; f <= 4; f++) for (k = 1; k <= 3; k++) { reset(); t = ty(3, 8, 0); print "O 1"; print "L 98"; print "F 0 " t; print "W 32 2 1"; print "K 120"; print "V 1"; print "A"; print "V 2"; print "Q 1"; print "I";
    v = ps[k]; if (f == 3 || f == 4) v = (k == 1 ? 513 : (k == 2 ? 129 : 1000)); if (f == 3 && k == 2) v = 512; if (f == 4 && k == 1) v = 128;
    print "P " f " 0 " v; print "S 1"; print "U 1"; print "Z 1"; print "M 1 0" }
  for (k = 0; k <= 2; k++) { reset(); print "O 1"; print "L " (1024 + k); print "P 5 0 1"; print "S 0"; print "M 0 0" }
  for (na = 6; na <= 9; na++) { reset(); print "O 6"; print "L 1024"; for (i = 0; i < na; i++) { key(i); print "G 512 " i " 1"; print "A" } print "I"; print "P 5 0 1"; print "S 0"; print "M 0 0" }
  for (na = 20; na <= 32; na += 4) for (p = 0; p <= 1; p++) { reset(); print "O 6"; print "L 4"; for (i = 0; i < na; i++) { key(i); print "G 400 " (p ? 33 : 1) " " (p ? 0 : 1); print "A" } print "P 5 0 1"; print "S 0" } }' > "$C/gen-attrs.txt"
# Relations and dependencies: kinds 0..12 and 65535; 0..65 relations (65 refused); resolved,
# dangling, duplicate and self targets; dependencies deduplicated across roles; opaque kinds.
awk "$LIB"'
BEGIN { for (kd = 0; kd <= 12; kd++) { reset(); t = ty(3, 8, 0); v = val(t, 1, 1); print "O 9"; print "L 3"; print "B 0 7"; print "T " kd " " t; print "Y " kd " 5"; print "T " kd " " v; print "Y 65535 0"; print "I"; print "S 2"; print "M 2 0" }
  for (r = 0; r <= 65; r += (r < 4 ? 1 : 15)) { reset(); t = ty(3, 8, 0); v = val(t, 1, 1); print "O 1"; print "L 98"; print "F 0 " t; print "W 32 2 1";
    for (i = 0; i < r; i++) { if (i % 3 == 0) print "T 6 " (i % 2 ? t : v); else print "Y 7 " (i % 250 + 1) } print "I"; print "S 2"; print "M 2 0" }
  reset(); for (i = 0; i < 66; i++) print "Y 6 " i; print "O 1"; for (i = 0; i < 66; i++) print "Y 6 " i; print "L 98"; print "I"; print "S 0"
  for (kd = 0; kd <= 12; kd++) { reset(); print "O " kd; print "L " (kd * 7); print "B 0 1"; print "I"; print "S 0"; print "U 0"; print "H 0"; print "Z 0"; print "J 0"; print "M 0 0" }
  reset(); print "O 255"; print "L 2"; print "I"; print "S 0"; print "M 0 0"
  reset(); print "O 12"; print "L 2"; print "I"; print "S 0"; print "M 0 0"
  reset(); t = ty(3, 8, 0); o = op(3, 1, t, 4, t, t, t); print "O 2"; print "L 44"; print "W 0 4 7"; print "F 12 " t; print "T 6 " t; print "T 7 " o; print "I"; print "S 2"; print "M 2 0"
  reset(); t = ty(3, 8, 0); print "O 1"; print "L 98"; print "F 0 " t; print "W 32 2 1"; print "I"; print "S 1"; print "S 1000"; print "S 1009"; print "M 1000 0"; print "U 1009"; print "H 1009"; print "Z 1009"; print "J 1009" }' > "$C/gen-rels.txt"
# Graph text: DAGs (each object once), a dependency cycle through relations, missing and
# malformed nodes (not followed), chains 62..66 deep (refused past 64), and buffers of 1..400
# bytes (refused when the text does not fit); the stored id altered after it was computed.
awk "$LIB"'
BEGIN { reset(); t = ty(3, 8, 0); v1 = val(t, 1, 1); v2 = val(t, 1, 2); o = op(3, 1, t, 2, t, t, t); a = ap(o, 2, v1, v2); b = ap(o, 2, a, v1);
  print "O 3"; print "L 161"; print "F 0 " o; print "B 32 2"; print "F 33 " b; print "X 65 77"; print "T 6 " a; print "I"; c = n++;
  for (sz = 1; sz <= 400; sz += 7) print "M " c " " sz; print "M " c " 0"; print "S " c
  reset(); print "O 4"; print "L 1"; print "Y 6 3"; print "I"; print "O 4"; print "L 1"; print "T 6 0"; print "Y 9 1"; print "I"; print "O 4"; print "L 2"; print "T 6 1"; print "T 6 0"; print "I"; print "M 2 0"; print "M 1 0"
  reset(); t = ty(3, 8, 0); print "O 1"; print "L 98"; print "F 0 " t; print "W 32 2 1"; print "I"; print "B 34 1"; print "O 4"; print "L 0"; print "T 6 1"; print "T 6 0"; print "Y 6 4"; print "I"; print "M 2 0"; print "S 1"; print "U 1"; print "Z 1"; print "H 1"; print "J 1"
  reset(); print "O 99"; print "L 0"; print "I"; print "O 4"; print "L 0"; print "T 6 0"; print "I"; print "M 1 0"; print "M 0 0"
  for (d = 62; d <= 66; d++) { reset(); print "O 4"; print "L 0"; print "I"; for (i = 1; i <= d; i++) { print "O 4"; print "L 0"; print "T 6 " (i - 1); print "I" } print "M " d " 0"; print "S " d }
  reset(); t = ty(3, 8, 0); o = op(3, 1, t, 2, t, t, t); v1 = val(t, 1, 1); a = ap(o, 2, v1, v1); print "P 5 0 0"; print "S " a; print "M " a " 0"; print "J " a }' > "$C/gen-graph.txt"
# Names: every value 0..20 of the five name helpers, and 255, 65535, 2^32-1.
awk 'BEGIN { split("255 65535 4294967295", xs, " "); for (w = 0; w <= 4; w++) { for (x = 0; x <= 20; x++) print "C " w " " x; for (k = 1; k <= 3; k++) print "C " w " " xs[k] } }' > "$C/gen-names.txt"

# ---- generate mode: write the goldens from the C dumper, keep the MANIFEST header line ----
if [ -n "$GEN" ]; then
  [ -x "$GEN" ] || { echo "SEM_PARITY FAIL $GEN is not an executable C dumper"; exit 2; }
  mkdir -p "$GOLD"
  hdr=$(head -n 1 "$GOLD/MANIFEST" 2>/dev/null | grep '^# generated once ' || true)
  [ -n "$hdr" ] || { echo "SEM_PARITY FAIL write the MANIFEST header line (commit, generator command) first"; exit 2; }
  rm -f "$GOLD"/*.out
  for c in "$C"/*.txt; do
    b=$(basename "$c" .txt)
    "$GEN" < "$c" > "$GOLD/$b.out" || { echo "SEM_PARITY FAIL the C dumper failed on $b"; exit 2; }
    [ -s "$GOLD/$b.out" ] || { echo "SEM_PARITY FAIL empty C output for $b"; exit 2; }
    printf 'corpus %s %s\n' "$b" "$(sha "$c")"
    printf 'golden %s %s\n' "$b" "$(sha "$GOLD/$b.out")"
  done > "$W/MANIFEST.body"
  { printf '%s\n' "$hdr"
    printf '# goldens sha256 (of the corpus and golden lines below) %s\n' "$(sha "$W/MANIFEST.body")"
    cat "$W/MANIFEST.body"; } > "$GOLD/MANIFEST"
  echo "SEM_PARITY generated $(grep -c '^golden ' "$GOLD/MANIFEST") goldens in $GOLD"
  exit 0
fi

# ---- the corpora and goldens must be the ones the MANIFEST records ----
M=$GOLD/MANIFEST
[ -f "$M" ] || { echo "SEM_PARITY FAIL missing $M"; exit 2; }
grep -q '^# generated once from the C at main commit 3f2c70dc5' "$M" \
  || { echo "SEM_PARITY FAIL $M header line does not name the C reference commit"; exit 2; }
grep -v '^#' "$M" > "$W/MANIFEST.body"
[ "$(sed -n 2p "$M")" = "# goldens sha256 (of the corpus and golden lines below) $(sha "$W/MANIFEST.body")" ] \
  || { echo "SEM_PARITY FAIL $M body does not match its recorded sha256"; exit 2; }
bad=0
nc=$(ls "$C"/*.txt | wc -l | tr -d ' ')
[ "$nc" -eq "$(grep -c '^corpus ' "$M")" ] || { echo "SEM_PARITY FAIL $nc corpora built, $(grep -c '^corpus ' "$M") in the MANIFEST"; bad=1; }
for c in "$C"/*.txt; do
  b=$(basename "$c" .txt)
  want=$(awk -v b="$b" '$1 == "corpus" && $2 == b { print $3 }' "$M")
  [ "$want" = "$(sha "$c")" ] || { echo "SEM_PARITY FAIL corpus $b is not the one the goldens were generated from (regenerate: --generate)"; bad=1; }
  want=$(awk -v b="$b" '$1 == "golden" && $2 == b { print $3 }' "$M")
  [ -f "$GOLD/$b.out" ] && [ "$want" = "$(sha "$GOLD/$b.out")" ] || { echo "SEM_PARITY FAIL golden $b.out missing or not the recorded sha256"; bad=1; }
done
[ "$bad" -eq 0 ] || exit 2

# ---- the OM-2 dumper, from the shipped modules (as mk/visor-semantic.mk joins them) ----
OMS="src/visor/visor.om src/visor/visor_semantic.om tests/visor/sem_dump.om"
(printf 'om2\n'; sed -e '/^om2$/d' -e 's/^export fn /fn /' $OMS) | "$OMC" > "$W/sem_dump_om"
chmod +x "$W/sem_dump_om"

# ---- compare ----
files=0; lines=0; diff=0
for c in "$C"/*.txt; do
  b=$(basename "$c" .txt)
  rc=0
  "$W/sem_dump_om" < "$c" > "$W/out/$b.om" || rc=$?
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
echo "SEM_PARITY files=$files lines=$lines diff=$diff reference=C@3f2c70dc5 (goldens) work=$W"
[ "$diff" -eq 0 ]
