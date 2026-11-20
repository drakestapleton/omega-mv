#!/bin/sh
set -eu
out=${1:?usage: sh om/gpu/dsv41/cache/build.sh OUTPUT_DIRECTORY}
src=om/gpu/dsv41/cache
mkdir -p "$out"
tmp=$(mktemp -d "$out/cache.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
( echo om2; cat seed/ng/sha256.om "$src/pack.om" ) > "$tmp/pack-input.om"
cat "$src/slabs.om" "$src/replay.om" > "$tmp/replay-input.om"
cat "$src/slabs.om" "$src/contract.om" > "$tmp/contract-input.om"
for name in pack replay contract; do
    seed/out/omc < "$tmp/$name-input.om" > "$tmp/$name"
    chmod +x "$tmp/$name"
done
"$tmp/contract"
mv "$tmp/pack" "$tmp/replay" "$tmp/contract" "$out/"
