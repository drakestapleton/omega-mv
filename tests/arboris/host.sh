#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
set -eu
out=${1:?supply the host build directory}
: "${OMC:?set OMC to the seeded compiler}"
dis=${NVDISASM:-/usr/local/cuda/bin/nvdisasm}
[ -x "$dis" ] || { echo "NOT_RUN: nvdisasm is required for SM121 parity"; exit 3; }
compile() {
    dest=$1
    shift
    cat "$@" > "$out/unit.om"
    sed 's/^export fn /fn /' "$out/unit.om" > "$out/program.om"
    "$OMC" < "$out/program.om" > "$dest"
    chmod +x "$dest"
}
grep -Fq "Arboris, Copyright 2026 Adam Pippert" NOTICE
compile "$out/arena" om/arboris_arena.om tests/arboris_arena_test.om
"$out/arena"
compile "$out/native-arena" om/arboris_arena.om gpu/nvidia/native/nvrm/context.om gpu/nvidia/native/share/share.om gpu/nvidia/native/arboris/arena.om tests/arboris/native-arena.om
"$out/native-arena"
compile "$out/spread" om/arboris_ontology.om om/tls/sha2.om om/arboris_records.om om/arboris_spread.om tests/arboris_spread_test.om
"$out/spread"
compile "$out/gated" om/arboris_arena.om gpu/nvidia/om/numeric/numeric.om om/arboris_gated.om tests/arboris_gated_test.om
"$out/gated"
compile "$out/caproot-check" seed/authority/caproot.om tests/arboris/caproot-check.om
cc -D_GNU_SOURCE -std=c11 -O2 -Wall -Wextra -Werror -Isrc tests/arboris/caproot_issuer.c src/runtime/rx_caproot.c -o "$out/caproot-issuer"
"$out/caproot-issuer" "$out/caproot-check"
compile "$out/wave-qmd" om/gpu/bw_qmd.om om/blackwell_arboris_qmd.om tests/arboris/wave-qmd.om
"$out/wave-qmd"
echo om2 > "$out/profile.om"
compile "$out/emit" "$out/profile.om" om/encoder/bw_enc_sm121.om om/blackwell_arboris_emit.om tests/arboris/emit-spread.om
"$out/emit" > "$out/wave.bin"
echo "53058a3139706a7688ef68192a8bf8a679ef5dbad77cebc6c65b7081dfc7eb42  $out/wave.bin" | sha256sum -c -
"$dis" -b SM121 "$out/wave.bin" > "$out/wave.dis"
diff -u tests/arboris/spread-sm121.dis "$out/wave.dis"
"$out/emit" compound relax > "$out/relax.bin"
echo "c9c1f2a6c5c7de7f8379d85d8bba1ad49e20479c76d0dde70b1fca1becfeba5b  $out/relax.bin" | sha256sum -c -
"$dis" -b SM121 "$out/relax.bin" > "$out/relax.dis"
diff -u tests/arboris/relax-sm121.dis "$out/relax.dis"
cc -O1 -c src/omega_om_units.c -o "$out/units.o"
cc -std=c11 -O2 -Wall -Wextra -Werror -Isrc tests/arboris/scoreboard_oracle.c src/omega_bw_hazard.c "$out/units.o" -o "$out/check-wave"
"$out/check-wave" < "$out/wave.bin"
"$out/check-wave" < "$out/relax.bin"
"$out/emit" mutant > "$out/wave-mutant.bin"
if "$out/check-wave" < "$out/wave-mutant.bin" > "$out/negative.log"; then
    echo "FAIL: scoreboard accepted a missing load wait"
    exit 1
fi
grep -E 'reachable, [1-9][0-9]* hazards' "$out/negative.log"
echo "PASS Arboris CPU oracles, QMD packing, SM121 disassembly and OM/C scoreboards"
