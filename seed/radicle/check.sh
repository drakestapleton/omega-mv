#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
out=${1:?new output directory required}
mkdir "$out"
cd "$root"
printf '%s\n' 'cfd96b48b0460ab5557853d6856f9c741b96ac8d0d624e06198defb4cbfa0d8a  seed/out/omc' | sha256sum -c -
{ printf 'om2\n'; cat seed/json/json.om seed/radicle/adapter.om; } > "$out/adapter.full.om"
seed/out/omc < "$out/adapter.full.om" > "$out/adapter"
test -s "$out/adapter"
chmod +x "$out/adapter"
python3 seed/radicle/test.py "$out/adapter" seed/radicle/catalog-patch.json
sha256sum seed/radicle/adapter.om "$out/adapter"
