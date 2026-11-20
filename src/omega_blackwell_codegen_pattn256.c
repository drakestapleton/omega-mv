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

/* omega_blackwell_codegen_pattn256.c: causal prefill attention for Qwen3.8-27B on tensor cores.
 * Implementation lives in pure OM-2 (om/gpu/cg_pattn256.om); this file is the thin fail-closed C ABI wrapper. */
#include "omega_blackwell_codegen_pattn256.h"
#include "omega_bw_om_ir.h"
#include "omega_native.h"
#include <string.h>

static void pattn256_pack_spec(const OmegaPrefillAttn256Spec *s, uint64_t sp[4]) {
    memset(sp, 0, 4u * sizeof(uint64_t));
    sp[0] = (uint64_t)(int64_t)s->mutant;
    sp[1] = s->q_heads;
    sp[2] = s->kv_heads;
}

int omega_pattn256_shape(const OmegaPrefillAttn256Spec *spec, OmegaPattn256Shape *s) {
    if (!spec || !s) return -1;
    const uint32_t qh = spec->q_heads ? spec->q_heads : 24u, kvh = spec->kv_heads ? spec->kv_heads : 4u;
    if (kvh == 0 || qh % kvh || qh / kvh > 8u) return -1;
    s->qh = qh; s->kvh = kvh; s->group = qh / kvh; s->out_words = qh * 256u; s->qf_pair_bytes = qh * 1024u;
    return 0;
}

int omega_pattn256_spec_ok(const OmegaPrefillAttn256Spec *s) {
    if (!s) return 0;
    uint64_t sp[4], ok = 0;
    pattn256_pack_spec(s, sp);
    if (omega2_cg_pattn256_spec_ok(&ok, sp, 4u) != 0) return 0;
    return ok != 0 ? 1 : 0;
}

int omega_blackwell_codegen_prefill_attn256_prog(const OmegaPrefillAttn256Spec *spec, BlackwellIRProgram *prog) {
    if (!prog) return -1;
    omega_bw_ir_init(prog);
    if (!spec) return -1;
    uint64_t sp[4], ins[8192], meta[512], rc = 1;
    memset(ins, 0, sizeof ins);
    memset(meta, 0, sizeof meta);
    pattn256_pack_spec(spec, sp);
    if (omega2_cg_pattn256_emit(&rc, sp, 4u, ins, 8192u, meta, 512u) != 0 || rc != 0) return -1;
    return omega_bw_ir_from_om_limit(ins, meta, prog, BW_PHYS_GPR_HW_LIMIT);
}

int omega_prefill_attn256_prog_stats(const OmegaPrefillAttn256Spec *spec, uint32_t *insns, uint32_t *gprs) {
    static BlackwellIRProgram p;
    if (omega_blackwell_codegen_prefill_attn256_prog(spec, &p) != 0) return -1;
    if (insns) *insns = (uint32_t)p.count;
    if (gprs) *gprs = p.regalloc.peak_gpr_usage;
    return 0;
}
