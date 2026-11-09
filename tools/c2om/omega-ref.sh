#!/bin/sh
# tools/c2om/omega-ref.sh <dir> [commit]: build the spec-only Omega interpreter tools/omega_ref from a pinned
# commit (default seed/omega-ref@3bc7d9fa, L412) with gcc through quiet-build, once per commit, under <dir>.
# It is an oracle: it runs Omega source and never builds a replacement. Prints the interpreter's path.
set -eu
D=$(cd "$(dirname "$0")/../.." && pwd)
[ $# -ge 1 ] || { echo "usage: $0 <dir> [commit]" >&2; exit 2; }
rsha=$(git -C "$D" rev-parse "${2:-3bc7d9faa589379280226d24f35886da0aca493a}^{commit}")
O=$1/omega_ref-$rsha
if [ ! -x "$O/omega_ref" ]; then
  if [ -d "$O.src" ]; then find "$O.src" -depth -delete; fi
  mkdir -p "$O.src" "$O"
  git -C "$D" archive "$rsha" tools/omega_ref | tar -x -C "$O.src"
  quiet-build gcc -std=gnu11 -O2 -Wall -o "$O/omega_ref" "$O.src/tools/omega_ref/omega_ref.c" > "$O.build.out" 2>&1 \
    || { echo "omega-ref: build failed: $(tail -3 "$O.build.out")" >&2; exit 1; }
fi
echo "$O/omega_ref"
