#!/bin/sh
# Drop the inverted-lifetime check and require the named assertion to fail.
# A mutant that still prints a passing inverted_lifetime_masks_overflow is a miss.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
src=tools/dagsim/dagsim.om
unit=tests/dagsim/dagsim_unit.om
OMC=${OMC:-seed/out/omc}
grep -q 'LIFETIME_ORDER_CHECK' "$src"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
sed '/LIFETIME_ORDER_CHECK/{n;s/dag_life m s/ulong 0/;}' "$src" > "$tmp/dagsim.om"
if cmp -s "$src" "$tmp/dagsim.om"; then
  echo "mutant: failed to drop LIFETIME_ORDER_CHECK call"
  exit 1
fi
grep -q 'fn dag_life' "$tmp/dagsim.om" || { echo "mutant: deleted more than the call"; exit 1; }

cat "$tmp/dagsim.om" "$unit" | "$OMC" > "$tmp/unit"
chmod +x "$tmp/unit"
set +e
"$tmp/unit" > "$tmp/out" 2>&1
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
  echo "mutant survived: unit suite passed after dropping LIFETIME_ORDER_CHECK"
  exit 1
fi
if ! grep -q 'inverted_lifetime_masks_overflow' "$tmp/out"; then
  echo "mutant did not fail named assertion inverted_lifetime_masks_overflow"
  cat "$tmp/out"
  exit 1
fi
echo "mutant killed: inverted_lifetime_masks_overflow"
