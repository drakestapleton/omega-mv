#!/bin/sh
# bench/inference_cost/tests/handover/run.sh [OMC]
# Builds bench/inference_cost/handover.om with the pinned omc, runs every known-verdict case in
# cases.txt on the TEST DATA in data/, checks the printed input digests against sha256sum, then
# applies each mutant in mutants.txt to a temporary copy of handover.om and requires that it fails
# at least one case. Tracked files are never changed; everything is built under
# build/inference_cost/handover/.
# Exit: 0 every case passes and every mutant is killed; 1 a case failed, a mutant survived or did
# not apply; 3 NOT_RUN (omc is not the pinned compiler, or handover.om does not build).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../../.." && pwd)
OMC=${1:-$REPO/seed/out/omc}
SRC=$REPO/bench/inference_cost/handover.om
SCORER=$REPO/bench/inference_cost/scorer.om
BUILD=$REPO/build/inference_cost/handover
say() { printf '%s\n' "$*"; }
not_run() { say "NOT_RUN: $*"; exit 3; }

[ -x "$OMC" ] || not_run "no compiler at $OMC"
want=$(awk '{print $1}' "$REPO/seed/out/omc.sha256")
have=$(sha256sum "$OMC" | awk '{print $1}')
[ "$have" = "$want" ] || not_run "omc sha256 $have is not the pin seed/out/omc.sha256 ($want)"
# handover.om shares scorer.om's wire reader by leaving out scorer.om's fn main, which must be
# the last function of the file; refuse to build anything else.
[ "$(grep -c '^fn main to int$' "$SCORER")" = 1 ] || not_run "scorer.om has no single 'fn main to int' line"
[ "$(sed -n '/^fn main to int$/,$p' "$SCORER" | grep -c '^fn ')" = 1 ] ||
    not_run "scorer.om has a function after fn main; the shared-reader build would drop it"
rm -rf "$BUILD"
mkdir -p "$BUILD"

build() { # source binary
    { printf 'om2\n'; cat "$REPO/om/tls/sha2.om"; sed '/^fn main to int$/,$d' "$SCORER"; cat "$1"; } > "$2.om"
    "$OMC" < "$2.om" > "$2" 2> "$2.err" || return 1
    chmod +x "$2"
}

# run_cases BIN QUIET: every case in cases.txt; prints ok/FAIL lines unless QUIET; returns failures
run_cases() {
    rc_bin=$1
    rc_fail=0
    while IFS='|' read -r c_name c_exit c_first c_line c_args; do
        case $c_name in ''|'#'*) continue ;; esac
        # shellcheck disable=SC2086
        c_out=$(cd "$HERE" && "$rc_bin" $c_args 2> /dev/null)
        c_rc=$?
        c_why=""
        [ "$c_rc" = "$c_exit" ] || c_why="exit $c_rc, expected $c_exit"
        c_got=$(printf '%s\n' "$c_out" | sed -n 1p)
        [ -n "$c_why" ] || [ "$c_got" = "$c_first" ] || c_why="first line '$c_got', expected '$c_first'"
        if [ -z "$c_why" ] && [ -n "$c_line" ]; then
            printf '%s\n' "$c_out" | grep -Fqx -- "$c_line" || c_why="no line '$c_line'"
        fi
        if [ -z "$c_why" ] && [ -n "$c_first" ]; then
            c_rules=$(printf '%s\n' "$c_out" | sed -n '2,6p' | cut -d' ' -f1 | tr '\n' ' ')
            [ "$c_rules" = "rule1 rule2 rule3 rule4 rule5 " ] || c_why="rule lines '$c_rules'"
        fi
        if [ -z "$c_why" ] && [ -z "$c_first" ] && [ -n "$c_out" ]; then
            c_why="usage error printed on stdout"
        fi
        if [ -n "$c_why" ]; then
            rc_fail=$((rc_fail + 1))
            [ "$2" = quiet ] || say "FAIL $c_name: $c_why"
        else
            [ "$2" = quiet ] || say "ok   $c_name ($c_first exit $c_rc)"
        fi
    done < "$HERE/cases.txt"
    return "$rc_fail"
}

# digests: every "sha256 <hex> <path>" line of one decision equals sha256sum of that file
check_digests() {
    cd_out=$(cd "$HERE" && "$1" om plain data/perm-0102 data/inc19 data/c1 data/c2 data/c3 2> /dev/null)
    cd_n=0
    cd_bad=0
    for cd_p in data/perm-0102 data/inc19/run.txt data/inc19/attempts.txt data/c1/run.txt \
        data/c1/attempts.txt data/c2/run.txt data/c2/attempts.txt data/c3/run.txt data/c3/attempts.txt; do
        cd_want="sha256 $(cd "$HERE" && sha256sum "$cd_p" | awk '{print $1}') $cd_p"
        cd_n=$((cd_n + 1))
        [ "$(printf '%s\n' "$cd_out" | sed -n "$((cd_n + 6))p")" = "$cd_want" ] || cd_bad=$((cd_bad + 1))
    done
    [ "$(printf '%s\n' "$cd_out" | wc -l)" = $((cd_n + 6)) ] || cd_bad=$((cd_bad + 1))
    return "$cd_bad"
}

say "== handover: build with omc $have"
build "$SRC" "$BUILD/handover" || not_run "handover.om does not build: $(cat "$BUILD/handover.err")"
say "== handover: known-verdict cases (TEST DATA)"
fails=0
run_cases "$BUILD/handover" loud || fails=$?
if check_digests "$BUILD/handover"; then
    say "ok   input digests equal sha256sum of every file read"
else
    say "FAIL input digests differ from sha256sum"
    fails=$((fails + 1))
fi

say "== handover: mutants (each must fail at least one case)"
survived=0
nm=0
while IFS='|' read -r m_name m_from m_to; do
    case $m_name in ''|'#'*) continue ;; esac
    nm=$((nm + 1))
    m_src=$BUILD/mutant-$m_name.om.src
    [ "$(grep -cFx -- "$m_from" "$SRC")" = 1 ] || {
        say "FAIL mutant $m_name: its line is not exactly once in handover.om: $m_from"
        survived=$((survived + 1))
        continue
    }
    awk -v f="$m_from" -v t="$m_to" '$0 == f { print t; next } { print }' "$SRC" > "$m_src"
    if ! build "$m_src" "$BUILD/mutant-$m_name"; then
        say "FAIL mutant $m_name does not compile: $(cat "$BUILD/mutant-$m_name.err")"
        survived=$((survived + 1))
        continue
    fi
    m_fail=0
    run_cases "$BUILD/mutant-$m_name" quiet || m_fail=$?
    if [ "$m_fail" -gt 0 ]; then
        say "ok   mutant $m_name killed by $m_fail case(s)"
    else
        say "FAIL mutant $m_name survived every case"
        survived=$((survived + 1))
    fi
done < "$HERE/mutants.txt"
[ "$nm" -gt 0 ] || { say "FAIL no mutants listed"; survived=$((survived + 1)); }

if [ "$fails" -eq 0 ] && [ "$survived" -eq 0 ]; then
    say "HANDOVER-TEST PASS cases ok, $nm mutants killed"
    exit 0
fi
say "HANDOVER-TEST FAIL $fails case failure(s), $survived mutant(s) survived or did not apply"
exit 1
