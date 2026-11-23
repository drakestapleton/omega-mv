#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# lang_parity.sh -- parity of the pure OM-2 Omega language V0 lane (lexer, parser, lowering,
# eval) with the retired C lane, against committed golden outputs.
#
# Runs every corpus through tests/language/lang_dump.om (the OM-2 lane: src/language/*.om) and
# compares its output byte for byte with tests/language/parity_golden/<corpus>.out: return
# codes, error texts with columns, result ids, every graph object added, table counts and every
# stored program (id, contract text and ids, body, code, realization id). Each corpus runs on a
# fresh session.
#
# The goldens were generated ONCE from the C lane (src/language/*.c, src/visor/*.c and the core
# C sources) at main commit 3f2c70dc5, the last main revision that has it; the header line of
# tests/language/parity_golden/MANIFEST records that commit, the generator command, and the
# sha256 of every corpus and every golden. This script needs no C compiler and no git history:
# it checks the corpora it builds and the goldens against the MANIFEST first, so a changed corpus
# or golden fails as such (regenerate with --generate) instead of as a parity difference.
#
# Corpora: tests/language/parity_corpus.txt; the sources of tests/language/golden/v0.txt; every
# tests/visor/qualification/*.omega-session and tests/visor/sessions/*.omega-session (each line
# as a source line); and generated capacity and boundary cases (binding, graph and program
# tables, nesting depth, node limit, token limit, line length, control bytes, program steps).
#
# usage: tests/language/lang_parity.sh [OMC]
#          prints PARITY lines and LANG_PARITY ...; exit 0 iff every corpus equals its golden
#        tests/language/lang_parity.sh --generate <C dumper binary>
#          rewrites the goldens and the MANIFEST body from that binary (keeps the header line)
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GOLD=$ROOT/tests/language/parity_golden
GEN=""
if [ "${1:-}" = "--generate" ]; then
  GEN=${2:?usage: lang_parity.sh --generate <C dumper binary>}
  case $GEN in /*) ;; *) GEN=$(pwd)/$GEN ;; esac
  OMC=""
else
  OMC=${1:-$ROOT/seed/out/omc}
  case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac
fi
W=${LANG_PARITY_WORK:-$(mktemp -d)}
mkdir -p "$W/corpus" "$W/out"
sha() { sha256sum "$1" | cut -d' ' -f1; }

# ---- corpora ----
cd "$ROOT"
C=$W/corpus
rm -f "$C"/*.txt
cp tests/language/parity_corpus.txt "$C/hand.txt"
awk -F'\t' '!/^#/ && NF >= 2 { print $2 }' tests/language/golden/v0.txt > "$C/golden.txt"
for f in tests/visor/qualification/*.omega-session tests/visor/sessions/*.omega-session; do
  b=$(basename "$f" .omega-session)
  cp "$f" "$C/session-$(basename "$(dirname "$f")")-$b.txt"
done
awk 'BEGIN { for (i = 0; i < 70; i++) printf "let v%d: u64 = %d\n", i, i;
             print "let v3: u64 = 99"; print "let w: u64 = 1"; print "v3"; print "fn q(x: u64) -> u64 { x + 1 }" }' > "$C/gen-bindings.txt"
awk 'BEGIN { for (i = 0; i < 140; i++) printf "(%d: u64) + %d\n", i, i + 1000;
             print "fn f(x: u64) -> u64 { x + 1 }"; print "7: u64"; print "let k: u64 = 7"; print "true";
             print "(5000: u64) * 2"; print "#!clear"; print "(1: u64) + 2" }' > "$C/gen-graph.txt"
awk 'BEGIN { for (i = 0; i < 20; i++) printf "fn p%d(x: u64) -> u64 { x + %d }\n", i, i + 1;
             print "fn p0(x: u64) -> u64 { x + 1 }"; print "fn again(x: u64) -> u64 { x + 3 }";
             print "fn zz(x: u64) -> u64 { x + 99 }" }' > "$C/gen-programs.txt"
awk 'function par(n, s,   i, o) { o = ""; for (i = 0; i < n; i++) o = o "("; o = o s; for (i = 0; i < n; i++) o = o ")"; return o }
     BEGIN { for (d = 29; d <= 35; d++) { print par(d, "7: u64"); print par(d, "1") ": u64"; print "fn d(x: u64) -> u64 { " par(d, "x + 1") " }" } }' > "$C/gen-depth.txt"
awk 'function chain(n, op,   i, o) { o = "(1: u64)"; for (i = 1; i < n; i++) o = o " " op " " i; return o }
     BEGIN { for (n = 60; n <= 68; n++) print chain(n, "+");
             for (n = 60; n <= 68; n++) print chain(n, "|");
             for (n = 125; n <= 130; n++) print chain(n, "+") }' > "$C/gen-nodes.txt"
awk 'function steps(n, op,   i, o) { o = "x"; for (i = 0; i < n; i++) o = o " " op " " (i + 1); return o }
     BEGIN { for (n = 30; n <= 34; n++) printf "fn s%d(x: u64) -> u64 { %s }\n", n, steps(n, "+");
             for (n = 30; n <= 34; n++) printf "fn m%d(x: u64) -> u64 { %s }\n", n, steps(n, "*");
             printf "fn mix(x: u64) -> u64 { %s }\n", "x * 3 + 7 & 4294967295 | 16 - 2 * 5 + 1" }' > "$C/gen-steps.txt"
awk 'function sp(n,   i, o) { o = ""; for (i = 0; i < n; i++) o = o " "; return o }
     BEGIN { print "7: u64" sp(1018); print "7: u64" sp(1017); print "7: u64" sp(1019); print "7: u64" sp(2000);
             print sp(1023) "7"; print sp(1024) "7"; print sp(1020) "/* x";
             o = "1"; for (i = 0; i < 126; i++) o = o " +"; print o;
             o = "1"; for (i = 0; i < 127; i++) o = o " +"; print o;
             o = "1"; for (i = 0; i < 128; i++) o = o " +"; print o;
             o = "x"; for (i = 0; i < 300; i++) o = o " x"; print o;
             for (n = 62; n <= 65; n++) { w = "n"; while (length(w) < n) w = w "a";
               printf "let %s: u64 = %d\n", w, n; print w; printf "fn %s(x: u64) -> u64 { x + 1 }\n", w } }' > "$C/gen-limits.txt"
printf '7: u64\r\n(7:\tu64) + 1\n\001\n\037\n\177\n\200\n\377\n7: u64 \001\n(7: u64) + \t\r 1\n\t\n\r\n' > "$C/gen-bytes.txt"

# ---- generate mode: write the goldens from the C dumper, keep the MANIFEST header line ----
if [ -n "$GEN" ]; then
  [ -x "$GEN" ] || { echo "LANG_PARITY FAIL $GEN is not an executable C dumper"; exit 2; }
  mkdir -p "$GOLD"
  hdr=$(head -n 1 "$GOLD/MANIFEST" 2>/dev/null | grep '^# generated once ' || true)
  [ -n "$hdr" ] || { echo "LANG_PARITY FAIL write the MANIFEST header line (commit, generator command) first"; exit 2; }
  rm -f "$GOLD"/*.out
  for c in "$C"/*.txt; do
    b=$(basename "$c" .txt)
    "$GEN" < "$c" > "$GOLD/$b.out" || { echo "LANG_PARITY FAIL the C dumper failed on $b"; exit 2; }
    [ -s "$GOLD/$b.out" ] || { echo "LANG_PARITY FAIL empty C output for $b"; exit 2; }
    printf 'corpus %s %s\n' "$b" "$(sha "$c")"
    printf 'golden %s %s\n' "$b" "$(sha "$GOLD/$b.out")"
  done > "$W/MANIFEST.body"
  { printf '%s\n' "$hdr"
    printf '# goldens sha256 (of the corpus and golden lines below) %s\n' "$(sha "$W/MANIFEST.body")"
    cat "$W/MANIFEST.body"; } > "$GOLD/MANIFEST"
  echo "LANG_PARITY generated $(grep -c '^golden ' "$GOLD/MANIFEST") goldens in $GOLD"
  exit 0
fi

# ---- the corpora and goldens must be the ones the MANIFEST records ----
M=$GOLD/MANIFEST
[ -f "$M" ] || { echo "LANG_PARITY FAIL missing $M"; exit 2; }
grep -q '^# generated once from the C language lane at main commit 3f2c70dc5' "$M" \
  || { echo "LANG_PARITY FAIL $M header line does not name the C reference commit"; exit 2; }
grep -v '^#' "$M" > "$W/MANIFEST.body"
[ "$(sed -n 2p "$M")" = "# goldens sha256 (of the corpus and golden lines below) $(sha "$W/MANIFEST.body")" ] \
  || { echo "LANG_PARITY FAIL $M body does not match its recorded sha256"; exit 2; }
bad=0
nc=$(ls "$C"/*.txt | wc -l | tr -d ' ')
[ "$nc" -eq "$(grep -c '^corpus ' "$M")" ] || { echo "LANG_PARITY FAIL $nc corpora built, $(grep -c '^corpus ' "$M") in the MANIFEST"; bad=1; }
for c in "$C"/*.txt; do
  b=$(basename "$c" .txt)
  want=$(awk -v b="$b" '$1 == "corpus" && $2 == b { print $3 }' "$M")
  [ "$want" = "$(sha "$c")" ] || { echo "LANG_PARITY FAIL corpus $b is not the one the goldens were generated from (regenerate: --generate)"; bad=1; }
  want=$(awk -v b="$b" '$1 == "golden" && $2 == b { print $3 }' "$M")
  [ -f "$GOLD/$b.out" ] && [ "$want" = "$(sha "$GOLD/$b.out")" ] || { echo "LANG_PARITY FAIL golden $b.out missing or not the recorded sha256"; bad=1; }
done
[ "$bad" -eq 0 ] || exit 2

# ---- the OM-2 dumper ----
OMS="src/visor/visor.om om/aarch64/aarch64_om2.om om/visor/verify_om2.om om/visor/validate_om2.om
src/visor/visor_program.om src/language/omega_lex.om src/language/omega_parse.om
src/language/omega_lower.om tests/language/lang_dump.om"
(printf 'om2\n'; sed -e '/^om2$/d' -e 's/^export fn /fn /' $OMS) | "$OMC" > "$W/lang_dump_om"
chmod +x "$W/lang_dump_om"

# ---- compare ----
files=0; lines=0; diff=0
for c in "$C"/*.txt; do
  b=$(basename "$c" .txt)
  "$W/lang_dump_om" < "$c" > "$W/out/$b.om" || true
  n=$(wc -l < "$c" | tr -d ' ')
  files=$((files + 1)); lines=$((lines + n))
  if cmp -s "$GOLD/$b.out" "$W/out/$b.om"; then
    echo "PARITY $b lines=$n same"
  else
    diff=$((diff + 1))
    echo "PARITY $b lines=$n DIFF"
    diff "$GOLD/$b.out" "$W/out/$b.om" | head -20 || true
  fi
done
echo "LANG_PARITY files=$files lines=$lines diff=$diff reference=C@3f2c70dc5 (goldens) work=$W"
[ "$diff" -eq 0 ]
