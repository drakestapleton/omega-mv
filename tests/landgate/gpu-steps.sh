#!/bin/sh
# TEST INSTRUMENT. The landing campaign names the AMD and GPU host gates and
# marks them requires: gb10, so a landing record includes them without taking
# the chip. It does not run them.
set -eu
ROOT=${1:-.}
cd "$ROOT"
fail=0
for step in gpu-amd gpu-amd-rest gpu-runtime gpu-checks bridge-nvml shlib gpu-units; do
  if ! grep -q "gb10 $step " tests/landgate/run.sh; then
    echo "FAIL missing $step"
    fail=1
  else
    echo "ok $step"
  fi
done
if ! grep -q 'requires: gb10' tests/landgate/run.sh; then
  echo "FAIL missing requires: gb10"
  fail=1
fi
if ! grep -q 'LANDGATE_GB10' tests/landgate/run.sh; then
  echo "FAIL missing LANDGATE_GB10"
  fail=1
fi
[ "$fail" = 0 ]
echo "GPU-STEPS PASS"
