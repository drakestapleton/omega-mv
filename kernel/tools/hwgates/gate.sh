#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# tools/hwgates/gate.sh: run the hardware-gate register check (hwgates.om) on its fixtures, kill
# its compiling behavior mutants, then check docs/hardware-gates.tsv, the receipts it cites, and
# planted-bad copies of it.
#   AIEN_OMC=<omega-mv seed/out/omc> sh tools/hwgates/gate.sh
# Prints HWGATES-GATE PASS checks=N (exit 0) or HWGATES-GATE FAIL (exit 1). Without the pinned compiler,
# or without the repository history (not a git work tree, a shallow clone, no base ref for
# tools/evidence_immutable.sh, a base ref without kernel/), it prints HWGATES-GATE NOT_RUN and exits 3.
# A NOT_RUN is not a pass.
# Invariants this gate holds:
#   - a PASS or FAIL row names a tracked, regular receipt file under evidence/ holding its
#     HWGATE <id> <tier> <status> line (no receipt, no claim). Of the receipt, this gate reads that
#     line and the source commit (below); it does not read an image digest, a machine identity, the
#     commands or what docs/hardware-gates-needs.tsv asks a PHYSICAL receipt to show. The register is
#     listed in tools/gate-anchors.txt, so a row change is GATE-ANCHOR CHANGED and the operator run
#     checks those fields before it acknowledges it [ctl:OMEGA-GATE-ANCHOR/edited];
#   - every gate id has exactly one PHYSICAL row, and QEMU is never PHYSICAL;
#   - a gate id is upper-case letters, digits, '-', '_' or '.', so two ids never differ by case alone;
#   - a gate whose receipt still names it cannot be deleted from the register;
#   - the register's gate ids equal those of docs/hardware-gates-needs.tsv, so a gate no receipt
#     names yet cannot leave the inventory silently either;
#   - a line CORRECTS HWGATE <id> <tier> <status> that any CORRECTION-*.txt under evidence/ holds or
#     ever held in HEAD's history (deleted or edited since included) withdraws that line everywhere:
#     it never backs a PASS or FAIL row, whatever receipt or folder the row cites;
#   - every HWGATE line in a tracked evidence file agrees with the register row for its id and
#     tier, unless it is withdrawn;
#   - evidence/ and import/ are checked by tools/evidence_immutable.sh kernel/evidence kernel/import
#     against the base ref, the commit that brought kernel/ in and the commits after it (its header says
#     which changes fail; the base ref's copy of that script runs as well when its bytes differ). With
#     a base ref that has no kernel/ (origin/main before the fold lands) this check, and so the gate, is
#     NOT_RUN [ctl:OMEGA-EVIDENCE-IMMUTABLE/kernel-base-without-script];
#   - a PASS or FAIL row's source REPO@COMMIT is recorded by tracked files in its receipt's folder;
#     aienux@COMMIT has exactly one import/commit-map row, naming a commit of the aienux history the
#     fold brought in (the rewritten aienux main in import/ref-map or an ancestor); the fold rewrote
#     aienux history, and rows keep the aienux hashes they were written with. import/ is additions
#     only (evidence_immutable.sh walks every commit after the import), so a row cannot be repointed
#     to another commit of that history either. Any other REPO names neither a commit of this
#     repository nor one the map lists;
#   - the checker's count line equals the counts of the register, and the checker has no size cap:
#     it accepts a register and a receipt far past its old tables, and the real register alarms
#     when it grows past what that control proves;
#   - the checks that pass are compared with tools/hwgates/checks.txt, once each: N in the PASS line
#     is asserted, so a check deleted, skipped or run twice in place of another fails the gate
#     (planted control 12). A check removed from this script and from checks.txt in one commit passes
#     that comparison; both files are listed in tools/gate-anchors.txt, so tools/gate_anchor.sh reports
#     them as GATE-ANCHOR CHANGED and the head is BLOCKED_OPERATOR [ctl:OMEGA-GATE-ANCHOR/edited].
set -eu
# the environment cannot point git at another repository, index or object store, or rewrite history
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR \
  GIT_NAMESPACE GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT
