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

/* omega_blackwell_codegen_pfhost.c: router logits and MoE combine for whole-prompt prefill (W-L1G-D).
 * Spec validation and IR emission run in pure seeded OM-2 (om/gpu/cg_pfhost.om). */
#include "omega_blackwell_codegen_pfhost.h"
#include "omega_bw_om_ir.h"
#include "omega_native.h"

int omega_rl_spec_ok(const OmegaRlSpec *s) {
    if (!s) return 0;
    uint64_t sp[8] = { s->k, s->e, s->t, (uint64_t)(uint32_t)s->mutant, 0, 0, 0, 0 };
    uint64_t ok = 0;
    if (omega2_cg_rl_ok(&ok, sp, 8u) != 0) return 0;
    return ok != 0;
}

uint32_t omega_rl_shared_bytes(const OmegaRlSpec *s) {
    return omega_rl_spec_ok(s) ? s->t * 512u : 0u;
}

int omega_blackwell_codegen_rl_prog(const OmegaRlSpec *spec, BlackwellIRProgram *prog) {
    if (!spec || !prog) return -1;
    omega_bw_ir_init(prog);
    uint64_t sp[8] = { spec->k, spec->e, spec->t, (uint64_t)(uint32_t)spec->mutant, 0, 0, 0, 0 };
    uint64_t ins[8192], meta[512], rc = 1;
    memset(ins, 0, sizeof ins);
    memset(meta, 0, sizeof meta);
    if (omega2_cg_rl_emit(&rc, sp, 8u, ins, 8192u, meta, 512u) != 0 || rc != 0) return -1;
    return omega_bw_ir_from_om(ins, meta, prog);
}

int omega_mc_spec_ok(const OmegaMcSpec *s) {
    if (!s) return 0;
    uint64_t sp[8] = { s->h, s->top_k, (uint64_t)(uint32_t)s->mutant, 0, 0, 0, 0, 0 };
    uint64_t ok = 0;
    if (omega2_cg_mc_ok(&ok, sp, 8u) != 0) return 0;
    return ok != 0;
}

int omega_blackwell_codegen_mc_prog(const OmegaMcSpec *spec, BlackwellIRProgram *prog) {
    if (!spec || !prog) return -1;
    omega_bw_ir_init(prog);
    uint64_t sp[8] = { spec->h, spec->top_k, (uint64_t)(uint32_t)spec->mutant, 0, 0, 0, 0, 0 };
    uint64_t ins[8192], meta[512], rc = 1;
    memset(ins, 0, sizeof ins);
    memset(meta, 0, sizeof meta);
    if (omega2_cg_mc_emit(&rc, sp, 8u, ins, 8192u, meta, 512u) != 0 || rc != 0) return -1;
    return omega_bw_ir_from_om(ins, meta, prog);
}
