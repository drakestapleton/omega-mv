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

/* omega_blackwell_codegen_tc2.c: tensor-core grouped FP8 GEMM v2 (OWN-30B T3b).
 * Implementation lives in pure OM-2 (om/gpu/cg_tc2.om); this file is the thin fail-closed C ABI wrapper. */
#include "omega_blackwell_codegen_tc2.h"
#include "omega_bw_om_ir.h"
#include "omega_native.h"
#include <string.h>

static void tc2_pack_spec(const OmegaTc2Spec *s, uint64_t sp[10]) {
    sp[0] = s->k;
    sp[1] = s->rt;
    sp[2] = s->ct;
    sp[3] = s->warps;
    sp[4] = s->aqn;
    sp[5] = s->epi;
    sp[6] = s->direct;
    sp[7] = s->n;
    sp[8] = (uint64_t)(int64_t)s->mutant;
    sp[9] = 0;
}

int omega_tc2_spec_ok(const OmegaTc2Spec *s) {
    if (!s) return 0;
    uint64_t sp[10], ok = 0;
    tc2_pack_spec(s, sp);
    if (omega2_cg_tc2_spec_ok(&ok, sp, 10u) != 0) return 0;
    return ok != 0 ? 1 : 0;
}

uint32_t omega_tc2_shared_bytes(const OmegaTc2Spec *s) { return omega_tc2_spec_ok(s) ? 2u * 16u * s->rt * 128u : 0u; }
uint32_t omega_tc2_span(const OmegaTc2Spec *s) { return omega_tc2_spec_ok(s) ? s->warps * 8u * s->ct : 0u; }

int omega_blackwell_codegen_tc2_prog(const OmegaTc2Spec *spec, BlackwellIRProgram *prog) {
    if (!prog) return -1;
    omega_bw_ir_init(prog);
    if (!spec) return -1;
    uint64_t sp[10], ins[8192], meta[512], rc = 1;
    memset(ins, 0, sizeof ins);
    memset(meta, 0, sizeof meta);
    tc2_pack_spec(spec, sp);
    if (omega2_cg_tc2_emit(&rc, sp, 10u, ins, 8192u, meta, 512u) != 0 || rc != 0) return -1;
    return omega_bw_ir_from_om(ins, meta, prog);
}
