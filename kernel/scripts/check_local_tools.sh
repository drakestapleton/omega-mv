#!/usr/bin/env bash
# Compile the pinned native Omega units and compare with signed embedded code.
set -euo pipefail
cd "$(dirname "$0")/.."
# The compiler is omega-mv's own seed/out/omc, checked against seed/out/omc.sha256 at the omega-mv root (kernel/ is
# folded into omega-mv, Drake 2026-11-17). Until then: omega-mv bf54b19f, omc 62775d2a, omc.om 96d51b63.
om=${OMEGA_SOURCE:-$(cd .. && pwd)}
[[ $(sha256sum "$om/seed/out/omc" | cut -d' ' -f1) = $(cut -c1-64 "$om/seed/out/omc.sha256") ]]
out=${LOCAL_TOOLS_OUT:-$PWD/target/local-tools-host}
mkdir -p "$out"
for name in arithmetic text system; do
    "$om/seed/out/omc" < "native/kernel/x86/tools/$name.om" > "$out/$name.raw"
done
cc -std=c11 -O2 -Wall -Wextra -Werror -Inative/sig -Inative/argus \
    native/kernel/x86/tests/local_admission_test.c native/kernel/artifact/format.c \
    native/argus/sha256.c native/sig/ed25519.c native/sig/sha512.c native/sig/ct.c -o "$out/admission"
"$out/admission" "$out/arithmetic.raw" "$out/text.raw" "$out/system.raw"
cargo test -p allen-courier --bin allen-courier
