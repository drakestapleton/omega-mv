#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Regenerates the wrapped struct run units nom_<name>.om from seed/omc/tests/struct/<name>.om.
# ng front-ir lowers only `fn main to int`; these fixtures return uint, ulong or long, so main becomes `subject`
# and a new `fn main to int` returns it as an int. Run from the repository root:
#   sh seed/ng/front/cases/nom-wrap.sh [check]
# With `check` nothing is written: exit 1 if a copy differs from what the originals generate.
set -e
bad=0
for n in t1 t1x t1y t2 t4 t5 t6 t7 t7b t8 t9; do
    src=seed/omc/tests/struct/$n.om
    out=seed/ng/front/cases/nom_$n.om
    tmp=$(mktemp)
    {
        printf 'note Wrapped copy of %s for gate-front-ir: main to uint, ulong or long becomes subject (nom-wrap.sh).\n' "$src"
        sed 's/^fn main to \(uint\|ulong\|long\)$/fn subject to \1/' "$src"
        printf 'fn main to int\nret int subject\nend\n'
    } > "$tmp"
    if [ "$1" = check ]; then
        cmp -s "$tmp" "$out" || { echo "differs: $out"; bad=1; }
        rm -f "$tmp"
    else
        mv "$tmp" "$out"
    fi
done
exit $bad
