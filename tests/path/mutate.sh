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

# TEST HARNESS: PATH-1 mutation oracle. Each mutant edits a scratch copy of
# src/path/rx_path.om, never the source. A mutant counts as killed only when it
# compiles with seed/out/omc and the test program reports at least one FAIL line.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
omc=${OMC:-"$root/seed/out/omc"}
scratch=$(mktemp -d "${TMPDIR:-/tmp}/omega-path-mutants.XXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
killed=0
total=0
run() {
    name=$1
    expression=$2
    total=$((total+1))
    cp "$root/src/path/rx_path.om" "$scratch/orig.om"
    sed "$expression" "$scratch/orig.om" > "$scratch/mutant.om"
    if cmp -s "$scratch/orig.om" "$scratch/mutant.om"; then
        echo "MUTANT $name: mutation did not apply" >&2; exit 1
    fi
    # A compiler error does not count as an invariant caught by tests.
    cat "$scratch/mutant.om" "$root/tests/path/test_path_identity.om" | "$omc" > "$scratch/test"
    chmod +x "$scratch/test"
    if "$scratch/test" > "$scratch/log" 2>&1; then
        echo "MUTANT $name: SURVIVED" >&2; cat "$scratch/log" >&2; exit 1
    fi
    if ! grep -q '^FAIL ' "$scratch/log"; then
        echo "MUTANT $name: crashed without assertion evidence" >&2; cat "$scratch/log" >&2; exit 1
    fi
    killed=$((killed+1))
    echo "MUTANT $name: killed"
}
run semantic-tag 's/text t_rxp_sem_tag "omega.path.v1"/text t_rxp_sem_tag "omega.path.v2"/'
run tag-terminator '/^fn rxp_raw_semantic_id/,/^end/{/rxp_emit_byte 0/d;}'
run little-endian '/^fn rxp_emit_u16/,/^end/{s/rxp_emit_byte b0/rxp_emit_byte X/;s/rxp_emit_byte b1/rxp_emit_byte b0/;s/rxp_emit_byte X/rxp_emit_byte b1/;};s/or shl b0 8 b1/or shl b1 8 b0/'
run step-limit 's/if ge rx_path_step_count pid RX_PATH_MAX_STEPS/if gt rx_path_step_count pid RX_PATH_MAX_STEPS/'
run input-limit 's/if gt nin RX_PATH_MAX_INPUTS_PER_STEP/if gt nin add RX_PATH_MAX_INPUTS_PER_STEP 1/'
run size-limit 's/if gt add ulong sz ssz RX_PATH_MAX_TOTAL_SERIALIZATION/if false/'
run attr-sort '/^fn rx_path_add_attribute/,/^end/{s/if ge rxp_key_cmp_slot_tmp add abase pos klen 0/if false/;}'
run constraint-sort '/^fn rx_path_add_constraint/,/^end/{s/if gt rxp_cons_cmp_slot_tmp add cbase pos kind plen 0/if false/;}'
run step-index-check 's/if ne ulong sidx idx/if false/'
run steps-payload-len 's/if ne ulong slen sub get g_rd 0 get g_rd 1/if false/'
run trailing-bytes 's/if ne get g_rd 1 get g_rd 0/if false/'
run magic 's/if or ne get g_dec_in p 79 ne get g_dec_in add p 1 77/if false/'
run family-role 's/if ne shr role 8 family/if false/'
run expected-id 's/rc = RX_PATH_ERR_ID_MISMATCH/rc = RX_PATH_OK/'
run parent-frozen 's/put g_p_frozen parent 1/put g_p_frozen parent 0/'
run lineage-check '/^fn rxp_check_lineage/,/^end/{s/ret RX_PATH_ERR_ID_MISMATCH/ret RX_PATH_OK/;}'
run divergence-bound 's/if gt div_idx rx_path_step_count parent/if gt div_idx add 1 rx_path_step_count parent/'
run prefix-resolve 's/if and ge par 0 lt i divi/if and ge par 0 le i divi/'
run realization-machine '/^fn rx_path_realization_id/,/^end/{/while lt i 32/,/end/{s/rxp_emit_byte get g_real_ids i/rxp_emit_byte 0/;};}'
run realization-evidence '/^fn rx_path_realization_id/,/^end/{/while lt i 128/,/end/{s/rxp_emit_byte get g_real_ids i/rxp_emit_byte 0/;};}'
run shape-check 's/ret rxp_check_step_fields.*/ret RX_PATH_OK/'
run ancestor-fork 's/if eq ulong q child/if false/'
run encode-lineage '/^fn rx_path_encode/,/^end/{s/rc = rxp_check_lineage pid/rc = RX_PATH_OK/;}'
run equal-constraints 's/if gt rxp_cons_cmp_slots sub sl 1 sl 0/if ge rxp_cons_cmp_slots sub sl 1 sl 0/'
echo "PATH mutations: $killed killed, $((total-killed)) survived ($total total)"
