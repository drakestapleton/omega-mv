#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# parity_check.sh -- the C-to-OM retirement check (REVIEW-LESSONS.md "C to OM migration";
# corrective actions CA-1 and CA-2 of the waves 29-36 review). Run by `make check-retirement`.
#
# CA-1. Every C file the change deletes, and every C file whose same-stem .om the change adds or
# edits outside tests/ (a replacement that a shipped OM binary can reach), needs a `c` row in
# docs/migration/PARITY.tsv. The row names the make target holding the C-vs-OM differential for
# it, and lists EVERY function the C file defines with external linkage (tools/migration/
# cfuncs.awk; read from the working tree when the row's ref is `live`, else from the row's ref
# commit) exactly once: as covered by that target, or as excluded with a reason. The check fails
# on a missing row, a target no Makefile or mk/*.mk rule defines, an unlisted or unknown
# function, a function listed twice, an exclusion without a reason, a `live` row whose C file is
# gone, or a ref commit that does not hold the file.
# CA-2. Every nm, objdump or grep check line in mk/ and tests/ that names a deleted C file or the
# object of one (its stem with .c or .o) fails unless the same file also names an existing .om
# source or an OM_SRCS source list (the check scans the OM replacement too), or a `check` row
# lists that file and stem with a reason.
#
# PARITY.tsv columns (tab separated, `#` lines are comments):
#   c      <C path> <ref: live | commit> <make target | - (none)> <covered: a,b,...|-> <excluded: name=reason;...|->
#          (a row with no differential target covers nothing: every function is excluded with a reason)
#   check  <file> <deleted C stem> - - <reason>
# usage: tools/migration/parity_check.sh   env: PARITY_BASE (default: merge-base of HEAD and
#   origin/main), PARITY_TSV (default docs/migration/PARITY.tsv), PARITY_MK (default: Makefile and
#   mk/*.mk), PARITY_SCAN (default: mk and tests; where CA-2 looks)
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT" || exit 2
TSV=${PARITY_TSV:-docs/migration/PARITY.tsv}
BASE=${PARITY_BASE:-$(git merge-base HEAD origin/main 2>/dev/null || echo)}
MKS=${PARITY_MK:-"Makefile $(ls mk/*.mk | tr '\n' ' ')"}
SCAN=${PARITY_SCAN:-"mk tests"}
AWKF=tools/migration/cfuncs.awk
W=$(mktemp -d "${TMPDIR:-/tmp}/parity.XXXXXX") || exit 2
trap 'rm -rf "$W"' EXIT INT TERM
fail=0
err() { printf 'PARITY_CHECK FAIL %s\n' "$*"; fail=1; }

[ -f "$TSV" ] || { echo "PARITY_CHECK FAIL missing $TSV"; exit 1; }
[ -n "$BASE" ] && git cat-file -e "$BASE^{commit}" 2>/dev/null || { echo "PARITY_CHECK FAIL no base commit (set PARITY_BASE)"; exit 1; }

# ---- the C files that need a row ----
git diff --name-only --diff-filter=D "$BASE"...HEAD -- '*.c' | sort -u > "$W/deleted"
git diff --name-only --diff-filter=AMR "$BASE"...HEAD -- '*.om' | grep -v '^tests/' | while read -r om; do
  [ -f "${om%.om}.c" ] && echo "${om%.om}.c"
done | sort -u > "$W/samestem"
cat "$W/deleted" "$W/samestem" | sort -u > "$W/required"
awk -F'\t' '!/^#/ && $1 == "c" { print $2 }' "$TSV" | sort > "$W/rows"
dup=$(uniq -d "$W/rows")
[ -z "$dup" ] || err "more than one row for: $dup"
for c in $(comm -23 "$W/required" "$W/rows"); do
  if grep -qx "$c" "$W/deleted"; then err "$c is deleted by this change and has no row in $TSV"
  else err "$c has a same-stem .om changed by this change and no row in $TSV"; fi
done

# ---- every make target any rule defines ----
awk '/^[A-Za-z0-9_.%$()\/ -]+:([^=]|$)/ { sub(/:.*/, ""); n = split($0, t, " "); for (i = 1; i <= n; i++) print t[i] }' $MKS | sort -u > "$W/targets"

