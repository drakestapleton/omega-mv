#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# tools/hwgates/gate.sh: run the hardware-gate register check (hwgates.om) on its fixtures, kill
# its compiling behavior mutants, then check docs/hardware-gates.tsv, the receipts it cites, and
# planted-bad copies of it.
#   AIEN_OMC=<omega-mv seed/out/omc> sh tools/hwgates/gate.sh
# Prints HWGATES-GATE PASS (exit 0) or HWGATES-GATE FAIL (exit 1). Without the pinned compiler it
# prints HWGATES-GATE NOT_RUN and exits 3. A NOT_RUN is never a pass.
# Invariants this gate holds:
#   - a PASS or FAIL row names a tracked, regular receipt file under evidence/ holding its
#     HWGATE <id> <tier> <status> line (no receipt, no claim);
#   - every gate id has exactly one PHYSICAL row, and QEMU is never PHYSICAL;
#   - a gate id is upper-case letters, digits, '-', '_' or '.', so two ids never differ by case alone;
#   - a gate whose receipt still names it cannot be deleted from the register;
#   - the register's gate ids equal those of docs/hardware-gates-needs.tsv, so a gate no receipt
#     names yet cannot leave the inventory silently either;
#   - every HWGATE line in a tracked evidence file agrees with the register row for its id and
#     tier, unless a tracked CORRECTION-*.txt beside it names that line;
#   - a line that a tracked CORRECTION-*.txt beside its receipt names (CORRECTS HWGATE <id> <tier>
#     <status>) is withdrawn: it never backs a PASS or FAIL row;
#   - receipts are never rewritten: every tracked file in the folder of a cited receipt or of a file
#     with HWGATE lines, and import/commit-map, has exactly the content of the commit that first
#     added it (so an appended or edited line fails, committed or not);
#   - a PASS or FAIL row's source REPO@COMMIT is recorded by tracked files in its receipt's folder;
#     aienux@COMMIT names an aienux commit that import/commit-map maps to a commit present here (the
#     fold into omega-mv rewrote aienux history; rows keep the aienux hashes they were written with);
#     any other REPO names neither an aienux commit nor a commit of this repository;
#   - the checker's count line equals the counts of the register, and the checker has no size cap:
#     it accepts a register and a receipt far past its old tables, and the real register alarms
#     when it grows past what that control proves.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
# The compiler pin is omega-mv's own (kernel/ is folded into omega-mv): seed/out/omc.sha256 at its root.
PIN=../seed/out/omc.sha256
want=$(cut -c1-64 "$PIN" 2>/dev/null) || want=
if ! printf '%s\n' "$want" | grep -qxE '[0-9a-f]{64}'; then
  echo "HWGATES-GATE NOT_RUN: no sha256 in $ROOT/$PIN"; exit 3
