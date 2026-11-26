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

# Pure seeded OM-2 Omega GPU Engine mutation sweep over src/omega_gpu_engine.om.
# Thin adapter over tools/mutation_runner.sh (-k table -B).
# Breaks each protection in src/omega_gpu_engine.om in a scratch tree, rebuilds
# tests/test_omega_gpu_engine.om with seed/out/omc, and requires it to FAIL.
# Host only, no GPU, no C compiler, no physics headers.
# Set GPU_ENGINE_MUT_OUT=path.json to also keep the JSON receipt.
set -u
cd "$(dirname "$0")/.." || exit 2
unset ONLY

OMC=$(cd "$(dirname "${OMC:-seed/out/omc}")" 2>/dev/null && pwd -P)/$(basename "${OMC:-seed/out/omc}")
[ -x "$OMC" ] || { echo "gpu_engine_mutations: missing executable omc at $OMC" >&2; exit 2; }

OM_SRCS="gpu/nvidia/native/nvrm/context.om om/gpu/bw_qmd.om om/gpu/bw_vecadd.om src/omega_gpu_platform.om src/omega_gpu_platform_linux.om src/omega_gpu_mem_cached.om src/omega_gpu_engine.om src/omega_blackwell_engine.om tests/test_omega_gpu_engine.om"
BUILD="(printf 'om2\n'; sed -e '/^om2$/d' -e 's/^export fn /fn /' $OM_SRCS) | \"$OMC\" > .gpu_engine_t && chmod +x .gpu_engine_t"

OUT=${GPU_ENGINE_MUT_OUT:-}
set -- -k table -m - -t ./.gpu_engine_t -b "$BUILD" \
    -c "$OM_SRCS" \
    -f 'FAIL' -B
[ -z "$OUT" ] || set -- "$@" -o "$OUT"

