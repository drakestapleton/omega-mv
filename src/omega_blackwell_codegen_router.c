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

/* omega_blackwell_codegen_router.c: the one-launch MoE router kernel.
 * Implementation lives in pure OM-2 (om/gpu/cg_router.om); this file is the thin fail-closed C ABI wrapper. */
#include "omega_blackwell_codegen_router.h"
#include "omega_bw_om_ir.h"
#include "omega_native.h"
#include <string.h>

static void router_pack_spec(const OmegaRouterSpec *s, uint64_t sp[8]) {
    memset(sp, 0, 8u * sizeof(uint64_t));
    sp[0] = s->warps;
    sp[1] = s->depth;
    sp[2] = (uint64_t)(int64_t)s->mutant;
    sp[3] = s->experts;
    sp[4] = s->shared;
    sp[5] = s->xstride;
    sp[6] = s->lbstride;
}

int omega_router_smem(const OmegaRouterSpec *spec, OmegaRouterSmem *m) {
    if (!spec || !m) return -1;
    const uint32_t ex = spec->experts ? spec->experts : OMEGA_ROUTER_EXPERTS;
    if ((ex != 128u && ex != 256u) || spec->shared > 1u) return -1;
    if (ex == OMEGA_ROUTER_EXPERTS && !spec->shared) {
        m->logit = OMEGA_ROUTER_SM_LOGIT; m->red = OMEGA_ROUTER_SM_RED; m->bc = OMEGA_ROUTER_SM_BC;
        m->sel = OMEGA_ROUTER_SM_SEL; m->selv = OMEGA_ROUTER_SM_SELV; m->total = OMEGA_ROUTER_SHARED_BYTES;
        return 0;
    }
    m->logit = OMEGA_ROUTER_SM_XN + OMEGA_ROUTER_HIDDEN * 4u;
    m->red = m->logit + (((ex + spec->shared) * 4u + 15u) & 0xfffffff0u);
    m->bc = m->red + 128u; m->sel = m->bc + 16u; m->selv = m->sel + 48u; m->total = m->selv + 32u;
    return 0;
}

int omega_blackwell_codegen_router_prog(const OmegaRouterSpec *spec, BlackwellIRProgram *prog) {
    if (!prog) return -1;
    omega_bw_ir_init(prog);
    if (!spec) return -1;
    uint64_t sp[8], ins[8192], meta[512], rc = 1;
    memset(ins, 0, sizeof ins);
    memset(meta, 0, sizeof meta);
    router_pack_spec(spec, sp);
    if (omega2_cg_router_emit(&rc, sp, 8u, ins, 8192u, meta, 512u) != 0 || rc != 0) return -1;
    return omega_bw_ir_from_om(ins, meta, prog);
}

int omega_router_prog_stats(const OmegaRouterSpec *spec, uint32_t *insns, uint32_t *gprs) {
    static BlackwellIRProgram prog;
    if (omega_blackwell_codegen_router_prog(spec, &prog) != 0) return -1;
    if (insns) *insns = (uint32_t)prog.count;
    if (gprs) *gprs = prog.regalloc.peak_gpr_usage;
    return 0;
}
