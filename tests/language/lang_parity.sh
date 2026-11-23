#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# lang_parity.sh -- C-vs-OM parity of the Omega language V0 lane (lexer, parser, lowering, eval).
#
# Runs every corpus through tests/language/lang_dump.c (the C lane: src/language/*.c) and
# tests/language/lang_dump.om (the pure OM-2 lane: src/language/*.om) and compares the two
# outputs byte for byte: return codes, error texts with columns, result ids, every graph object
# added, table counts and every stored program (id, contract text and ids, body, code,
# realization id). Each corpus runs on a fresh session.
#
# Corpora: tests/language/parity_corpus.txt; the sources of tests/language/golden/v0.txt; every
# tests/visor/qualification/*.omega-session and tests/visor/sessions/*.omega-session (each line
# as a source line); and generated capacity and boundary cases (binding, graph and program
# tables, nesting depth, node limit, token limit, line length, control bytes, program steps).
#
# The C lane is the reference only: it is built from LANG_C_REF_DIR (a tree that still has
# src/language/*.c, src/visor/*.c and the core C sources) or, by default, from the git revision
# LANG_C_REF (the last revision with the C lane) of this repository.
#
# usage: tests/language/lang_parity.sh [OMC]     prints PARITY lines and LANG_PARITY ...; 0 iff equal
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OMC=${1:-$ROOT/seed/out/omc}
REF=${LANG_C_REF:-b2601a1b4}
W=${LANG_PARITY_WORK:-$(mktemp -d)}
mkdir -p "$W/corpus" "$W/out"
CC=${CC:-cc}

# ---- the C reference dumper ----
if [ -n "${LANG_C_REF_DIR:-}" ]; then
  R=$LANG_C_REF_DIR
else
  R=$W/ref
  rm -rf "$R"; mkdir -p "$R"
  git -C "$ROOT" archive "$REF" | tar -x -C "$R"
fi
O=$R/build/langref
if [ ! -f "$O/language/omega_lower.o" ]; then
  # every object is a goal, so make keeps the pattern-rule intermediates
  GOALS=$(cd "$R" && ls src/visor/*.c src/language/*.c | sed -e 's|^src/|build/langref/|' -e 's|\.c$|.o|')
  make -C "$R" PHYSICS_DIR=/nonexistent PHYSICS_LOCK_CHECK=0 OUT_DIR=build/langref \
    build/langref/tests-visor/test_visor_console $GOALS >"$W/ref-build.log" 2>&1 || {
      echo "LANG_PARITY FAIL cannot build the C reference (see $W/ref-build.log)"; exit 2; }
fi
OBJS=$(ls "$O"/*.o "$O"/visor/*.o "$O"/language/*.o | grep -v '/omega_main\.o$')
"$CC" -std=gnu11 -O1 -D_GNU_SOURCE -I"$R/src" -I"$R/src/visor" -I"$R/src/language" \
  -o "$W/lang_dump_c" "$ROOT/tests/language/lang_dump.c" $OBJS

# ---- the OM-2 dumper ----
cd "$ROOT"
OMS="src/visor/visor.om om/aarch64/aarch64_om2.om om/visor/verify_om2.om om/visor/validate_om2.om
src/visor/visor_program.om src/language/omega_lex.om src/language/omega_parse.om
src/language/omega_lower.om tests/language/lang_dump.om"
(printf 'om2\n'; sed -e '/^om2$/d' -e 's/^export fn /fn /' $OMS) | "$OMC" > "$W/lang_dump_om"
chmod +x "$W/lang_dump_om"

# ---- corpora ----
C=$W/corpus
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

# ---- compare ----
files=0; lines=0; diff=0
for c in "$C"/*.txt; do
  b=$(basename "$c" .txt)
  "$W/lang_dump_c" < "$c" > "$W/out/$b.c" || true
  "$W/lang_dump_om" < "$c" > "$W/out/$b.om" || true
  n=$(wc -l < "$c" | tr -d ' ')
  files=$((files + 1)); lines=$((lines + n))
  if cmp -s "$W/out/$b.c" "$W/out/$b.om" && [ -s "$W/out/$b.c" ]; then
    echo "PARITY $b lines=$n same"
  else
    diff=$((diff + 1))
    echo "PARITY $b lines=$n DIFF"
    diff "$W/out/$b.c" "$W/out/$b.om" | head -20 || true
  fi
done
echo "LANG_PARITY files=$files lines=$lines diff=$diff work=$W"
[ "$diff" -eq 0 ]
