#!/bin/sh
# TEST INSTRUMENT. The wording this branch added must not say Radicle.
# Older history that already said it is left where it was.
set -eu
ROOT=${1:-.}
cd "$ROOT"
fail=0
for f in tests/landgate/run.sh seed/host/EFFECT-MATRIX.md seed/host/affinity/sched.om seed/omc/keyword-users.om; do
  if grep -q 'Radicle' "$f"; then
    echo "FAIL $f still says Radicle"
    grep -n 'Radicle' "$f"
    fail=1
  else
    echo "ok $f"
  fi
done
if grep -q 'Radicle issue a02876a' CONTRIBUTORS.md; then
  echo "FAIL CONTRIBUTORS.md still cites Radicle issue a02876a"
  fail=1
else
  echo "ok CONTRIBUTORS.md dropped the new issue citation"
fi
[ "$fail" = 0 ]
echo "NO-NEW-RADICLE PASS"
