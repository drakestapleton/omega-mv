#!/bin/bash
# TEST INSTRUMENT (tests/landgate): exact existing-program compilation identity. No lowering or diagnostic exception.
# usage: samebytes.sh OLD_OMC NEW_OMC OUTDIR REPO@COMMIT...
set -u
OLD=$(readlink -f "$1"); NEW=$(readlink -f "$2"); OUT=$3; shift 3
mkdir -p "$OUT"; OUT=$(readlink -f "$OUT")
same=0; diff=0; errors=0
: > "$OUT/differ.tsv"; : > "$OUT/checker-errors.txt"
ce() { errors=$((errors+1)); echo "$*" >> "$OUT/checker-errors.txt"; echo "SAMEBYTES CHECKER ERROR $*"; }
for c in "$OLD" "$NEW"; do [ -x "$c" ] || { echo "SAMEBYTES FAIL missing executable $c"; exit 1; }; done
{
 echo "SAMEBYTES old $OLD sha256 $(sha256sum "$OLD" | cut -d' ' -f1)"
 echo "SAMEBYTES new $NEW sha256 $(sha256sum "$NEW" | cut -d' ' -f1)"
 echo "SAMEBYTES instrument $(readlink -f "$0") sha256 $(sha256sum "$0" | cut -d' ' -f1)"
 echo 'SAMEBYTES policy exact exit/stdout/stderr; no changed-lowering exceptions'
} | tee "$OUT/header.txt"
for rc in "$@"; do
 repo=${rc%@*}; commit=${rc#*@}
 full=$(git -C "$repo" rev-parse "$commit^{commit}") || { ce "missing commit $rc"; continue; }
 echo "SAMEBYTES corpus $repo commit $full tree $(git -C "$repo" rev-parse "$full^{tree}")" | tee -a "$OUT/header.txt"
 git -C "$repo" ls-tree -r --name-only "$full" > "$OUT/all" || { ce "ls-tree $rc"; continue; }
 grep '\.om$' "$OUT/all" > "$OUT/files"; r=$?; [ "$r" -le 1 ] || { ce 'file-list filter'; continue; }
 if [ -n "${SAMEBYTES_ONLY:-}" ]; then
   grep -E -- "$SAMEBYTES_ONLY" "$OUT/files" > "$OUT/selected"; r=$?
   [ "$r" -le 1 ] || { ce 'invalid selection pattern'; continue; }
   mv "$OUT/selected" "$OUT/files"
 fi
 while read -r f; do
   git -C "$repo" show "$full:$f" > "$OUT/unit.om" 2> "$OUT/source.err" || { ce "source unavailable $repo@$full:$f"; continue; }
   timeout 60 "$OLD" < "$OUT/unit.om" > "$OUT/old.bin" 2> "$OUT/old.err"; a=$?
   timeout 60 "$NEW" < "$OUT/unit.om" > "$OUT/new.bin" 2> "$OUT/new.err"; b=$?
   if [ "$a" -gt 30 ] || [ "$b" -gt 30 ]; then ce "abnormal compiler exit $repo:$f actual_exit=$a/$b"; continue; fi
   if [ "$a" = "$b" ] && cmp -s "$OUT/old.bin" "$OUT/new.bin" && cmp -s "$OUT/old.err" "$OUT/new.err"; then
     same=$((same+1))
   else
     diff=$((diff+1))
     printf '%s\t%s\t%s/%s\t%s/%s\t%s/%s\n' "$repo@$full" "$f" "$a" "$b" "$(sha256sum "$OUT/old.bin" | cut -d' ' -f1)" "$(sha256sum "$OUT/new.bin" | cut -d' ' -f1)" "$(sha256sum "$OUT/old.err" | cut -d' ' -f1)" "$(sha256sum "$OUT/new.err" | cut -d' ' -f1)" >> "$OUT/differ.tsv"
   fi
 done < "$OUT/files"
done
echo "SAMEBYTES same=$same differ=$diff checker_errors=$errors" | tee -a "$OUT/header.txt"
[ "$same" -gt 0 ] && [ "$diff" = 0 ] && [ "$errors" = 0 ]
