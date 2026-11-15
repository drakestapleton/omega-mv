#!/bin/sh
# Refresh the FR-7 unit pins from the sources and from seed/out/omc.
#
#   sh seed/omc/cabi/regen.sh
#   sh seed/omc/cabi/regen.sh --check
#
# seed/omc/cabi/introduced.txt is the list. One line, no comments:
#   <sha256 of the source bytes> <path>
# seed/omc/cabi/golden.sha256 is what seed/out/omc emits for that source:
#   <sha256 of stdout> <sha256 of stderr> <exit> <path>
# call.om and trap.om exit 0 and the stdout hash is the object file.
# The other six are refusals. Their exit and their diagnostic bytes are the
# pin, so a different refusal is not a match. seed/units/regen.sh runs this
# after the unit bindings, once the sidecar compiler is in seed/out/omc.
# A compiler change rewrites golden.sha256. A source change rewrites both.
# The path list is not rewritten: a unit that is not already on the list,
# a listed unit that is gone, or a line this script cannot read, exits 1
# and writes nothing. --check writes nothing and exits 1 when a committed
# file would change.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
case ${1:-} in
''|--check) ;;
*) echo 'usage: sh seed/omc/cabi/regen.sh [--check]' >&2; exit 2 ;;
esac
OMC=$ROOT/seed/out/omc
[ -x "$OMC" ] || { echo 'NOT_RUN: seed/out/omc is missing; run sh seed/omega-from-seed.sh'; exit 3; }
intro=seed/omc/cabi/introduced.txt
gold=seed/omc/cabi/golden.sha256
[ -f "$intro" ] || { echo "FAIL: $intro is missing"; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT HUP INT TERM
n=0
while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    printf '%s\n' "$line" | grep -Eq '^[0-9a-f]{64} seed/omc/cabi/[A-Za-z0-9._-]+\.om$' \
        || { echo "FAIL: unparseable line $n in $intro"; exit 1; }
    path=${line#* }
    if grep -qxF "$path" "$T/paths" 2>/dev/null; then echo "FAIL: duplicate $path"; exit 1; fi
    printf '%s\n' "$path" >> "$T/paths"
done < "$intro"
git ls-files 'seed/omc/cabi/*.om' | sort > "$T/tracked"
sort "$T/paths" > "$T/listed"
if ! cmp -s "$T/tracked" "$T/listed"; then
    echo 'FAIL: introduced.txt is not exactly the tracked units under seed/omc/cabi/'
    comm -3 "$T/tracked" "$T/listed" | sed 's/^/  /'
    exit 1
fi
: > "$T/intro.new"
: > "$T/gold.new"
while IFS= read -r path; do
    src=$(sha256sum < "$path" | cut -c1-64)
    printf '%s %s\n' "$src" "$path" >> "$T/intro.new"
    set +e
    "$OMC" < "$path" > "$T/out" 2> "$T/err"
    rc=$?
    set -e
    out=$(sha256sum < "$T/out" | cut -c1-64)
    err=$(sha256sum < "$T/err" | cut -c1-64)
    printf '%s %s %s %s\n' "$out" "$err" "$rc" "$path" >> "$T/gold.new"
done < "$T/listed"
if [ "${1:-}" = --check ]; then
    ok=0
    cmp -s "$T/intro.new" "$intro" || ok=1
    cmp -s "$T/gold.new" "$gold" || ok=1
    if [ "$ok" != 0 ]; then
        echo 'FAIL: cabi pins differ from what seed/out/omc emits; run sh seed/omc/cabi/regen.sh'
        exit 1
    fi
    echo 'ok   cabi pins match seed/out/omc'
    exit 0
fi
mv "$T/intro.new" "$intro"
mv "$T/gold.new" "$gold"
echo "wrote $intro and $gold"
