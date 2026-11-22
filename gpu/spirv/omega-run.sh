#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
# gpu/spirv/omega-run.sh -- thin compatibility shim over pure seeded-Omega seed/build/gpucoord.om.
# Usage: sh gpu/spirv/omega-run.sh vadd|fsum16|gemm16|rmsnorm cl|vk
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
OMC="${OMC:-$ROOT/seed/out/omc}"
cd "$ROOT"
mkdir -p build
BIN="$ROOT/build/om-gpucoord.$$"
trap 'rm -f "$BIN"' EXIT
cat seed/build/common.om seed/build/gpucoord.om | "$OMC" > "$BIN"
chmod 755 "$BIN"
rc=0
OMC="$OMC" "$BIN" spirv-run "$@" || rc=$?
exit "$rc"
