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

/*
 * omega_blackwell_codegen_dec.c: thin C ABI wrapper over the pure OM-2
 * decode glue kernels emitter in om/gpu/cg_dec.om.
 */
#include "omega_blackwell_codegen_dec.h"
#include "omega_bw_om_ir.h"
#include "omega_native.h"

int omega_blackwell_codegen_dec_prog(const OmegaDecSpec *spec, BlackwellIRProgram *prog) {
    if (!prog) return -1;
    omega_bw_ir_init(prog);
    if (!spec) return -1;
    static uint64_t ins[8192], meta[512];
    uint64_t sp[8] = {
        (uint64_t)(uint32_t)spec->kind,
        (uint64_t)spec->mode,
        (uint64_t)spec->stride,
        (uint64_t)(uint32_t)spec->mutant,
        (uint64_t)spec->width,
        (uint64_t)spec->groups,
        0, 0
    };
    uint64_t rc = 1;
    if (omega2_cg_dec_emit(&rc, sp, 8u, ins, 8192u, meta, 512u) != 0 || rc != 0) return -1;
    return omega_bw_ir_from_om(ins, meta, prog);
}

int omega_dec_prog_stats(const OmegaDecSpec *spec, uint32_t *insns, uint32_t *gprs) {
    static BlackwellIRProgram prog;
    if (omega_blackwell_codegen_dec_prog(spec, &prog) != 0) return -1;
    if (insns) *insns = (uint32_t)prog.count;
    if (gprs) *gprs = prog.regalloc.peak_gpr_usage;
    return 0;
}
