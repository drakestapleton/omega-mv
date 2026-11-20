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

/* omega_blackwell_codegen_qg.c: native FP8 prefill kernels (W-L1G).
 * Implementation lives in pure OM-2 (om/gpu/cg_qg.om); this file is the thin fail-closed C ABI wrapper. */
#include "omega_blackwell_codegen_qg.h"
#include "omega_bw_om_ir.h"
#include "omega_native.h"
#include <string.h>

static void pq_pack_spec(const OmegaPqSpec *s, uint64_t sp[8]) {
    memset(sp, 0, 8u * sizeof(uint64_t));
    sp[0] = s->k;
    sp[1] = s->in_type;
    sp[2] = (uint64_t)(int64_t)s->mutant;
    sp[3] = s->groups;
}

int omega_pq_spec_ok(const OmegaPqSpec *s) {
    if (!s) return 0;
    uint64_t sp[8], ok = 0;
    pq_pack_spec(s, sp);
    if (omega2_cg_pq_spec_ok(&ok, sp, 8u) != 0) return 0;
    return ok != 0 ? 1 : 0;
}

int omega_blackwell_codegen_pq_prog(const OmegaPqSpec *spec, BlackwellIRProgram *prog) {
    if (!prog) return -1;
    omega_bw_ir_init(prog);
    if (!spec) return -1;
    uint64_t sp[8], ins[8192], meta[512], rc = 1;
    memset(ins, 0, sizeof ins);
    memset(meta, 0, sizeof meta);
    pq_pack_spec(spec, sp);
    if (omega2_cg_pq_emit(&rc, sp, 8u, ins, 8192u, meta, 512u) != 0 || rc != 0) return -1;
    return omega_bw_ir_from_om(ins, meta, prog);
}

static void qg_pack_spec(const OmegaQgSpec *s, uint64_t sp[10]) {
    memset(sp, 0, 10u * sizeof(uint64_t));
    sp[0] = s->k;
    sp[1] = s->rt;
    sp[2] = s->warps;
    sp[3] = s->epi;
    sp[4] = s->direct;
    sp[5] = s->n;
    sp[6] = s->wait;
    sp[7] = (uint64_t)(int64_t)s->mutant;
}

int omega_qg_spec_ok(const OmegaQgSpec *s) {
    if (!s) return 0;
    uint64_t sp[10], ok = 0;
    qg_pack_spec(s, sp);
    if (omega2_cg_qg_spec_ok(&ok, sp, 10u) != 0) return 0;
    return ok != 0 ? 1 : 0;
}

uint32_t omega_qg_shared_bytes(const OmegaQgSpec *s) { return omega_qg_spec_ok(s) ? 2u * (16u * s->rt * 64u + 16u * s->rt * 4u) : 0u; }
uint32_t omega_qg_span(const OmegaQgSpec *s) { return omega_qg_spec_ok(s) ? s->warps * 16u : 0u; }

int omega_blackwell_codegen_qgemm_prog(const OmegaQgSpec *spec, BlackwellIRProgram *prog) {
    if (!prog) return -1;
    omega_bw_ir_init(prog);
    if (!spec) return -1;
    uint64_t sp[10], ins[8192], meta[512], rc = 1;
    memset(ins, 0, sizeof ins);
    memset(meta, 0, sizeof meta);
    qg_pack_spec(spec, sp);
    if (omega2_cg_qgemm_emit(&rc, sp, 10u, ins, 8192u, meta, 512u) != 0 || rc != 0) return -1;
    return omega_bw_ir_from_om(ins, meta, prog);
}
