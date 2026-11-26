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

# Pure seeded OM-2 Omega GPU Engine BACKEND & submit-wrapper mutation sweep over
# src/omega_blackwell_engine.om and src/omega_blackwell_submit.om.
# Thin adapter over tools/mutation_runner.sh (-k table -B).
# Host only, no GPU, no C compiler, no physics headers.
# Set GPU_ENGINE_BMUT_OUT=path.json to also keep the JSON receipt.
set -u
cd "$(dirname "$0")/.." || exit 2
unset ONLY

OMC=$(cd "$(dirname "${OMC:-seed/out/omc}")" 2>/dev/null && pwd -P)/$(basename "${OMC:-seed/out/omc}")
[ -x "$OMC" ] || { echo "gpu_engine_backend_mutations: missing executable omc at $OMC" >&2; exit 2; }

OM_SRCS="gpu/nvidia/native/nvrm/context.om om/gpu/bw_qmd.om om/gpu/bw_vecadd.om src/omega_gpu_platform.om src/omega_gpu_platform_linux.om src/omega_gpu_mem_cached.om src/omega_gpu_engine.om src/omega_blackwell_engine.om src/omega_blackwell_submit.om tests/test_omega_blackwell_engine.om"
BUILD="(printf 'om2\n'; sed -e '/^om2$/d' -e 's/^export fn /fn /' $OM_SRCS) | \"$OMC\" > .gpu_engine_bt && chmod +x .gpu_engine_bt"

OUT=${GPU_ENGINE_BMUT_OUT:-}
set -- -k table -m - -t ./.gpu_engine_bt -b "$BUILD" \
    -c "$OM_SRCS" \
    -f 'FAIL' -B
[ -z "$OUT" ] || set -- "$@" -o "$OUT"

tools/mutation_runner.sh "$@" <<'ROWS'
# ---- Blackwell engine page rounding, pushbuffer & cbank ----
BE_ROUND_PAGES_ZERO_ACCEPTED~src/omega_blackwell_engine.om~R:if eq nbytes 0@>@if false~a zero-byte allocation rounds to 0 (refused)
BE_ROUND_PAGES_NO_ROUNDING~src/omega_blackwell_engine.om~R:v = and add nbytes 4095 not ulong 4095@>@v = nbytes~allocation sizes round up to 4 KiB pages
BE_PB_OVERFLOW_GUARD~src/omega_blackwell_engine.om~R:if ge pos 1024@>@if false~pushbuffer write refuses overflow past 1024 words
BE_PB_OVERFLOW_FLAG~src/omega_blackwell_engine.om~R:put obwe_pb_overflow 0 1@>@put obwe_pb_overflow 0 0~pushbuffer overflow latches obwe_pb_overflow
BE_SETUP_CLASS_WORD~src/omega_blackwell_engine.om~R:obwe_pb_put 0x0000cec0@>@obwe_pb_put 0x00000000~compute class 0xcec0 is emitted in setup
BE_DMA_BYTE_COUNT~src/omega_blackwell_engine.om~R:obwe_pb_put mul count 4@>@obwe_pb_put count~inline DMA sets byte count = words * 4
BE_DMA_NONINC_HDR~src/omega_blackwell_engine.om~R:obwe_pb_put or uint 0x6000206d shl count 16@>@obwe_pb_put uint 0x6000206d~inline DMA header encodes word count
BE_WFI_FLAG_RELEASE~src/omega_blackwell_engine.om~R:obwe_pb_put 0x00100001@>@obwe_pb_put 0x00000001~semaphore release carries WFI flag (bit 20)
BE_L2_FLUSH_METHOD~src/omega_blackwell_engine.om~R:obwe_mth 0 40 4@>@obwe_mth 0 44 4~L2 flush uses memory-operation method 0x0028
BE_L2_FLUSH_OP~src/omega_blackwell_engine.om~R:obwe_pb_put 0x80000000@>@obwe_pb_put 0x00000000~L2 flush operation word is L2_FLUSH_DIRTY
BE_CBANK_VA_HI~src/omega_blackwell_engine.om~R:put cb 68 uint shr va 32@>@put cb 68 0~cbank encodes high 32 bits of cbank VA
BE_CBANK_VA_LO~src/omega_blackwell_engine.om~R:put cb 69 uint and va 0xffffffff@>@put cb 69 0~cbank encodes low 32 bits of cbank VA
BE_CBANK_ARG_VA~src/omega_blackwell_engine.om~R:put cb 210 uint shr add va 896 32@>@put cb 210 0~cbank encodes parameter base VA (va+896)
BE_CBANK_THREADS~src/omega_blackwell_engine.om~R:put cb 216 64@>@put cb 216 32~cbank encodes 64 threads per block
BE_BUSY_OPEN_REFUSED~src/omega_blackwell_engine.om~/^fn obwe_be_open/,/^end$/ s/if ne get obwe_busy 0 0/if false/~second open while busy is refused
BE_BUSY_SHUTDOWN_REFUSED~src/omega_blackwell_engine.om~/^fn obwe_shutdown/,/^end$/ s/if ne get obwe_busy 0 0/if false/~shutdown while busy is refused
# ---- Blackwell submit wrapper (src/omega_blackwell_submit.om) ----
WRAP_NEEDLE_SCAN~src/omega_blackwell_submit.om~R:if ne get buf add i j get needle j@>@if false~libcuda runtime scanner matches needle bytes
WRAP_POISON_NOT_COMPLEMENT~src/omega_blackwell_submit.om~R:put oge_job_poison i xor uint s 0xffffffff@>@put oge_job_poison i uint s~poison word is bit-complement of expected sum
WRAP_POISON_CONSTANT~src/omega_blackwell_submit.om~R:put oge_job_poison i xor uint s 0xffffffff@>@put oge_job_poison i uint 0xdeadbeef~poison word never collides with 0xdeadbeef sum
WRAP_ORACLE_IGNORED~src/omega_blackwell_submit.om~R:if ne v uint s@>@if false~host oracle detects corrupted output word
WRAP_MARKER1_CHECK~src/omega_blackwell_submit.om~R:if ne get info 2 ulong OBWE_MARKER1_PAYLOAD@>@if false~wrapper verifies first completion marker payload
WRAP_MARKER2_CHECK~src/omega_blackwell_submit.om~R:if ne get info 3 ulong OBWE_MARKER2_PAYLOAD@>@if false~wrapper verifies second completion marker payload
WRAP_SEM_CHECK~src/omega_blackwell_submit.om~R:if ne get info 4 ulong OBWE_SEM_DONE@>@if false~wrapper verifies intermediate semaphore DONE (6)
WRAP_ELAPSED_TIME~src/omega_blackwell_submit.om~R:put exec_info 3 sub get info 1 get info 0@>@put exec_info 3 0~wrapper computes elapsed_ns = completion - launch
WRAP_BOUNDS_GUARD~src/omega_blackwell_submit.om~R:if or eq n 0 gt n 1024@>@if false~wrapper refuses n == 0 and n > 1024
ROWS
