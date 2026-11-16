#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# tools/hwgates/gate.sh: run the hardware-gate register check (hwgates.om) on its fixtures, kill
# its compiling behavior mutants, then check docs/hardware-gates.tsv, the receipts it cites, and
# planted-bad copies of it.
#   AIEN_OMC=<the omc named in tools/hwgates/PIN> sh tools/hwgates/gate.sh
# Prints HWGATES-GATE PASS (exit 0) or HWGATES-GATE FAIL (exit 1). Without the pinned compiler it
# prints HWGATES-GATE NOT_RUN and exits 3. A NOT_RUN is never a pass.
# Invariants this gate holds:
#   - a PASS or FAIL row names a tracked, regular receipt file under evidence/ holding its
#     HWGATE <id> <tier> <status> line (no receipt, no claim);
#   - every gate id has exactly one PHYSICAL row, and QEMU is never PHYSICAL;
#   - a gate whose receipt still names it cannot be deleted from the register;
#   - the register's gate ids equal those of docs/hardware-gates-needs.tsv, so a gate no receipt
#     names yet cannot leave the inventory silently either;
#   - a cited receipt's HWGATE line agrees with the register row for its id and tier, unless a
#     CORRECTION-*.txt beside the receipt names that line (receipts are never rewritten);
#   - a PASS or FAIL row's source commit is recorded by a file in its receipt's folder.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
PIN=tools/hwgates/PIN
want=$(sed -n 's/^sha256 //p' "$PIN")
commit=$(sed -n 's/^commit //p' "$PIN")
if [ -z "${AIEN_OMC:-}" ] || [ ! -r "$AIEN_OMC" ]; then
  echo "HWGATES-GATE NOT_RUN: set AIEN_OMC to omc sha256 $want (omega-mv $commit, $PIN)"; exit 3
