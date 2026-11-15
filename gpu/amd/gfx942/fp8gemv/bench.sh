#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
# Correctness first. Bandwidth only on a machine that has the device.
# The denominator, when a run happens, is the published MI300X HBM peak of
# 5.3 TB/s. This script never prints a measured GB/s of its own.
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
"$HERE/check.sh"

echo "shapes M in 4096 8192 14336 28672, K in 4096 8192, batch 1"
echo "flags: bit0 row remap, bit1 residual+rmsnorm scale, bit2 bf16 store"
echo "peak denominator 5.3 TB/s (published MI300X HBM peak, not a measurement)"

if [ ! -e /dev/kfd ]; then
  echo "BLOCKED_HARDWARE no /dev/kfd"
  echo "on the MI300X, after the code object is loaded, run this same script"
  echo "hipblaslt-bench: take the FP8 type token from hipblaslt-bench --help"
  echo "rocprof --stats --kernel fp8gemv_stream <launcher>"
  echo "omniperf profile -n fp8gemv -- <launcher>"
  exit 0
fi

echo "BLOCKED_HARDWARE /dev/kfd is present but this tree has no KFD launcher for fp8gemv_stream"
echo "do not treat a host timing as a device timing"
exit 0
