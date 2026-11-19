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

/* omega_blackwell_codegen_moe.c: FP8 e4m3 block-scaled GEMV kernel (OWN-30B Cut 6 / Cut 5).
 * Spec validation, IR emission (om/gpu/cg_moe.om), and sched=1 stall scheduling
 * (om/gpu/bw_sched.om) all run in pure seeded OM-2. */
#include "omega_blackwell_codegen_moe.h"
#include "omega_bw_om_ir.h"
#include "omega_native.h"
#ifndef OMEGA_GPU_NO_POSIX
#include <stdlib.h>
#endif

static void moe_pack_spec(const OmegaFp8GemvSpec *s, uint64_t sp[8]) {
    sp[0] = s->k;
    sp[1] = s->lane_bytes;
    sp[2] = s->rows;
    sp[3] = s->warps;
    sp[4] = (uint64_t)(uint32_t)s->mutant;
    sp[5] = s->depth;
    sp[6] = s->sched;
    sp[7] = (s->coal > 1u || s->wfirst > 1u) ? 4u : ((uint64_t)s->coal | ((uint64_t)s->wfirst << 1));
}

static int moe_spec_ok(const OmegaFp8GemvSpec *s) {
    if (!s) return 0;
    uint64_t sp[8], ok = 0;
    moe_pack_spec(s, sp);
    if (omega2_cg_moe_ok(&ok, sp, 8u) != 0) return 0;
    return ok != 0;
}

uint32_t omega_fp8_gemv_steps(const OmegaFp8GemvSpec *spec) {
    return moe_spec_ok(spec) ? spec->k / (32u * spec->lane_bytes) : 0u;
}

uint32_t omega_fp8_gemv_shared_bytes(const OmegaFp8GemvSpec *spec) {
    if (!moe_spec_ok(spec)) return 0u;
    uint32_t xsb = spec->depth ? spec->k * 4u + 16u : 0u;
    uint32_t osb = spec->warps * spec->rows * 4u;
    return xsb + (spec->coal ? 2u * osb : 0u);
}

int omega_blackwell_codegen_fp8_gemv_prog(const OmegaFp8GemvSpec *spec, BlackwellIRProgram *prog) {
    if (!spec || !prog) return -1;
    uint64_t sp[8], ins[8192], meta[512], rc = 1;
    moe_pack_spec(spec, sp);
    if (omega2_cg_moe_emit(&rc, sp, 8u, ins, 8192u, meta, 512u) != 0 || rc != 0) return -1;
    if (omega_bw_ir_from_om(ins, meta, prog) != 0) return -1;
    if (spec->sched) {
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
    }
    return 0;
}

int omega_fp8_gemv_prog_stats(const OmegaFp8GemvSpec *spec, uint32_t *insns, uint32_t *gprs) {
    static BlackwellIRProgram prog;
    if (omega_blackwell_codegen_fp8_gemv_prog(spec, &prog) != 0) return -1;
    if (insns) *insns = (uint32_t)prog.count;
    if (gprs) *gprs = prog.regalloc.peak_gpr_usage;
    return 0;
}

#ifndef OMEGA_GPU_NO_POSIX
int omega_blackwell_codegen_fp8_gemv(const OmegaFp8GemvSpec *spec, OmegaBlackwellKernel *kernel) {
    if (!kernel) return -1;
    BlackwellIRProgram *prog = calloc(1, sizeof *prog);
    if (!prog) return -1;
    int rc = omega_blackwell_codegen_fp8_gemv_prog(spec, prog);
    size_t need = rc == 0 ? omega_bw_program_code_bytes(prog) : 0;
    uint8_t *buf = need ? malloc(need) : NULL;
    if (!buf) { free(prog); return -1; }
    rc = omega_blackwell_kernel_encode_into(prog, buf, need, kernel);
    free(prog);
    if (rc != 0) { free(buf); return -1; }
    return 0;
}
#endif
