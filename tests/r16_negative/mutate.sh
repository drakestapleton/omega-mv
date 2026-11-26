#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Drake Stapleton (AIEN / aien-dev)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# R16-G4 guard mutants (spec/r16-orchestrator-retirement.md §5 R16-G4:
# "removing any one guard turns the test red") — pure seeded OM-2.
#
# Usage: tests/r16_negative/mutate.sh [omc] [sources...]
#
# For each mutant, one guard is removed from a scratch copy of one .om file
# (the tree is never edited), the G4 test is rebuilt with seed/out/omc using
# that copy in place of the original, and run. A mutant is KILLED when the test
# does not print its gate PASS line ("R16 gate: R16_G4_LEGACY_REFUSED=PASS").
# Every mutant must be killed. The unmutated control build must pass, and every
# edit must apply exactly where named, or the run fails. Host only; no chip.
set -u
OMC=${1:-seed/out/omc}
if [ $# -ge 1 ]; then shift; fi
if [ $# -ge 1 ]; then
    srcs="$*"
else
    srcs="seed/authority/cap_table_om2.om src/runtime/rx_caproot.om src/runtime/rx_operator.om src/runtime/rx_aegis.om tests/runtime/rx_r16_negative.om"
fi
[ -x "$OMC" ] || { echo "R16-G4 mutants: missing seeded compiler $OMC" >&2; exit 2; }
tmp=$(mktemp -d "${TMPDIR:-/tmp}/r16-mutants.XXXXXX") || exit 2
trap 'rm -rf "$tmp"' EXIT INT TERM
. "$(dirname "$0")/../../tools/mutpool.sh"; mp_init || exit 2

# replace FILE OUT OCCURRENCE: literal OLD (env R16_OLD) -> NEW (env R16_NEW).
# OCCURRENCE is a number (only that match) or "all". Fails unless it applied.
replace() {
    awk -v nth="$3" '
        BEGIN { old = ENVIRON["R16_OLD"]; new = ENVIRON["R16_NEW"]; seen = 0; done = 0 }
        {
            line = $0
            p = index(line, old)
            if (p > 0) {
                seen++
                if (nth == "all" || seen == nth + 0) {
                    line = substr(line, 1, p - 1) new substr(line, p + length(old))
                    done++
                }
            }
            print line
        }
        END { if (done == 0) exit 3 }' "$1" > "$2"
}

build_run() {  # name out-dir sources
    name=$1; d=$2; use_srcs=$3
    # shellcheck disable=SC2086
    if ! ( echo om2; sed -e '/^om2$/d' -e 's/^export fn /fn /' $use_srcs ) | "$OMC" > "$d/g4" 2> "$d/build.log"; then
        return 2
    fi
    chmod +x "$d/g4"
    timeout 60 "$d/g4" > "$d/run.log" 2>&1
    if grep -q "^R16 gate: R16_G4_LEGACY_REFUSED=PASS" "$d/run.log"; then
        return 0
    fi
    return 1
}

mutant() { mp_run mutant_job "$@"; }
mutant_job() {
    name=$1; file=$2; nth=$3
    d="$tmp/$name"; mkdir -p "$d"
    base=$(basename "$file")
    if ! R16_OLD=$4 R16_NEW=$5 replace "$file" "$d/$base" "$nth"; then
        echo "R16-G4 mutant $name: edit did not apply  BROKEN"; return
    fi
    use_srcs=""
    for s in $srcs; do
        if [ "$s" = "$file" ]; then use_srcs="$use_srcs $d/$base"; else use_srcs="$use_srcs $s"; fi
    done
    build_run "$name" "$d" "$use_srcs"
    case $? in
        0) echo "R16-G4 mutant $name: test still PASSES  SURVIVED" ;;
        1) why=$(grep -E 'FAIL|not refused|ACCEPTED|changed' "$d/run.log" | head -1)
           [ -n "$why" ] || why="exit or missing gate line: $(tail -1 "$d/run.log")"
           echo "R16-G4 mutant $name: test red  KILLED  ($why)" ;;
        *) echo "R16-G4 mutant $name: build failed  BROKEN ($(head -1 "$d/build.log"))"
    esac
}

CT=seed/authority/cap_table_om2.om
CR=src/runtime/rx_caproot.om
AE=src/runtime/rx_aegis.om

# control: the unmutated build must pass, or nothing below means anything
mkdir -p "$tmp/control"
if ! build_run control "$tmp/control" "$srcs"; then
    echo "R16-G4 mutants: control build does not pass (see run below)"
    tail -5 "$tmp/control/run.log" "$tmp/control/build.log" 2>/dev/null
    echo "R16 G4 mutants: CONTROL FAIL"; exit 1
fi
echo "R16-G4 control (no guard removed): PASS"

# Capability root token and authority guards
mutant cap_token_check $CR 1 'if ne diff 0' 'if eq ulong 1 0'
mutant cap_mint_token_gate $CR 1 'if ne trc ERR_OK' 'if eq ulong 1 0'
mutant cap_mint_auth_right $CT 1 'arc = auth_check hdr slots delivered aid agen RIGHT_MINT' 'arc = ERR_OK'
mutant cap_clock_auth_right $CT 1 'arc = auth_check hdr slots delivered get args 0 get args 1 RIGHT_CLOCK' 'arc = ERR_OK'
mutant cap_epoch_auth_right $CT 1 'arc = auth_check hdr slots delivered aid agen RIGHT_EPOCH' 'arc = ERR_OK'
mutant cap_validate_revoked $CT 2 'if ne get slots add base 2 STATE_LIVE' 'if eq ulong 1 0'
mutant cap_validate_subject $CT 1 'if ne get slots add base 4 get args 2' 'if eq ulong 1 0'

# AEGIS policy and install-check guards
mutant aegis_privileged_deny $AE 1 'if ne and rights RX_AEGIS_RIGHT_PRIVILEGED 0' 'if eq ulong 1 0'
mutant aegis_no_rule_deny $AE 1 'put res 1 RX_AEGIS_WHY_NO_RULE' 'put res 1 0'
mutant aegis_human_reject $AE 1 'if ne get in_f 7 RX_AEGIS_APPROVE' 'if eq ulong 1 0'
mutant aegis_install_seq $AE 1 'if ne get dec 0 get req 0' 'if eq ulong 1 0'

mp_wait > "$tmp/mutants.log"; pool_rc=$?
cat "$tmp/mutants.log"
total=$(grep -c '^R16-G4 mutant ' "$tmp/mutants.log")
killed=$(grep -c '^R16-G4 mutant .*: test red  KILLED  (' "$tmp/mutants.log")
survived=$(grep -c '^R16-G4 mutant .*: test still PASSES  SURVIVED$' "$tmp/mutants.log")
broken=$(grep -c '^R16-G4 mutant .*  BROKEN' "$tmp/mutants.log")
echo "R16 G4 mutants: $total total, $killed killed, $survived survived, $broken broken"
if [ $survived -eq 0 ] && [ $broken -eq 0 ] && [ $pool_rc -eq 0 ] && [ $killed -eq $total ]; then
    echo "R16 gate: R16_G4_GUARDS_LOAD_BEARING=PASS"; exit 0
fi
echo "R16 gate: R16_G4_GUARDS_LOAD_BEARING=FAIL"; exit 1
