#!/bin/sh
# gate18.sh -- keyword generator parity. genkw.awk is a text generator (not on the seed path), but it
# must reproduce the committed keyword chain: every literal pack/id pair, plus the two computed entries
# readlnk (133) and sockopt (134). This catches list drift and awk precision regressions (packs above
# 2^53 are printed with decimal string arithmetic, not doubles). The one target-scoped entry, efi (178)
# under `target x86efi` only, is not generated; it must appear exactly once in its fixed form.
# Foreign gate kept by a minimal fix (173 pairs with execenv 233, setprio 234, prlimit 235, setaff 237 and execkeep 238); .om successor seed/omc/gate18.om,
# tracked in aien-dev/omega-mv#1073.
set -eu
R=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$R"
mkdir -p build/seed/r18
T=$(mktemp -d build/seed/r18/kw.XXXXXX)
trap 'rm -rf "$T"' EXIT HUP INT TERM
bad() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

awk -f seed/omc/genkw.awk > "$T/gen"

# The committed chain, scoped to fn kw: stop at its final `ret 0` fallback.
awk '
    /^fn kw /{inkw=1; next}
    inkw && /^if eq w /{p=$4; next}
    inkw && /^if and eq w /{p=$5 " target=" $NF; next}
    inkw && /^ret /{
        if ($2 == 0) { inkw=0; exit }
        if ($2 != 133 && $2 != 134) print $2, p
    }
' seed/omc/omc.om | sort -n > "$T/all.pairs"
[ "$(grep -c '^178 ' "$T/all.pairs")" = 1 ] || bad "committed chain must hold efi (178) exactly once"
grep -qx '178 6907493 target=2' "$T/all.pairs" || bad "efi (178) must be scoped to x86efi (xtarget 2)"
grep -v '^178 ' "$T/all.pairs" > "$T/chain.pairs"

awk '
    /^if eq w /{p=$4}
    /^ret /{ if ($2 != 133 && $2 != 134) print $2, p }
' "$T/gen" | sort -n > "$T/gen.pairs"

cmp -s "$T/chain.pairs" "$T/gen.pairs" || {
    diff -u "$T/chain.pairs" "$T/gen.pairs" | sed -n '1,20p' >&2
    bad "generated keyword packs differ from the committed chain"
}
n=$(wc -l < "$T/gen.pairs")
[ "$n" = 173 ] || bad "compared $n literal pairs, wanted 173"

grep -q '^ret 133$' seed/omc/omc.om || bad "committed chain lacks readlnk (133)"
grep -q '^ret 134$' seed/omc/omc.om || bad "committed chain lacks sockopt (134)"
grep -q 'readlnk:133' seed/omc/genkw.awk || bad "generator lacks readlnk:133"
grep -q 'sockopt:134' seed/omc/genkw.awk || bad "generator lacks sockopt:134"
grep -q '^ret 224$' seed/omc/omc.om || bad "committed chain lacks peername (224)"
grep -q 'peername:224' seed/omc/genkw.awk || bad "generator lacks peername:224"
grep -q '^ret 227$' seed/omc/omc.om || bad "committed chain lacks fma (227)"
grep -q 'fma:227' seed/omc/genkw.awk || bad "generator lacks fma:227"

printf 'PASS gate18 173 literal packs, both computed entries and the x86efi-scoped efi entry match the committed chain\n'
exit 0
