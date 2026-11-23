#!/bin/sh
# om/units.sh -- thin compatibility shim over the pure seeded-Omega regenerator (seed/build/units.om).
# Keeps OMC_PIN and NATIVE_PIN at top level for legacy pin-reading scripts (seed/effects/check.sh, om/tls/test/*).
# Regenerates or checks (--check) src/{omega_om_units.c,omega_native.h,omega_api_decl.h,omega_om_units.ident,omega_om_units_fs.c}.
set -eu
OMC_PIN=708fdc0f81866594ed6df2f492b7a8a6bc7456f2d733a838b7f840549ebba6c3
NATIVE_PIN=9788b27a92c8dd365de7052439653de62f89634189a34cb6b3f582cae65dda83

# Check required env vars and host architecture BEFORE invoking any AArch64 binary.
[ -n "${OMEGA_OMC:-}" ] && [ -n "${OMEGA_BRIDGE:-}" ] || { echo "NOT_RUN: set OMEGA_OMC and OMEGA_BRIDGE"; exit 3; }
[ "$(uname -s)-$(uname -m)" = "Linux-aarch64" ] || { echo "NOT_RUN: om/units.sh requires Linux aarch64"; exit 3; }

CALLER_PWD="$PWD"
abs_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *)  printf '%s/%s\n' "$CALLER_PWD" "$1" ;;
  esac
}

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
OMEGA_OMC=$(abs_path "$OMEGA_OMC")
OMEGA_BRIDGE=$(abs_path "$OMEGA_BRIDGE")
if [ -n "${OMEGA_UNITS_DEST:-}" ]; then
  OMEGA_UNITS_DEST=$(abs_path "$OMEGA_UNITS_DEST")
else
  OMEGA_UNITS_DEST="$ROOT/src"
fi
export OMEGA_OMC OMEGA_BRIDGE OMEGA_UNITS_DEST

[ -x "$OMEGA_OMC" ] || { echo "NOT_RUN: omc is not executable ($OMEGA_OMC)"; exit 3; }
[ -f "$OMEGA_BRIDGE/src/native.om" ] || { echo "NOT_RUN: native.om not found under $OMEGA_BRIDGE"; exit 3; }

SB="$ROOT/seed/build"
[ -f "$SB/units.om" ] || SB="$CALLER_PWD/seed/build"
[ -f "$SB/units.om" ] || { echo "FAIL: seed/build/units.om not found"; exit 1; }

cd "$ROOT"
mkdir -p build
BIN="$ROOT/build/om-units.$$"
trap 'rm -f "$BIN"' EXIT INT TERM
cat "$SB/common.om" "$SB/units.om" | "$OMEGA_OMC" > "$BIN"
chmod 755 "$BIN"
rc=0
OMEGA_OMC_PIN="$OMC_PIN" OMEGA_NATIVE_PIN="$NATIVE_PIN" "$BIN" "$@" || rc=$?
exit "$rc"
