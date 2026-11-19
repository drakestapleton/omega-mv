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

/* omega_blackwell_codegen_bf16.c: bf16 streaming GEMV kernel (the lm_head).
 * Spec validation and IR emission run in pure seeded OM-2 (om/gpu/cg_bf16.om). */
#include "omega_blackwell_codegen_bf16.h"
#include "omega_bw_om_ir.h"
#include "omega_native.h"
#ifndef OMEGA_GPU_NO_POSIX
#include <stdlib.h>
#endif

static void bf16_pack_spec(const OmegaBf16GemvSpec *s, uint64_t sp[8]) {
    sp[0] = s->k;
    sp[1] = s->rows;
    sp[2] = s->warps;
    sp[3] = s->depth;
    sp[4] = (uint64_t)(uint32_t)s->mutant;
    sp[5] = s->ystride;
    sp[6] = s->xbatch;
    sp[7] = s->mask;
}

static int bf16_spec_ok(const OmegaBf16GemvSpec *s) {
    if (!s) return 0;
    uint64_t sp[8], ok = 0;
    bf16_pack_spec(s, sp);
    if (omega2_cg_bf16_ok(&ok, sp, 8u) != 0) return 0;
    return ok != 0;
}

uint32_t omega_bf16_gemv_steps(const OmegaBf16GemvSpec *spec) {
    return bf16_spec_ok(spec) ? spec->k / 256u : 0u;
}

uint32_t omega_bf16_gemv_shared_bytes(const OmegaBf16GemvSpec *spec) {
    return bf16_spec_ok(spec) ? spec->k * 4u * (spec->xbatch ? spec->xbatch : 1u) : 0u;
}

int omega_blackwell_codegen_bf16_gemv_prog(const OmegaBf16GemvSpec *spec, BlackwellIRProgram *prog) {
    if (!spec || !prog) return -1;
    omega_bw_ir_init(prog);
    uint64_t sp[8], ins[8192], meta[512], rc = 1;
    memset(ins, 0, sizeof ins);
    memset(meta, 0, sizeof meta);
    bf16_pack_spec(spec, sp);
    if (omega2_cg_bf16_emit(&rc, sp, 8u, ins, 8192u, meta, 512u) != 0 || rc != 0) return -1;
    return omega_bw_ir_from_om(ins, meta, prog);
}

int omega_bf16_gemv_prog_stats(const OmegaBf16GemvSpec *spec, uint32_t *insns, uint32_t *gprs) {
    static BlackwellIRProgram prog;
    if (omega_blackwell_codegen_bf16_gemv_prog(spec, &prog) != 0) return -1;
    if (insns) *insns = (uint32_t)prog.count;
    if (gprs) *gprs = prog.regalloc.peak_gpr_usage;
    return 0;
}

#ifndef OMEGA_GPU_NO_POSIX
int omega_blackwell_codegen_bf16_gemv(const OmegaBf16GemvSpec *spec, OmegaBlackwellKernel *kernel) {
    if (!kernel) return -1;
    BlackwellIRProgram *prog = calloc(1, sizeof *prog);
    if (!prog) return -1;
    int rc = omega_blackwell_codegen_bf16_gemv_prog(spec, prog);
    size_t need = rc == 0 ? omega_bw_program_code_bytes(prog) : 0;
    uint8_t *buf = need ? malloc(need) : NULL;
    if (!buf) { free(prog); return -1; }
    rc = omega_blackwell_kernel_encode_into(prog, buf, need, kernel);
    free(prog);
    if (rc != 0) { free(buf); return -1; }
    return 0;
}
#endif
