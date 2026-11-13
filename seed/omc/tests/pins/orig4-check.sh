#!/bin/sh
# TEST INSTRUMENT: orig4 live pin baseline and one byte-different executable control; not a shadow-advisor execution claim.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../../.." && pwd)
mkdir -p "$ROOT/build/seed"
B=$(mktemp -d "$ROOT/build/seed/orig4-pin.XXXXXX")
trap 'rm -rf "$B"' EXIT HUP INT TERM
mkdir -p "$B/repo/tests/orig4" "$B/repo/native/orig4" "$B/repo/seed/out"
cp "$ROOT/tests/orig4/run.sh" "$B/repo/tests/orig4/run.sh"
cp "$ROOT/native/orig4/orig4.pin" "$B/repo/native/orig4/orig4.pin"
cp "$ROOT/seed/out/omc" "$B/repo/seed/out/omc"
cp "$ROOT/seed/out/omc.sha256" "$B/repo/seed/out/omc.sha256"
# The real unmodified guard runs on the exact canonical compiler before the negative input is created.
OUT="$B/base-out" sh "$B/repo/tests/orig4/run.sh" --check-compiler-pin > "$B/base.log" 2>&1
 grep -qx 'ORIG4_SHADOW compiler pin PASS' "$B/base.log"
printf '\000' >> "$B/repo/seed/out/omc"
if OUT="$B/wrong-out" sh "$B/repo/tests/orig4/run.sh" --check-compiler-pin > "$B/wrong.log" 2>&1; then status=0; else status=$?; fi
[ "$status" = 3 ] && grep -q '^ORIG4_SHADOW NOT_RUN: compiler hash .* differs from seed/out/omc.sha256$' "$B/wrong.log" || { cat "$B/wrong.log"; echo 'ORIG4 PIN CONTROL FAIL'; exit 1; }
echo 'ORIG4 PIN CONTROL PASS consumers=1 baseline=accepted wrong-compiler=NOT_RUN3'
