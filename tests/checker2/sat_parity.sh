#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# sat_parity.sh -- differential qualification of the pure OM-2 SAT solver
# (src/checker2/untrusted/c2sat.om, built as $(C2_DIR)/c2sat by mk/checker2.mk) against the C
# solver it replaced (src/checker2/untrusted/c2sat.c, retired; held by main commit 3f2c70dc5).
#
# Every corpus case runs the solver binary as `c2sat in.cnf out.lrat [limit]` (or with the
# argument list of an I/O case) and records the exit status, stdout (its byte count and sha256
# when over 64 KiB), stderr, whether the proof file exists, and its byte count and sha256. The
# record of every corpus is compared byte for byte with tests/checker2/sat_golden/<corpus>.out.
# The goldens were generated ONCE from the C solver at main commit 3f2c70dc5 (the retired c2sat.c
# itself is the generator, built with gcc; no dumper is needed); tests/checker2/sat_golden/MANIFEST
# records the commit, the generator command, the C file's git blob and sha256, and the sha256 of
# every corpus and golden. Needs no C compiler.
#
# Corpora:
#   hand      tests/checker2/sat_corpus.txt (header, comment, count and clause edge cases), at
#             the decision limits default, 0, 1, 2, 7 and 100
#   io        usage and I/O errors: no arguments, one, a missing input, an unwritable or
#             directory output, and limit strings parsed by atol (" 5", "-3", "abc", "+4", "",
#             saturation)
#   gen-rand  300 random CNFs (Park-Miller generator, seed 34): 1..45 variables, 0..6 clause
#             width, a few empty clauses, comments, two-space clause separators; limits as hand
#   gen-big   more than 1024 clauses (the clause table grows), 4+ occurrences per literal (the
#             occurrence lists grow) and over 64 KiB of input, SAT and UNSAT
#   gen-deep  long decision chains (20000 free variables, a 3000-long implication chain: the
#             recursion depth of solve; the C overflows its 8 MiB stack near 60000 levels, so no
#             deeper), a 200000-step level-0 refutation and a 200000-unit model (proof and stdout
#             over the 1 MiB output buffer of the OM)
#
# usage: tests/checker2/sat_parity.sh <c2sat binary>
#          prints PARITY lines and SAT_PARITY ...; exit 0 iff every corpus equals its golden
#        tests/checker2/sat_parity.sh --generate <C c2sat binary>
#          rewrites the goldens and the MANIFEST body from that binary (keeps the header line)
#   env: SAT_PARITY_WORK (default: a new temporary dir)
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GOLD=$ROOT/tests/checker2/sat_golden
GEN=""
if [ "${1:-}" = "--generate" ]; then
  BIN=${2:?usage: sat_parity.sh --generate <C c2sat binary>}; GEN=1
else
  BIN=${1:?usage: sat_parity.sh <c2sat binary>}
