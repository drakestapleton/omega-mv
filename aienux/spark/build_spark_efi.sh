#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# aienux/spark/build_spark_efi.sh -- thin compatibility shim over pure seeded-Omega seed/build/sparkefi.om.
# Zero Python on the bare-metal SPARK.EFI delivery path (word-boundary namespacing + PE32+ verification
# all execute inside pure seeded Omega).
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
OMC="${OMC:-$ROOT/seed/out/omc}"
[ -x "$OMC" ] || { echo "FAIL: omc compiler not executable at $OMC (set OMC=/path/to/omc)" >&2; exit 1; }
cd "$ROOT"
mkdir -p build
BIN="$ROOT/build/om-sparkefi.$$"
trap 'rm -f "$BIN"' EXIT
cat seed/build/common.om seed/build/sparkefi.om | "$OMC" > "$BIN"
chmod 755 "$BIN"
rc=0
OMC="$OMC" "$BIN" "$@" || rc=$?
exit "$rc"
