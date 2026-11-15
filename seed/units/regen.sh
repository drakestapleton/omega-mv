#!/bin/sh
# Rewrite the generated C bindings so they name the compiler in seed/out/omc.sha256.
#
#   sh seed/units/regen.sh
#   sh seed/units/regen.sh --check
#
# --check exits 1 when a committed binding differs, and writes nothing. Either
# way the compiler must already be seed/out/omc and must match the sidecar.
# Build that compiler with sh seed/omega-from-seed.sh first. After a rewrite,
# commit the five files under src/ before the seed gate: the host check refuses
# a dirty checkout.
#
# The generator is omega-bridge src/native.om at the commit in om/omega-bridge.lock,
# compiled by seed/out/omc (om/units.sh). This step does not call tools/bridge-seeded
# or tools/bridge-freest. Those two refuse any compiler other than the one
# fingerprint typed in them, and they exit 65. That fingerprint qualifies an
# older frontend for a different entry point. native.om has no compiler fingerprint,
# so a new sidecar compiler can compile it.
#
# OMEGA_BRIDGE, when set, is a checkout whose src/native.om matches the generator
# pin in om/units.sh. Otherwise the file is read from OMEGA_BRIDGE_GIT (default
# $HOME/git/omega-bridge.git) at the lock commit. Nothing in that repository is modified.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
case ${1:-} in
''|--check) ;;
*) echo 'usage: sh seed/units/regen.sh [--check]' >&2; exit 2 ;;
esac
. "$ROOT/seed/omc-pin.sh"
OMC_PIN_ROOT=$ROOT
omc_pin_load || { echo 'NOT_RUN: seed/out/omc.sha256 has no compiler pin'; exit 3; }
OMC=$ROOT/seed/out/omc
[ -f "$OMC" ] || { echo 'NOT_RUN: seed/out/omc is missing; run sh seed/omega-from-seed.sh'; exit 3; }
have=$(sha256sum < "$OMC" | cut -c1-64)
[ "$have" = "$OMC_PIN" ] || { echo "FAIL: seed/out/omc sha256 $have disagrees with seed/out/omc.sha256 pin $OMC_PIN"; exit 1; }
native=$(sed -n 's/^NATIVE_PIN=//p' "$ROOT/om/units.sh")
lock=$(awk 'NF && $1 !~ /^#/ { print $1; exit }' "$ROOT/om/omega-bridge.lock")
case $lock in
*[!0-9a-f]*|'') echo 'NOT_RUN: om/omega-bridge.lock has no commit'; exit 3 ;;
esac
[ ${#lock} -eq 40 ] || { echo 'NOT_RUN: om/omega-bridge.lock has no commit'; exit 3; }
owned=''
if [ -n "${OMEGA_BRIDGE:-}" ]; then
    bridge=$OMEGA_BRIDGE
else
    gitdir=${OMEGA_BRIDGE_GIT:-$HOME/git/omega-bridge.git}
    [ -d "$gitdir" ] || { echo "NOT_RUN: no omega-bridge git at $gitdir"; exit 3; }
    owned=$(mktemp -d)
    trap 'rm -rf "$owned"' EXIT HUP INT TERM
    git -C "$gitdir" archive "$lock" src/native.om | tar -x -C "$owned"
    bridge=$owned
fi
got=$(sha256sum < "$bridge/src/native.om" | cut -c1-64)
[ "$got" = "$native" ] || { echo "FAIL: src/native.om sha256 $got disagrees with om/units.sh generator pin $native"; exit 1; }
OMEGA_OMC=$OMC OMEGA_BRIDGE=$bridge nice -n 19 sh "$ROOT/om/units.sh" ${1:+"$1"}
