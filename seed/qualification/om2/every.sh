#!/bin/sh
# every.sh -- run seed/qualification/om2/gate.om over EVERY seed/omc/om2/*/*.cases file (ROADMAP-1.0 RM1)
# and the error-site fixtures seed/omc/sites/*.cases (RM8), plus the qualification files listed below,
# so a regression in any OM-2 stage is visible to seed/host/check.sh, not only s5.
# A case file must PASS with fail=0 invalid=0 not_run=0. A mutant file (*mutants.cases) must make the
# gate exit 1 with every ctl-* case PASS, every other case FAIL (the mutant was caught) and none
# INVALID or NOT_RUN. Two negative controls prove this script itself fails: a case with a wrong expected
# exit, a mutant file whose substitutions are removed (its mutants then survive), and a wrong compiler
# identity (every case NOT_RUN, none declared).
# Run from the repository root. Prints OM2EVERY PASS files=F cases=C skipped_declared=K mutants=M
# (C counts cases that ran; K counts declared notrun cases).
set -eu
R=$(pwd)
B=$R/build/seed/om2every
rm -rf "$B"; mkdir -p "$B"
"$R/seed/out/omc" < "$R/seed/qualification/om2/gate.om" > "$B/gate"
chmod +x "$B/gate"
pin=$(sha256sum "$R/seed/out/omc" | cut -d' ' -f1)
bad() { printf 'OM2EVERY FAIL %s\n' "$*" >&2; exit 1; }
n=0
# anchors FILE: every "subst FROM TO" row of FILE must find FROM exactly once in the source the next case
# compiles (the gate's own rule, INVALID otherwise). Checked here for all files at once, before any case
# runs, so one stale mutation recipe cannot hide the others and names its file, line and match count.
# Sources joined with + or given as pack:/cyc: segments are left to the gate, which enforces the same rule.
anchors() {
    awk -v cf="$1" '
    function whole(p,   x, r) { r = RS; RS = "\001"; x = ""; if ((getline x < p) < 0) x = "\001unreadable"; close(p); RS = r; return x }
    NF == 0 || $1 ~ /^#/ { next }
    $1 == "subst" { from = $2; at = NR; next }
    from == "" || $1 == "deadline" { next }
    {
        src = ($1 == "cc") ? $2 : $3
        if (src != "pinned" && src !~ /[:+]/) {
            h = whole(src); n = whole(from); c = 0
            if (n != "" && h != "\001unreadable" && n != "\001unreadable") {
                while ((i = index(h, n)) > 0) { c++; h = substr(h, i + 1) }
            } else c = -1
            if (c != 1) { printf "%s:%d: %s matches %d times in %s (need exactly 1)\n", cf, at, from, c, src; bad++ }
        }
        from = ""
    }
    END { exit bad > 0 }' "$1"
}
stale=0
for c in seed/omc/om2/*/*.cases seed/omc/sites/*.cases; do
    anchors "$c" >> "$B/anchors.log" || stale=1
done
[ "$stale" = 0 ] || { cat "$B/anchors.log" >&2; bad "stale mutation anchors (list above)"; }
# judge FILE LOG STATUS: 0 when the run is what FILE's kind requires, else prints why and returns 1.
# A case file may skip only the cases it declares with a notrun line (a planned case whose prerequisite,
# such as the omega-bridge ABI generator, is absent): the NOT_RUN count must equal those lines and every
# NOT_RUN verdict must be the declared kind ("NOT_RUN not run:"), never an identity or build failure.
judge() {
    sum=$(grep '^OM2GATE ' "$2" | tail -1)
    dn=$(grep -c '^[^ #]* notrun ' "$1") || true
    vn=$(grep -c '^VERDICT [^ ]* NOT_RUN not run:' "$2") || true
    an=$(grep -c '^VERDICT [^ ]* NOT_RUN' "$2") || true
    [ "$dn" = "$vn" ] && [ "$vn" = "$an" ] || { echo "declared notrun $dn, declared NOT_RUN verdicts $vn, all NOT_RUN $an"; return 1; }
    case "$sum" in *" invalid=0 not_run=$dn") ;; *) echo "summary: $sum"; return 1 ;; esac
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
        if [ "$dn" = 0 ]; then w=0 v=PASS; else w=2 v=NOT_RUN; fi
        [ "$3" = "$w" ] || { echo "exit $3, expected $w"; return 1; }
        case "$sum" in "OM2GATE $v cases="*" fail=0 "*) ;; *) echo "summary: $sum"; return 1 ;; esac
        n=$(echo "$sum" | sed 's/.* cases=\([0-9]*\) .*/\1/'); n=$((n - dn)) ;;
    esac
}
# run FILE TAG: gate FILE and judge it; prints its case count, or the reason and returns 1.
run() {
    st=0
    "$B/gate" "$R/seed/out/omc" "${PIN:-$pin}" "$1" "$B/s-$2" > "$B/$2.log" 2>&1 || st=$?
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
# Qualification files that pass on the committed compiler (the four sec/leak candidate files skip only
# their declared notrun cases). The other files under
# seed/qualification are left out on purpose: pinned.cases run against the OM-1 reference omc 734f0a39,
# mutant and selftest fail/controls files are designed failures run by their own drivers, and security673 bindings.cases
# stays out until derive-wrong-image's stored evidence/run3/embed.bin (2184 bytes, 2026-10-30) is
# re-derived by its owner: today's omc emits 2308 bytes for embed.om, so that pin is stale.
for c in seed/qualification/om2/baseline/guard.cases seed/qualification/om2/baseline/language.cases \
    seed/qualification/om2/baseline/sha256.cases seed/qualification/om2/baseline/transform.cases \
    seed/qualification/om2/sec/s4fuel/candidate.cases seed/qualification/om2/selftest/pass.cases \
    seed/qualification/security673/relational/consumer.cases \
    seed/qualification/security673/relational/l4-tripwire.cases \
    seed/qualification/security673/relational/qualification.cases \
    seed/qualification/om2/sec/s0s2/candidate.cases seed/qualification/om2/sec/s3s4/candidate.cases \
    seed/qualification/om2/sec/s5s7/candidate.cases seed/qualification/om2/leak/candidate.cases; do
    t=$(echo "$c" | tr / _)
    n=$(run "$c" "$t") || bad "$c: $n (log $B/$t.log)"
    cases=$((cases + n)); files=$((files + 1))
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
# negative control 3: an undeclared NOT_RUN (wrong compiler identity: every case NOT_RUN) must be refused.
PIN=0000000000000000000000000000000000000000000000000000000000000000 run seed/qualification/om2/sec/s0s2/candidate.cases neg3 > /dev/null && bad "negative control 3 (undeclared NOT_RUN) was accepted"
printf 'PASS negative control: an undeclared NOT_RUN is refused\n'
# negative control 4: a substitution whose FROM text is absent from its source must be refused by the preflight.
printf 'no such text in omc.om\n' > "$B/neg4.from"
printf 'subst %s/neg4.from seed/omc/om2/bnd/mutants/bnd-extra.to\ncc seed/omc/omc.om\n' "$B" > "$B/neg4.cases"
anchors "$B/neg4.cases" > /dev/null && bad "negative control 4 (stale mutation anchor) was accepted"
printf 'PASS negative control: a stale mutation anchor is refused\n'
sk=$(cat seed/qualification/om2/sec/s0s2/candidate.cases seed/qualification/om2/sec/s3s4/candidate.cases \
    seed/qualification/om2/sec/s5s7/candidate.cases seed/qualification/om2/leak/candidate.cases | grep -c '^[^ #]* notrun ') || true
printf 'OM2EVERY PASS files=%s cases=%s skipped_declared=%s mutants=%s\n' "$files" "$cases" "$sk" "$muts"
