#!/usr/bin/env bash
# Compile the pinned native Omega units and compare with signed embedded code.
set -euo pipefail
cd "$(dirname "$0")/.."
# The pin is omega-mv's own: the first field of seed/out/omc.sha256 at the root of the omega-mv checkout
# this kernel/ is in (aienux is folded into omega-mv, Drake 2026-11-17). Until then: omega-mv bf54b19f,
# omc 62775d2a, omc.om 96d51b63. OMEGA_SOURCE may name another omega-mv checkout to take the compiler
# from; its seed/out/omc must still have this checkout's pin, and its own omc.sha256 is never read
# (before, the pin file moved with the compiler, so any compiler with its own sha256 beside it ran).
root=$(cd .. && pwd)
pin=$(head -n 1 "$root/seed/out/omc.sha256" 2>/dev/null | cut -c1-64) || pin=
[[ $pin =~ ^[0-9a-f]{64}$ ]] || { echo "LOCAL_TOOLS: NOT_RUN compiler pin refused: no sha256 in $root/seed/out/omc.sha256" >&2; exit 3; }
omc=${OMEGA_SOURCE:-$root}/seed/out/omc
[[ -f $omc ]] || { echo "LOCAL_TOOLS: NOT_RUN compiler pin refused: no compiler at $omc" >&2; exit 3; }
have=$(sha256sum "$omc" | cut -d' ' -f1)
[[ $have = "$pin" ]] || { echo "LOCAL_TOOLS: NOT_RUN compiler pin mismatch (compiler pin refused): $omc has sha256 $have, the pin in $root/seed/out/omc.sha256 is $pin" >&2; exit 3; }
out=${LOCAL_TOOLS_OUT:-$PWD/target/local-tools-host}
mkdir -p "$out"
for name in arithmetic text system; do
    "$omc" < "native/kernel/x86/tools/$name.om" > "$out/$name.raw"
done
cc -std=c11 -O2 -Wall -Wextra -Werror -Inative/sig -Inative/argus \
    native/kernel/x86/tests/local_admission_test.c native/kernel/artifact/format.c \
    native/argus/sha256.c native/sig/ed25519.c native/sig/sha512.c native/sig/ct.c -o "$out/admission"
"$out/admission" "$out/arithmetic.raw" "$out/text.raw" "$out/system.raw"
cargo test -p allen-courier --bin allen-courier
