#!/bin/sh
# L835 run 300: build the three arms of spec/omegese-om2-measure.md from clean git archives.
#   A  baseline acb3f15c (OM-1 sha256.om through the src/sha256.c adapter), its own seed-born omc
#   B  delivered main (OM-2 sha256-om2.om through the generated ABI v2 binding), its own seed-born omc
#   C  reference only: the historical pure-C src/sha256.c at a647b6a9 (the parity oracle), no gate role
# Flags are the libomega_gpu compile flags of both trees (cc -std=gnu11 -Wall -Wextra -Werror -D_GNU_SOURCE -O2 -Isrc).
# Usage: sh build.sh REPO M   (REPO: omega-mv clone; M: scratch dir)
set -eu
REPO=$1; M=$2; HERE=$(cd "$(dirname "$0")" && pwd)
CF="-std=gnu11 -Wall -Wextra -Werror -D_GNU_SOURCE -O2"
rm -rf "$M"; mkdir -p "$M/A" "$M/B" "$M/C/src" "$M/bin"
git -C "$REPO" archive acb3f15cdc691b1b046b48b0dad0f9255a12ba4b | tar -x -C "$M/A"
git -C "$REPO" archive 1e3ecbba779ee84e2de70ec231e83533a9c61f45 | tar -x -C "$M/B"
git -C "$REPO" show a647b6a9:src/sha256.c > "$M/C/src/sha256.c"
git -C "$REPO" show a647b6a9:src/sha256.h > "$M/C/src/sha256.h"
for a in A B; do
  (cd "$M/$a" && cp seed/out/omc "$M/omc-$a.committed" && sh seed/omega-from-seed.sh > "$M/seed-$a.log" 2>&1)
  echo "arm $a seed rc=0 born=$(sha256sum < "$M/$a/seed/out/omc" | cut -c1-64) pin=$(cut -c1-64 "$M/$a/seed/out/omc.sha256") committed=$(sha256sum < "$M/omc-$a.committed" | cut -c1-64)"
done
"$M/A/seed/out/omc" < "$M/A/om/sha256/sha256.om" > "$M/unit-A.bin"
"$M/B/seed/out/omc" < "$M/B/om/sha256/sha256-om2.om" > "$M/unit-B.bin"
echo "unit A om/sha256/sha256.om     src=$(sha256sum < "$M/A/om/sha256/sha256.om" | cut -c1-64) bytes=$(wc -c < "$M/unit-A.bin") sha256=$(sha256sum < "$M/unit-A.bin" | cut -c1-64)"
echo "unit B om/sha256/sha256-om2.om src=$(sha256sum < "$M/B/om/sha256/sha256-om2.om" | cut -c1-64) bytes=$(wc -c < "$M/unit-B.bin") sha256=$(sha256sum < "$M/unit-B.bin" | cut -c1-64)"
build() { # arm srcs...
  a=$1; shift; d=$M/$a
  for s in "$@"; do cc $CF -I"$d/src" -c "$d/$s" -o "$M/bin/$a-$(basename "$s" .c).o"; done
  objs=$(for s in "$@"; do printf '%s ' "$M/bin/$a-$(basename "$s" .c).o"; done)
  cc $CF -I"$d/src" "$HERE/bench2.c" $objs -o "$M/bin/bench-$a"
  cc $CF -I"$d/src" "$HERE/cold.c" $objs -o "$M/bin/cold-$a"
  echo "arm $a objects:"; size $objs | sed 's/^/  /'
}
build A src/sha256.c
build B src/omega_om_units.c
build C src/sha256.c
cc --version | head -1
for a in A B C; do echo "bench-$a $(sha256sum < "$M/bin/bench-$a" | cut -c1-64)  cold-$a $(sha256sum < "$M/bin/cold-$a" | cut -c1-64)"; done