fi
if [ -z "${AIEN_OMC:-}" ] || [ ! -r "$AIEN_OMC" ]; then
  echo "HWGATES-GATE NOT_RUN: set AIEN_OMC to omc sha256 $want (omega-mv $PIN)"; exit 3
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
NEEDS=docs/hardware-gates-needs.tsv
# aienux old-to-new commit map written by the fold (kernel/MIGRATION.md): "OLD NEW" per line after a
# header, NEW 40 zeros for an aienux commit that touched only left-out paths
MAP=import/commit-map
# the repository the register's rows were written in, as the source column spells it
OLD=aienux
# the size of the no-cap control: the checker must accept a register of SROWS rows and a receipt of
# SBYTES bytes; the real register alarms past either (raise them here and rerun before it grows)
SROWS=4096
SBYTES=2097152
build() { "$AIEN_OMC" < "$1" > "$2" && chmod +x "$2"; }
# fixtures BIN QUIET: prints one line per fixture unless QUIET; returns the number of wrong verdicts.
# A good*.tsv must exit 0 printing exactly the count line in good*.out (counts are asserted, not
# only printed); a bad-RK-*.tsv must exit 1 with a rule=RK line.
fixtures() {
  bad=0
  for f in "$FX"/good*.tsv; do
    b=$(basename "$f"); exp=$(cat "${f%.tsv}.out" 2> /dev/null || true)
    frc=0; "$1" "$f" "$ROOT/$FX" > "$W/out" 2>&1 || frc=$?
    if [ "$frc" = 0 ] && [ -n "$exp" ] && [ "$(cat "$W/out")" = "$exp" ]; then
      [ -n "$2" ] || echo "PASS fixture $b: $exp"
    else
      [ -n "$2" ] || echo "FAIL fixture $b: rc=$frc, expected exit 0 and '$exp': $(tr '\n' ' ' < "$W/out")"
      bad=$((bad + 1))
    fi
  done
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
nfx=$(ls "$FX"/good*.tsv "$FX"/bad-R*.tsv | wc -l)
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
mutant physical-pass-uncounted '$0=="pp = add pp 1" {next} {print}'
mutant id-case-unchecked '$0=="fail ln 10" {next} {print}'
mutant row-table-not-grown '$0=="growrows r" {next} {print}'
# the register itself, and its count line against the register's own counts
rc=0; "$W/hwgates" "$REG" "$ROOT" > "$W/reg" 2>&1 || rc=$?
cat "$W/reg"
if [ "$rc" = 0 ]; then echo "PASS register $REG"; n=$((n + 1)); else echo "FAIL register $REG rc=$rc"; fail=1; fi
cnt=$(awk -F '\t' '!/^#/ && NF == 7 {r++; if (!($1 in g)) {g[$1] = 1; ng++}; if ($4 == "PHYSICAL") {p++; if ($5 == "PASS") pp++}}
  END {printf "HWGATES PASS rows=%d gates=%d physical=%d physical_pass=%d physical_not_pass=%d\n", r, ng, p, pp, p - pp}' "$REG")
if [ "$(cat "$W/reg")" = "$cnt" ]; then echo "PASS count line equals the register's counts"; n=$((n + 1))
else echo "FAIL count line: the checker printed '$(tr '\n' ' ' < "$W/reg")', the register has '$cnt'"; fail=1; fi
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
# immut PATH...: run inside a work tree; every tracked file under PATH has exactly the content of the
# commit that first added it (git log --diff-filter=A, oldest), so a receipt line appended, edited,
# or deleted and re-added, committed or only in the work tree, fails. One FAIL immutable line each.
immut() {
  ib=0
  if [ "$(git rev-parse --is-shallow-repository)" != false ]; then
    echo "FAIL immutable: shallow history, the commit that added a file cannot be found"; return 1
  fi
  top=$(git rev-parse --show-toplevel)
  git -c core.quotePath=false log --diff-filter=A --format='C %H' --name-only -- "$@" |
    awk '/^C / {c = $2; next} NF {a[$0] = c} END {for (p in a) print p "\t" a[p]}' > "$W/adds"
  git -c core.quotePath=false ls-files --full-name -- "$@" > "$W/files"
  while IFS= read -r p; do
    c=$(awk -F '\t' -v p="$p" '$1 == p {print $2; exit}' "$W/adds")
    if [ -z "$c" ]; then echo "FAIL immutable: no commit adds $p"; ib=1; continue; fi
    was=$(git rev-parse "$c:$p" 2> /dev/null) || was=none
    now=$(git hash-object -- "$top/$p" 2> /dev/null) || now=missing
    if [ "$was" != "$now" ]; then echo "FAIL immutable: $p is not the file $c added ($now, was $was)"; ib=1; fi
  done < "$W/files"
  return "$ib"
}
{ awk -F '\t' '!/^#/ && NF == 7 && $6 != "-" {print $6}' "$REG"; git grep -l '^HWGATE ' -- evidence/ || true; } |
  while IFS= read -r f; do dirname "$f"; done | sort -u > "$W/evdirs"
echo "$MAP" >> "$W/evdirs"
rc=0; immut $(cat "$W/evdirs") > "$W/imm.out" || rc=$?
cat "$W/imm.out"
if [ "$rc" = 0 ]; then echo "PASS receipts unchanged since added: $(git ls-files -- $(cat "$W/evdirs") | wc -l) tracked files in $(tr '\n' ' ' < "$W/evdirs")"; n=$((n + 1))
else fail=1; fi
# tracked DIR SUFFIX: the content of every tracked regular file under DIR whose name ends in SUFFIX
tracked() {
  git ls-files -- "$1" | while IFS= read -r f; do
    case ${f##*/} in *"$2") if [ -f "$f" ] && [ ! -L "$f" ]; then cat "$f"; fi ;; esac
  done
}
# corrof DIR: the content of every tracked regular CORRECTION-*.txt directly in DIR
corrof() {
  for c in "$1"/CORRECTION-*.txt; do
    if [ -f "$c" ] && [ ! -L "$c" ] && git ls-files --error-unmatch -- "$c" > /dev/null 2>&1; then cat "$c"; fi
  done
}
# inventory, receipt claims, withdrawn lines and source commits (regsh REGISTER NEEDS [MAP]): one
# FAIL line per problem, exit 1 if any. Claims are read from every tracked file under evidence/ with
# HWGATE lines, cited or not.
regsh() {
  rb=0; map=${3:-$MAP}
  awk -F '\t' '!/^#/ && NF == 7 {print $1}' "$1" | sort -u > "$W/ids-reg"
  awk -F '\t' '!/^#/ && NF == 2 {print $1}' "$2" | sort -u > "$W/ids-need"
  for g in $(comm -23 "$W/ids-need" "$W/ids-reg"); do echo "FAIL inventory: gate $g is in $NEEDS but has no rows in the register"; rb=1; done
  for g in $(comm -13 "$W/ids-need" "$W/ids-reg"); do echo "FAIL inventory: gate $g has rows but no entry in $NEEDS"; rb=1; done
  for r in $( (git grep -l '^HWGATE ' -- evidence/; awk -F '\t' '!/^#/ && NF == 7 && $6 != "-" {print $6}' "$1") | sort -u); do
    [ -f "$r" ] || continue
    grep '^HWGATE ' "$r" > "$W/claims" || true
    corrof "$(dirname "$r")" > "$W/corr"
    while read -r _ id tier st; do
      have=$(awk -F '\t' -v i="$id" -v t="$tier" '!/^#/ && NF == 7 && $1 == i && $4 == t {print $5}' "$1")
      [ "$have" = "$st" ] && continue
      if grep -qxF "CORRECTS HWGATE $id $tier $st" "$W/corr"; then continue; fi
      echo "FAIL claim: $r says HWGATE $id $tier $st, the register says ${have:-no row}, and no tracked CORRECTION-*.txt beside it names the line"; rb=1
    done < "$W/claims"
  done
  # a PASS or FAIL row never rests on a line a correction beside its receipt withdrew
  awk -F '\t' '!/^#/ && NF == 7 && ($5 == "PASS" || $5 == "FAIL") {print $1 " " $4 " " $5 " " $6}' "$1" > "$W/pf"
  while read -r id tier st r; do
    [ -f "$r" ] || continue
    corrof "$(dirname "$r")" > "$W/corr"
    if grep -qxF "CORRECTS HWGATE $id $tier $st" "$W/corr"; then
      echo "FAIL withdrawn: $id $tier $st cites $r, whose line HWGATE $id $tier $st a tracked CORRECTION-*.txt beside it withdraws"; rb=1
    fi
  done < "$W/pf"
  # a PASS or FAIL row names REPO@COMMIT (40 hex); a tracked *source-commit.txt in its receipt's
  # folder or below holds COMMIT as a whole line. REPO $OLD: $map maps COMMIT to a commit present
  # here. Any other REPO: COMMIT is neither a commit here nor one $map knows, and a tracked
  # *source-repo.txt there holds REPO@COMMIT as a whole line.
  awk -F '\t' '!/^#/ && NF == 7 && ($5 == "PASS" || $5 == "FAIL") {print $1 " " $3 " " $6}' "$1" > "$W/srcs"
  while read -r id src r; do
    repo=${src%%@*}; c=${src#*@}
    if ! printf '%s\n' "$src" | grep -qxE '[A-Za-z0-9._-]+@[0-9a-f]{40}'; then echo "FAIL source: $id names '$src', not REPO@<40 hex commit>"; rb=1; continue; fi
    [ -f "$r" ] || continue
    if ! tracked "$(dirname "$r")" source-commit.txt | grep -xF -- "$c" > /dev/null; then
      echo "FAIL source: $id names $src, which no tracked *source-commit.txt in the folder of $r records"; rb=1; continue; fi
    own=no; [ "$(git cat-file -t "$c" 2> /dev/null)" = commit ] && own=yes
    new=$(awk -v c="$c" 'NR > 1 && $1 == c && $2 !~ /^0+$/ {print $2; exit}' "$map")
    if [ "$repo" = "$OLD" ]; then
      if [ -z "$new" ]; then echo "FAIL source: $id names $src, which $map does not map to a commit here"; rb=1
      elif [ "$(git cat-file -t "$new" 2> /dev/null)" != commit ]; then echo "FAIL source: $id names $src, which $map maps to $new, not a commit here"; rb=1; fi
      continue
    fi
    if [ "$own" = yes ]; then echo "FAIL source: $id names $src, a commit of this repository, not of $repo"; rb=1; continue; fi
    if [ -n "$new" ]; then echo "FAIL source: $id names $src, an $OLD commit ($map), not of $repo"; rb=1; continue; fi
    if ! tracked "$(dirname "$r")" source-repo.txt | grep -xF -- "$src" > /dev/null; then
      echo "FAIL source: $id names $src, which no tracked *source-repo.txt in the folder of $r records"; rb=1; fi
  done < "$W/srcs"
  return "$rb"
}
rc=0; regsh "$REG" "$NEEDS" > "$W/rs" || rc=$?
cat "$W/rs"
if [ "$rc" = 0 ]; then echo "PASS inventory, receipt claims, withdrawn lines and source commits agree with $REG"; n=$((n + 1)); else fail=1; fi
# plantsh NAME KIND REGISTER [NEEDS [MAP]]: regsh must refuse the copy with a FAIL KIND line
plantsh() {
  pn=${4:-$NEEDS}; pm=${5:-$MAP}
  rc=0; regsh "$3" "$pn" "$pm" > "$W/out" || rc=$?
  if { ! cmp -s "$REG" "$3" || ! cmp -s "$NEEDS" "$pn" || ! cmp -s "$MAP" "$pm"; } && [ "$rc" = 1 ] && grep -q "^FAIL $2:" "$W/out"; then
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
# empty commit, an $OLD commit under another repository's name, or another repository's
# recorded commit under a misspelt name -> source
awk -F '\t' 'BEGIN{OFS="\t"} !done && !/^#/ && $5=="PASS" {sub(/@.*/, "@0000000000000000000000000000000000000000", $3); done=1} {print}' "$REG" > "$W/p8.tsv"
plantsh "PASS row with an unrecorded source commit" source "$W/p8.tsv"
awk -F '\t' 'BEGIN{OFS="\t"} !done && !/^#/ && $5=="PASS" {sub(/@.*/, "@", $3); done=1} {print}' "$REG" > "$W/p8e.tsv"
plantsh "PASS row with an empty source commit" source "$W/p8e.tsv"
oldc=$(awk -F '\t' -v s="$OLD" '!/^#/ && NF == 7 && $5 == "PASS" && index($3, s "@") == 1 {print substr($3, length(s) + 2); exit}' "$REG")
awk -F '\t' -v s="$OLD" -v c="$oldc" 'BEGIN{OFS="\t"} !done && !/^#/ && $5=="PASS" && index($3, s "@") != 1 {sub(/@.*/, "@" c, $3); done=1} {print}' "$REG" > "$W/p8x.tsv"
plantsh "another repository's PASS row naming $OLD@$oldc" source "$W/p8x.tsv"
awk -F '\t' -v s="$OLD" 'BEGIN{OFS="\t"} !done && !/^#/ && $5=="PASS" && index($3, s "@") != 1 {sub(/@/, "x@", $3); done=1} {print}' "$REG" > "$W/p8r.tsv"
plantsh "another repository's PASS row under a misspelt repository name" source "$W/p8r.tsv"
# planted control 9: $OLD@$oldc, cited by the real register, left out of the commit map, mapped
# to 40 zeros (a commit that touched only left-out paths), or mapped to a commit not here -> source
awk -v c="$oldc" '$1 != c' "$MAP" > "$W/m-out"
plantsh "$OLD@$oldc missing from $MAP" source "$REG" "$NEEDS" "$W/m-out"
awk -v c="$oldc" -v z="0000000000000000000000000000000000000000" '$1 == c {$2 = z} {print}' "$MAP" > "$W/m-zero"
plantsh "$OLD@$oldc mapped to zeros" source "$REG" "$NEEDS" "$W/m-zero"
awk -v c="$oldc" -v z="ffffffffffffffffffffffffffffffffffffffff" '$1 == c {$2 = z} {print}' "$MAP" > "$W/m-absent"
plantsh "$OLD@$oldc mapped to a commit not here" source "$REG" "$NEEDS" "$W/m-absent"
# planted control 10: the row of the first line a tracked correction withdraws, set back to that
# line's status and citing the receipt that holds it -> withdrawn (the checker alone accepts it)
cl=$(git grep '^CORRECTS HWGATE [^ ]* [^ ]* [^ ]*$' -- 'evidence/*CORRECTION-*.txt' | head -n 1 || true)
cf=${cl%%:*}; set -- ${cl#*:}
rcp=""
if [ -n "$cl" ]; then
  for f in $(git grep -lF -e "HWGATE $3 $4 $5" -- "$(dirname "$cf")" || true); do
    if grep -qxF "HWGATE $3 $4 $5" "$f"; then rcp=$f; break; fi
  done
fi
if [ -n "$rcp" ]; then
  awk -F '\t' -v i="$3" -v t="$4" -v s="$5" -v r="$rcp" 'BEGIN{OFS="\t"} !/^#/ && $1 == i && $4 == t {$5 = s; $6 = r} {print}' "$REG" > "$W/p10.tsv"
  rc=0; "$W/hwgates" "$W/p10.tsv" "$ROOT" > /dev/null 2>&1 || rc=$?
  if [ "$rc" = 0 ]; then plantsh "$3 $4 set back to $5 on the line $cf withdraws" withdrawn "$W/p10.tsv"
  else echo "FAIL planted withdrawn line: the checker itself refuses the planted register (rc=$rc), so the control tests nothing"; fail=1; fi
else echo "FAIL planted withdrawn line: no tracked CORRECTION-*.txt with a CORRECTS line and its receipt line to plant"; fail=1; fi
# planted control 11: receipts are never rewritten, on a throwaway repository: an untouched receipt
# passes; a line appended in the work tree, the same append committed, and the receipt deleted and
# added again with other content each fail
G="git -c user.name=hwgates -c user.email=hwgates@invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null"
imm() { # NAME WANT(0 accept, 1 refuse)
  rc=0; (cd "$W/imm" && unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE && immut evidence/R) > "$W/out" 2>&1 || rc=$?
  if [ "$rc" = "$2" ] && { [ "$2" = 0 ] || grep -q '^FAIL immutable:' "$W/out"; }; then echo "PASS planted $1 (exit $rc)"; n=$((n + 1))
  else echo "FAIL planted $1: rc=$rc, expected $2: $(tr '\n' ' ' < "$W/out")"; fail=1; fi
}
mkdir -p "$W/imm/evidence/R"
( cd "$W/imm" && unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE && git -c init.defaultBranch=main init -q &&
  printf 'planted receipt\nHWGATE ZZ HOST PASS\nHWGATE ZZ PHYSICAL NOT_RUN\n' > evidence/R/RECEIPT.txt &&
  git add evidence && $G commit -q -m add )
imm "untouched receipt accepted" 0
printf 'HWGATE ZZ PHYSICAL PASS\n' >> "$W/imm/evidence/R/RECEIPT.txt"
imm "line appended in the work tree refused" 1
( cd "$W/imm" && unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE && $G commit -q -am append )
imm "appended line committed refused" 1
( cd "$W/imm" && unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE && git rm -q evidence/R/RECEIPT.txt && $G commit -q -m delete &&
  mkdir -p evidence/R && printf 'planted receipt\nHWGATE ZZ PHYSICAL PASS\n' > evidence/R/RECEIPT.txt &&
  git add evidence && $G commit -q -m again )
imm "receipt deleted and added again refused" 1
# no cap: the checker accepts a register of SROWS rows (over a megabyte) whose PHYSICAL PASS row
# cites a receipt of more than SBYTES bytes with the claim line last, and prints the exact counts
mkdir -p "$W/big/evidence"
awk -v n="$SROWS" 'BEGIN { pad = sprintf("%300s", ""); gsub(/ /, "o", pad)
  for (i = 1; i < n; i++) printf "ZZ-%d\tc\ts\tPHYSICAL\tNOT_RUN\t-\t%s\n", i, pad
  printf "ZZ-0\tc\ts\tPHYSICAL\tPASS\tevidence/BIG.txt\t%s\n", pad }' > "$W/big/reg.tsv"
awk -v b="$SBYTES" 'BEGIN { l = sprintf("%1023s", ""); for (i = 0; i < b / 1024; i++) print l; print "HWGATE ZZ-0 PHYSICAL PASS" }' > "$W/big/evidence/BIG.txt"
rc=0; "$W/hwgates" "$W/big/reg.tsv" "$W/big" > "$W/out" 2>&1 || rc=$?
exp="HWGATES PASS rows=$SROWS gates=$SROWS physical=$SROWS physical_pass=1 physical_not_pass=$((SROWS - 1))"
if [ "$rc" = 0 ] && [ "$(cat "$W/out")" = "$exp" ]; then
  echo "PASS no cap: a $(wc -c < "$W/big/reg.tsv")-byte register of $SROWS rows citing a $(wc -c < "$W/big/evidence/BIG.txt")-byte receipt: $exp"; n=$((n + 1))
else echo "FAIL no cap: rc=$rc, expected '$exp': $(tr '\n' ' ' < "$W/out")"; fail=1; fi
# alarm: the real register and every receipt it cites stay within what the no-cap control proves
rows=$(awk -F '\t' '!/^#/ && NF > 0' "$REG" | wc -l)
big=0
if [ "$rows" -gt "$SROWS" ]; then echo "ALARM register has $rows rows, past the $SROWS the no-cap control proves: raise SROWS in tools/hwgates/gate.sh and rerun"; big=1; fi
for f in "$REG" $(awk -F '\t' '!/^#/ && NF == 7 && $6 != "-" {print $6}' "$REG" | sort -u); do
  [ -f "$f" ] || continue
  s=$(wc -c < "$f")
  if [ "$s" -gt "$SBYTES" ]; then echo "ALARM $f is $s bytes, past the $SBYTES the no-cap control proves: raise SBYTES in tools/hwgates/gate.sh and rerun"; big=1; fi
done
if [ "$big" = 0 ]; then echo "PASS sizes: $rows rows of $SROWS, every file at most $SBYTES bytes"; n=$((n + 1)); else fail=1; fi
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
# planted control 5: the first gate's PHYSICAL row given its id in lower case -> R10
awk -F '\t' 'BEGIN{OFS="\t"} !done && !/^#/ && $4=="PHYSICAL" {$1=tolower($1); done=1} {print}' "$REG" > "$W/p5.tsv"
planted "a PHYSICAL row whose id differs from its gate's by case" R10 "$W/p5.tsv"
if [ "$fail" = 0 ]; then echo "HWGATES-GATE PASS checks=$n"; exit 0; fi
echo "HWGATES-GATE FAIL checks_passed=$n"; exit 1