fi
have=$(sha256sum "$AIEN_OMC"); have=${have%% *}
if [ "$have" != "$want" ]; then
  echo "HWGATES-GATE NOT_RUN: compiler sha256 $have is not the pin $want ($PIN)"; exit 3
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
# planted NAME RULE FILE: the checker must refuse FILE with exit 1 and rule=RULE
planted() {
  rc=0; "$W/hwgates" "$3" "$ROOT" > "$W/out" 2>&1 || rc=$?
  if ! cmp -s "$REG" "$3" && [ "$rc" = 1 ] && grep -q "rule=$2\$" "$W/out"; then
    echo "PASS planted $1 refused ($2)"; n=$((n + 1))
  else echo "FAIL planted $1: rc=$rc, expected exit 1 with rule=$2: $(tr '\n' ' ' < "$W/out")"; fail=1; fi
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
mutant empty-register-accepted '$0=="fail 0 8" {next} {print}'
mutant receipt-ids-unchecked '$0=="receiptids" {next} {print}'
# the register itself
rc=0; "$W/hwgates" "$REG" "$ROOT" > "$W/reg" 2>&1 || rc=$?
cat "$W/reg"
if [ "$rc" = 0 ]; then echo "PASS register $REG"; n=$((n + 1)); else echo "FAIL register $REG rc=$rc"; fail=1; fi
# the receipts it cites: tracked regular files that resolve inside evidence/
bad=0
for r in $(awk -F '\t' '!/^#/ && NF == 7 && $6 != "-" {print $6}' "$REG" | sort -u); do
  rp=$(realpath -e "$r" 2>/dev/null || true)
  if [ -L "$r" ] || [ ! -f "$r" ]; then echo "FAIL receipt $r is not a regular file"; bad=1
  elif [ "${rp#"$ROOT/evidence/"}" = "$rp" ]; then echo "FAIL receipt $r resolves outside evidence/"; bad=1
  elif ! git ls-files --error-unmatch -- "$r" > /dev/null 2>&1; then echo "FAIL receipt $r is not tracked by git"; bad=1
  fi
done
if [ "$bad" = 0 ]; then echo "PASS receipts are tracked regular files under evidence/"; n=$((n + 1)); else fail=1; fi
# inventory, receipt claims and source commits (regsh REGISTER NEEDS): one FAIL line per problem,
# exit 1 if any. Claims are read from every tracked file under evidence/ with HWGATE lines, cited
# or not; a CORRECTION-*.txt counts only when it is a tracked regular file beside the receipt.
NEEDS=docs/hardware-gates-needs.tsv
# this repository's name as the register's source column spells it
SELF=aienux
regsh() {
  rb=0
  awk -F '\t' '!/^#/ && NF == 7 {print $1}' "$1" | sort -u > "$W/ids-reg"
  awk -F '\t' '!/^#/ && NF == 2 {print $1}' "$2" | sort -u > "$W/ids-need"
  for g in $(comm -23 "$W/ids-need" "$W/ids-reg"); do echo "FAIL inventory: gate $g is in $NEEDS but has no rows in the register"; rb=1; done
  for g in $(comm -13 "$W/ids-need" "$W/ids-reg"); do echo "FAIL inventory: gate $g has rows but no entry in $NEEDS"; rb=1; done
  for r in $( (git grep -l '^HWGATE ' -- evidence/; awk -F '\t' '!/^#/ && NF == 7 && $6 != "-" {print $6}' "$1") | sort -u); do
    [ -f "$r" ] || continue
    grep '^HWGATE ' "$r" > "$W/claims" || true
    : > "$W/corr"
    for c in "$(dirname "$r")"/CORRECTION-*.txt; do
      if [ -f "$c" ] && [ ! -L "$c" ] && git ls-files --error-unmatch -- "$c" > /dev/null 2>&1; then cat "$c" >> "$W/corr"; fi
    done
    while read -r _ id tier st; do
      have=$(awk -F '\t' -v i="$id" -v t="$tier" '!/^#/ && NF == 7 && $1 == i && $4 == t {print $5}' "$1")
      [ "$have" = "$st" ] && continue
      if grep -qxF "CORRECTS HWGATE $id $tier $st" "$W/corr"; then continue; fi
      echo "FAIL claim: $r says HWGATE $id $tier $st, the register says ${have:-no row}, and no tracked CORRECTION-*.txt beside it names the line"; rb=1
    done < "$W/claims"
  done
  # a PASS or FAIL row names REPO@COMMIT (40 hex); a *source-commit.txt beside its receipt holds
  # COMMIT as a whole line; COMMIT is a commit of this repository exactly when REPO is $SELF
  awk -F '\t' '!/^#/ && NF == 7 && ($5 == "PASS" || $5 == "FAIL") {print $1 " " $3 " " $6}' "$1" > "$W/srcs"
  while read -r id src r; do
    repo=${src%%@*}; c=${src#*@}
    if ! printf '%s\n' "$src" | grep -qxE '[A-Za-z0-9._-]+@[0-9a-f]{40}'; then echo "FAIL source: $id names '$src', not REPO@<40 hex commit>"; rb=1; continue; fi
    [ -f "$r" ] || continue
    if ! find "$(dirname "$r")" -name '*source-commit.txt' -type f -exec cat {} + | grep -qxF -- "$c"; then
      echo "FAIL source: $id names $src, which no *source-commit.txt beside $r records"; rb=1; continue; fi
    own=no; [ "$(git cat-file -t "$c" 2> /dev/null)" = commit ] && own=yes
    if [ "$repo" = "$SELF" ] && [ "$own" = no ]; then echo "FAIL source: $id names $src, which is not a commit of this repository"; rb=1; fi
    if [ "$repo" != "$SELF" ] && [ "$own" = yes ]; then echo "FAIL source: $id names $src, a commit of $SELF, not of $repo"; rb=1; fi
  done < "$W/srcs"
  return "$rb"
}
rc=0; regsh "$REG" "$NEEDS" > "$W/rs" || rc=$?
cat "$W/rs"
if [ "$rc" = 0 ]; then echo "PASS inventory, receipt claims and source commits agree with $REG"; n=$((n + 1)); else fail=1; fi
# plantsh NAME KIND REGISTER [NEEDS]: regsh must refuse the copy with a FAIL KIND line
plantsh() {
  pn=${4:-$NEEDS}
  rc=0; regsh "$3" "$pn" > "$W/out" || rc=$?
  if { ! cmp -s "$REG" "$3" || ! cmp -s "$NEEDS" "$pn"; } && [ "$rc" = 1 ] && grep -q "^FAIL $2:" "$W/out"; then
    echo "PASS planted $1 refused ($2)"; n=$((n + 1))
  else echo "FAIL planted $1: rc=$rc, expected a FAIL $2 line: $(tr '\n' ' ' < "$W/out")"; fail=1; fi
}
# planted control 6: a gate listed in the inventory with no rows (a deleted gate that no receipt
# names, which R9 cannot see), and a gate with rows but no inventory entry -> inventory.
# ZZ-PLANTED is synthetic, so the control holds whatever receipts the real gates have.
{ cat "$NEEDS"; printf 'ZZ-PLANTED\tplanted control\n'; } > "$W/p6n.tsv"
plantsh "gate ZZ-PLANTED listed without rows" inventory "$REG" "$W/p6n.tsv"
{ cat "$REG"; printf 'ZZ-PLANTED\tplanted\tplanted\tPHYSICAL\tNOT_RUN\t-\tplanted control\n'; } > "$W/p6r.tsv"
plantsh "gate ZZ-PLANTED with rows but no inventory entry" inventory "$W/p6r.tsv"
# planted control 7: the first PASS row downgraded to NOT_RUN without a correction -> claim
awk -F '\t' 'BEGIN{OFS="\t"} !done && !/^#/ && $5=="PASS" {$5="NOT_RUN"; $6="-"; done=1} {print}' "$REG" > "$W/p7.tsv"
plantsh "PASS row silently downgraded" claim "$W/p7.tsv"
# planted control 8: the first PASS row names a source commit its receipt does not record, an
# empty commit, or a commit of this repository under another repository's name -> source
awk -F '\t' 'BEGIN{OFS="\t"} !done && !/^#/ && $5=="PASS" {sub(/@.*/, "@0000000000000000000000000000000000000000", $3); done=1} {print}' "$REG" > "$W/p8.tsv"
plantsh "PASS row with an unrecorded source commit" source "$W/p8.tsv"
awk -F '\t' 'BEGIN{OFS="\t"} !done && !/^#/ && $5=="PASS" {sub(/@.*/, "@", $3); done=1} {print}' "$REG" > "$W/p8e.tsv"
plantsh "PASS row with an empty source commit" source "$W/p8e.tsv"
selfc=$(awk -F '\t' -v s="$SELF" '!/^#/ && NF == 7 && $5 == "PASS" && index($3, s "@") == 1 {print substr($3, length(s) + 2); exit}' "$REG")
awk -F '\t' -v s="$SELF" -v c="$selfc" 'BEGIN{OFS="\t"} !done && !/^#/ && $5=="PASS" && index($3, s "@") != 1 {sub(/@.*/, "@" c, $3); done=1} {print}' "$REG" > "$W/p8x.tsv"
plantsh "another repository's PASS row naming $SELF@$selfc" source "$W/p8x.tsv"
# alarm: the checker refuses registers and receipts larger than its tables (CAP bytes, MAXR rows,
# read from hwgates.om); fail loudly at three quarters of either so the tables grow first
cap=$(sed -n 's/^const CAP ulong \([0-9]*\)$/\1/p' "$SRC")
maxr=$(sed -n 's/^const MAXR ulong \([0-9]*\)$/\1/p' "$SRC")
rows=$(awk -F '\t' '!/^#/ && NF > 0' "$REG" | wc -l)
big=0
if [ $((rows * 4)) -gt $((maxr * 3)) ]; then echo "ALARM register has $rows rows; the checker holds MAXR=$maxr ($SRC)"; big=1; fi
for f in "$REG" $(awk -F '\t' '!/^#/ && NF == 7 && $6 != "-" {print $6}' "$REG" | sort -u); do
  s=$(wc -c < "$f")
  if [ $((s * 4)) -gt $((cap * 3)) ]; then echo "ALARM $f is $s bytes; the checker reads CAP=$cap ($SRC)"; big=1; fi
done
if [ "$big" = 0 ]; then echo "PASS sizes: $rows rows of MAXR=$maxr, every file under 3/4 of CAP=$cap"; n=$((n + 1)); else fail=1; fi
# planted control 1: the first PHYSICAL row, whatever its status, claims PASS without a receipt -> R3
awk -F '\t' 'BEGIN{OFS="\t"} !done && !/^#/ && $4=="PHYSICAL" {$5="PASS"; $6="-"; done=1} {print}' "$REG" > "$W/p1.tsv"
planted "physical PASS without receipt" R3 "$W/p1.tsv"
# planted control 2: every PHYSICAL row removed -> R5
awk -F '\t' '$4!="PHYSICAL"' "$REG" > "$W/p2.tsv"
planted "register without physical rows" R5 "$W/p2.tsv"
# planted control 3: every row of the first gate with a receipt removed -> R9
gid=$(awk -F '\t' '!/^#/ && NF == 7 && $6 != "-" {print $1; exit}' "$REG")
awk -F '\t' -v g="$gid" '$1 != g' "$REG" > "$W/p3.tsv"
planted "gate $gid deleted while its receipt names it" R9 "$W/p3.tsv"
# planted control 4: comments only -> R8
grep '^#' "$REG" > "$W/p4.tsv" || true
planted "register without rows" R8 "$W/p4.tsv"
# planted control 5: one row more than MAXR -> exit 2 naming the row table, never a rule verdict
awk -v m="$maxr" 'BEGIN{for (i = 0; i <= m; i++) printf "ZZ-%d\tc\ts\tPHYSICAL\tNOT_RUN\t-\to\n", i}' > "$W/p5.tsv"
rc=0; "$W/hwgates" "$W/p5.tsv" "$ROOT" > "$W/out" 2>&1 || rc=$?
if [ "$rc" = 2 ] && grep -q 'MAXR' "$W/out"; then echo "PASS planted $((maxr + 1)) rows refused (exit 2, MAXR)"; n=$((n + 1))
else echo "FAIL planted $((maxr + 1)) rows: rc=$rc: $(tr '\n' ' ' < "$W/out")"; fail=1; fi
if [ "$fail" = 0 ]; then echo "HWGATES-GATE PASS checks=$n"; exit 0; fi
echo "HWGATES-GATE FAIL checks_passed=$n"; exit 1
