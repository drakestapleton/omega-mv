#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
set -eu
bin=${1:?supply output executable}
: "${OMC:?set OMC to the seeded compiler}"
# The seeded compiler takes one profile declaration per composed program.
main=${2:-tests/arboris/sparse-silicon.om}
# Compile an exact fixture into each probe so replay cannot change its shape.
case "${3:-compound}" in
    compound) dims="100000 2 1 8" ;;
    wave)     dims="100000 2 2 8" ;;
    small)    dims="4096 1 1 8" ;;
    wide)     dims="100000 2 1 264" ;;
    *) exit 2 ;;
esac
set -- $dims
printf 'const probe_n ulong %s
const probe_batch ulong %s
const probe_planes ulong %s
const probe_dim ulong %s
' "$1" "$2" "$3" "$4" > "$bin.shape.om"
common=tests/arboris/probe-common.om
case "$main" in *packet.om) common=/dev/null ;; esac
# Only the gated CPU oracle needs the numeric reference. Its public "shape"
# classifier shares a name with a QMD parameter outside the numeric unit.
sed '/^fn logpoly /,$d' gpu/nvidia/om/numeric/numeric.om > "$bin.numeric.om"
cat om/arboris_arena.om om/arboris_ontology.om om/tls/sha2.om om/arboris_records.om \
    om/arboris_spread.om om/runtime/rx_capq_core.om seed/authority/capq.om "$bin.numeric.om" om/arboris_gated.om seed/authority/caproot.om om/gpu/bw_qmd.om \
    om/blackwell_arboris_qmd.om om/encoder/bw_enc_sm121.om om/blackwell_arboris_emit.om om/blackwell_arboris_gated_emit.om \
    gpu/nvidia/native/nvrm/context.om gpu/nvidia/native/share/share.om \
    gpu/nvidia/native/blackwell/vector.om gpu/nvidia/native/blackwell/launch.om \
    gpu/nvidia/native/arboris/arena.om gpu/nvidia/native/arboris/step.om gpu/nvidia/native/arboris/query.om gpu/nvidia/native/arboris/gated-step.om gpu/nvidia/native/arboris/digest.om \
    protocol/omnet/om/sha512/sha512.om protocol/omnet/om/ed25519/ed25519.om gpu/nvidia/native/arboris/commit.om \
    "$bin.shape.om" "$common" "$main" > "$bin.sources"
awk '/^om2$/{if(profile++) next} {sub(/^export fn /,"fn ");print}' "$bin.sources" > "$bin.om"
"$OMC" < "$bin.om" > "$bin"
chmod +x "$bin"