# ---- each c row ----
nrow=0; nfun=0; ncov=0; nexc=0
awk -F'\t' '!/^#/ && $1 == "c"' "$TSV" > "$W/crows"
while IFS="$(printf '\t')" read -r kind cpath ref target covered excluded; do
  nrow=$((nrow + 1))
  [ -n "$cpath" ] && [ -n "$ref" ] && [ -n "$target" ] && [ -n "$covered" ] && [ -n "$excluded" ] \
    || { err "row $nrow ($cpath) does not have 6 columns"; continue; }
  if [ "$target" = - ]; then
    [ "$covered" = - ] || err "$cpath: covers functions but names no differential target"
  else
    grep -qx -- "$target" "$W/targets" || err "$cpath: target $target is defined by no rule in Makefile or mk/*.mk"
  fi
  if [ "$ref" = live ]; then
    [ -f "$cpath" ] || { err "$cpath: row says live but the file is not in the tree"; continue; }
    awk -f "$AWKF" "$cpath" > "$W/funcs"
  else
    git cat-file -e "$ref:$cpath" 2>/dev/null || { err "$cpath: not in ref commit $ref"; continue; }
    git show "$ref:$cpath" | awk -f "$AWKF" > "$W/funcs"
  fi
  [ -s "$W/funcs" ] || err "$cpath: no function found (extractor failed?)"
  : > "$W/listed"
  [ "$covered" = - ] || printf '%s\n' "$covered" | tr ',' '\n' | sed '/^$/d' >> "$W/listed"
  if [ "$excluded" != - ]; then
    printf '%s\n' "$excluded" | tr ';' '\n' | sed '/^$/d' > "$W/exc"
    while read -r e; do
      name=${e%%=*}; reason=${e#*=}
      { [ "$name" != "$e" ] && [ -n "$(printf '%s' "$reason" | tr -d ' ')" ]; } || err "$cpath: exclusion '$e' has no reason"
      echo "$name" >> "$W/listed"
    done < "$W/exc"
    nexc=$((nexc + $(grep -c . "$W/exc")))
  fi
  [ "$covered" = - ] || ncov=$((ncov + $(printf '%s\n' "$covered" | tr ',' '\n' | grep -c .)))
  sort "$W/listed" | uniq -d | while read -r d; do echo "PARITY_CHECK FAIL $cpath: $d is listed twice"; done | grep . && fail=1
  for f in $(sort -u "$W/funcs"); do grep -qx -- "$f" "$W/listed" || err "$cpath: function $f is neither covered by $target nor excluded with a reason"; done
  for f in $(sort -u "$W/listed"); do grep -qx -- "$f" "$W/funcs" || err "$cpath: lists $f, which the C file does not define"; done
  nfun=$((nfun + $(sort -u "$W/funcs" | grep -c .)))
done < "$W/crows"

# ---- CA-2: checks whose input was retired C ----
awk -F'\t' '!/^#/ && $1 == "check" { print $2 "\t" $3 "\t" $6 }' "$TSV" > "$W/checks"
nck=0
for c in $(cat "$W/deleted"); do
  stem=$(basename "$c" .c)
  # shellcheck disable=SC2086
  grep -rnE "(^|[^A-Za-z0-9_])(nm|objdump|grep)([^A-Za-z0-9_]|$)" $SCAN 2>/dev/null \
    | grep -E "(^|[^A-Za-z0-9_])$stem\.(c|o)([^A-Za-z0-9_]|$)" > "$W/hits" || true
  while IFS= read -r h; do
    file=${h%%:*}
    nck=$((nck + 1))
    # scans OM: the file names an existing .om source, or an *OM_SRCS* source list
    if grep -q 'OM_SRCS' "$file"; then continue; fi
    scans=0
    for om in $(grep -oE '[A-Za-z0-9_./-]+\.om([^A-Za-z0-9_]|$)' "$file" | sed -E 's/[^A-Za-z0-9_]$//' | sort -u); do
      [ -f "$om" ] && { scans=1; break; }
    done
    [ "$scans" -eq 1 ] && continue
    awk -F'\t' -v f="$file" -v s="$stem" '$1 == f && $2 == s && $3 != "" { ok = 1 } END { exit !ok }' "$W/checks" \
      || err "CA-2: $file runs a check on retired C $stem ($h) and scans no OM source; add the OM scan or a check row with a reason"
  done < "$W/hits"
done

if [ "$fail" -ne 0 ]; then echo "PARITY_CHECK FAIL base=$BASE rows=$nrow"; exit 1; fi
echo "PARITY_CHECK PASS base=$BASE required=$(grep -c . "$W/required") rows=$nrow functions=$nfun covered=$ncov excluded=$nexc retired-C-checks=$nck"
