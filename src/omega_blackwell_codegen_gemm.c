/* SPDX-License-Identifier: Apache-2.0
 * Copyright 2026 Drake Stapleton (AIEN / aien-dev)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/* omega_blackwell_codegen_gemm.c: FP8 e4m3 block-scaled grouped GEMM for prefill.
 * Spec validation, IR emission (om/gpu/cg_gemm.om), and stall scheduling
 * (om/gpu/bw_sched.om) all run in pure seeded OM-2. */
#include "omega_blackwell_codegen_gemm.h"
#include "omega_bw_om_ir.h"
#include "omega_native.h"

static void gemm_pack_spec(const OmegaFp8GemmSpec *s, uint64_t sp[8]) {
    sp[0] = s->k;
    sp[1] = s->lane_bytes;
    sp[2] = s->mt;
    sp[3] = s->warps;
    sp[4] = (uint64_t)(uint32_t)s->mutant;
    sp[5] = s->rowmap;
    sp[6] = 0;
    sp[7] = 0;
}

static int gemm_spec_ok(const OmegaFp8GemmSpec *s) {
    if (!s) return 0;
    uint64_t sp[8], ok = 0;
    gemm_pack_spec(s, sp);
    if (omega2_cg_gemm_ok(&ok, sp, 8u) != 0) return 0;
    return ok != 0;
}

uint32_t omega_fp8gemm_steps(const OmegaFp8GemmSpec *spec) {
    return gemm_spec_ok(spec) ? spec->k / (32u * spec->lane_bytes) : 0u;
}

uint32_t omega_fp8gemm_shared_bytes(const OmegaFp8GemmSpec *spec) {
    return gemm_spec_ok(spec) ? spec->mt * 128u * spec->lane_bytes : 0u;
}

int omega_blackwell_codegen_fp8gemm_prog(const OmegaFp8GemmSpec *spec, BlackwellIRProgram *prog) {
    if (!spec || !prog) return -1;
    uint64_t sp[8], ins[8192], meta[512], rc = 1;
    gemm_pack_spec(spec, sp);
    if (omega2_cg_gemm_emit(&rc, sp, 8u, ins, 8192u, meta, 512u) != 0 || rc != 0) return -1;
    if (omega_bw_ir_from_om(ins, meta, prog) != 0) return -1;
    const size_t n = prog->count;
    uint64_t phys[BW_MAX_VREGS], bsz[BW_MAX_VREGS];
    for (int v = 0; v < BW_MAX_VREGS; v++) {
        phys[v] = (v < prog->regalloc.num_vregs) ? (uint64_t)(int64_t)prog->regalloc.vreg_to_phys[v] : (uint64_t)-1;
        bsz[v] = (v < prog->regalloc.num_vregs && prog->regalloc.intervals[v].bundle_size) ? prog->regalloc.intervals[v].bundle_size : 1u;
    }
    uint64_t res = 1;
    if (omega2_bw_sched_stalls(&res, ins, 8192u, phys, BW_MAX_VREGS, bsz, BW_MAX_VREGS, (uint64_t)n) != OMEGA_OK || res != 0)
        return -1;
    for (size_t i = 0; i < n; i++) prog->insns[i].control = (uint32_t)(ins[i * 8u + 6u] >> 32);
    return 0;
}

int omega_fp8gemm_prog_stats(const OmegaFp8GemmSpec *spec, uint32_t *insns, uint32_t *gprs) {
    static BlackwellIRProgram prog;
    if (omega_blackwell_codegen_fp8gemm_prog(spec, &prog) != 0) return -1;
    if (insns) *insns = (uint32_t)prog.count;
    if (gprs) *gprs = prog.regalloc.peak_gpr_usage;
    return 0;
}
