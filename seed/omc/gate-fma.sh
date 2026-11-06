#!/bin/sh
# Candidate-only AArch64 FMADD and exact-literal negative controls. No production pin is changed.
# Requires the settled source's seed fixpoint in seed/out/omc. All transforms and compilers are seeded .om.
set -eu
cd "$(dirname "$0")/../.."
S=seed/out/omc
T=seed/omc/tests/float
B=build/seed/fma
mkdir -p "$B"
bad() { printf 'FAIL gate-fma %s\n' "$*" >&2; exit 1; }
"$S" < "$T/fma.om" > "$B/control" 2> "$B/control.err" || bad 'control compile'
chmod +x "$B/control"
"$B/control" || bad 'control behavior'
printf 'PASS fused control exit 0\n'
"$S" < "$T/mutate.om" > "$B/mutate" 2> "$B/mutate.err" || bad 'mutator compile'
chmod +x "$B/mutate"
set +e
"$B/mutate" 0 < "$T/fma.om" > "$B/absent.om"
rc=$?
set -e
[ "$rc" = 93 ] || bad "absent-site control exit $rc, wanted 93"
printf 'PASS mutator absent-site refusal 93\n'
for mode in 0 1 2 3; do
    "$B/mutate" "$mode" < seed/omc/omc.om > "$B/m$mode.om" || bad "mutation $mode not exact-once"
    "$S" < "$B/m$mode.om" > "$B/m$mode" 2> "$B/m$mode.err" || bad "mutant $mode compile"
    chmod +x "$B/m$mode"
    if [ "$mode" = 0 ] || [ "$mode" = 1 ]; then
        "$B/m$mode" < "$T/fma.om" > "$B/probe$mode" 2> "$B/probe$mode.err" || bad "mutant $mode fixture compile"
        chmod +x "$B/probe$mode"
        set +e
        "$B/probe$mode"
        rc=$?
        set -e
        [ "$rc" != 0 ] || bad "mutant $mode survived"
        printf 'PASS mutant %s detected: fused fixture exit %s\n' "$mode" "$rc"
    else
        "$B/m$mode" < "$T/lit_round.om" > "$B/probe$mode" 2> "$B/probe$mode.err" || bad "mutant $mode literal compile"
        chmod +x "$B/probe$mode"
        "$B/probe$mode" > "$B/lit$mode.raw" || bad "mutant $mode literal run"
        od -An -v -tx8 -w8 "$B/lit$mode.raw" | tr -d ' ' > "$B/lit$mode.got"
        cut -d' ' -f1 "$T/lit_round.want" > "$B/lit.want"
        if cmp -s "$B/lit.want" "$B/lit$mode.got"; then bad "mutant $mode survived"; fi
        printf 'PASS mutant %s detected: literal bits differ\n' "$mode"
    fi
done
printf 'PASS gate-fma fused control, fail-closed mutator and 4 wrong-word/rounding mutants\n'
