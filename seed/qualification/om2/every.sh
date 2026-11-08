#!/bin/sh
# every.sh -- run seed/qualification/om2/gate.om over EVERY seed/omc/om2/*/*.cases file (ROADMAP-1.0 RM1)
# and the error-site fixtures seed/omc/sites/*.cases (RM8),
# so a regression in any OM-2 stage is visible to seed/host/check.sh, not only s5.
# A case file must PASS with fail=0 invalid=0 not_run=0. A mutant file (*mutants.cases) must make the
# gate exit 1 with every ctl-* case PASS, every other case FAIL (the mutant was caught) and none
# INVALID or NOT_RUN. Two negative controls prove this script itself fails: a case with a wrong expected
# exit, and a mutant file whose substitutions are removed (its mutants then survive).
# Run from the repository root. Prints OM2EVERY PASS files=F cases=C mutants=M.
set -eu
R=$(pwd)
B=$R/build/seed/om2every
rm -rf "$B"; mkdir -p "$B"
"$R/seed/out/omc" < "$R/seed/qualification/om2/gate.om" > "$B/gate"
chmod +x "$B/gate"
pin=$(sha256sum "$R/seed/out/omc" | cut -d' ' -f1)
bad() { printf 'OM2EVERY FAIL %s\n' "$*" >&2; exit 1; }
n=0
# judge FILE LOG STATUS: 0 when the run is what FILE's kind requires, else prints why and returns 1.
judge() {
    sum=$(grep '^OM2GATE ' "$2" | tail -1)
    case "$sum" in *" invalid=0 not_run=0") ;; *) echo "summary: $sum"; return 1 ;; esac
    case "$1" in
    *mutants.cases)
        [ "$3" = 1 ] || { echo "mutant file exit $3, expected 1"; return 1; }
        k=$(grep -c '^VERDICT ' "$2") || true
        cp=$(grep -c '^VERDICT ctl-[^ ]* PASS' "$2") || true
        mf=$(grep '^VERDICT ' "$2" | grep -v '^VERDICT ctl-' | grep -c '^VERDICT [^ ]* FAIL') || true
        mt=$(grep '^VERDICT ' "$2" | grep -vc '^VERDICT ctl-') || true
        [ "$mt" -gt 0 ] || { echo "no mutant cases"; return 1; }
        [ "$mf" = "$mt" ] || { echo "mutant survived: caught $mf of $mt"; return 1; }
        [ "$cp" = $((k - mt)) ] || { echo "control failed: $cp of $((k - mt)) PASS"; return 1; }
        n=$mt ;;
    *)
        [ "$3" = 0 ] || { echo "exit $3, expected 0"; return 1; }
        case "$sum" in "OM2GATE PASS cases="*" fail=0 "*) ;; *) echo "summary: $sum"; return 1 ;; esac
        n=$(echo "$sum" | sed 's/.* cases=\([0-9]*\) .*/\1/') ;;
    esac
}
# run FILE TAG: gate FILE and judge it; prints its case count, or the reason and returns 1.
run() {
    st=0
    "$B/gate" "$R/seed/out/omc" "$pin" "$1" "$B/s-$2" > "$B/$2.log" 2>&1 || st=$?
    judge "$1" "$B/$2.log" "$st" && echo "$n"
}
files=0 cases=0 muts=0
for c in seed/omc/om2/*/*.cases seed/omc/sites/*.cases; do
    t=$(echo "$c" | tr / _)
    n=$(run "$c" "$t") || bad "$c: $n (log $B/$t.log)"
    case "$c" in *mutants.cases) muts=$((muts + n)) ;; *) cases=$((cases + n)) ;; esac
    files=$((files + 1))
    printf 'PASS %s (%s)\n' "$c" "$n"
done
[ "$files" -gt 0 ] || bad "no case files"
# negative control 1: the first run case of s1 with its expected exit changed must be refused.
awk '!d && $2 == "run" { $NF = $NF + 1; d = 1 } { print }' seed/omc/om2/s1/s1.cases > "$B/neg1.cases"
cmp -s seed/omc/om2/s1/s1.cases "$B/neg1.cases" && bad "negative control 1 did not change the file"
run "$B/neg1.cases" neg1 > /dev/null && bad "negative control 1 (wrong expected exit) was accepted"
printf 'PASS negative control: a wrong expected exit is refused\n'
# negative control 2: s4's mutants without their substitutions (mutants survive) must be refused.
grep -v '^subst ' seed/omc/om2/s4/s4-mutants.cases > "$B/neg2-mutants.cases"
run "$B/neg2-mutants.cases" neg2 > /dev/null && bad "negative control 2 (surviving mutants) was accepted"
printf 'PASS negative control: surviving mutants are refused\n'
printf 'OM2EVERY PASS files=%s cases=%s mutants=%s\n' "$files" "$cases" "$muts"
