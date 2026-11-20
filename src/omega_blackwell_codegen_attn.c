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

/* omega_blackwell_codegen_attn.c: the one-launch decode attention kernel.
 * Implementation lives in pure OM-2 (om/gpu/cg_attn.om); this file is the thin fail-closed C ABI wrapper. */
#include "omega_blackwell_codegen_attn.h"
#include "omega_bw_om_ir.h"
#include "omega_native.h"
#include <string.h>

static void attn_pack_spec(const OmegaDecodeAttnSpec *s, uint64_t sp[4]) {
    memset(sp, 0, 4u * sizeof(uint64_t));
    sp[0] = s->depth;
    sp[1] = (uint64_t)(int64_t)s->mutant;
}

int omega_blackwell_codegen_decode_attn_prog(const OmegaDecodeAttnSpec *spec, BlackwellIRProgram *prog) {
    if (!prog) return -1;
    omega_bw_ir_init(prog);
    if (!spec) return -1;
    uint64_t sp[4], ins[8192], meta[512], rc = 1;
    memset(ins, 0, sizeof ins);
    memset(meta, 0, sizeof meta);
    attn_pack_spec(spec, sp);
    if (omega2_cg_attn_emit(&rc, sp, 4u, ins, 8192u, meta, 512u) != 0 || rc != 0) return -1;
    return omega_bw_ir_from_om(ins, meta, prog);
}

int omega_decode_attn_prog_stats(const OmegaDecodeAttnSpec *spec, uint32_t *insns, uint32_t *gprs) {
    static BlackwellIRProgram prog;
    if (omega_blackwell_codegen_decode_attn_prog(spec, &prog) != 0) return -1;
    if (insns) *insns = (uint32_t)prog.count;
    if (gprs) *gprs = prog.regalloc.peak_gpr_usage;
    return 0;
}
