#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# console_parity.sh -- differential qualification of the pure OM-2 omega console (the omega
# binary: src/visor/visor_console.om, visor_parse_command.om, visor.om, tools/omega.om,
# omega_ops.om, omega_wire.om and the lanes they call, built from $(OMEGA_OM_SRCS) exactly as
# mk/00-visor-core.mk builds omega) against the C console it replaced (tools/omega.c with
# src/visor/visor_console.c, visor_parse_command.c, visor.c and the C lanes, at main 3f2c70dc5).
#
# Every case runs the whole CLI from the repository root: its stdout, its stderr and its exit
# code are compared byte for byte with tests/visor/console_golden/<corpus>.out. Corpora:
#   sessions  every *.omega-session corpus (the committed console and qualification sessions,
#             tests/visor/console_parity/hand.omega-session and the generated ones below), each
#             run twice through `--script -` (stdin): text, then --json;
#   args      tests/visor/console_parity/args.cases: argv cases (--help, usage errors, --command
#             lists, --script paths, the stdin REPL, --evidence-root, byte-level lines).
# The goldens were generated ONCE from the C omega at main commit 3f2c70dc5 (built from the
# archive of that commit; tests/visor/console_golden/MANIFEST records the commit, the generator
# command, tools/omega.c's blob and sha256, and the sha256 of every corpus and golden). This
# script needs no C compiler.
#
# Known capacity bound (not compared): the OM console keeps the first 65536 bytes of a line; in text
# mode it echoes only those, where the C echoed the whole line. Lines longer than that run in JSON
# mode only (long.bin), where nothing is echoed and the length in the error is compared.
#
# usage: tests/visor/console_parity.sh [OMC]
#          prints PARITY lines and CONSOLE_PARITY ...; exit 0 iff every corpus equals its golden
#        tests/visor/console_parity.sh --generate <C omega binary>
#          rewrites the goldens and the MANIFEST body from that binary (keeps the header line)
#        CONSOLE_PARITY_BIN=<omega binary> tests/visor/console_parity.sh --run-only
#          runs the corpora through that binary into $CONSOLE_PARITY_WORK/out (for the mutants)
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GOLD=$ROOT/tests/visor/console_golden
HAND=$ROOT/tests/visor/console_parity
MODE=check
GEN=""
OMC=""
case "${1:-}" in
  --generate) MODE=generate; GEN=${2:?usage: console_parity.sh --generate <C omega binary>}
              case $GEN in /*) ;; *) GEN=$(pwd)/$GEN ;; esac ;;
  --run-only) MODE=runonly ;;
  *) OMC=${1:-$ROOT/seed/out/omc}; case $OMC in /*) ;; *) OMC=$(pwd)/$OMC ;; esac ;;
esac
W=${CONSOLE_PARITY_WORK:-$(mktemp -d)}
mkdir -p "$W/corpus"
sha() { sha256sum "$1" | cut -d' ' -f1; }
ER="--evidence-root tests/visor/sessions/evidence-root"

# ---- corpora ----
cd "$ROOT"
C=$W/corpus
rm -f "$C"/*
cp tests/visor/sessions/basic.omega-session "$C/basic.omega-session"
cp tests/visor/sessions/e2e.omega-session "$C/e2e.omega-session"
for q in semantic hostile usability; do cp tests/visor/qualification/$q.omega-session "$C/qual-$q.omega-session"; done
cp "$HAND/hand.omega-session" "$C/hand.omega-session"
cp "$HAND/args.cases" "$C/args.cases"
# Every command against every kind of subject: none, a value, a bool, an apply, a let-bound
# apply, a program (u64 and u32), the last result, the zero id, an unknown name; then again
# after realizing the applies and programs, then after `clear`.
awk 'BEGIN {
  print "let x: u64 = 7"; print "let y: u64 = 11"; print "let bt: bool = true"; print "let t: u32 = 5"
  print "x + y"; print "let s: u64 = x * y"; print "let tt: u32 = t + t"
  print "fn f(x: u64) -> u64 requires true ensures result >= 1 { x * 2 + 1 }"
  print "fn g(v: u32) -> u32 { v + 1 }"
  n = split("inspect type id graph verify realize cost run evidence effects alternatives why help", cmds, " ")
  m = split("x bt s tt f g _ sha256:0000000000000000000000000000000000000000000000000000000000000000 nosuch", subs, " ")
  for (pass = 1; pass <= 3; pass++) {
    for (i = 1; i <= n; i++) { print cmds[i]; for (j = 1; j <= m; j++) print cmds[i] " " subs[j] }
    for (j = 1; j <= m; j++) for (k = 1; k <= m; k++) print "compare " subs[j] " " subs[k]
    for (j = 1; j <= m; j++) { print "run " subs[j] " 3"; print "run " subs[j] " 3 4"; print "realize " subs[j] " for current.machine" }
    print "bindings"; print "machine"; print "world"
    if (pass == 1) { print "realize s"; print "realize tt"; print "realize f"; print "realize g"; print "x + y" }
    if (pass == 2) print "clear"
  } }' > "$C/gen-matrix.omega-session"
# The session tables: more programs and realizations than the session holds (16 each), and
# more bindings (64).
awk 'BEGIN {
  for (i = 0; i < 20; i++) { print "fn p" i "(x: u64) -> u64 { x + " i " }"; print "realize p" i; print "run p" i " " i }
  for (i = 0; i < 70; i++) print "let v" i ": u64 = " i
  for (i = 0; i < 20; i++) { print "v" i " + v" (i + 1); print "realize _"; print "run _"; print "alternatives _" }
  print "bindings"; print "id v0"; print "id v69"; print "run p19 1"; print "alternatives p0" }' > "$C/gen-tables.omega-session"
# Byte-level lines (fed through --script -): control bytes, DEL, CR and CRLF, a NUL byte, invalid
# and valid UTF-8, a 4095- and a 4096-byte line, a token of 255 and of 256 bytes, too many
# arguments, blanks.
{
  printf 'help\001\n'; printf 'help\177\n'; printf 'help\033[0m\n'; printf 'help\tquit\n'
  printf 'help\r\n'; printf 'bindings\r\n'; printf 'help\rquit\n'; printf 'he\000lp\n'; printf 'bindings\n'
  printf 'let \303\251: u64 = 1\n'; printf 'inspect \303\251\n'; printf 'inspect \377\n'; printf 'inspect \300\257\n'
  printf 'inspect \342\202\n'; printf 'inspect \342\202\254\n'; printf 'inspect \360\237\230\200\n'
  printf 'inspect \355\240\200\n'; printf 'inspect \364\220\200\200\n'; printf 'inspect \340\200\200\n'
  printf 'inspect \303A\n'; printf 'inspect \200\n'; printf 'inspect \360\200\200\200\n'; printf 'inspect \301\277\n'
  printf '   \t  \n'; printf '  # indented comment\n'; printf '\t help  \t \n'
  awk 'BEGIN { s = "help "; while (length(s) < 4095) s = s "a"; print s; print s "b";
       t = "inspect "; u = ""; while (length(u) < 255) u = u "n"; print t u; print t u "n";
       print "help a b c d e f g"; print "realize a b c d for current.machine"; print "compare a b c d e";
       print "realize a for"; print "realize for current.machine"; print "realize a for current.machine b" }'
  printf 'quit'
} > "$C/ctl.bin"
# A last line (no LF) that ends inside a UTF-8 sequence, after a longer line whose bytes past it
# would complete the sequence.
{ printf 'inspect \342\202\254\n'; printf 'inspect \342\202'; } > "$C/tail.bin"
# Lines longer than the OM console's 65536-byte line buffer (LF, CRLF, CR, a comment, and a last
# line ending in CR without LF): their length in the error. Run in JSON mode only: the text-mode echo of
# such a line is cut at 65536 bytes by the OM (a capacity bound; see the header).
awk 'BEGIN { v = "help "; while (length(v) < 70000) v = v "abcdefghij"; print v; printf "%s\r\n", v; printf "%s\r\r\n", v;
       print "#" v; print "bindings"; printf "%s\r", v }' > "$C/long.bin"

# ---- run every corpus through one omega binary into $2 ----
run_case() { # bin name stdin args... -> one record
  bin=$1; name=$2; in=$3; shift 3
  rc=0
  (cd "$ROOT" && "$bin" "$@" < "$in" > "$W/o.stdout" 2> "$W/o.stderr") || rc=$?
  printf '== %s\n' "$name"; cat "$W/o.stdout"; printf '\n-- stderr\n'; cat "$W/o.stderr"; printf -- '-- exit %s\n' "$rc"
}
run_all() { # bin outdir
  bin=$1; out=$2
  mkdir -p "$out"; rm -f "$out"/*.out
  for s in "$C"/*.omega-session; do
    b=$(basename "$s" .omega-session)
    { run_case "$bin" "$b text" "$s" $ER --script -
      run_case "$bin" "$b json" "$s" --json $ER --script -; } > "$out/$b.out"
  done
  tab=$(printf '\t')
  grep -v '^#' "$C/args.cases" | while IFS="$tab" read -r name in args; do
    [ -n "$name" ] || continue
    if [ "$in" = - ]; then in=/dev/null; else in=$C/$in; fi
    eval "set -- $args"
    run_case "$bin" "$name" "$in" "$@"
  done > "$out/args.out"
}

# ---- generate mode: write the goldens from the C omega, keep the MANIFEST header line ----
if [ "$MODE" = generate ]; then
  [ -x "$GEN" ] || { echo "CONSOLE_PARITY FAIL $GEN is not an executable C omega"; exit 2; }
  mkdir -p "$GOLD"
  hdr=$(head -n 1 "$GOLD/MANIFEST" 2>/dev/null | grep '^# generated once ' || true)
  [ -n "$hdr" ] || { echo "CONSOLE_PARITY FAIL write the MANIFEST header line (commit, generator command) first"; exit 2; }
  rm -f "$GOLD"/*.out
  run_all "$GEN" "$GOLD"
  for c in "$C"/*; do printf 'corpus %s %s\n' "$(basename "$c")" "$(sha "$c")"; done > "$W/MANIFEST.body"
  for g in "$GOLD"/*.out; do
    [ -s "$g" ] || { echo "CONSOLE_PARITY FAIL empty C output $g"; exit 2; }
    printf 'golden %s %s\n' "$(basename "$g" .out)" "$(sha "$g")"
  done >> "$W/MANIFEST.body"
  { printf '%s\n' "$hdr"
    printf '# goldens sha256 (of the corpus and golden lines below) %s\n' "$(sha "$W/MANIFEST.body")"
    cat "$W/MANIFEST.body"; } > "$GOLD/MANIFEST"
  echo "CONSOLE_PARITY generated $(grep -c '^golden ' "$GOLD/MANIFEST") goldens in $GOLD"
  exit 0
fi

if [ "$MODE" = runonly ]; then
  run_all "${CONSOLE_PARITY_BIN:?set CONSOLE_PARITY_BIN}" "$W/out"
  exit 0
fi

# ---- the corpora and goldens must be the ones the MANIFEST records ----
M=$GOLD/MANIFEST
[ -f "$M" ] || { echo "CONSOLE_PARITY FAIL missing $M"; exit 2; }
grep -q '^# generated once from the C at main commit 3f2c70dc5' "$M" \
  || { echo "CONSOLE_PARITY FAIL $M header line does not name the C reference commit"; exit 2; }
grep -v '^#' "$M" > "$W/MANIFEST.body"
[ "$(sed -n 2p "$M")" = "# goldens sha256 (of the corpus and golden lines below) $(sha "$W/MANIFEST.body")" ] \
  || { echo "CONSOLE_PARITY FAIL $M body does not match its recorded sha256"; exit 2; }
bad=0
nc=$(ls "$C" | wc -l | tr -d ' ')
[ "$nc" -eq "$(grep -c '^corpus ' "$M")" ] || { echo "CONSOLE_PARITY FAIL $nc corpora built, $(grep -c '^corpus ' "$M") in the MANIFEST"; bad=1; }
for c in "$C"/*; do
  b=$(basename "$c")
  want=$(awk -v b="$b" '$1 == "corpus" && $2 == b { print $3 }' "$M")
  [ "$want" = "$(sha "$c")" ] || { echo "CONSOLE_PARITY FAIL corpus $b is not the one the goldens were generated from (regenerate: --generate)"; bad=1; }
done
ng=0
for g in $(awk '$1 == "golden" { print $2 }' "$M"); do
  ng=$((ng + 1))
  want=$(awk -v b="$g" '$1 == "golden" && $2 == b { print $3 }' "$M")
  [ -f "$GOLD/$g.out" ] && [ "$want" = "$(sha "$GOLD/$g.out")" ] || { echo "CONSOLE_PARITY FAIL golden $g.out missing or not the recorded sha256"; bad=1; }
done
[ "$ng" -eq "$(ls "$GOLD"/*.out | wc -l | tr -d ' ')" ] || { echo "CONSOLE_PARITY FAIL golden files are not the MANIFEST's"; bad=1; }
[ "$bad" -eq 0 ] || exit 2

# ---- the OM-2 omega, from the shipped sources, as mk/00-visor-core.mk builds it ----
OMS=${CONSOLE_PARITY_OMS:?set CONSOLE_PARITY_OMS to $(OMEGA_OM_SRCS) (make test-visor-console-parity does)}
(printf 'om2\n'; sed -e '/^om2$/d' -e 's/^export fn /fn /' $OMS) | "$OMC" > "$W/omega_om"
chmod +x "$W/omega_om"
printf '%s\n' "$OMS" > "$W/oms"
run_all "$W/omega_om" "$W/out"

# ---- compare ----
files=0; cases=0; diff=0
for g in "$GOLD"/*.out; do
  b=$(basename "$g" .out)
  n=$(grep -c '^== ' "$g" || true)
  files=$((files + 1)); cases=$((cases + n))
  if cmp -s "$g" "$W/out/$b.out"; then
    echo "PARITY $b cases=$n same"
  else
    diff=$((diff + 1))
    echo "PARITY $b cases=$n DIFF"
    diff "$g" "$W/out/$b.out" | head -20 || true
  fi
done
echo "CONSOLE_PARITY files=$files cases=$cases diff=$diff reference=C@3f2c70dc5 (goldens) work=$W"
[ "$diff" -eq 0 ]