fi
case $BIN in /*) ;; *) BIN=$(pwd)/$BIN ;; esac
[ -x "$BIN" ] || { echo "SAT_PARITY FAIL $BIN is not an executable"; exit 2; }
W=${SAT_PARITY_WORK:-$(mktemp -d)}
case $W in /*) ;; *) W=$(pwd)/$W ;; esac
mkdir -p "$W"
sha() { sha256sum "$1" | cut -d' ' -f1; }
C=$W/corpus
rm -rf "$C"; mkdir -p "$C/hand" "$C/gen-rand" "$C/gen-big" "$C/gen-deep"

# ---- corpora: one file per input under $C/<corpus>/, plus $C/<corpus>.txt listing the runs ----
cd "$ROOT"
grep -v '^#' tests/checker2/sat_corpus.txt | while IFS="$(printf '\t')" read -r name body; do
  [ -n "$name" ] || continue
  printf '%b' "$body" > "$C/hand/$name.cnf"
done
awk 'function rnd() { s = (s * 16807) % 2147483647; return s }
     function ri(a, b) { return a + rnd() % (b - a + 1) }
     { } END { s = 34
       for (k = 0; k < 300; k++) {
         f = sprintf("%s/r%03d.cnf", dir, k); nv = ri(1, 45); m = ri(0, nv * ri(1, 6) + 1); kmax = ri(1, 6)
         if (rnd() % 10 < 3) printf "c random %d\nc\n", k > f
         printf "p cnf %d %d\n", nv, m > f
         for (c = 0; c < m; c++) {
           w = (rnd() % 20 == 0) ? ri(0, kmax) : ri(1, kmax)
           for (j = 0; j < w; j++) printf "%d ", (rnd() % 2 ? -1 : 1) * ri(1, nv) > f
           printf "0%s", (rnd() % 10 == 0 ? "  " : "\n") > f
         }
         close(f) } }' dir="$C/gen-rand" /dev/null
awk 'function rnd() { s = (s * 16807) % 2147483647; return s }
     function ri(a, b) { return a + rnd() % (b - a + 1) }
     function rand3(f, nv, m,   c, j) { printf "p cnf %d %d\n", nv, m > f
       for (c = 0; c < m; c++) { for (j = 0; j < 3; j++) printf "%d ", (rnd() % 2 ? -1 : 1) * ri(1, nv) > f; printf "0\n" > f }
       close(f) }
     { } END { s = 1024
       rand3(dir "/b3_40_1100.cnf", 40, 1100); rand3(dir "/b3_60_2100.cnf", 60, 2100); rand3(dir "/b3_12_40.cnf", 12, 40)
       rand3(dir "/b3_200_8000.cnf", 200, 8000)
       f = dir "/bsat_units_1500.cnf"; printf "p cnf 30 1500\n" > f
       for (c = 0; c < 1500; c++) printf "%d %d 0\n", c % 30 + 1, (c + 7) % 30 + 1 > f; close(f)
       f = dir "/bocc_pairs.cnf"; printf "p cnf 8 64\n" > f
       for (a = 1; a <= 8; a++) for (b = 1; b <= 8; b++) printf "%d %d 0\n", (a % 2 ? a : -a), (b % 3 ? -b : b) > f; close(f) }' dir="$C/gen-big" /dev/null
awk 'END { f = dir "/d20000.cnf"; printf "p cnf 20000 1\n1 -1 0\n" > f; close(f)
       f = dir "/chain3000.cnf"; printf "p cnf 3000 3000\n" > f
       for (i = 1; i < 3000; i++) printf "-%d %d 0\n", i, i + 1 > f; printf "-3000 -1 0\n" > f; close(f)
       f = dir "/chain_unsat.cnf"; printf "p cnf 400 401\n1 0\n" > f
       for (i = 1; i < 400; i++) printf "-%d %d 0\n", i, i + 1 > f; printf "-400 0\n" > f; close(f)
       f = dir "/chain_unsat_200k.cnf"; printf "p cnf 200000 200001\n1 0\n" > f
       for (i = 1; i < 200000; i++) printf "-%d %d 0\n", i, i + 1 > f; printf "-200000 0\n" > f; close(f)
       f = dir "/units_200k.cnf"; printf "p cnf 200000 200000\n" > f
       for (i = 1; i <= 200000; i++) printf "%d 0\n", (i % 3 ? i : -i) > f; close(f) }' dir="$C/gen-deep" /dev/null
for c in hand gen-rand; do
  for f in $(cd "$C/$c" && ls); do for lim in - 0 1 2 7 100; do printf '%s %s\n' "$f" "$lim"; done; done > "$C/$c.txt"
done
for f in $(cd "$C/gen-big" && ls); do for lim in - 3 100000; do printf '%s %s\n' "$f" "$lim"; done; done > "$C/gen-big.txt"
for f in $(cd "$C/gen-deep" && ls); do for lim in - 5000; do printf '%s %s\n' "$f" "$lim"; done; done > "$C/gen-deep.txt"
# io: argument lists (words; "_" is an empty word, "%" a space)
cp "$C/hand/php32.cnf" "$C/io-php32.cnf"
cat > "$C/io.txt" <<'EOF'
-
in.cnf
missing.cnf out.lrat
in.cnf ro/x.lrat
in.cnf dir
in.cnf out.lrat %5
in.cnf out.lrat -3
in.cnf out.lrat abc
in.cnf out.lrat +4
in.cnf out.lrat 0x10
in.cnf out.lrat 7abc
in.cnf out.lrat _
in.cnf out.lrat 99999999999999999999999
in.cnf out.lrat -99999999999999999999999
in.cnf out.lrat 9223372036854775807
in.cnf out.lrat 3 extra
EOF

# ---- run one corpus through a binary: the record of every run ----
run() { # bin corpus -> stdout record
  bin=$1 c=$2 R=$W/run
  while read -r a b; do
    rm -rf "$R"; mkdir -p "$R/dir" "$R/ro"; chmod 555 "$R/ro"
    if [ "$c" = io ]; then
      cp "$C/io-php32.cnf" "$R/in.cnf"
      set --
      if [ "$a" != - ]; then
        for wd in $a $b; do wd=$(printf '%s' "$wd" | tr '%' ' '); [ "$wd" = _ ] && wd=""; set -- "$@" "$wd"; done
      fi
      label="args [$a${b:+ $b}]"
    else
      cp "$C/$c/$a" "$R/in.cnf"
      if [ "$b" = - ]; then set -- in.cnf out.lrat; else set -- in.cnf out.lrat "$b"; fi
      label="$a lim=$b"
    fi
    rc=0; (cd "$R" && "$bin" "$@" > "$R/stdout" 2> "$R/stderr") || rc=$?
    echo "run $label exit=$rc"
    if [ "$(wc -c < "$R/stdout")" -gt 65536 ]; then echo "o bytes=$(wc -c < "$R/stdout" | tr -d ' ') sha256=$(sha "$R/stdout")"
    else sed 's/^/o /' "$R/stdout"; fi; sed 's/^/e /' "$R/stderr"
    if [ -f "$R/out.lrat" ]; then echo "lrat bytes=$(wc -c < "$R/out.lrat" | tr -d ' ') sha256=$(sha "$R/out.lrat")"
    else echo "lrat none"; fi
    chmod 755 "$R/ro"
  done < "$C/$c.txt"
}
CORPORA="hand io gen-rand gen-big gen-deep"

# ---- generate mode ----
if [ -n "$GEN" ]; then
  mkdir -p "$GOLD"
  hdr=$(head -n 1 "$GOLD/MANIFEST" 2>/dev/null | grep '^# generated once ' || true)
  [ -n "$hdr" ] || { echo "SAT_PARITY FAIL write the MANIFEST header line (commit, generator command) first"; exit 2; }
  rm -f "$GOLD"/*.out
  for c in $CORPORA; do
    run "$BIN" "$c" > "$GOLD/$c.out"
    [ -s "$GOLD/$c.out" ] || { echo "SAT_PARITY FAIL empty C output for $c"; exit 2; }
    cat "$C/$c.txt" $( [ "$c" = io ] && echo "$C/io-php32.cnf" || (cd "$C/$c" && ls | sed "s|^|$C/$c/|") ) > "$W/$c.inputs"
    printf 'corpus %s %s\n' "$c" "$(sha "$W/$c.inputs")"
    printf 'golden %s %s\n' "$c" "$(sha "$GOLD/$c.out")"
  done > "$W/MANIFEST.body"
  { printf '%s\n' "$hdr"
    printf '# goldens sha256 (of the corpus and golden lines below) %s\n' "$(sha "$W/MANIFEST.body")"
    cat "$W/MANIFEST.body"; } > "$GOLD/MANIFEST"
  echo "SAT_PARITY generated $(grep -c '^golden ' "$GOLD/MANIFEST") goldens in $GOLD"
  exit 0
fi

# ---- the corpora and goldens must be the ones the MANIFEST records ----
M=$GOLD/MANIFEST
[ -f "$M" ] || { echo "SAT_PARITY FAIL missing $M"; exit 2; }
grep -q '^# generated once from the C at main commit 3f2c70dc5' "$M" \
  || { echo "SAT_PARITY FAIL $M header line does not name the C reference commit"; exit 2; }
grep -v '^#' "$M" > "$W/MANIFEST.body"
[ "$(sed -n 2p "$M")" = "# goldens sha256 (of the corpus and golden lines below) $(sha "$W/MANIFEST.body")" ] \
  || { echo "SAT_PARITY FAIL $M body does not match its recorded sha256"; exit 2; }
bad=0
[ "$(echo $CORPORA | wc -w)" -eq "$(grep -c '^corpus ' "$M")" ] || { echo "SAT_PARITY FAIL corpus count differs from the MANIFEST"; bad=1; }
for c in $CORPORA; do
  cat "$C/$c.txt" $( [ "$c" = io ] && echo "$C/io-php32.cnf" || (cd "$C/$c" && ls | sed "s|^|$C/$c/|") ) > "$W/$c.inputs"
  want=$(awk -v b="$c" '$1 == "corpus" && $2 == b { print $3 }' "$M")
  [ "$want" = "$(sha "$W/$c.inputs")" ] || { echo "SAT_PARITY FAIL corpus $c is not the one the goldens were generated from"; bad=1; }
  want=$(awk -v b="$c" '$1 == "golden" && $2 == b { print $3 }' "$M")
  [ -f "$GOLD/$c.out" ] && [ "$want" = "$(sha "$GOLD/$c.out")" ] || { echo "SAT_PARITY FAIL golden $c.out missing or not the recorded sha256"; bad=1; }
done
[ "$bad" -eq 0 ] || exit 2

# ---- compare ----
mkdir -p "$W/out"
files=0; runs=0; diff=0
for c in $CORPORA; do
  run "$BIN" "$c" > "$W/out/$c.out"
  n=$(grep -c '^run ' "$W/out/$c.out")
  files=$((files + 1)); runs=$((runs + n))
  if cmp -s "$GOLD/$c.out" "$W/out/$c.out"; then echo "PARITY $c runs=$n same"
  else diff=$((diff + 1)); echo "PARITY $c runs=$n DIFF"; diff "$GOLD/$c.out" "$W/out/$c.out" | cut -c1-200 | head -20 || true; fi
done
echo "SAT_PARITY corpora=$files runs=$runs diff=$diff reference=C@3f2c70dc5 (goldens) work=$W"
[ "$diff" -eq 0 ]
