#!/bin/sh
set -eu
test -z "$(git status --porcelain)" || { echo 'Dirty tree' >&2; exit 1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
src=om/runtime/slab_arena.om
gate=tests/slab-arena/gate.om
seed/out/omc < "$src" > "$tmp/unit"
sed 's/^export fn /fn /' "$src" > "$tmp/program.om"
cat "$gate" >> "$tmp/program.om"
seed/out/omc < "$tmp/program.om" > "$tmp/gate"
chmod +x "$tmp/gate"
"$tmp/gate"
git rev-parse HEAD
sha256sum seed/out/omc "$src" "$gate"
(cd "$tmp" && sha256sum unit gate)
echo 'PASS slab-arena host transitions'
