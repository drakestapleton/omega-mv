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

# C4 mutant check (pure seeded OM-2): each mutant weakens one recovery/isolation
# guard in a COPY of src/runtime/rx_compose.om, rebuilds tests/runtime/rx_c4_requal.om
# via seed/out/omc and runs it. A mutant is KILLED when the harness fails (exit
# nonzero, FAIL line printed), SURVIVED when it still passes, ERROR when it did
# not build or the edit did not apply. Exit 0 only if every mutant is KILLED.
#   usage: tools/c4_requal_mutants.sh [out.json]
set -u
root=$(git rev-parse --show-toplevel)
out=${1:-"$root/build/c4_mutants.json"}
omc=${OMC:-"$root/seed/out/omc"}
[ -x "$omc" ] || { echo "missing seeded compiler $omc" >&2; exit 2; }

# id~file~sed expression~what the original check does[~class~rationale]
MUTANTS='
M01~src/runtime/rx_compose.om~s/if ne rxc_bind_check get rxc_subj 3 get rxc_st 6 get rxc_st 7 w_id w_gen RXC_OK/if eq ulong 1 0/~refuse commit when commit binder rejects winner
M02~src/runtime/rx_compose.om~s/put rxc_last_res 0 RXC_OUT_NOT_COMMITTED/put rxc_last_res 0 RXC_OUT_COMMITTED/~report NOT_COMMITTED on binder refusal
M03~src/runtime/rx_compose.om~s/put rxc_last_res 7 rxc_reclaim_staged/put rxc_last_res 7 0/~reclaim staged branches after goal run
M04~src/runtime/rx_compose.om~s/if eq winner RXC_NONE/if eq ulong 1 0/~refuse commit when neither candidate passes AEGIS contract
M05~src/runtime/rx_compose.om~s/put rxc_br add wb 3 0/put rxc_br add wb 3 1/~unstage winning branch upon seal
M06~src/runtime/rx_compose.om~s/if eq k RXC_WREC_T_START_NS/if eq ulong 1 0/~mask start timestamp in deterministic record digest
M07~src/runtime/rx_compose.om~s/if eq k RXC_WREC_T_END_NS/if eq ulong 1 0/~mask end timestamp in deterministic record digest
M08~src/runtime/rx_compose.om~s/if lt k add RXC_WREC_DIGEST0 4/if eq ulong 1 0/~mask volatile crumb digest words in record digest
'
copy="seed/ng/sha256.om src/runtime/rx_compose.om tests/runtime/rx_c4_requal.om"
build="mkdir -p build && ( echo om2; sed -e '/^om2$/d' -e 's/^export fn /fn /' seed/ng/sha256.om src/runtime/rx_compose.om tests/runtime/rx_c4_requal.om ) | \"$omc\" > build/rx_c4_requal_om && chmod +x build/rx_c4_requal_om"
test_cmd='./build/rx_c4_requal_om'

res=$(printf '%s\n' "$MUTANTS" | "$root/tools/mutation_runner.sh" -B -k table -m - -t "$test_cmd" \
    -d "$root" -b "$build" -e "empty build log" \
    -c "$copy" -o "$out" -f FAIL)
rc=$?
printf '%s\n' "$res"
case $res in "mutants: 0 total,"*) rc=0;; esac
exit $rc
