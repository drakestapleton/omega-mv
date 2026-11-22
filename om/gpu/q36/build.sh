#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# om/gpu/q36/build.sh -- thin compatibility shim over pure seeded-Omega seed/build/gpucoord.om.
set -eu
out=${1:?usage: sh om/gpu/q36/build.sh OUTPUT_DIR}
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
OMC="${OMC:-$ROOT/seed/out/omc}"
cd "$ROOT"
mkdir -p build
BIN="$ROOT/build/om-gpucoord.$$"
trap 'rm -f "$BIN"' EXIT
cat seed/build/common.om seed/build/gpucoord.om | "$OMC" > "$BIN"
chmod 755 "$BIN"
rc=0
OMC="$OMC" "$BIN" build-q36 "$out" || rc=$?
exit "$rc"
