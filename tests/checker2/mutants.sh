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

# Negative controls for checker2 (omega#446): every `note GUARD:<name>` tag in a pure OM-2
# checker2 source and the guarded line immediately following it are removed, one at a time, in a
# scratch copy; the matching OM-2 test is rebuilt with omc against that copy and MUST fail.
# A mutant that survives means the test cannot see that check, and this script fails.
# Also requires the unmutated build to pass first (otherwise "fails" proves nothing).
# Usage: sh tests/checker2/mutants.sh <omc> <scratch-dir> <ir-dir from differential.sh> <work-dir from lrat.sh>
set -u
OMC=${1:-seed/out/omc}
OUT=${2:-build/checker2/mutants}
IRDIR=${3:-build/checker2/differential/ir}
LRATDIR=${4:-build/checker2/lrat}
HDR="src/checker2/c2_om2_hdr.om"
CRYPTO="seed/ng/sha256.om protocol/omnet/om/sha512/sha512.om protocol/omnet/om/ed25519/ed25519.om protocol/uor-gpu/ed_sign.om"
mkdir -p "$OUT"
CORPUS_LIST="$OUT/corpus.list"
LRAT_LIST="$OUT/lrat.list"
ls -1 "$IRDIR"/*.ir >"$CORPUS_LIST" 2>/dev/null || true
ls -1 "$LRATDIR"/*.ir >"$LRAT_LIST" 2>/dev/null || true
total=0
tagged=0
killed=0
survived=""

# run_family <source under test .om> <prefix .om files> <suffix .om files> <test args>
run_family() {
    src=$1; pre=$2; suf=$3; targs=$4
    base="$OUT/$(basename "$src" .om)"
    # shellcheck disable=SC2086
    if ! cat $pre "$src" $suf | "$OMC" >"$base.orig" 2>"$base.orig.log"; then
        echo "mutants: baseline build failed for $src"; cat "$base.orig.log"; exit 1
    fi
    chmod +x "$base.orig"
    # shellcheck disable=SC2086
    if ! "$base.orig" $targs >/dev/null 2>&1; then
        echo "mutants: baseline test fails for $src; negative controls are meaningless"; exit 1
    fi
    # every "GUARD:" occurrence must be exactly one well-formed, unique tag on its own line, so the
    # number of mutants run equals the number of tags (an empty, malformed, repeated or doubled
    # tag would otherwise be skipped silently)
    occ=$(grep -o "GUARD:" "$src" | wc -l)
    names=$(grep -o "GUARD:[a-z0-9-]*" "$src" | sed "s/GUARD://" | grep -c . )
    uniq_names=$(grep -o "GUARD:[a-z0-9-]*" "$src" | sed "s/GUARD://" | grep . | sort -u | wc -l)
    lines=$(grep -c "GUARD:" "$src")
    if [ "$occ" -ne "$names" ] || [ "$names" -ne "$uniq_names" ] || [ "$names" -ne "$lines" ]; then
        echo "mutants: $src has $occ GUARD: occurrences on $lines lines but $uniq_names distinct well-formed tags"
        exit 1
    fi
    tagged=$((tagged + occ))
    for name in $(grep -o "GUARD:[a-z0-9-]*" "$src" | sed "s/GUARD://" | sort -u); do
        total=$((total + 1))
        m="$base.$name.om"
        # drop the `note GUARD:<name>` line AND the single guarded line immediately following it
        awk -v tag="GUARD:$name" '
            skip { skip = 0; next }
            index($0, tag) && substr($0, index($0, tag) + length(tag)) ~ /^([^a-z0-9-]|$)/ { skip = 1; next }
            { print }' "$src" > "$m"
        # shellcheck disable=SC2086
        if ! cat $pre "$m" $suf | "$OMC" >"$base.$name" 2>"$base.$name.log"; then
            echo "mutants: $src GUARD:$name does not build (counts as killed)"
            killed=$((killed + 1))
            continue
        fi
        chmod +x "$base.$name"
        # shellcheck disable=SC2086
        if timeout 120 "$base.$name" $targs >/dev/null 2>&1; then
            survived="$survived $src:$name"
        else
            killed=$((killed + 1))
        fi
    done
}

run_family src/checker2/c2_receipt.om "$HDR $CRYPTO" "tests/checker2/test_c2_receipt.om" "tests/checker2/fixtures"
run_family src/checker2/c2_ir.om "$HDR" "src/checker2/c2_check.om tests/checker2/test_c2_ir.om" "$CORPUS_LIST"
run_family src/checker2/c2_check.om "$HDR src/checker2/c2_ir.om" "tests/checker2/test_c2_ir.om" "$CORPUS_LIST"
run_family src/checker2/c2_lrat.om "$HDR" "tests/checker2/test_c2_lrat.om" ""
run_family src/checker2/c2_blast.om "$HDR src/checker2/c2_ir.om src/checker2/c2_check.om src/checker2/c2_lrat.om" "tests/checker2/test_c2_blast.om" "$CORPUS_LIST $LRAT_LIST"

echo "checker2 mutants: $killed of $total killed"
# every GUARD tag in the checker2 sources is covered by a family above (none silently skipped)
all=$(cat src/checker2/*.om | grep -o "GUARD:" | wc -l)
if [ "$all" -ne "$total" ] || [ "$tagged" -ne "$total" ]; then
    echo "mutants: $all GUARD tags in src/checker2 but $total mutants run"; exit 1
fi
if [ -n "$survived" ]; then
    echo "SURVIVED (a test cannot see this check):$survived"
    exit 1
fi
[ "$total" -gt 0 ] || { echo "mutants: no GUARD lines found"; exit 1; }
exit 0
