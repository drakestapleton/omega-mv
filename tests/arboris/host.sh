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
printf 'om2\n' > "$out/signer-profile.om"
compile "$out/world-signer" "$out/signer-profile.om" om/tls/sha2.om \
    protocol/omnet/om/sha512/sha512.om protocol/omnet/om/ed25519/ed25519.om seed/authority/arboris-signer.om
sed '/^fn main to int/,$d' seed/authority/arboris-signer.om > "$out/signer-unit.om"
compile "$out/signer-ledger" "$out/signer-profile.om" om/tls/sha2.om \
    protocol/omnet/om/sha512/sha512.om protocol/omnet/om/ed25519/ed25519.om "$out/signer-unit.om" tests/arboris/signer-ledger.om
mkdir -p "$out/signer-ledger-fixture"
(cd "$out/signer-ledger-fixture" && ../signer-ledger)
grep -Fq "Arboris, Copyright 2026 Adam Pippert" NOTICE
compile "$out/arena" om/arboris_arena.om tests/arboris_arena_test.om
"$out/arena"
compile "$out/native-arena" om/arboris_arena.om gpu/nvidia/native/nvrm/context.om gpu/nvidia/native/share/share.om gpu/nvidia/native/arboris/arena.om tests/arboris/native-arena.om
"$out/native-arena"
sh tests/arboris/build-sparse-probe.sh "$out/sparse-packet" tests/arboris/sparse-packet.om
"$out/sparse-packet"
sh tests/arboris/build-sparse-probe.sh "$out/commit-packet" tests/arboris/commit-packet.om
"$out/commit-packet"
sh tests/arboris/build-sparse-probe.sh "$out/sparse-chip"
sh tests/arboris/build-sparse-probe.sh "$out/wave-chip" tests/arboris/sparse-silicon.om wave
sh tests/arboris/build-sparse-probe.sh "$out/small-chip" tests/arboris/sparse-silicon.om small
sh tests/arboris/build-sparse-probe.sh "$out/gated-chip" tests/arboris/gated-silicon.om
sh tests/arboris/build-sparse-probe.sh "$out/wide-chip" tests/arboris/gated-silicon.om wide
for model in small sparse wave; do
    "$out/$model-chip" reference > "$out/$model-reference.log"
    case "$model" in
        small)  expected=33dfc6bc867a2bfbe09192038538c209c9b8bc89e16b6cedcaf0e7cf32b1a8f6 ;;
        sparse) expected=8ded4456ffe03d54cad43b7b7b8d07ff1997919c103dd1b49b61c6782d6e3d19 ;;
        wave)   expected=b2d9f9458d97db2f5415078fbc43ad0256229175bbc28127eeaad941a708dc7a ;;
    esac
    grep -qx "output_sha256=$expected" "$out/$model-reference.log"
done
"$out/gated-chip" reference > "$out/gated-reference.log"
"$out/wide-chip" reference > "$out/wide-reference.log"
grep -qx "output_sha256=ca8052acb8c6306df043531ab6c116c5d8dd69a7e565974338088119f8355e34" "$out/wide-reference.log"
compile "$out/spread" om/arboris_ontology.om om/tls/sha2.om om/arboris_records.om om/arboris_spread.om tests/arboris_spread_test.om
"$out/spread"
compile "$out/gated" om/arboris_arena.om gpu/nvidia/om/numeric/numeric.om om/arboris_gated.om tests/arboris_gated_test.om
"$out/gated"
compile "$out/capq" om/runtime/rx_capq_core.om seed/authority/capq.om tests/arboris/capq.om
"$out/capq"
compile "$out/caproot-check" seed/authority/caproot.om tests/arboris/caproot-check.om
cc -D_GNU_SOURCE -std=c11 -O2 -Wall -Wextra -Werror -Isrc tests/arboris/caproot_issuer.c src/runtime/rx_caproot.c -o "$out/caproot-issuer"
"$out/caproot-issuer" "$out/caproot-check"
compile "$out/wave-qmd" om/gpu/bw_qmd.om om/blackwell_arboris_qmd.om tests/arboris/wave-qmd.om
"$out/wave-qmd"
echo om2 > "$out/profile.om"
compile "$out/emit" "$out/profile.om" om/encoder/bw_enc_sm121.om om/blackwell_arboris_emit.om tests/arboris/emit-spread.om
compile "$out/emit-gated" "$out/profile.om" om/encoder/bw_enc_sm121.om om/blackwell_arboris_emit.om om/blackwell_arboris_gated_emit.om tests/arboris/emit-gated.om
"$out/emit-gated" > "$out/gated.sass"
echo "66efbbc55e3e0434aa0e43416d25c22112c383a3f4c91da5337304d1fea85182  $out/gated.sass" | sha256sum -c -
grep -qx "output_sha256=ad8a70b5e2935b7fca819ce4823afea8bef95c56135b6d86e7cf4ada6f16a089" "$out/gated-reference.log"
"$dis" -b SM121 "$out/gated.sass" > "$out/gated.dis"
diff -u tests/arboris/gated-sm121.dis "$out/gated.dis"
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
"$out/check-wave" < "$out/gated.sass"
"$out/emit-gated" wide > "$out/wide.sass"
echo "e1950992aaf3ba1a22562f68ddf2575d27dc39fc8e50f33e2683e0f2c6ed32af  $out/wide.sass" | sha256sum -c -
"$out/check-wave" < "$out/wide.sass"
"$out/emit" compound relax small > "$out/small.bin"
"$out/check-wave" < "$out/small.bin"
"$out/emit" mutant > "$out/wave-mutant.bin"
if "$out/check-wave" < "$out/wave-mutant.bin" > "$out/negative.log"; then
    echo "FAIL: scoreboard accepted a missing load wait"
    exit 1
fi
grep -E 'reachable, [1-9][0-9]* hazards' "$out/negative.log"
echo "PASS Arboris CPU oracles, QMD packing, SM121 disassembly and OM/C scoreboards"
