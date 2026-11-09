#!/usr/bin/env bash
# tools/c2om/c2om-gate.sh: the gate of the C-to-Omega translator seed/c2om/c2om.om (ledger L418 S2).
#
#   1. omc is born from the seed (tools/c2om/seed-omc.sh); its sha256 goes into the evidence.
#   2. omc compiles seed/c2om/c2om.om, twice, to the same bytes. Nothing else builds the translator.
#   3. Accept corpus tools/c2om/corpus/ok/*.c: c2om translates each (exit 0, nothing on stderr, the same
#      bytes twice), omc compiles the translation, gcc builds the same C (-include stdio.h, the only
#      line the subset cannot spell). Every program runs on every input in tools/c2om/equiv/inputs and
#      tools/c2om/corpus/inputs, each in its own empty directory: stdout, stderr and exit status of the
#      gcc build and of the omc build must be the same bytes, and the spec-only interpreter omega_ref
#      must give the omc build's stdout and status (second oracle).
#   4. Refusal corpus tools/c2om/corpus/refuse/*.c: exit 65, empty stdout, stderr exactly <name>.want.
#   5. Negative controls: each one-line mutant of c2om.om below must compile and make at least one
#      accept case differ from gcc; otherwise the gate is blind.
# Exit 0 only when cases run = cases written and every check above holds.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
SRC=seed/c2om/c2om.om
CORPUS=tools/c2om/corpus
EV=evidence/C2OM/c2om
B=$ROOT/build/c2om/gate
mkdir -p "$EV" "$B"
LOG=$EV/gate.log
: > "$LOG"
say() { echo "$*" | tee -a "$LOG"; }
fail() { say "FAIL $*"; say "RESULT FAIL"; exit 1; }
clean() { if [ -d "$1" ]; then find "$1" -depth -delete; fi; mkdir -p "$1"; }

MUTANTS=(
  's/^sb = add s 1$/sb = s/'
  's/@sub @mul @/@add @mul @/'
)

# 1. omc from the seed
tools/c2om/seed-omc.sh build/c2om/seed > "$B/seed-omc.out" 2>&1 || fail "seed omc: $(tail -1 "$B/seed-omc.out")"
OMC=$ROOT/build/c2om/seed/omc
say "omc sha256    $(cat build/c2om/seed/omc.sha256) (born by seed/omega-from-seed.sh; equal to seed/out/omc)"
REF=$(tools/c2om/omega-ref.sh "$ROOT/build/c2om/equiv" 2> "$B/ref.err") || fail "omega_ref: $(cat "$B/ref.err")"
say "interpreter   ${REF#"$ROOT"/}"
say "gcc           $(gcc --version | head -1)"

# 2. the translator, by omc only
"$OMC" < "$SRC" > "$B/c2om" 2> "$B/c2om.err" || fail "omc refused $SRC: $(cat "$B/c2om.err")"
"$OMC" < "$SRC" > "$B/c2om.again" 2>&1 || fail "omc refused $SRC on the second build"
cmp -s "$B/c2om" "$B/c2om.again" || fail "two omc builds of $SRC differ"
chmod +x "$B/c2om"
say "c2om          $SRC sha256 $(sha256sum "$SRC" | cut -d' ' -f1), $(wc -l < "$SRC") lines"
say "c2om binary   sha256 $(sha256sum "$B/c2om" | cut -d' ' -f1), $(wc -c < "$B/c2om") bytes, two builds identical"

run1() { # <bin> <dir> <stdin> ; bin 'ref:<file>' runs the interpreter on <file>
  local bin=$1 d=$2 in=$3
  clean "$d"
  set +e
  if [ "${bin#ref:}" != "$bin" ]; then (cd "$d" && timeout 120 "$REF" run "${bin#ref:}" < "$in" > out 2> err)
  else (cd "$d" && timeout 120 "$bin" < "$in" > out 2> err); fi
  echo $? > "$d/rc"
  set -e
}
same() { cmp -s "$1/out" "$2/out" && cmp -s "$1/rc" "$2/rc" && { [ "${3:-1}" = 0 ] || cmp -s "$1/err" "$2/err"; }; }

