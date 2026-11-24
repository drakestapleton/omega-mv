#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# om/gpu/q38/build.sh -- Build pure seeded-Omega Zero-CUDA Qwen 3.8 27B binaries (q38-decode, q38-serve).
set -eu
out=${1:?usage: sh om/gpu/q38/build.sh OUTPUT_DIR}
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
OMC="${OMC:-$ROOT/seed/out/omc}"
cd "$ROOT"
mkdir -p "$out"

(
  printf 'om2\n'
  cat gpu/nvidia/native/nvrm/context.om \
      gpu/nvidia/native/blackwell/vector.om \
      gpu/nvidia/native/blackwell/launch.om \
      gpu/nvidia/native/blackwell/batch.om \
      om/encoder/bw_enc_sm121.om \
      om/gpu/q36/emit_fast.om \
      om/gpu/q36/emit_prefill.om \
      om/gpu/q38/emit_q38.om \
      om/gpu/q38/core.om \
      om/gpu/q38/decode_cli.om
) | "$OMC" > "$out/q38-decode"
chmod 755 "$out/q38-decode"

(
  printf 'om2\n'
  cat gpu/nvidia/native/nvrm/context.om \
      gpu/nvidia/native/blackwell/vector.om \
      gpu/nvidia/native/blackwell/launch.om \
      gpu/nvidia/native/blackwell/batch.om \
      om/encoder/bw_enc_sm121.om \
      om/gpu/q36/emit_fast.om \
      om/gpu/q36/emit_prefill.om \
      om/gpu/q38/emit_q38.om \
      om/gpu/q38/core.om \
      om/gpu/q36/serve/tokenizer.om \
      om/gpu/q38/serve_cli.om
) | "$OMC" > "$out/q38-serve"
chmod 755 "$out/q38-serve"

echo "PASS built q38-decode and q38-serve -> $out"
