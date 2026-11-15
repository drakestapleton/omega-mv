#!/bin/sh
# gate18.sh -- keyword generator parity. genkw.awk is a text generator (not on the seed path), but it
# must reproduce the committed keyword chain: every literal pack/id pair, plus the two computed entries
# readlnk (133) and sockopt (134). This catches list drift and awk precision regressions (packs above
# 2^53 are printed with decimal string arithmetic, not doubles). The one target-scoped entry, efi (178)
# under `target x86efi` only, is not generated; it must appear exactly once in its fixed form.
# Foreign gate kept for generator parity; pair count is derived, never hand-maintained. .om successor seed/omc/gate18.om,
# tracked in aien-dev/omega-mv#1073.
# Replacing `[ "$n" = N ]` with `[ "$n" -gt 0 ]` is a weakened gate.
# The expectation comes from a committed table the gate does not regenerate in that run.
# A control that deletes the new keyword from the generator and from `omc.om`, and leaves
# that table unchanged, must exit nonzero when only `sh seed/omc/gate18.sh` is run.
set -eu
R=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$R"
mkdir -p build/seed/r18
T=$(mktemp -d build/seed/r18/kw.XXXXXX)
trap 'rm -rf "$T"' EXIT HUP INT TERM
bad() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# No input file: gawk waits on a terminal otherwise, and the seed gate never returns.
awk -f seed/omc/genkw.awk > "$T/gen" < /dev/null

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
# The canonicalizer consumes a separate committed keyword inventory. Do not
# regenerate that inventory in this gate: losing an entry from both files above
# must still fail. Compare the complete ID multiset, including spelling aliases.
awk '
    /^text tkw1 "/ {
        sub(/^text tkw1 "/, ""); sub(/"$/, "")
        n=split($0, a, /\\n/)
        for (i=1; i<=n; i++) {
            split(a[i], p, " ")
            if (a[i] != "" && p[2] != 133 && p[2] != 134) print p[2]
        }
    }
' seed/semhash/semhash.om | sort -n > "$T/semantic.ids"
[ -s "$T/semantic.ids" ] || bad "semantic keyword inventory is absent"
cut -d ' ' -f 1 "$T/gen.pairs" > "$T/generated.ids"
cmp -s "$T/generated.ids" "$T/semantic.ids" ||
    bad "generated keyword inventory differs from committed semantic inventory"
n=$(wc -l < "$T/gen.pairs")
expected=$(wc -l < "$T/semantic.ids")
[ "$n" = "$expected" ] || bad "literal pair count $n differs from semantic inventory $expected"

grep -q '^ret 133$' seed/omc/omc.om || bad "committed chain lacks readlnk (133)"
grep -q '^ret 134$' seed/omc/omc.om || bad "committed chain lacks sockopt (134)"
grep -q 'readlnk:133' seed/omc/genkw.awk || bad "generator lacks readlnk:133"
grep -q 'sockopt:134' seed/omc/genkw.awk || bad "generator lacks sockopt:134"
grep -q '^ret 224$' seed/omc/omc.om || bad "committed chain lacks peername (224)"
grep -q 'peername:224' seed/omc/genkw.awk || bad "generator lacks peername:224"
grep -q '^ret 227$' seed/omc/omc.om || bad "committed chain lacks fma (227)"
grep -q 'fma:227' seed/omc/genkw.awk || bad "generator lacks fma:227"

printf 'PASS gate18 %s literal packs, both computed entries and the x86efi-scoped efi entry match the committed chain\n' "$n"
exit 0
