#!/bin/sh
# TEST INSTRUMENT: existing host-word pool fixtures, refusals and compiler mutants, with a supplied compiler runner.
set -eu
cd "$(dirname "$0")/../../.."
OMC=${1:-${OMC:-seed/out/omc}}
OMC=$(readlink -f "$OMC")
[ -x "$OMC" ] || { echo 'HOSTPOOL NOT_RUN: compiler missing' >&2; exit 3; }
mkdir -p build/seed/hostpool
B=$(mktemp -d build/seed/hostpool/owner.XXXXXX)
trap 'rm -rf "$B"' EXIT HUP INT TERM
python3 seed/host/hostpool/oracle.py > "$B/oracle.out" || { echo 'HOSTPOOL FAIL: oracle failed' >&2; exit 1; }
cmp "$B/oracle.out" seed/host/hostpool/env70.want || { echo 'HOSTPOOL FAIL: environment fixture differs from oracle' >&2; exit 1; }
"$OMC" < seed/qualification/om2/gate.om > "$B/gate"
chmod +x "$B/gate"
pin=$(sha256sum "$OMC")
pin=${pin%% *}
"$B/gate" "$OMC" "$pin" seed/host/hostpool/hostpool.cases "$B/cases"
echo 'HOSTPOOL PASS: fixture, legacy pool operands, oracle, refusals and mutants'
