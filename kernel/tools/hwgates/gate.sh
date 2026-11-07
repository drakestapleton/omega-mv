#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# tools/hwgates/gate.sh: run the hardware-gate register check (hwgates.om) on its fixtures,
# kill three compiling behavior mutants of the checker, then check docs/hardware-gates.tsv and two
# planted-bad copies of it.
#   AIEN_OMC=<omc sha256 bcfa5828...> sh tools/hwgates/gate.sh
# Prints HWGATES-GATE PASS (exit 0) or HWGATES-GATE FAIL (exit 1). Without the pinned compiler it
# prints HWGATES-GATE NOT_RUN and exits 3. A NOT_RUN is never a pass.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
want=bcfa582892afca8f65e551fe56867d918d86e84540c7381be8fa9ef18d0cf0f6
if [ -z "${AIEN_OMC:-}" ] || [ ! -r "$AIEN_OMC" ]; then
  echo "HWGATES-GATE NOT_RUN: set AIEN_OMC to omc sha256 $want (omega-mv 397e6704)"; exit 3
fi
have=$(sha256sum "$AIEN_OMC"); have=${have%% *}
if [ "$have" != "$want" ]; then
  echo "HWGATES-GATE NOT_RUN: compiler sha256 $have is not the pin $want"; exit 3
fi
W=$(mktemp -d "${TMPDIR:-/tmp}/hwgates.XXXXXX")
trap 'rm -rf "$W"' EXIT
SRC=tools/hwgates/hwgates.om
FX=tools/hwgates/fixtures
REG=docs/hardware-gates.tsv
build() { "$AIEN_OMC" < "$1" > "$2" && chmod +x "$2"; }
# fixtures BIN QUIET: prints one line per fixture unless QUIET; returns the number of wrong verdicts
fixtures() {
  bad=0
  if "$1" "$FX/good.tsv" "$ROOT/$FX" > "$W/out" 2>&1; then
    [ -n "$2" ] || echo "PASS fixture good.tsv: $(cat "$W/out")"
  else
    [ -n "$2" ] || echo "FAIL fixture good.tsv: $(tr '\n' ' ' < "$W/out")"; bad=$((bad + 1))
  fi
  for f in "$FX"/bad-R*.tsv; do
    b=$(basename "$f"); rule=$(echo "$b" | sed 's/^bad-\(R[0-9]*\)-.*/\1/')
    frc=0; "$1" "$f" "$ROOT/$FX" > "$W/out" 2>&1 || frc=$?
    if [ "$frc" = 1 ] && grep -q "rule=$rule\$" "$W/out"; then
      [ -n "$2" ] || echo "PASS fixture $b refused ($rule)"
    else
      [ -n "$2" ] || echo "FAIL fixture $b: rc=$frc, expected exit 1 with rule=$rule: $(tr '\n' ' ' < "$W/out")"
      bad=$((bad + 1))
    fi
  done
  return "$bad"
}
fail=0; n=0
build "$SRC" "$W/hwgates" || { echo "HWGATES-GATE FAIL: compile"; exit 1; }
rc=0; fixtures "$W/hwgates" "" || rc=$?
nfx=$(ls "$FX"/good.tsv "$FX"/bad-R*.tsv | wc -l)
if [ "$rc" = 0 ]; then n=$((n + nfx)); else fail=1; fi
# compiling behavior mutants of the checker; each must change at least one fixture verdict
mutant() { # NAME AWK-PROGRAM
  awk "$2" "$SRC" > "$W/m-$1.om"
  if cmp -s "$SRC" "$W/m-$1.om"; then echo "FAIL mutant $1 did not apply"; fail=1; return; fi
  build "$W/m-$1.om" "$W/m-$1" || { echo "FAIL mutant $1 does not compile"; fail=1; return; }
  k=0; fixtures "$W/m-$1" quiet || k=$?
  if [ "$k" -gt 0 ]; then echo "PASS mutant $1 killed ($k fixture verdicts changed)"; n=$((n + 1))
  else echo "FAIL mutant $1 survived"; fail=1; fi
}
mutant claim-without-receipt 'prev=="if dash" && $0=="fail ln 3" {prev=$0; next} {prev=$0; print}'
mutant physical-row-optional '$0=="if ne np 1" {print "if gt np 1"; next} {print}'
mutant any-line-of-length '$0=="ok = eqneed ls n" {print "ok = true"; next} {print}'
# the register itself
rc=0; "$W/hwgates" "$REG" "$ROOT" > "$W/reg" 2>&1 || rc=$?
cat "$W/reg"
if [ "$rc" = 0 ]; then echo "PASS register $REG"; n=$((n + 1)); else echo "FAIL register $REG rc=$rc"; fail=1; fi
# planted control 1: the first PHYSICAL NOT_RUN row claims PASS without a receipt -> R3
awk -F '\t' 'BEGIN{OFS="\t"} !done && $4=="PHYSICAL" && $5=="NOT_RUN" {$5="PASS"; done=1} {print}' "$REG" > "$W/p1.tsv"
rc=0; "$W/hwgates" "$W/p1.tsv" "$ROOT" > "$W/out" 2>&1 || rc=$?
if ! cmp -s "$REG" "$W/p1.tsv" && [ "$rc" = 1 ] && grep -q 'rule=R3$' "$W/out"; then
  echo "PASS planted physical PASS without receipt refused (R3)"; n=$((n + 1))
else echo "FAIL planted physical PASS: rc=$rc"; fail=1; fi
# planted control 2: every PHYSICAL row removed -> R5
awk -F '\t' '$4!="PHYSICAL"' "$REG" > "$W/p2.tsv"
rc=0; "$W/hwgates" "$W/p2.tsv" "$ROOT" > "$W/out" 2>&1 || rc=$?
if [ "$rc" = 1 ] && grep -q 'rule=R5$' "$W/out"; then
  echo "PASS planted register without physical rows refused (R5)"; n=$((n + 1))
else echo "FAIL planted no-physical: rc=$rc"; fail=1; fi
if [ "$fail" = 0 ]; then echo "HWGATES-GATE PASS checks=$n"; exit 0; fi
echo "HWGATES-GATE FAIL checks_passed=$n"; exit 1
