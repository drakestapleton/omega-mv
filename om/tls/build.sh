#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# om/tls/build.sh -- thin compatibility shim over pure seeded-Omega seed/build/tlsbuild.om.
# Usage: sh om/tls/build.sh OMC PROGRAM.om OUT
#        sh om/tls/build.sh -p OMC BIN
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
OMC_ARG="${1:-}"
if [ "$OMC_ARG" = "-p" ]; then OMC_ARG="${2:-}"; fi
OMC_BOOT="${OMC_ARG:-$ROOT/seed/out/omc}"
[ -x "$OMC_BOOT" ] || OMC_BOOT="$ROOT/seed/out/omc"
mkdir -p "$ROOT/build"
BIN="$ROOT/build/om-tlsbuild.$$"
trap 'rm -f "$BIN"' EXIT
cat "$ROOT/seed/build/common.om" "$ROOT/seed/build/tlsbuild.om" | "$OMC_BOOT" > "$BIN"
chmod 755 "$BIN"
rc=0
(cd "$ROOT" && "$BIN" "$@") || rc=$?
exit "$rc"
