#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
set -eu
bin=${1:?supply output executable}
: "${OMC:?set OMC to the seeded compiler}"
# The seeded compiler takes one profile declaration per composed program.
main=${2:-tests/arboris/sparse-silicon.om}
common=tests/arboris/probe-common.om
case "$main" in *packet.om) common=/dev/null ;; esac
# Only the gated CPU oracle needs the numeric reference. Its public "shape"
# classifier shares a name with a QMD parameter outside the numeric unit.
sed '/^fn logpoly /,$d' gpu/nvidia/om/numeric/numeric.om > "$bin.numeric.om"
cat om/arboris_arena.om om/arboris_ontology.om om/tls/sha2.om om/arboris_records.om \
    om/arboris_spread.om "$bin.numeric.om" om/arboris_gated.om seed/authority/caproot.om om/gpu/bw_qmd.om \
    om/blackwell_arboris_qmd.om om/encoder/bw_enc_sm121.om om/blackwell_arboris_emit.om om/blackwell_arboris_gated_emit.om \
    gpu/nvidia/native/nvrm/context.om gpu/nvidia/native/share/share.om \
    gpu/nvidia/native/blackwell/vector.om gpu/nvidia/native/blackwell/launch.om \
    gpu/nvidia/native/arboris/arena.om gpu/nvidia/native/arboris/step.om gpu/nvidia/native/arboris/gated-step.om gpu/nvidia/native/arboris/digest.om \
    "$common" "$main" > "$bin.sources"
awk '/^om2$/{if(profile++) next} {sub(/^export fn /,"fn ");print}' "$bin.sources" > "$bin.om"
"$OMC" < "$bin.om" > "$bin"
chmod +x "$bin"
