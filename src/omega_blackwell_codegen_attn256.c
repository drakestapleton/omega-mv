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

/* omega_blackwell_codegen_attn256.c: the one-launch decode attention kernel for head_dim 256.
 * Implementation lives in pure OM-2 (om/gpu/cg_attn256.om); this file is the thin fail-closed C ABI wrapper. */
#include "omega_blackwell_codegen_attn256.h"
#include "omega_bw_om_ir.h"
#include "omega_native.h"
#include <string.h>

static void attn256_pack_spec(const OmegaDecodeAttn256Spec *s, uint64_t sp[8]) {
    memset(sp, 0, 8u * sizeof(uint64_t));
    sp[0] = s->depth;
    sp[1] = (uint64_t)(int64_t)s->mutant;
    sp[2] = s->prep;
    sp[3] = s->q_heads;
    sp[4] = s->kv_heads;
    sp[5] = s->q_per_cta;
    sp[6] = s->multi;
}

int omega_dattn256_shape(const OmegaDecodeAttn256Spec *spec, OmegaDattn256Shape *s) {
    if (!spec || !s) return -1;
    const uint32_t qh = spec->q_heads ? spec->q_heads : OMEGA_DATTN256_Q_HEADS;
    const uint32_t kvh = spec->kv_heads ? spec->kv_heads : OMEGA_DATTN256_KV_HEADS;
    const uint32_t h = spec->q_per_cta ? spec->q_per_cta : OMEGA_DATTN256_Q_PER_KV;
    if (h < 1u || h > 6u || qh % h || kvh == 0 || (qh / h) % kvh) return -1;
    const uint32_t g = (qh / h) / kvh;
    if (g != 1u && g != 2u) return -1;
    s->qh = qh; s->kvh = kvh; s->h = h; s->vy = qh / h; s->g = g;
    s->qkv_words = (qh + 2u * kvh) * 256u; s->out_words = qh * 256u;
    return 0;
}

int omega_blackwell_codegen_decode_attn256_prog(const OmegaDecodeAttn256Spec *spec, BlackwellIRProgram *prog) {
    if (!prog) return -1;
    omega_bw_ir_init(prog);
    if (!spec) return -1;
    uint64_t sp[8], ins[8192], meta[512], rc = 1;
    memset(ins, 0, sizeof ins);
    memset(meta, 0, sizeof meta);
    attn256_pack_spec(spec, sp);
    if (omega2_cg_attn256_emit(&rc, sp, 8u, ins, 8192u, meta, 512u) != 0 || rc != 0) return -1;
    return omega_bw_ir_from_om(ins, meta, prog);
}

int omega_decode_attn256_prog_stats(const OmegaDecodeAttn256Spec *spec, uint32_t *insns, uint32_t *gprs) {
    static BlackwellIRProgram prog;
    if (omega_blackwell_codegen_decode_attn256_prog(spec, &prog) != 0) return -1;
    if (insns) *insns = (uint32_t)prog.count;
    if (gprs) *gprs = prog.regalloc.peak_gpr_usage;
    return 0;
}
