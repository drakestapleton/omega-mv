#!/bin/sh
# Run from the repository root after growing seed/out/omc.
set -eu
out=${1:?usage: sh om/gpu/dsv41/build.sh OUTPUT_DIR}
mkdir -p "$out"
tmp=$(mktemp -d "$out/build.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
( echo om2; cat om/encoder/bw_enc_sm121.om om/gpu/dsv41/emit.om ) > "$tmp/input.om"
seed/out/omc < "$tmp/input.om" > "$tmp/emit"
seed/out/omc < seed/kflow/kpack.om > "$tmp/kpack"
seed/out/omc < om/gpu/dsv41/lookup.om > "$tmp/lookup"
chmod +x "$tmp/emit" "$tmp/kpack" "$tmp/lookup"
"$tmp/lookup" > "$tmp/decode.f32le"
while read -r mode name abi; do
    "$tmp/emit" "$mode" > "$tmp/$name.bin"
    "$tmp/kpack" 121-tk "$name" "$tmp/$name.bin" "$tmp/$name.cubin" 64 0 $abi
done < om/gpu/dsv41/kernels.list
mv "$tmp"/*.cubin "$tmp/decode.f32le" "$out"
