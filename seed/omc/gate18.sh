#!/bin/sh
# gate18.sh -- keyword generator parity. genkw.awk is a text generator (not on the seed path), but it
# must reproduce the committed keyword chain: every literal pack/id pair, plus the two computed entries
# readlnk (133) and sockopt (134). This catches list drift and awk precision regressions (packs above
# 2^53 are printed with decimal string arithmetic, not doubles). The one target-scoped entry, efi (178)
# under the two EFI targets only, is not generated; its complete condition is checked below.
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
    inkw && /^if and eq w /{p=$5 " scoped"; next}
    inkw && /^ret /{
        if ($2 == 0) { inkw=0; exit }
        if ($2 != 133 && $2 != 134) print $2, p
    }
' seed/omc/omc.om | sort -n > "$T/all.pairs"
[ "$(grep -c '^178 ' "$T/all.pairs")" = 1 ] || bad "committed chain must hold efi (178) exactly once"
grep -qx '178 6907493 scoped' "$T/all.pairs" || bad "efi (178) must remain target-scoped"
grep -qx 'if and eq w 6907493 or eq get xtarget 0 2 ne get atarget 0 0' seed/omc/omc.om || bad "efi (178) must be scoped to x86efi or aarch64efi only"
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
[ "$n" = 170 ] || bad "compared $n literal pairs, wanted 170"

grep -q '^ret 133$' seed/omc/omc.om || bad "committed chain lacks readlnk (133)"
grep -q '^ret 134$' seed/omc/omc.om || bad "committed chain lacks sockopt (134)"
grep -q 'readlnk:133' seed/omc/genkw.awk || bad "generator lacks readlnk:133"
grep -q 'sockopt:134' seed/omc/genkw.awk || bad "generator lacks sockopt:134"
grep -q '^ret 224$' seed/omc/omc.om || bad "committed chain lacks peername (224)"
grep -q 'peername:224' seed/omc/genkw.awk || bad "generator lacks peername:224"
grep -q '^ret 227$' seed/omc/omc.om || bad "committed chain lacks fma (227)"
grep -q 'fma:227' seed/omc/genkw.awk || bad "generator lacks fma:227"

printf 'PASS gate18 170 literal packs, both computed entries and the two-target EFI entry match the committed chain\n'
exit 0
