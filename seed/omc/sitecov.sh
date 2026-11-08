#!/bin/sh
# sitecov.sh -- which omc error sites does some refused input in the repository actually reach?
# (ROADMAP-1.0 RM8: "a coverage check lists any emitting site without a fixture".)
# Method (mutation, no instrumentation): every whole line "fail N", "nfail N" or "unkfail N" in
# seed/omc/omc.om is one site. For each site, a copy of omc.om with only that line's code changed to
# 97 (no real code) is compiled by seed/out/omc. The inputs are every tracked .om file and every gate15
# case that seed/out/omc refuses. A site is reached when some input that the real omc refuses with code
# N makes the mutant exit 97. Only inputs refused with N are tried for a site of code N: an input stops
# at the first site it reaches, so one that exits with another code cannot reach this one.
# Sound for "reached" (the mutant's own exit proves it); a site listed as unreached may still be
# reachable by a program the repository does not contain.
# Usage: sh seed/omc/sitecov.sh [check] [OUT_DIR]   (from the repository root; default build/seed/sitecov)
# With "check", it also fails when fewer sites are reached than seed/omc/sitecov.floor records, so a
# deleted fixture or a site moved out of reach is seen; raise the floor when new fixtures land.
# Writes OUT/sites.tsv (line, function, word, code, reached-by input or "-") and prints
#   SITECOV sites=S reached=R unreached=U inputs=I
set -eu
ck=0; [ "${1:-}" = check ] && { ck=1; shift; }
R=$(pwd); S=$R/seed/out/omc; O=${1:-$R/build/seed/sitecov}
[ -x "$S" ] || { echo "sitecov: $S missing; run sh seed/omega-from-seed.sh" >&2; exit 2; }
rm -rf "$O"; mkdir -p "$O/in" "$O/m"
bad() { echo "SITECOV FAIL $*" >&2; exit 1; }
# inputs: tracked .om files and gate15 cases the real compiler refuses, filed by exit code
i=0
add() { # add FILE ORIGIN
    set +e; "$S" < "$1" > /dev/null 2>&1; rc=$?; set -e
    [ "$rc" -gt 0 ] && [ "$rc" -lt 97 ] || return 0
    i=$((i + 1)); mkdir -p "$O/in/$rc"; cp "$1" "$O/in/$rc/$i.om"; printf '%s\t%s\n' "$i" "$2" >> "$O/inputs.tsv"
}
: > "$O/inputs.tsv"
git ls-files '*.om' > "$O/files"
while read -r f; do add "$f" "$f"; done < "$O/files"
awk "/<<'CASES'/{f=1;next} /^CASES\$/{f=0} f" seed/omc/gate15.sh > "$O/g15"
[ "$(grep -c '|' "$O/g15")" -ge 20 ] || bad "read too few gate15 cases"
while IFS='|' read -r name want line src; do
    [ -n "$name" ] || continue
    printf '%b\n' "$src" > "$O/g.om"; add "$O/g.om" "gate15:$name"
done < "$O/g15"
# sites
awk '/^fn /{fn=$2} /^(fail|nfail|unkfail) [0-9]+$/{print NR "\t" fn "\t" $1 "\t" $2}' seed/omc/omc.om > "$O/sitelist"
[ -s "$O/sitelist" ] || bad "no sites found"
: > "$O/sites.tsv"
while IFS='	' read -r ln fn w code; do
    by=-
    if [ -d "$O/in/$code" ]; then
        awk -v L="$ln" -v W="$w" 'NR == L { print W " 97"; next } { print }' seed/omc/omc.om > "$O/m.om"
        "$S" < "$O/m.om" > "$O/m/omc" 2> "$O/m.err" || bad "mutant at line $ln does not compile: $(cat "$O/m.err")"
        chmod +x "$O/m/omc"
        for x in "$O/in/$code"/*.om; do
            set +e; "$O/m/omc" < "$x" > /dev/null 2>&1; rc=$?; set -e
            if [ "$rc" = 97 ]; then by=$(basename "$x" .om); break; fi
        done
    fi
    [ "$by" = - ] || by=$(awk -F'\t' -v k="$by" '$1 == k { print $2 }' "$O/inputs.tsv")
    printf '%s\t%s\t%s\t%s\t%s\n' "$ln" "$fn" "$w" "$code" "$by" >> "$O/sites.tsv"
done < "$O/sitelist"
s=$(grep -c '' "$O/sites.tsv"); u=$(awk -F'\t' '$5 == "-"' "$O/sites.tsv" | grep -c '') || u=0
printf 'SITECOV sites=%s reached=%s unreached=%s inputs=%s\n' "$s" $((s - u)) "$u" "$i"
if [ "$ck" = 1 ]; then
    fl=$(cat "$R/seed/omc/sitecov.floor")
    [ $((s - u)) -ge "$fl" ] || bad "reached $((s - u)) is below the floor $fl (seed/omc/sitecov.floor)"
    printf 'SITECOV PASS reached=%s floor=%s\n' $((s - u)) "$fl"
fi
