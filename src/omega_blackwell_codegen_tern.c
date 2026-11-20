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

/* omega_blackwell_codegen_tern.c: KT1 W2A8 ternary GEMV kernel.
 * Emitter and stall scheduler live in pure OM-2 (om/gpu/cg_tern.om); this file is the thin fail-closed C ABI wrapper. */
#include "omega_blackwell_codegen_tern.h"
#include "omega_bw_om_ir.h"
#include "omega_native.h"
#include <string.h>

static void tern_pack_spec(const OmegaTernGemvSpec *s, uint64_t sp[8]) {
    memset(sp, 0, 8u * sizeof(uint64_t));
    sp[0] = s->k;
    sp[1] = s->layout;
    sp[2] = s->rows;
    sp[3] = s->warps;
    sp[4] = s->depth;
    sp[5] = s->epi;
    sp[6] = (uint64_t)(int64_t)s->mutant;
}

uint32_t omega_tern_gemv_chunks(const OmegaTernGemvSpec *s) {
    if (!s || s->k == 0) return 0;
    return (s->k + OMEGA_TERN_CHUNK_MAX - 1u) / OMEGA_TERN_CHUNK_MAX;
}

int omega_tern_gemv_spec_ok(const OmegaTernGemvSpec *s) {
    if (!s) return 0;
    uint64_t sp[8], ok = 0;
    tern_pack_spec(s, sp);
    if (omega2_cg_tern_spec_ok(&ok, sp, 8u) != 0) return 0;
    return ok != 0 ? 1 : 0;
}

uint32_t omega_tern_gemv_steps(const OmegaTernGemvSpec *s) { return omega_tern_gemv_spec_ok(s) ? s->k / 256u : 0; }
uint32_t omega_tern_gemv_out_slot_bytes(const OmegaTernGemvSpec *s) { return s ? 2u * s->rows * s->warps * 4u : 0; }

int omega_tern_gemv_coalesced_out(const OmegaTernGemvSpec *s) {
    if (!omega_tern_gemv_spec_ok(s) || omega_tern_gemv_chunks(s) != 1 || 2u * s->rows * s->warps > 32u) return 0;
    return s->k * 2u + 2u * omega_tern_gemv_out_slot_bytes(s) <= OMEGA_TERN_SHARED_MAX;
}

uint32_t omega_tern_gemv_shared_bytes(const OmegaTernGemvSpec *s) {
    if (!omega_tern_gemv_spec_ok(s)) return 0;
    const uint32_t x_bytes = (s->k / omega_tern_gemv_chunks(s)) * 2u;
    return omega_tern_gemv_coalesced_out(s) ? x_bytes + 2u * omega_tern_gemv_out_slot_bytes(s) : x_bytes;
}

uint64_t omega_tern_word_offset(uint32_t layout, uint32_t R, uint32_t k, uint32_t r, uint32_t c) {
    const uint64_t kw = k / 16u;
    if (layout == OMEGA_TERN_LAYOUT_ROWMAJOR) return ((uint64_t)r * kw + c) * 4u;
    const uint64_t blk = r / (2u * R), j = r % (2u * R);
    return blk * 2u * R * kw * 4u + (uint64_t)c * 2u * R * 4u + j * 4u;
}

int omega_blackwell_codegen_tern_gemv_prog(const OmegaTernGemvSpec *spec, BlackwellIRProgram *prog) {
    if (!prog) return -1;
    omega_bw_ir_init(prog);
    if (!spec) return -1;
    uint64_t sp[8], ins[8192], meta[512], rc = 1;
    memset(ins, 0, sizeof ins);
    memset(meta, 0, sizeof meta);
    tern_pack_spec(spec, sp);
    if (omega2_cg_tern_emit(&rc, sp, 8u, ins, 8192u, meta, 512u) != 0 || rc != 0) return -1;
    if (omega_bw_ir_from_om(ins, meta, prog) != 0) return -1;
    uint64_t v2p[256], bsz[256];
    for (int v = 0; v < 256; v++) {
        if (v < prog->regalloc.num_vregs && prog->regalloc.vreg_to_phys[v] >= 0) {
            v2p[v] = (uint64_t)prog->regalloc.vreg_to_phys[v];
            bsz[v] = prog->regalloc.intervals[v].bundle_size ? prog->regalloc.intervals[v].bundle_size : 1u;
        } else {
            v2p[v] = 0xffffffffffffffffull;
            bsz[v] = 0u;
        }
    }
    rc = 1;
    if (omega2_cg_tern_sched_stalls(&rc, ins, 8192u, (uint64_t)prog->count, v2p, 256u, bsz, 256u) != 0 || rc != 0) {
        omega_bw_ir_init(prog);
        return -1;
    }
    for (size_t i = 0; i < prog->count; i++) prog->insns[i].control = (uint32_t)(ins[i * 8u + 6u] >> 32);
    return 0;
}

int omega_tern_gemv_prog_stats(const OmegaTernGemvSpec *spec, uint32_t *insns, uint32_t *gprs) {
    static BlackwellIRProgram prog;
    if (omega_blackwell_codegen_tern_gemv_prog(spec, &prog) != 0) return -1;
    if (insns) *insns = (uint32_t)prog.count;
    if (gprs) *gprs = prog.regalloc.peak_gpr_usage;
    return 0;
}
