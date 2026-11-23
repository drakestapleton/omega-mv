#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# om/tls/build.sh -- compatibility entry point over pure seeded-Omega seed/build/tlsbuild.om.
# Usage: sh om/tls/build.sh OMC PROGRAM.om OUT
#        sh om/tls/build.sh -p OMC BIN
# Works both in-tree and when copied into an isolated mutant scratch directory, preserves caller
# relative paths (no cd), and honors OMTLS_RUN.
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)

# Locate seed/build without assuming dirname($0)/../.. is the repository root.
SB=""
d="$HERE"
while :; do
  if [ -f "$d/seed/build/common.om" ] && [ -f "$d/seed/build/tlsbuild.om" ]; then
    SB="$d/seed/build"
    break
  fi
  parent=$(dirname "$d")
  [ "$parent" = "$d" ] && break
  d="$parent"
done
if [ -z "$SB" ] && [ -f "$PWD/seed/build/common.om" ] && [ -f "$PWD/seed/build/tlsbuild.om" ]; then
  SB="$PWD/seed/build"
fi
if [ -z "$SB" ] && [ -n "${OMEGA_ROOT:-}" ] && [ -f "$OMEGA_ROOT/seed/build/common.om" ] && [ -f "$OMEGA_ROOT/seed/build/tlsbuild.om" ]; then
  SB="$OMEGA_ROOT/seed/build"
fi

# Resolve OMTLS_RUN to an executable path when set (execprog does not search PATH).
RUN_BIN=""
if [ -n "${OMTLS_RUN:-}" ]; then
  case "$OMTLS_RUN" in
    /*) RUN_BIN="$OMTLS_RUN" ;;
    *)  RUN_BIN=$(command -v "$OMTLS_RUN" 2>/dev/null || printf '%s' "$OMTLS_RUN") ;;
  esac
fi

OMC_ARG="${1:-}"
if [ "$OMC_ARG" = "-p" ]; then OMC_ARG="${2:-}"; fi

# Use pure seeded-Omega tlsbuild.om when seed/build is available, OMC is a single executable path,
# and we can execute AArch64 binaries (native Linux-aarch64 or via OMTLS_RUN).
can_run_om=0
if [ -n "$SB" ] && [ -n "$OMC_ARG" ] && [ -x "$OMC_ARG" ]; then
  if [ "$(uname -s)-$(uname -m)" = "Linux-aarch64" ]; then
    can_run_om=1
  fi
fi

if [ "$can_run_om" -eq 1 ]; then
  BIN="${TMPDIR:-/tmp}/om-tlsbuild.$$"
  trap 'rm -f "$BIN"' EXIT INT TERM
  cat "$SB/common.om" "$SB/tlsbuild.om" | "$OMC_ARG" > "$BIN"
  chmod 755 "$BIN"
  rc=0
  OMTLS_DIR="$HERE" OMTLS_RUN="$RUN_BIN" "$BIN" "$@" || rc=$?
  exit "$rc"
fi

# Standalone / cross-runner fallback (e.g. isolated temp copy without seed/build or multi-word OMC).
units() { for u in sha2 hkdf drbg x25519 sha3 mlkem chacha aesgcm ec ecdh rsa x509 rev fips tls; do cat "$HERE/$u.om"; done; }
run_omc() {
  if [ -x "$1" ]; then "$1"
  else
    # shellcheck disable=SC2086
    $1
  fi
}
integ() {
  { printf 'om2\n'; units; printf 'fn main to int\nret fips_itool\nend\n'; } > "$2.itool.om"
  if run_omc "$1" < "$2.itool.om" > "$2.itool" 2> "$2.itool.err"; then :; else
    rc=$?; cat "$2.itool.err" >&2; rm -f "$2.itool" "$2.itool.om" "$2.itool.err"; return "$rc"
  fi
  chmod +x "$2.itool"
  rc=0; ${OMTLS_RUN:+"$OMTLS_RUN"} "$2.itool" "$2" || rc=$?
  rm -f "$2.itool" "$2.itool.om" "$2.itool.err"
  [ "$rc" -eq 0 ] || echo "build.sh: integrity step failed on $2 (tool exit $rc)" >&2
  return "$rc"
}
if [ "${1:-}" = -p ]; then
  omc=${2:?usage: build.sh -p OMC BIN}; bin=${3:?usage: build.sh -p OMC BIN}
  integ "$omc" "$bin"; exit
fi
omc=${1:?usage: build.sh OMC PROGRAM.om OUT}; prog=${2:?}; out=${3:?}
{ printf 'om2\n'; units; cat "$prog"; } > "$out.unit.om"
rm -f "$out"
if run_omc "$omc" < "$out.unit.om" > "$out.tmp" 2> "$out.err"; then
  rm -f "$out.err"
else
  rc=$?; rm -f "$out.tmp"; cat "$out.err" >&2; exit "$rc"
fi
if integ "$omc" "$out.tmp"; then
  mv "$out.tmp" "$out"; chmod +x "$out"
else
  rc=$?; rm -f "$out.tmp"; exit "$rc"
fi
