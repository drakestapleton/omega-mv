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

/* omega_blackwell_codegen_tc.c: tensor-core kernels for the OWN-30B one-pass prefill (T3).
 * Kernel emitters live in pure OM-2 (om/gpu/cg_tc.om); this file is the thin fail-closed C ABI wrapper. */
#include "omega_blackwell_codegen_tc.h"
#include "omega_bw_om_ir.h"
#include "omega_native.h"
#include <string.h>

int omega_blackwell_codegen_tc_probe_prog(int mutant, BlackwellIRProgram *prog) {
    if (!prog) return -1;
    omega_bw_ir_init(prog);
    uint64_t sp[4] = { (uint64_t)(int64_t)mutant, 0, 0, 0 };
    uint64_t ins[8192], meta[512], rc = 1;
    memset(ins, 0, sizeof ins);
    memset(meta, 0, sizeof meta);
    if (omega2_cg_tc_probe_emit(&rc, sp, 4u, ins, 8192u, meta, 512u) != 0 || rc != 0) return -1;
    return omega_bw_ir_from_om(ins, meta, prog);
}

static void tcgemm_pack_spec(const OmegaTcGemmSpec *s, uint64_t sp[8]) {
    memset(sp, 0, 8u * sizeof(uint64_t));
    sp[0] = s->k;
    sp[1] = s->rt;
    sp[2] = s->ct;
    sp[3] = s->warps;
    sp[4] = (uint64_t)(int64_t)s->mutant;
}

int omega_tcgemm_spec_ok(const OmegaTcGemmSpec *s) {
    if (!s) return 0;
    uint64_t sp[8], ok = 0;
    tcgemm_pack_spec(s, sp);
    if (omega2_cg_tcgemm_spec_ok(&ok, sp, 8u) != 0) return 0;
    return ok != 0 ? 1 : 0;
}

uint32_t omega_tcgemm_shared_bytes(const OmegaTcGemmSpec *s) { return omega_tcgemm_spec_ok(s) ? 2u * 16u * s->rt * 128u : 0u; }
uint32_t omega_tcgemm_span(const OmegaTcGemmSpec *s) { return omega_tcgemm_spec_ok(s) ? s->warps * 8u * s->ct : 0u; }

static uint16_t bf16_rne(float f) {
    uint32_t u; memcpy(&u, &f, 4);
    if ((u & 0x7fffffffu) > 0x7f800000u) return (uint16_t)((u >> 16) | 0x40u); /* NaN stays NaN */
    u += 0x7fffu + ((u >> 16) & 1u);
    return (uint16_t)(u >> 16);
}
void omega_tcgemm_permute_x(const float *x, uint32_t k, uint16_t *out) {
    static const unsigned ord[4] = { 0, 2, 1, 3 };
    for (uint32_t q = 0; q + 4 <= k; q += 4)
        for (unsigned i = 0; i < 4; i++) out[q + i] = bf16_rne(x[q + ord[i]] * 18446744073709551616.0f);
}
uint16_t omega_tcgemm_w_bf16(uint8_t c) { return (uint16_t)(((c & 0x7Fu) << 4) | ((c & 0x80u) << 8)); }

int omega_blackwell_codegen_tcgemm_prog(const OmegaTcGemmSpec *spec, BlackwellIRProgram *prog) {
    if (!prog) return -1;
    omega_bw_ir_init(prog);
    if (!spec) return -1;
    uint64_t sp[8], ins[8192], meta[512], rc = 1;
    memset(ins, 0, sizeof ins);
    memset(meta, 0, sizeof meta);
    tcgemm_pack_spec(spec, sp);
    if (omega2_cg_tcgemm_emit(&rc, sp, 8u, ins, 8192u, meta, 512u) != 0 || rc != 0) return -1;
    return omega_bw_ir_from_om(ins, meta, prog);
}

int omega_blackwell_codegen_tc_peak_prog(uint32_t iters, uint32_t chains, uint32_t stall, uint32_t threads, BlackwellIRProgram *prog) {
    if (!prog) return -1;
    omega_bw_ir_init(prog);
    uint64_t sp[4] = { iters, chains, stall, threads };
    uint64_t ins[8192], meta[512], rc = 1;
    memset(ins, 0, sizeof ins);
    memset(meta, 0, sizeof meta);
    if (omega2_cg_tc_peak_emit(&rc, sp, 4u, ins, 8192u, meta, 512u) != 0 || rc != 0) return -1;
    return omega_bw_ir_from_om(ins, meta, prog);
}

int omega_blackwell_codegen_tc_bw_prog(uint32_t iters, uint32_t groups, uint32_t threads, BlackwellIRProgram *prog) {
    if (!prog) return -1;
    omega_bw_ir_init(prog);
    uint64_t sp[4] = { iters, groups, threads, 0 };
    uint64_t ins[8192], meta[512], rc = 1;
    memset(ins, 0, sizeof ins);
    memset(meta, 0, sizeof meta);
    if (omega2_cg_tc_bw_emit(&rc, sp, 4u, ins, 8192u, meta, 512u) != 0 || rc != 0) return -1;
    return omega_bw_ir_from_om(ins, meta, prog);
}
