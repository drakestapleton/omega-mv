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

# est_eval's prefix-invariance temp directory under the TMPDIR values the C est_eval
# (tools/estimation/est_eval.c, retired) handled specially. The C formed
# "$TMPDIR/est_eval_prefix_XXXXXX" with snprintf into char dir[600], so:
#   TMPDIR of 576 bytes (an existing directory): the check runs   -> "runs": 3, "pass": true
#   TMPDIR of 577 bytes (an existing directory): suffix truncated,
#     mkdtemp fails                                                -> "runs": 0, "pass": false
#   TMPDIR of 5000 bytes (longer than a 4096-byte environment read) -> "runs": 0, "pass": false
#   TMPDIR empty: /tmp                                             -> "runs": 3, "pass": true
# The expected lines were measured on the C est_eval built at main commit 3f2c70dc5.
#   tools/estimation/test_est_eval_tmpdir.sh <est_fit> <est_eval> <workdir>
set -u
FIT=${1:?est_fit}
EVAL=${2:?est_eval}
W=${3:?workdir}
RUNA=evidence/R15/raw/20260929T020536Z-ad8e1f2ea4e4-silicon
rm -rf "$W"; mkdir -p "$W"
W=$(cd "$W" && pwd)
pass=0; fail=0
"$FIT" "$RUNA/machine-state.ndjson" "$W/params.txt" > "$W/fit.out" 2>&1 || { echo "test_est_eval_tmpdir: est_fit failed"; exit 1; }

# mkpath <length>: an existing directory under $W whose absolute path is exactly <length> bytes
mkpath() {
    p=$W/t
    # 150-byte components while more than 250 bytes remain, then one component of the rest
    # (100 to 249 bytes), so no component passes NAME_MAX
    while [ $(($1 - ${#p})) -gt 250 ]; do
        p=$p/$(printf '%*s' 150 '' | tr ' ' d)
    done
    p=$p/$(printf '%*s' $(($1 - ${#p} - 1)) '' | tr ' ' e)
    mkdir -p "$p" && printf '%s' "$p"
}

case_run() {   # case_run <label> <TMPDIR value> <expected fragment>
    rm -f "$W"/rec.json*
    TMPDIR=$2 "$EVAL" --params "$W/params.txt" --raw "$RUNA/machine-state.ndjson" \
        --marks "$RUNA/machine-state-marks.txt" --out "$W/rec.json" > "$W/eval.out" 2>&1
    if [ -f "$W/rec.json" ] && grep -q "\"prefix_invariance\": {[^}]*$3" "$W/rec.json"; then
        pass=$((pass + 1)); echo "test_est_eval_tmpdir: $1 (TMPDIR ${#2} bytes): $3 PASS"
    else
        fail=$((fail + 1)); echo "test_est_eval_tmpdir: $1 (TMPDIR ${#2} bytes): expected $3 FAIL"
        grep -o '"prefix_invariance": {[^}]*}' "$W/rec.json" 2>/dev/null | head -1
    fi
}

d576=$(mkpath 576); d577=$(mkpath 577)
[ "${#d576}" -eq 576 ] && [ "${#d577}" -eq 577 ] || { echo "test_est_eval_tmpdir: could not build the test directories (${#d576}, ${#d577})"; exit 1; }
long=$(printf '%*s' 4999 '' | tr ' ' l); long=/$long
case_run "576-byte TMPDIR" "$d576" '"runs": 3, "pass": true'
case_run "577-byte TMPDIR" "$d577" '"runs": 0, "pass": false'
case_run "5000-byte TMPDIR" "$long" '"runs": 0, "pass": false'
case_run "empty TMPDIR" "" '"runs": 3, "pass": true'
echo "test_est_eval_tmpdir: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
