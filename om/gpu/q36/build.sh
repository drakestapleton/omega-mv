#!/bin/sh
# Build pure seeded-Omega zero-CUDA native GB10 runner for Qwen 3.6 35B-A3B FP8.
# Run from the repository root after growing seed/out/omc.
set -eu
out=${1:?usage: sh om/gpu/q36/build.sh OUTPUT_DIR}
mkdir -p "$out"
tmp=$(mktemp -d "$out/build.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

( echo om2
  cat gpu/nvidia/native/nvrm/context.om \
    gpu/nvidia/native/blackwell/vector.om \
    gpu/nvidia/native/blackwell/launch.om \
    gpu/nvidia/native/blackwell/batch.om \
    om/encoder/bw_enc_sm121.om \
    om/gpu/q36/emit_fast.om \
    om/gpu/q36/arboris/prefetch.om \
    om/gpu/q36/native_run.om
) > "$tmp/q36-native-input.om"
seed/out/omc < "$tmp/q36-native-input.om" > "$tmp/q36-native"
chmod +x "$tmp/q36-native"
mv "$tmp/q36-native" "$out/q36-native"

( echo om2
  cat gpu/nvidia/native/nvrm/context.om \
    gpu/nvidia/native/blackwell/vector.om \
    gpu/nvidia/native/blackwell/launch.om \
    gpu/nvidia/native/blackwell/batch.om \
    om/encoder/bw_enc_sm121.om \
    om/gpu/q36/head/emit_head.om \
    om/gpu/q36/head/head_run.om
) > "$tmp/q36-head-input.om"
seed/out/omc < "$tmp/q36-head-input.om" > "$tmp/q36-head"
chmod +x "$tmp/q36-head"
mv "$tmp/q36-head" "$out/q36-head"
