#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Drake Stapleton (AIEN / aien-dev)
# Host-only regression controls for tools/pinned_checkout.sh. No network or GPU.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TOOL="$ROOT/tools/pinned_checkout.sh"
SCR="$(mktemp -d "${TMPDIR:-/tmp}/omega-pin-test.XXXXXX")"
trap 'chmod -R u+w "$SCR" 2>/dev/null || true; rm -rf "$SCR"' EXIT
SRC="$SCR/source"
PASS=0

check() {
    local title=$1
    shift
    if "$@"; then PASS=$((PASS + 1)); else echo "FAIL $title" >&2; exit 1; fi
}
refuse() { ! "$@" >/dev/null 2>&1; }

git init -q "$SRC"
git -C "$SRC" config user.name pin-test
git -C "$SRC" config user.email pin-test@example.invalid
printf 'locked bytes\n' > "$SRC/regular"
printf '#!/bin/sh\nexit 0\n' > "$SRC/executable"
chmod 755 "$SRC/executable"
ln -s regular "$SRC/link"
git -C "$SRC" add regular executable link
git -C "$SRC" commit -qm locked
LOCK=$(git -C "$SRC" rev-parse HEAD)
TREE=$(git -C "$SRC" rev-parse "$LOCK^{tree}")

printf 'replacement bytes\n' > "$SRC/regular"
git -C "$SRC" add regular
git -C "$SRC" commit -qm replacement
REPLACEMENT=$(git -C "$SRC" rev-parse HEAD)
git -C "$SRC" replace "$LOCK" "$REPLACEMENT"
git -C "$SRC" -c advice.detachedHead=false checkout -q "$LOCK"
printf 'dirty bytes\n' > "$SRC/regular"
printf 'untracked\n' > "$SRC/untracked"

PIN1="$SCR/pin1"
GOT_TREE=$("$TOOL" materialize "$SRC" "$LOCK" "$PIN1")
check "tree identity retained" test "$GOT_TREE" = "$TREE"
check "dirty source ignored" grep -qx 'locked bytes' "$PIN1/regular"
check "replacement ref ignored" test "$(git -C "$PIN1" rev-parse HEAD)" = "$LOCK"
check "independent objects copied" test ! -s "$PIN1/.git/objects/info/alternates"
check "executable mode retained" test -x "$PIN1/executable"
check "symlink retained" test "$(readlink "$PIN1/link")" = regular
check "materialized tree verifies" test "$("$TOOL" verify "$PIN1" "$LOCK")" = "$TREE"
check "source files are read-only" test "$((8#$(stat -c %a "$PIN1/regular") & 8#222))" -eq 0

# The caller's repository need not use the pin's object format.
git init --quiet --object-format=sha256 "$SCR/sha256-caller"
check "SHA-1 checkout verifies from a SHA-256 repository" \
    test "$(cd "$SCR/sha256-caller" && "$TOOL" verify "$PIN1" "$LOCK")" = "$TREE"

HOOK="$SCR/hook-ran"
rm -f "$HOOK"
git -C "$SRC" config uploadpack.packObjectsHook "touch $HOOK"
git -C "$SRC" config core.fsmonitor "touch $HOOK"
PINH="$SCR/pinh"
GOT_HOOK=$("$TOOL" materialize "$SRC" "$LOCK" "$PINH")
check "source pack and fsmonitor hooks did not run" test ! -e "$HOOK"
check "hooked source still pins the locked tree" test "$GOT_HOOK" = "$TREE"

chmod u+w "$PIN1/regular"
printf 'changed after setup\n' > "$PIN1/regular"
check "changed bytes refused" refuse "$TOOL" verify "$PIN1" "$LOCK"

PIN2="$SCR/pin2"
"$TOOL" materialize "$SRC" "$LOCK" "$PIN2" >/dev/null
chmod u+w "$PIN2/executable"
chmod a-x "$PIN2/executable"
check "changed mode refused" refuse "$TOOL" verify "$PIN2" "$LOCK"

PIN3="$SCR/pin3"
"$TOOL" materialize "$SRC" "$LOCK" "$PIN3" >/dev/null
chmod u+w "$PIN3"
printf 'extra\n' > "$PIN3/extra"
check "extra path refused" refuse "$TOOL" verify "$PIN3" "$LOCK"
check "short commit refused" refuse "$TOOL" materialize "$SRC" "${LOCK:0:12}" "$SCR/short"
mkdir "$SCR/existing"
check "existing destination refused" refuse "$TOOL" materialize "$SRC" "$LOCK" "$SCR/existing"

echo "OMEGA_PINNED_CHECKOUT_PASS checks=$PASS"
