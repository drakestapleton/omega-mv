#!/bin/sh
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
OMC="${OMC:-$ROOT/seed/out/omc}"
OUT_DIR="${1:-$ROOT/build/omega-engine}"
mkdir -p "$OUT_DIR"

SRC="$OUT_DIR/omega-engine.om"
{
  printf 'om2\n'
  cat \
    "$ROOT/gpu/nvidia/native/nvrm/context.om" \
    "$ROOT/gpu/nvidia/native/blackwell/vector.om" \
    "$ROOT/gpu/nvidia/native/blackwell/launch.om" \
    "$ROOT/gpu/nvidia/native/blackwell/batch.om" \
    "$ROOT/om/encoder/bw_enc_sm121.om" \
    "$ROOT/om/gpu/q36/emit_fast.om" \
    "$ROOT/om/gpu/q36/serve/tokenizer.om" \
    "$ROOT/om/gpu/engine/config.om" \
    "$ROOT/om/gpu/engine/safetensors.om" \
    "$ROOT/om/gpu/engine/emit_generic.om" \
    "$ROOT/om/gpu/engine/emit_qwen4.om" \
    "$ROOT/om/gpu/engine/runtime.om" \
    "$ROOT/om/gpu/engine/arboris_q4.om" \
    "$ROOT/om/gpu/engine/runtime_qwen4.om" \
    "$ROOT/om/gpu/engine/cli.om"
} > "$SRC"

"$OMC" < "$SRC" > "$OUT_DIR/omega-engine"
chmod 755 "$OUT_DIR/omega-engine"
echo "PASS built omega-engine -> $OUT_DIR/omega-engine"
