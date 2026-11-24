#!/bin/sh
# Re-derive this folder's results from its stored run files. Needs only python3; runs on any machine.
# usage: sh tools/verify.sh        Prints EVIDENCE-VERIFY PASS and exits 0 only if everything agrees.
set -u
cd "$(dirname "$0")/.." || exit 1
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
python3 -I tools/results.py . > "$tmp" || { echo "EVIDENCE-VERIFY FAIL: a run check failed (see the generated output)"; exit 1; }
cmp -s "$tmp" RESULTS.md || { echo "EVIDENCE-VERIFY FAIL: RESULTS.md is not what tools/results.py generates"; diff "$tmp" RESULTS.md | head -20; exit 1; }
python3 -I tools/check-evidence.py . || { echo "EVIDENCE-VERIFY FAIL: REPORT.md or replay.txt disagrees with the stored files"; exit 1; }
for f in inputs.sha256 model.sha256 model-upstream.sha256; do
  [ -s "$f" ] || { echo "EVIDENCE-VERIFY FAIL: $f missing"; exit 1; }
done
echo "EVIDENCE-VERIFY PASS"
