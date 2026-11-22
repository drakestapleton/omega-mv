#!/bin/sh
# Drop the unsupported-return and refused checks. Leave the p.known test in
# place. The named assertions must fail: a prediction can be marked known and
# still be a refusal.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
src=tools/dagsim/dagsim.om
unit=tests/dagsim/dagsim_unit.om
OMC=${OMC:-seed/out/omc}
grep -q 'PREDICT_REFUSAL_CHECK_START' "$src"
grep -q 'PREDICT_REFUSAL_CHECK_END' "$src"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
sed '/PREDICT_REFUSAL_CHECK_START/,/PREDICT_REFUSAL_CHECK_END/d' "$src" > "$tmp/dagsim.om"
if cmp -s "$src" "$tmp/dagsim.om"; then
  echo "mutant: failed to drop PREDICT_REFUSAL_CHECK block"
  exit 1
fi
grep -q 'fn dr_bad' "$tmp/dagsim.om" || { echo "mutant: deleted dr_bad"; exit 1; }

cat "$tmp/dagsim.om" "$unit" | "$OMC" > "$tmp/unit"
chmod +x "$tmp/unit"
set +e
"$tmp/unit" > "$tmp/out" 2>&1
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
  echo "mutant survived: unit suite passed after dropping the predict refusal check"
  exit 1
fi
if ! grep -q 'predict_unsupported_despite_known' "$tmp/out"; then
  echo "mutant did not fail named assertion predict_unsupported_despite_known"
  cat "$tmp/out"
  exit 1
fi
if ! grep -q 'predict_refused_despite_known' "$tmp/out"; then
  echo "mutant did not fail named assertion predict_refused_despite_known"
  cat "$tmp/out"
  exit 1
fi
echo "mutant killed: predict_unsupported_despite_known predict_refused_despite_known"
