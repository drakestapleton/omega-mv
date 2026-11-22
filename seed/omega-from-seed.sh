#!/bin/sh
# omega-from-seed.sh -- compatibility entry point for the pure seeded-Omega birth coordinator.
# All birth logic (seed0 -> hex1 -> asm2 -> om4 -> omc 3-stage fixpoint -> diaggen -> 8-case
# size-record verification -> 4 names-pass probes) lives in pure seeded Omega: seed/build/birth.om.
# Zero Python on the delivery path. Cold-start load0.sh runs only if seed/out/omc does not exist yet.
set -eu
R=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$R"
mkdir -p build/seed

if [ -x seed/out/omc ]; then
  cat seed/build/common.om seed/build/birth.om | seed/out/omc > build/seed/om-birth
  chmod 755 build/seed/om-birth
  exec ./build/seed/om-birth "$@"
fi

# Cold-start bootstrap (only when seed/out/omc is absent): grow stage1 from seed0.hex, then hand
# off immediately to pure-Omega seed/build/birth.om.
B=build/seed/cold
mkdir -p "$B"
sh seed/rung0/load0.sh seed/rung0/seed0.hex "$B/seed0.bin"
chmod 755 "$B/seed0.bin"
"$B/seed0.bin" < seed/rung1/hex1.hex > "$B/hex1.bin"
chmod 755 "$B/hex1.bin"
"$B/hex1.bin" < seed/rung2/asm2.hex1 > "$B/asm2.bin"
chmod 755 "$B/asm2.bin"
cat seed/rung2/table.s2 seed/rung3/table3.s2 seed/rung4/table4.s2 seed/rung4/om4.s | "$B/asm2.bin" > "$B/om4.bin"
chmod 755 "$B/om4.bin"
"$B/om4.bin" < seed/omc/omc.om > "$B/stage1"
chmod 755 "$B/stage1"
cat seed/build/common.om seed/build/birth.om | "$B/stage1" > build/seed/om-birth
chmod 755 build/seed/om-birth
exec ./build/seed/om-birth "$@"
