#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# tests/landgate/merge-residue.sh: TEST INSTRUMENT. No merge residue (a line starting "<<<<<<< " or ">>>>>>> ", or a
# line that is exactly "=======") in any tracked text file outside evidence/. A clean result is believed only when the
# scan was observed to complete: the tracked-file listing succeeds and is not empty; git grep exits 1 (scanned, nothing
# found) with no output; and a second git grep finds this instrument's own text, which shows that git grep reads this
# checkout. git grep exit 0 or any output is residue. Any other exit means the scan did not run: that is a failure
# ("MERGE-RESIDUE SCAN FAILED"), never "no residue".
# usage: merge-residue.sh      (inside a checkout)     exit 0 "MERGE-RESIDUE PASS files=N", else 1
set -u
cd "$(git rev-parse --show-toplevel)" || { echo "MERGE-RESIDUE SCAN FAILED: not inside a git checkout"; exit 1; }
lst=$(git ls-files -- . ':!evidence'); ls=$?; n=$(printf '%s' "$lst" | grep -c .)
[ "$ls" = 0 ] && [ "$n" -gt 0 ] || { echo "MERGE-RESIDUE SCAN FAILED: tracked-file listing exit $ls, $n files"; exit 1; }
out=$(git grep -n -I -E '^(<<<<<<< |=======$|>>>>>>> )' -- . ':!evidence'); rc=$?
[ "$rc" -le 1 ] || { echo "MERGE-RESIDUE SCAN FAILED: git grep exit $rc"; exit 1; }  # scan-exit predicate
[ -z "$out" ] || { printf '%s\n' "$out"; echo "MERGE-RESIDUE FAIL lines=$(printf '%s\n' "$out" | wc -l) files=$n"; exit 1; }
[ "$rc" = 1 ] || { echo "MERGE-RESIDUE SCAN FAILED: git grep exit $rc with no output"; exit 1; }  # scan-exit predicate
git grep -q -I -F 'MERGE-RESIDUE SCAN FAILED: probe' -- tests/landgate/merge-residue.sh ||
  { echo "MERGE-RESIDUE SCAN FAILED: probe: git grep does not find this instrument's own text"; exit 1; }
echo "MERGE-RESIDUE PASS files=$n: no line starts with '<<<<<<< ' or '>>>>>>> ' or is exactly '=======' in tracked text files outside evidence/"
