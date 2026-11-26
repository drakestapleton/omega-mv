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

# Compile pure seeded OM-2 lifecycle wrappers with one safety check disabled at a time.
# Compilation failure is not a kill: each mutated binary must run and exit nonzero.
set -eu
ulimit -c 0
out=${1:?output directory required}
omc=${OMC:-seed/out/omc}
[ -x "$omc" ] || { echo "FAIL: missing seeded compiler $omc"; exit 2; }
mkdir -p "$out"
for mutant in POISON RETAIN EXACT; do
    dir="$out/$mutant"
    mkdir -p "$dir"
    sed "s/^const OMEGA_NL_MUTANT_${mutant} ulong 0$/const OMEGA_NL_MUTANT_${mutant} ulong 1/" \
        src/omega_numeric_lifecycle.om > "$dir/omega_numeric_lifecycle.om"
    if cmp -s src/omega_numeric_lifecycle.om "$dir/omega_numeric_lifecycle.om"; then
        echo "FAIL: mutation $mutant changed nothing"; exit 1
    fi
    (printf 'om2\n'; sed '/^om2$/d' "$dir/omega_numeric_lifecycle.om" tests/test_numeric_lifecycle.om) \
        | "$omc" > "$dir/test.tmp.$$"
    chmod +x "$dir/test.tmp.$$"
    mv -f "$dir/test.tmp.$$" "$dir/test"
    rc=0
    "$dir/test" > "$dir/output" 2>&1 || rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "FAIL: mutation $mutant survived"; cat "$dir/output"; exit 1
    fi
    echo "numeric lifecycle mutant $mutant: killed (rc=$rc)"
done