tools/mutation_runner.sh "$@" <<'ROWS'
# ---- job validation ----
VALIDATE_SKIPPED~src/omega_gpu_engine.om~R:if not oge_job_valid job@>@if false~oge_execute refuses an invalid job descriptor
VALID_PROGRAM~src/omega_gpu_engine.om~R:if eq get job 0 0@>@if false~zero program_len is refused
VALID_LAYOUT~src/omega_gpu_engine.om~R:if ne get job 1 OGE_LAYOUT_VECTOR_1D@>@if false~unsupported layout is refused
VALID_COUNT_ZERO~src/omega_gpu_engine.om~R:if eq n 0@>@if false~zero element_count is refused
VALID_INPUT_A_LEN~src/omega_gpu_engine.om~R:if ne get job 3 nbytes@>@if false~input A length mismatch is refused
VALID_INPUT_B_LEN~src/omega_gpu_engine.om~R:if ne get job 4 nbytes@>@if false~input B length mismatch is refused
VALID_OUTPUT_LEN~src/omega_gpu_engine.om~R:if ne get job 5 nbytes@>@if false~output length mismatch is refused
VALID_POISON_COUNT~src/omega_gpu_engine.om~R:if ne get job 6 n@>@if false~poison count mismatch is refused
VALID_FLAGS~src/omega_gpu_engine.om~R:if ne and get job 7 not OGE_FLAG_NO_C3 0@>@if false~unknown flags are refused
VALID_TIMEOUT_MARKER1~src/omega_gpu_engine.om~R:if eq get job 8 0@>@if false~zero marker1 timeout is refused
VALID_TIMEOUT_RELEASE~src/omega_gpu_engine.om~R:if eq get job 9 0@>@if false~zero release semaphore timeout is refused
VALID_TIMEOUT_VIS~src/omega_gpu_engine.om~R:if eq get job 11 0@>@if false~zero visibility timeout is refused
VALID_TIMEOUT_MARKER2~src/omega_gpu_engine.om~R:if eq get job 10 0@>@if false~zero marker2 timeout is refused when C3 active
# ---- block & backend guards ----
BLOCK_CHECK_SKIPPED~src/omega_gpu_engine.om~R:if ne oge_is_blocked 0@>@if false~latched uncertain-completion block refuses further jobs
BACKEND_NONE_SKIPPED~src/omega_gpu_engine.om~R:if eq bk OGE_BACKEND_NONE@>@if false~missing backend is refused as INTERNAL_INVARIANT
BACKEND_INCOMPLETE_SKIPPED~src/omega_gpu_engine.om~R:if eq bk OGE_BACKEND_INCOMPLETE@>@if false~incomplete backend is refused as INTERNAL_INVARIANT
# ---- resource tracking & cleanup ----
OPEN_NOT_TRACKED~src/omega_gpu_engine.om~R:opened = ulong 1@>@opened = ulong 0~opened device is tracked for cleanup close
ALLOC_NOT_TRACKED~src/omega_gpu_engine.om~R:alloc_mask = or alloc_mask shl ulong 1 role@>@alloc_mask = alloc_mask~allocated buffer roles are tracked for cleanup free
FREE_UNALLOCATED~src/omega_gpu_engine.om~R:if ne and alloc_mask shl ulong 1 i 0@>@if true~cleanup only frees allocated buffer roles
FREE_SKIPPED~src/omega_gpu_engine.om~R:rc = oge_be_free i@>@rc = ulong 0~cleanup actually calls free_buf
CLOSE_SKIPPED~src/omega_gpu_engine.om~R:rc = oge_be_close@>@rc = ulong 0~cleanup actually calls close
CLEANUP_OVERWRITES_FIRST~src/omega_gpu_engine.om~R:if eq get res 0 OGE_OK@>@if true~cleanup failure does not overwrite earlier failure
CLEANUP_FLAG_NOT_SET~src/omega_gpu_engine.om~R:put res 12 1@>@put res 12 0~cleanup fault sets cleanup_failed flag
# ---- state transitions ----
STATE_PREPARED_SKIPPED~src/omega_gpu_engine.om~R:put res 1 OGE_STATE_PREPARED@>@put res 1 OGE_STATE_INITIAL~PREPARED state is recorded before submit
STATE_SUBMITTED_SKIPPED~src/omega_gpu_engine.om~R:put res 1 OGE_STATE_SUBMITTED@>@put res 1 OGE_STATE_PREPARED~SUBMITTED state is recorded before wait
STATE_GPU_COMPLETE_SKIPPED~src/omega_gpu_engine.om~R:put res 1 OGE_STATE_GPU_COMPLETE@>@put res 1 OGE_STATE_SUBMITTED~GPU_COMPLETE state is recorded after wait
STATE_OUTPUT_VISIBLE_SKIPPED~src/omega_gpu_engine.om~R:put res 1 OGE_STATE_OUTPUT_VISIBLE@>@put res 1 OGE_STATE_GPU_COMPLETE~OUTPUT_VISIBLE state is recorded before poison scan
STATE_OUTPUT_PRODUCED_SKIPPED~src/omega_gpu_engine.om~R:put res 1 OGE_STATE_OUTPUT_PRODUCED@>@put res 1 OGE_STATE_OUTPUT_VISIBLE~OUTPUT_PRODUCED state is recorded before leave
SUCCESS_AFTER_CLEANUP_FAIL~src/omega_gpu_engine.om~R:if eq rc OGE_OK@>@if true~cleanup failure prevents SUCCESS state
STATE_SUCCESS_SKIPPED~src/omega_gpu_engine.om~R:put res 1 OGE_STATE_SUCCESS@>@put res 1 OGE_STATE_OUTPUT_PRODUCED~SUCCESS state is recorded on clean completion
# ---- waits, C3 flag, uncertain completion retention ----
MARKER1_WAIT_SKIPPED~src/omega_gpu_engine.om~R:rc = oge_be_wait_marker get job 8@>@rc = ulong 0~marker1 wait is enforced
MARKER1_TIMEOUT_WRONG~src/omega_gpu_engine.om~R:OGE_WAIT_MARKER get job 8 w@>@OGE_WAIT_MARKER get job 9 w~marker1 timeout limit is reported accurately
MARKER2_WAIT_SKIPPED~src/omega_gpu_engine.om~/^fn oge_wait_phase/,/oge_be_wait_marker2/ s/if eq and get job 7 OGE_FLAG_NO_C3 0/if false/~marker2 wait runs when C3 is active
C3_FLAG_IGNORED~src/omega_gpu_engine.om~/^fn oge_wait_phase/,/oge_be_wait_marker2/ s/if eq and get job 7 OGE_FLAG_NO_C3 0/if true/~NO_C3 flag skips marker2 wait
RELEASE_WAIT_SKIPPED~src/omega_gpu_engine.om~R:rc = oge_be_wait_sem get job 9@>@rc = ulong 0~release semaphore wait is enforced
WAITED_NOT_A_DIFFERENCE~src/omega_gpu_engine.om~/^fn oge_wait_phase/,/OGE_WAIT_MARKER/ s/w = sub t1 t0/w = t1/~waited_ms is t1 - t0, not raw t1
RETAINED_FLAG_NOT_SET~src/omega_gpu_engine.om~R:put res 11 1@>@put res 11 0~uncertain completion sets retained flag
NO_BLOCK~src/omega_gpu_engine.om~/^fn oge_uncertain/,/^end$/ s/put oge_blocked 0 1/put oge_blocked 0 0/~uncertain completion latches global block
UNCERTAIN_FREES~src/omega_gpu_engine.om~R:if ne rc OGE_OK@>@if false~uncertain wait does not fall through to leave/free
# ---- barrier, copy_out, poison scan ----
BARRIER_SKIPPED~src/omega_gpu_engine.om~R:if ne oge_be_barrier get job 11 0@>@if false~visibility barrier failure is reported
COPY_OUT_SKIPPED~src/omega_gpu_engine.om~R:if ne oge_be_copy_out get job 2 0@>@if false~copy_out failure is reported
POISON_SCAN_SKIPPED~src/omega_gpu_engine.om~R:if eq get oge_job_out i get oge_job_poison i@>@if false~poison scan checks output words against poison
UNCHANGED_COUNT_SATURATES~src/omega_gpu_engine.om~R:unchanged = add unchanged 1@>@unchanged = ulong 1~unchanged count counts all unchanged words
UNCHANGED_CHECK_SKIPPED~src/omega_gpu_engine.om~R:if ne unchanged 0@>@if false~nonzero unchanged count fails with OGE_OUTPUT_UNCHANGED
ROWS
