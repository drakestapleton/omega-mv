#!/bin/sh
set -eu
umask 077
[ "$#" = 1 ] || { echo 'usage: build.sh NEW_KIT_DIRECTORY' >&2; exit 2; }
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$here/../../../.." && pwd)
mkdir -- "$1"
kit=$(CDPATH= cd -- "$1" && pwd)
cp "$root/seed/out/omc" "$kit/omc"
for name in om_formalize om_sketch om_synth; do
  "$kit/omc" < "$root/seed/helix/ollm_factory/$name.om" > "$kit/$name"
  chmod 700 "$kit/$name"
done
sed '/^fn main to int$/,$d' "$here/../bench/bench.om" > "$kit/combined.src"
cat "$here/combined.om" >> "$kit/combined.src"
"$kit/omc" < "$kit/combined.src" > "$kit/combined"
chmod 700 "$kit/combined"
cp "$here/solve" "$kit/solve"
