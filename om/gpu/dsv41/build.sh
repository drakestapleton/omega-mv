#!/bin/sh
# Run from the repository root after growing seed/out/omc.
set -eu
out=${1:?usage: sh om/gpu/dsv41/build.sh OUTPUT_DIR}
mkdir -p "$out"
tmp=$(mktemp -d "$out/build.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
( echo om2; cat om/encoder/bw_enc_sm121.om om/gpu/dsv41/emit.om om/gpu/dsv41/emit-cli.om ) > "$tmp/input.om"
seed/out/omc < "$tmp/input.om" > "$tmp/emit"
seed/out/omc < seed/kflow/kpack.om > "$tmp/kpack"
seed/out/omc < om/gpu/dsv41/lookup.om > "$tmp/lookup"
chmod +x "$tmp/emit" "$tmp/kpack" "$tmp/lookup"
"$tmp/lookup" > "$tmp/decode.f32le"
while read -r mode name abi; do
    "$tmp/emit" "$mode" > "$tmp/$name.bin"
    "$tmp/kpack" 121-tk "$name" "$tmp/$name.bin" "$tmp/$name.cubin" 64 0 $abi
done < om/gpu/dsv41/kernels.list
( echo om2
  cat seed/json/json.om gpu/nvidia/native/nvrm/context.om \
    gpu/nvidia/native/blackwell/vector.om gpu/nvidia/native/blackwell/launch.om \
    gpu/nvidia/native/blackwell/batch.om om/encoder/bw_enc_sm121.om \
    om/gpu/dsv41/emit.om om/gpu/dsv41/head/weights.om om/gpu/dsv41/head/launch.om om/gpu/dsv41/head/session.om
) > "$tmp/head.om"
seed/out/omc < "$tmp/head.om" > "$tmp/dsv41-head"
chmod +x "$tmp/dsv41-head"
for src in om/gpu/dsv41/mma/*.om; do
    name=$(basename "$src" .om)
    seed/out/omc < "$src" > "$tmp/$name"
    chmod +x "$tmp/$name"
    "$tmp/$name" > "$tmp/$name.bin"
    "$tmp/kpack" 121-tk "$name" "$tmp/$name.bin" "$tmp/$name.cubin" 64 0 p8 p8 p8 p8 p8 4
done
mv "$tmp/dsv41-head" "$out"
mv "$tmp"/*.cubin "$tmp/decode.f32le" "$out"
