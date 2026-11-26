#!/bin/sh
# om/units.sh -- thin compatibility shim over the pure seeded-Omega regenerator (seed/build/units.om).
# Keeps OMC_PIN and NATIVE_PIN at top level for legacy pin-reading scripts (seed/effects/check.sh, om/tls/test/*).
# Regenerates or checks (--check) src/{omega_om_units.c,omega_native.h,omega_api_decl.h,omega_om_units.ident,omega_om_units_fs.c}.
set -eu
OMC_PIN=8d7d50dc98061767e11af475af1ab5ec36fd51e9212068af16c25f9d5c265dfb
NATIVE_PIN=9788b27a92c8dd365de7052439653de62f89634189a34cb6b3f582cae65dda83
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SB="$ROOT/seed/build"
[ -f "$SB/units.om" ] || SB="$(pwd)/seed/build"
OMC_BOOT="$ROOT/seed/out/omc"
[ -x "$OMC_BOOT" ] || OMC_BOOT="${OMEGA_OMC:-$(pwd)/seed/out/omc}"
[ -x "$OMC_BOOT" ] || { echo "NOT_RUN: set OMEGA_OMC and OMEGA_BRIDGE"; exit 3; }
cd "$ROOT"
mkdir -p build
BIN="$ROOT/build/om-units.$$"
trap 'rm -f "$BIN"' EXIT
cat "$SB/common.om" "$SB/units.om" | "$OMC_BOOT" > "$BIN"
chmod 755 "$BIN"
rc=0
OMEGA_OMC_PIN="$OMC_PIN" OMEGA_NATIVE_PIN="$NATIVE_PIN" OMEGA_UNITS_DEST="${OMEGA_UNITS_DEST:-$ROOT/src}" \
  "$BIN" "$@" || rc=$?
exit "$rc"
