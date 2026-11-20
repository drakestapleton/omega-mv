#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-only
set -eu
bin=${1:?supply output executable}
: "${OMC:?set OMC to the seeded compiler}"
# The seeded compiler takes one profile declaration per composed program.
cat om/arboris_arena.om om/arboris_ontology.om om/tls/sha2.om om/arboris_records.om \
    om/arboris_spread.om seed/authority/caproot.om om/gpu/bw_qmd.om \
    om/blackwell_arboris_qmd.om om/encoder/bw_enc_sm121.om om/blackwell_arboris_emit.om \
    gpu/nvidia/native/nvrm/context.om gpu/nvidia/native/share/share.om \
    gpu/nvidia/native/blackwell/vector.om gpu/nvidia/native/blackwell/launch.om \
    gpu/nvidia/native/arboris/arena.om gpu/nvidia/native/arboris/step.om \
    "${2:-tests/arboris/sparse-silicon.om}" > "$bin.sources"
awk '/^om2$/{if(profile++) next} {sub(/^export fn /,"fn ");print}' "$bin.sources" > "$bin.om"
"$OMC" < "$bin.om" > "$bin"
chmod +x "$bin"