# 3. accept corpus
INPUTS=("$ROOT"/tools/c2om/equiv/inputs/* "$ROOT/$CORPUS"/inputs/*)
progs=("$CORPUS"/ok/*.c)
written=$(( ${#progs[@]} * ${#INPUTS[@]} ))
run=0; pass=0
TSV=$EV/cases.tsv
printf 'program\tinput\tgcc rc\tomc rc\tinterp rc\tstdout bytes\tgcc = omc\tomc = interp\n' > "$TSV"
for c in "${progs[@]}"; do
  n=$(basename "$c" .c); P=$B/ok/$n
  clean "$P"
  "$B/c2om" < "$c" > "$P/t.om" 2> "$P/t.err" || fail "c2om refused $c: $(cat "$P/t.err")"
  [ ! -s "$P/t.err" ] || fail "c2om wrote to stderr on $c"
  "$B/c2om" < "$c" > "$P/t2.om" 2>/dev/null; cmp -s "$P/t.om" "$P/t2.om" || fail "c2om is not deterministic on $c"
  "$OMC" < "$P/t.om" > "$P/o.bin" 2> "$P/o.err" || fail "omc refused the translation of $c: $(cat "$P/o.err")"
  chmod +x "$P/o.bin"
  quiet-build gcc -std=c11 -include stdio.h -O1 -o "$P/c.bin" "$c" > "$P/gcc.out" 2>&1 || fail "gcc: $(tail -3 "$P/gcc.out")"
  cp "$P/t.om" "$EV/$n.om"
  for in in "${INPUTS[@]}"; do
    run1 "$P/c.bin" "$P/c" "$in"; run1 "$P/o.bin" "$P/o" "$in"; run1 "ref:$P/t.om" "$P/r" "$in"
    run=$((run+1)); co=no; or=no
    same "$P/c" "$P/o" && co=yes
    same "$P/o" "$P/r" 0 && or=yes
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$n" "$(basename "$in")" "$(cat "$P/c/rc")" "$(cat "$P/o/rc")" "$(cat "$P/r/rc")" \
      "$(wc -c < "$P/o/out")" "$co" "$or" >> "$TSV"
    if [ $co = yes ] && [ $or = yes ]; then pass=$((pass+1)); else say "DIFF $n on $(basename "$in"): gcc = omc $co, omc = interp $or"; fi
  done
done
say "accept        programs ${#progs[@]}, inputs ${#INPUTS[@]}: cases written $written, run $run, identical on gcc, omc and interpreter $pass"

# 4. refusal corpus
rw=0; rp=0
for c in "$CORPUS"/refuse/*.c; do
  rw=$((rw+1))
  set +e; "$B/c2om" < "$c" > "$B/r.out" 2> "$B/r.err"; rc=$?; set -e
  if [ $rc = 65 ] && [ ! -s "$B/r.out" ] && cmp -s "$B/r.err" "${c%.c}.want"; then rp=$((rp+1))
  else say "REFUSAL MISMATCH $c: exit $rc, stdout $(wc -c < "$B/r.out") bytes, stderr $(cat "$B/r.err")"; fi
done
say "refuse        written $rw, refused with the named reason $rp ($(cut -d' ' -f2 "$CORPUS"/refuse/*.want | sort -u | tr '\n' ' '))"

# 5. negative controls
for m in "${MUTANTS[@]}"; do
  sed "$m" "$SRC" > "$B/mutant.om"
  [ "$(diff "$SRC" "$B/mutant.om" | grep -c '^[<>]')" = 2 ] || fail "mutant ($m) must change exactly one line"
  "$OMC" < "$B/mutant.om" > "$B/mutant" 2> "$B/mutant.err" || fail "mutant ($m) does not compile: $(cat "$B/mutant.err")"
  chmod +x "$B/mutant"
  caught=0
  for c in "${progs[@]}"; do
    n=$(basename "$c" .c); P=$B/ok/$n
    if ! "$B/mutant" < "$c" > "$B/m.om" 2>/dev/null || ! "$OMC" < "$B/m.om" > "$B/m.bin" 2>/dev/null; then
      caught=$((caught+${#INPUTS[@]})); continue
    fi
    chmod +x "$B/m.bin"
    for in in "${INPUTS[@]}"; do
      run1 "$P/c.bin" "$B/mc" "$in"; run1 "$B/m.bin" "$B/mm" "$in"
      same "$B/mc" "$B/mm" || caught=$((caught+1))
    done
  done
  say "control       mutant ($m) compiles; cases that catch it: $caught of $written"
  [ $caught -gt 0 ] || fail "mutant ($m) passed every case (gate blind)"
done

[ $run = "$written" ] || fail "cases run $run != written $written"
[ $pass = "$run" ] || fail "$((run-pass)) of $run accept cases differ"
[ $rp = "$rw" ] || fail "$((rw-rp)) of $rw refusals differ"
say "RESULT PASS"
