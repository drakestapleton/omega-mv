#!/bin/sh
# External orchestration, using the pinned native Omega compiler and HOME oracle module order.
set -eu
[ "$#" = 1 ] || { echo 'usage: test-look-home-dirty.sh FRESH_OUTPUT_DIR' >&2; exit 64; }
a=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
out=$1
mkdir "$out"
out=$(CDPATH= cd -- "$out" && pwd)
cat "$a/font-data.om" "$a/font.om" "$a/look-paint.om" "$a/tests/look-home-stubs.om" "$a/look-home.om" \
 "$a/tests/look-home-dirty.om" > "$out/home-dirty.om"
"$a/build-one.sh" "$out/home-dirty.om" "$out/home-dirty"
"$out/home-dirty" pixels 1280
"$out/home-dirty" pixels 4k
"$out/home-dirty" budget 1280
"$out/home-dirty" budget 4k
# A missing caret redraw must actually be detected by the pixel oracle.
sed '/^hmmarkcaret$/d' "$out/home-dirty.om" > "$out/missing-caret.om"
"$a/build-one.sh" "$out/missing-caret.om" "$out/missing-caret"
rc=0
"$out/missing-caret" pixels 1280 || rc=$?
[ "$rc" = 30 ] || { echo "missing-caret control expected 30, got $rc" >&2; exit 1; }
echo 'LOOK_HOME_DIRTY: PASS; full-redraw pixel equality and idle redraw budget at 1280 and 4K'