export GIT_NO_REPLACE_OBJECTS=1 GIT_GRAFT_FILE=/nonexistent/hwgates-grafts
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
# The receipt, correction and commit-map checks read git history: without it, NOT_RUN, not FAIL.
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "HWGATES-GATE NOT_RUN: $ROOT is not in a git work tree (a tarball?): the receipt history cannot be read"; exit 3
fi
if [ "$(git rev-parse --is-shallow-repository)" != false ]; then
  echo "HWGATES-GATE NOT_RUN: shallow clone: the receipt history cannot be read (fetch the full history)"; exit 3
fi
W=$(mktemp -d "${TMPDIR:-/tmp}/hwgates.XXXXXX")
trap 'rm -rf "$W"' EXIT
SRC=tools/hwgates/hwgates.om
FX=tools/hwgates/fixtures
REG=docs/hardware-gates.tsv
NEEDS=docs/hardware-gates-needs.tsv
# aienux old-to-new commit map written by the fold (kernel/MIGRATION.md): "OLD NEW" per line after a
# header, NEW 40 zeros for an aienux commit that touched only left-out paths; import/ref-map gives
# the rewritten aienux main, the head of the history the fold brought in
MAP=import/commit-map
AMAIN=$(awk 'NR > 1 && $3 == "refs/heads/main" {print $2}' import/ref-map 2> /dev/null)
CHECKS=tools/hwgates/checks.txt
# the repository the register's rows were written in, as the source column spells it
OLD=aienux
# the size of the no-cap control: the checker must accept a register of SROWS rows and a receipt of
# SBYTES bytes; the real register alarms past either (raise them here and rerun before it grows)
SROWS=4096
SBYTES=2097152
build() { "$AIEN_OMC" < "$1" > "$2" && chmod +x "$2"; }
# pass KEY: one passing check; its line in tools/hwgates/checks.txt is $key when set (a fixed name for a
# control whose message names register-dependent ids or commits), else KEY
key=""
pass() { n=$((n + 1)); printf '%s\n' "${key:-$1}" >> "$W/keys"; key=""; }
# fixtures BIN QUIET: prints one line per fixture unless QUIET; returns the number of wrong verdicts.
# A good*.tsv must exit 0 printing exactly the count line in good*.out (counts are asserted, not
# only printed); a bad-RK-*.tsv must exit 1 with a rule=RK line.
fixtures() {
  bad=0
  for f in "$FX"/good*.tsv; do
    b=$(basename "$f"); exp=$(cat "${f%.tsv}.out" 2> /dev/null || true)
    frc=0; "$1" "$f" "$ROOT/$FX" > "$W/out" 2>&1 || frc=$?
    if [ "$frc" = 0 ] && [ -n "$exp" ] && [ "$(cat "$W/out")" = "$exp" ]; then
      [ -n "$2" ] || { echo "PASS fixture $b: $exp"; pass "fixture $b"; }
    else
      [ -n "$2" ] || echo "FAIL fixture $b: rc=$frc, expected exit 0 and '$exp': $(tr '\n' ' ' < "$W/out")"
      bad=$((bad + 1))
    fi
  done
  for f in "$FX"/bad-R*.tsv; do
    b=$(basename "$f"); rule=$(echo "$b" | sed 's/^bad-\(R[0-9]*\)-.*/\1/')
    frc=0; "$1" "$f" "$ROOT/$FX" > "$W/out" 2>&1 || frc=$?
    if [ "$frc" = 1 ] && grep -q "rule=$rule\$" "$W/out"; then
      [ -n "$2" ] || { echo "PASS fixture $b refused ($rule)"; pass "fixture $b"; }
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
    echo "PASS planted $1 refused ($2)"; pass "planted $1"
  else echo "FAIL planted $1: rc=$rc, expected exit 1 with rule=$2: $(tr '\n' ' ' < "$W/out")"; fail=1; fi
}
fail=0; n=0; notrun=0; : > "$W/keys"
build "$SRC" "$W/hwgates" || { echo "HWGATES-GATE FAIL: compile"; exit 1; }
rc=0; fixtures "$W/hwgates" "" || rc=$?
[ "$rc" = 0 ] || fail=1
# compiling behavior mutants of the checker; each must change at least one fixture verdict
mutant() { # NAME AWK-PROGRAM
  awk "$2" "$SRC" > "$W/m-$1.om"
  if cmp -s "$SRC" "$W/m-$1.om"; then echo "FAIL mutant $1 did not apply"; fail=1; return; fi
  build "$W/m-$1.om" "$W/m-$1" || { echo "FAIL mutant $1 does not compile"; fail=1; return; }
  k=0; fixtures "$W/m-$1" quiet || k=$?
  if [ "$k" -gt 0 ]; then echo "PASS mutant $1 killed ($k fixture verdicts changed)"; pass "mutant $1"
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
if [ "$rc" = 0 ]; then echo "PASS register $REG"; pass register; else echo "FAIL register $REG rc=$rc"; fail=1; fi
cnt=$(awk -F '\t' '!/^#/ && NF == 7 {r++; if (!($1 in g)) {g[$1] = 1; ng++}; if ($4 == "PHYSICAL") {p++; if ($5 == "PASS") pp++}}
  END {printf "HWGATES PASS rows=%d gates=%d physical=%d physical_pass=%d physical_not_pass=%d\n", r, ng, p, pp, p - pp}' "$REG")
if [ "$(cat "$W/reg")" = "$cnt" ]; then echo "PASS count line equals the register's counts"; pass "count line"
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
if [ "$bad" = 0 ]; then echo "PASS receipts are tracked regular files under evidence/"; pass "receipts tracked"; else fail=1; fi
# evidence/ and import/ are additions only, against the base ref, the import and every commit after
# it, index and work tree included (tools/evidence_immutable.sh, which runs its own controls first)
# Against a base ref without kernel/ there is no reviewed kernel/ to compare with: NOT_RUN, not a pass.
kbase=${AIEN_BASE_REF:-origin/main}
if ! kb=$(git rev-parse --verify -q "$kbase^{commit}") || ! git cat-file -e "$kb:kernel" 2> /dev/null; then
  echo "NOT_RUN evidence/ and import/ additions only: the base ref $kbase is not a commit here or has no kernel/ (set AIEN_BASE_REF to the branch this head lands on)"; notrun=1
else
  rc=0; bash "$ROOT/../tools/evidence_immutable.sh" kernel/evidence kernel/import > "$W/imm.out" 2>&1 || rc=$?
  cat "$W/imm.out"
  if [ "$rc" = 0 ] && grep -q '^EVIDENCE-IMMUTABLE PASS' "$W/imm.out"; then echo "PASS evidence/ and import/ are additions only"; pass "additions only"
  elif [ "$rc" = 3 ]; then echo "NOT_RUN evidence/ and import/ additions only: no history to compare with (above)"; notrun=1
  else echo "FAIL evidence/ or import/ is not additions only (above), exit $rc"; fail=1; fi
fi
# withdrawals: every CORRECTS HWGATE <id> <tier> <status> line that a CORRECTION-*.txt anywhere under
# evidence/ holds in the work tree or held in any commit reachable from HEAD (every blob such a path
# ever had, merges compared with each parent), so deleting or editing a correction cannot reinstate
# its line. Run inside a work tree; prints the lines, sorted and unique.
withdrawals() {
  { git log --format= --raw --no-abbrev --no-renames -m --full-history HEAD -- ':(glob)evidence/**/CORRECTION-*.txt' |
      awk '/^:/ {print $3; print $4}' | grep -v '^0*$' | sort -u | while IFS= read -r b; do git cat-file blob "$b"; echo; done
    git -c core.quotePath=false ls-files -- ':(glob)evidence/**/CORRECTION-*.txt' | while IFS= read -r c; do
      if [ -f "$c" ] && [ ! -L "$c" ]; then cat "$c"; echo; fi
    done
  } | grep -x 'CORRECTS HWGATE [^ ]* [^ ]* [^ ]*' | sort -u
}
withdrawals > "$W/withdrawn"
# tracked DIR SUFFIX: the content of every tracked regular file under DIR whose name ends in SUFFIX
tracked() {
  git ls-files -- "$1" | while IFS= read -r f; do
    case ${f##*/} in *"$2") if [ -f "$f" ] && [ ! -L "$f" ]; then cat "$f"; fi ;; esac
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
    while read -r _ id tier st; do
      have=$(awk -F '\t' -v i="$id" -v t="$tier" '!/^#/ && NF == 7 && $1 == i && $4 == t {print $5}' "$1")
      [ "$have" = "$st" ] && continue
      if grep -qxF "CORRECTS HWGATE $id $tier $st" "$W/withdrawn"; then continue; fi
      echo "FAIL claim: $r says HWGATE $id $tier $st, the register says ${have:-no row}, and no CORRECTION-*.txt withdraws the line"; rb=1
    done < "$W/claims"
  done
  # a PASS or FAIL row never rests on a withdrawn line, whatever receipt or folder it cites
  awk -F '\t' '!/^#/ && NF == 7 && ($5 == "PASS" || $5 == "FAIL") {print $1 " " $4 " " $5 " " $6}' "$1" > "$W/pf"
  while read -r id tier st r; do
    if grep -qxF "CORRECTS HWGATE $id $tier $st" "$W/withdrawn"; then
      echo "FAIL withdrawn: $id $tier $st cites $r, but a CORRECTION-*.txt (now or in history) withdraws HWGATE $id $tier $st"; rb=1
    fi
  done < "$W/pf"
  # a PASS or FAIL row names REPO@COMMIT (40 hex); a tracked *source-commit.txt in its receipt's
  # folder or below holds COMMIT as a whole line. REPO $OLD: $map has exactly one row for COMMIT,
  # naming a commit of the aienux history the fold brought in ($AMAIN or an ancestor). Any other REPO: COMMIT is neither a commit here nor one $map lists, and a tracked
  # *source-repo.txt there holds REPO@COMMIT as a whole line.
  awk -F '\t' '!/^#/ && NF == 7 && ($5 == "PASS" || $5 == "FAIL") {print $1 " " $3 " " $6}' "$1" > "$W/srcs"
  while read -r id src r; do
    repo=${src%%@*}; c=${src#*@}
    if ! printf '%s\n' "$src" | grep -qxE '[A-Za-z0-9._-]+@[0-9a-f]{40}'; then echo "FAIL source: $id names '$src', not REPO@<40 hex commit>"; rb=1; continue; fi
    [ -f "$r" ] || continue
    if ! tracked "$(dirname "$r")" source-commit.txt | grep -xF -- "$c" > /dev/null; then
      echo "FAIL source: $id names $src, which no tracked *source-commit.txt in the folder of $r records"; rb=1; continue; fi
    own=no; [ "$(git cat-file -t "$c" 2> /dev/null)" = commit ] && own=yes
    nrow=$(awk -v c="$c" 'NR > 1 && $1 == c' "$map" | wc -l)
    new=$(awk -v c="$c" 'NR > 1 && $1 == c {print $2; exit}' "$map")
    if [ "$repo" = "$OLD" ]; then
      if [ "$nrow" != 1 ]; then echo "FAIL source: $id names $src, for which $map has $nrow rows, not one"; rb=1
      elif ! printf '%s\n' "$new" | grep -qxE '[0-9a-f]{40}' || printf '%s\n' "$new" | grep -qxE '0{40}'; then
        echo "FAIL source: $id names $src, which $map maps to '$new', not a commit (zeros: the commit touched only left-out paths)"; rb=1
      elif [ "$(git cat-file -t "$new" 2> /dev/null)" != commit ]; then echo "FAIL source: $id names $src, which $map maps to $new, not a commit here"; rb=1
      elif ! printf '%s\n' "$AMAIN" | grep -qxE '[0-9a-f]{40}' || ! git merge-base --is-ancestor "$new" "$AMAIN" 2> /dev/null; then
        echo "FAIL source: $id names $src, which $map maps to $new, not a commit of the aienux history the fold brought in (${AMAIN:-no refs/heads/main row in import/ref-map})"; rb=1
      fi
      continue
    fi
    if [ "$own" = yes ]; then echo "FAIL source: $id names $src, a commit of this repository, not of $repo"; rb=1; continue; fi
    if [ "$nrow" != 0 ]; then echo "FAIL source: $id names $src, an $OLD commit ($map), not of $repo"; rb=1; continue; fi
    if ! tracked "$(dirname "$r")" source-repo.txt | grep -xF -- "$src" > /dev/null; then
      echo "FAIL source: $id names $src, which no tracked *source-repo.txt in the folder of $r records"; rb=1; fi
  done < "$W/srcs"
  return "$rb"
}
rc=0; regsh "$REG" "$NEEDS" > "$W/rs" || rc=$?
cat "$W/rs"
if [ "$rc" = 0 ]; then echo "PASS inventory, receipt claims, withdrawn lines and source commits agree with $REG"; pass "register agrees"; else fail=1; fi
# plantsh NAME KIND REGISTER [NEEDS [MAP]]: regsh must refuse the copy with a FAIL KIND line
plantsh() {
  pn=${4:-$NEEDS}; pm=${5:-$MAP}
  rc=0; regsh "$3" "$pn" "$pm" > "$W/out" || rc=$?
  if { ! cmp -s "$REG" "$3" || ! cmp -s "$NEEDS" "$pn" || ! cmp -s "$MAP" "$pm"; } && [ "$rc" = 1 ] && grep -q "^FAIL $2:" "$W/out"; then
    echo "PASS planted $1 refused ($2)"; pass "planted $1"
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
key="planted another repository's PASS row naming an $OLD commit"; plantsh "another repository's PASS row naming $OLD@$oldc" source "$W/p8x.tsv"
awk -F '\t' -v s="$OLD" 'BEGIN{OFS="\t"} !done && !/^#/ && $5=="PASS" && index($3, s "@") != 1 {sub(/@/, "x@", $3); done=1} {print}' "$REG" > "$W/p8r.tsv"
plantsh "another repository's PASS row under a misspelt repository name" source "$W/p8r.tsv"
# planted control 9: $OLD@$oldc, cited by the real register, left out of the commit map, mapped
# to 40 zeros (a commit that touched only left-out paths), or mapped to a commit not here -> source
awk -v c="$oldc" '$1 != c' "$MAP" > "$W/m-out"
key="planted $OLD commit missing from $MAP"; plantsh "$OLD@$oldc missing from $MAP" source "$REG" "$NEEDS" "$W/m-out"
awk -v c="$oldc" -v z="0000000000000000000000000000000000000000" '$1 == c {$2 = z} {print}' "$MAP" > "$W/m-zero"
key="planted $OLD commit mapped to zeros"; plantsh "$OLD@$oldc mapped to zeros" source "$REG" "$NEEDS" "$W/m-zero"
awk -v c="$oldc" -v z="ffffffffffffffffffffffffffffffffffffffff" '$1 == c {$2 = z} {print}' "$MAP" > "$W/m-absent"
key="planted $OLD commit mapped to a commit not here"; plantsh "$OLD@$oldc mapped to a commit not here" source "$REG" "$NEEDS" "$W/m-absent"
# ... given a zero row and a later duplicate row naming its commit (a later row cannot override an
# earlier one), mapped to the tree of its commit (an object here, not a commit), or mapped to HEAD (a
# commit here, not of the aienux history the fold brought in) -> source
awk -v c="$oldc" -v z="0000000000000000000000000000000000000000" '$1 == c {print c, z} {print}' "$MAP" > "$W/m-dup"
key="planted $OLD commit given a zero row and a duplicate row"; plantsh "$OLD@$oldc given a zero row and a duplicate row" source "$REG" "$NEEDS" "$W/m-dup"
awk -v c="$oldc" -v a="$AMAIN" '$1 == c {print c, a} {print}' "$MAP" > "$W/m-dup2"
key="planted $OLD commit given an earlier duplicate row naming another imported commit"; plantsh "$OLD@$oldc given an earlier row naming $AMAIN" source "$REG" "$NEEDS" "$W/m-dup2"
oldn=$(awk -v c="$oldc" 'NR > 1 && $1 == c {print $2; exit}' "$MAP")
awk -v c="$oldc" -v t="$(git rev-parse "$oldn^{tree}" 2> /dev/null || echo none)" '$1 == c {$2 = t} {print}' "$MAP" > "$W/m-tree"
key="planted $OLD commit mapped to a tree"; plantsh "$OLD@$oldc mapped to a tree, not a commit" source "$REG" "$NEEDS" "$W/m-tree"
awk -v c="$oldc" -v h="$(git rev-parse HEAD)" '$1 == c {$2 = h} {print}' "$MAP" > "$W/m-head"
key="planted $OLD commit mapped to HEAD"; plantsh "$OLD@$oldc mapped to HEAD, outside the imported aienux history" source "$REG" "$NEEDS" "$W/m-head"
# planted control 10: the row of the first withdrawn line, set back to that line's status and citing a
# receipt that holds it -> withdrawn (the checker alone accepts it); the same row citing a receipt in a
# subfolder of that receipt's folder, or in a new folder -> withdrawn (a correction holds everywhere)
set -- $(head -n 1 "$W/withdrawn")
rcp=""
if [ $# = 5 ]; then
  for f in $(git grep -lF -e "HWGATE $3 $4 $5" -- evidence/ || true); do
    if grep -qxF "HWGATE $3 $4 $5" "$f"; then rcp=$f; break; fi
  done
fi
if [ -n "$rcp" ]; then
  for r in "$rcp" "$(dirname "$rcp")/sub/RECEIPT.txt" "evidence/ZZ-NEW-FOLDER/RECEIPT.txt"; do
    k=${r#"$(dirname "$rcp")/"}; [ "$r" = "$rcp" ] && k="the receipt that holds it"
    awk -F '\t' -v i="$3" -v t="$4" -v s="$5" -v r="$r" 'BEGIN{OFS="\t"} !/^#/ && $1 == i && $4 == t {$5 = s; $6 = r} {print}' "$REG" > "$W/p10.tsv"
    if [ "$r" = "$rcp" ]; then
      rc=0; "$W/hwgates" "$W/p10.tsv" "$ROOT" > /dev/null 2>&1 || rc=$?
      if [ "$rc" != 0 ]; then echo "FAIL planted withdrawn line: the checker itself refuses the planted register (rc=$rc), so the control tests nothing"; fail=1; continue; fi
    fi
    key="planted withdrawn line set back, citing $k";     plantsh "$3 $4 set back to $5, a withdrawn line, citing $k" withdrawn "$W/p10.tsv"
  done
else echo "FAIL planted withdrawn line: no withdrawn line with a receipt holding it to plant"; fail=1; fi
# planted control 11: withdrawals reads history, on a throwaway repository: a correction deleted, a
# correction edited so it no longer names its line, a correction added on a side branch that its
# merge dropped, and one added by a merge commit itself and dropped by a later merge each still withdraw their
# line; a line no correction ever named is not withdrawn
G="git -c user.name=hwgates -c user.email=hwgates@invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null -c init.defaultBranch=main"
wd() { # NAME WANT(1 listed, 0 not listed) LINE
  got=0; (cd "$W/wd" && withdrawals) | grep -qxF "$3" && got=1
  if [ "$got" = "$2" ]; then echo "PASS planted $1"; pass "planted $1"
  else echo "FAIL planted $1: '$3' listed=$got, expected $2"; fail=1; fi
}
mkdir -p "$W/wd/evidence/R"
if ( cd "$W/wd" && $G init -q &&
  printf 'CORRECTS HWGATE ZZ HOST PASS\n' > evidence/R/CORRECTION-1.txt &&
  printf 'CORRECTS HWGATE ZZ QEMU PASS\n' > evidence/R/CORRECTION-2.txt && $G add evidence && $G commit -qm add &&
  $G rm -q evidence/R/CORRECTION-1.txt && $G commit -qm delete &&
  printf 'nothing withdrawn\n' > evidence/R/CORRECTION-2.txt && $G commit -qam edit &&
  $G checkout -q -b side && mkdir -p evidence/S && printf 'CORRECTS HWGATE ZZ PHYSICAL PASS\n' > evidence/S/CORRECTION-3.txt &&
  $G add evidence && $G commit -qm side && $G checkout -q main && $G merge -q --no-ff --no-commit side &&
  $G rm -q -f evidence/S/CORRECTION-3.txt && $G commit -qm merge && $G branch -q -D side &&
  $G checkout -q -b side2 HEAD~1 && $G commit -q --allow-empty -m side2 && $G checkout -q main &&
  $G merge -q --no-ff --no-commit side2 && mkdir -p evidence/T && printf 'CORRECTS HWGATE ZZ HOST NOT_RUN\n' > evidence/T/CORRECTION-4.txt &&
  $G add evidence && $G commit -qm "merge that adds a correction" && $G branch -q -D side2 &&
  $G checkout -q -b side3 HEAD~1 && $G commit -q --allow-empty -m side3 && $G checkout -q main &&
  $G merge -q --no-ff --no-commit side3 && $G rm -q evidence/T/CORRECTION-4.txt && $G commit -qm "merge that drops it" &&
  $G branch -q -D side3 ) > "$W/wd.log" 2>&1; then
  wd "correction deleted, its line still withdrawn" 1 "CORRECTS HWGATE ZZ HOST PASS"
  wd "correction edited to drop its line, the line still withdrawn" 1 "CORRECTS HWGATE ZZ QEMU PASS"
  wd "correction dropped by the merge of its side branch, its line still withdrawn" 1 "CORRECTS HWGATE ZZ PHYSICAL PASS"
  wd "correction added and later dropped only by merge commits, its line still withdrawn" 1 "CORRECTS HWGATE ZZ HOST NOT_RUN"
  wd "a line no correction named is not withdrawn" 0 "CORRECTS HWGATE ZZ HOST FAIL"
else echo "FAIL planted withdrawals: cannot build the throwaway repository: $(tr '\n' ' ' < "$W/wd.log")"; fail=1; fi
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
  echo "PASS no cap: a $(wc -c < "$W/big/reg.tsv")-byte register of $SROWS rows citing a $(wc -c < "$W/big/evidence/BIG.txt")-byte receipt: $exp"; pass "no cap"
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
if [ "$big" = 0 ]; then echo "PASS sizes: $rows rows of $SROWS, every file at most $SBYTES bytes"; pass sizes; else fail=1; fi
# keyscmp KEYS: the checks that passed (KEYS, one per line) are tools/hwgates/checks.txt, once each
keyscmp() {
  grep -v '^#' "$CHECKS" | grep . | sort > "$W/kw" || true
  sort "$1" > "$W/kg"
  [ -s "$W/kw" ] && cmp -s "$W/kw" "$W/kg" && return 0
  comm -23 "$W/kw" "$W/kg" | sed 's/^/FAIL check listed in tools\/hwgates\/checks.txt but not passed: /'
  comm -13 "$W/kw" "$W/kg" | sed 's/^/FAIL check passed but not listed (or passed twice) in tools\/hwgates\/checks.txt: /'
  return 1
}
# planted control 12: the count is asserted: the list itself passes, and one check missing, one passed
# twice in place of another, or one unlisted check each fail keyscmp
grep -v '^#' "$CHECKS" | grep . > "$W/k0" || true
kc() { # NAME WANT FILE
  rc=0; keyscmp "$3" > /dev/null || rc=$?
  if [ "$rc" = "$2" ]; then echo "PASS planted $1 (exit $rc)"; pass "planted $1"; else echo "FAIL planted $1: keyscmp exit $rc, expected $2"; fail=1; fi
}
kc "check list compared with itself" 0 "$W/k0"
sed 1d "$W/k0" > "$W/k1"; kc "one check missing" 1 "$W/k1"
{ sed 1d "$W/k0"; sed -n 2p "$W/k0"; } > "$W/k2"; kc "one check passed twice in place of another" 1 "$W/k2"
{ cat "$W/k0"; echo "an unlisted check"; } > "$W/k3"; kc "an unlisted check" 1 "$W/k3"
# planted control 13: without history this gate is NOT_RUN (exit 3), not FAIL: a copy of it in a
# directory that is no git work tree, and in a shallow clone, each with the compiler pin beside it
for h in no-git shallow; do
  d=$W/nohist-$h; mkdir -p "$d/src/kernel/tools/hwgates" "$d/src/seed/out"
  cp "$ROOT/tools/hwgates/gate.sh" "$d/src/kernel/tools/hwgates/gate.sh"; cp "$ROOT/$PIN" "$d/src/seed/out/omc.sha256"
  if [ "$h" = shallow ]; then
    ( cd "$d/src" && $G init -q && $G add -A && $G commit -qm one && $G commit -q --allow-empty -m two &&
      $G clone -q --depth 1 "file://$d/src" "$d/run" ) > "$d/log" 2>&1 || true
  else mv "$d/src" "$d/run"; fi
  rc=0; ( cd "$d" && GIT_CEILING_DIRECTORIES=$d AIEN_OMC=$AIEN_OMC sh "$d/run/kernel/tools/hwgates/gate.sh" ) > "$d/out" 2>&1 || rc=$?
  if [ "$rc" = 3 ] && grep -q '^HWGATES-GATE NOT_RUN: .*\(git work tree\|shallow\)' "$d/out"; then echo "PASS planted $h: NOT_RUN (exit 3)"; pass "planted $h: NOT_RUN"
  else echo "FAIL planted $h: exit $rc, expected 3 with a history NOT_RUN line: $(tr '\n' ' ' < "$d/out" | cut -c1-200)"; fail=1; fi
done
# planted control 1: the first PHYSICAL row, whatever its status, claims PASS without a receipt -> R3
awk -F '\t' 'BEGIN{OFS="\t"} !done && !/^#/ && $4=="PHYSICAL" {$5="PASS"; $6="-"; done=1} {print}' "$REG" > "$W/p1.tsv"
planted "physical PASS without receipt" R3 "$W/p1.tsv"
# planted control 2: every PHYSICAL row removed -> R5
awk -F '\t' '$4!="PHYSICAL"' "$REG" > "$W/p2.tsv"
planted "register without physical rows" R5 "$W/p2.tsv"
# planted control 3: every row of the first gate with a receipt removed -> R9
gid=$(awk -F '\t' '!/^#/ && NF == 7 && $6 != "-" {print $1; exit}' "$REG")
awk -F '\t' -v g="$gid" '$1 != g' "$REG" > "$W/p3.tsv"
key="planted gate deleted while its receipt names it"; planted "gate $gid deleted while its receipt names it" R9 "$W/p3.tsv"
# planted control 4: comments only -> R8
grep '^#' "$REG" > "$W/p4.tsv" || true
planted "register without rows" R8 "$W/p4.tsv"
# planted control 5: the first gate's PHYSICAL row given its id in lower case -> R10
awk -F '\t' 'BEGIN{OFS="\t"} !done && !/^#/ && $4=="PHYSICAL" {$1=tolower($1); done=1} {print}' "$REG" > "$W/p5.tsv"
planted "a PHYSICAL row whose id differs from its gate's by case" R10 "$W/p5.tsv"
if [ "$fail" != 0 ]; then echo "HWGATES-GATE FAIL checks_passed=$n"; exit 1; fi
if [ "$notrun" != 0 ]; then echo "HWGATES-GATE NOT_RUN checks_passed=$n"; exit 3; fi
# every listed check passed exactly once, and nothing else counted
if keyscmp "$W/keys" > "$W/kc"; then echo "HWGATES-GATE PASS checks=$n"; exit 0; fi
cat "$W/kc"; echo "HWGATES-GATE FAIL checks_passed=$n listed=$(grep -v '^#' "$CHECKS" | grep -c .)"; exit 1
