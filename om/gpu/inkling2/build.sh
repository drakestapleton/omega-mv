#!/bin/sh
# Run from the repository root after growing seed/out/omc.
set -eu
out=${1:?usage: sh om/gpu/inkling2/build.sh OUTPUT_DIR}
mkdir -p "$out"
tmp=$(mktemp -d "$out/build.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
( echo om2; cat om/encoder/bw_enc_sm121.om om/gpu/inkling2/emit.om om/gpu/inkling2/emit-cli.om ) > "$tmp/input.om"
seed/out/omc < "$tmp/input.om" > "$tmp/emit"
( echo om2; cat om/encoder/bw_enc_sm121.om om/gpu/inkling2/emit_fast.om om/gpu/inkling2/emit_fast-cli.om ) > "$tmp/input_fast.om"
seed/out/omc < "$tmp/input_fast.om" > "$tmp/emit_fast"
seed/out/omc < seed/kflow/kpack.om > "$tmp/kpack"
seed/out/omc < om/gpu/inkling2/lookup.om > "$tmp/lookup"
chmod +x "$tmp/emit" "$tmp/emit_fast" "$tmp/kpack" "$tmp/lookup"
"$tmp/lookup" > "$tmp/decode.f32le"
while read -r mode name abi; do
    "$tmp/emit" "$mode" > "$tmp/$name.bin"
    "$tmp/kpack" 121-tk "$name" "$tmp/$name.bin" "$tmp/$name.cubin" 64 0 $abi
done < om/gpu/inkling2/kernels.list
while read -r mode name regs shared abi; do
    "$tmp/emit_fast" "$mode" > "$tmp/$name.bin"
    "$tmp/kpack" 121-tk "$name" "$tmp/$name.bin" "$tmp/$name.cubin" "$regs" 0 $abi
done < om/gpu/inkling2/kernels_fast.list
( echo om2; cat om/gpu/inkling2/arboris/prefetch.om om/gpu/inkling2/arboris/hints-cli.om ) > "$tmp/hints-input.om"
seed/out/omc < "$tmp/hints-input.om" > "$tmp/arboris-expert-hints"
( echo om2; cat om/gpu/inkling2/arboris/prefetch.om om/gpu/inkling2/arboris/check-arboris.om ) > "$tmp/check-arboris-input.om"
seed/out/omc < "$tmp/check-arboris-input.om" > "$tmp/check-arboris"
( echo om2
  cat gpu/nvidia/native/nvrm/context.om \
    gpu/nvidia/native/blackwell/vector.om \
    gpu/nvidia/native/blackwell/launch.om \
    gpu/nvidia/native/blackwell/batch.om \
    om/encoder/bw_enc_sm121.om \
    om/gpu/inkling2/emit_fast.om \
    om/gpu/inkling2/native_run.om
) > "$tmp/native-input.om"
seed/out/omc < "$tmp/native-input.om" > "$tmp/inkling2-native"
( echo om2
  cat gpu/nvidia/native/nvrm/context.om \
    gpu/nvidia/native/blackwell/vector.om \
    gpu/nvidia/native/blackwell/launch.om \
    gpu/nvidia/native/blackwell/batch.om \
    om/encoder/bw_enc_sm121.om \
    om/gpu/inkling2/emit_fast.om \
    om/gpu/inkling2/arboris/prefetch.om \
    om/gpu/inkling2/decoder/safetensors.om \
    om/gpu/inkling2/decoder/tokenizer.om \
    om/gpu/inkling2/decoder/decode.om
) > "$tmp/decode-input.om"
seed/out/omc < "$tmp/decode-input.om" > "$tmp/inkling2-decode"
( echo om2
  cat gpu/nvidia/native/nvrm/context.om \
    gpu/nvidia/native/blackwell/vector.om \
    gpu/nvidia/native/blackwell/launch.om \
    gpu/nvidia/native/blackwell/batch.om \
    om/encoder/bw_enc_sm121.om \
    om/gpu/inkling2/emit_fast.om \
    om/gpu/inkling2/emit_batch.om \
    om/gpu/inkling2/multistream/batcher.om \
    om/gpu/inkling2/multistream/ms_run.om
) > "$tmp/ms-input.om"
seed/out/omc < "$tmp/ms-input.om" > "$tmp/inkling2-multistream"
( echo om2
  cat om/gpu/inkling2/multistream/batcher.om \
    om/gpu/inkling2/multistream/serve_ms.om
) > "$tmp/serve-ms-input.om"
seed/out/omc < "$tmp/serve-ms-input.om" > "$tmp/check-ms-server"
chmod +x "$tmp/arboris-expert-hints" "$tmp/check-arboris" "$tmp/inkling2-native" "$tmp/inkling2-decode" "$tmp/inkling2-multistream" "$tmp/check-ms-server"
mv "$tmp/arboris-expert-hints" "$tmp/check-arboris" "$tmp/inkling2-native" "$tmp/inkling2-decode" "$tmp/inkling2-multistream" "$tmp/check-ms-server" "$out"
mv "$tmp"/*.cubin "$tmp/decode.f32le" "$out"
