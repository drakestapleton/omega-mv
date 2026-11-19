/* SPDX-License-Identifier: Apache-2.0
 * Shared unpacker for pure-OM-2 Blackwell IR emitters (om/gpu/cg_*.om).
 * Converts the standard 8-ulong-per-insn + 512-ulong meta wire format into
 * BlackwellIRProgram, extends live intervals across recorded loop back-edges,
 * and runs omega_bw_regalloc_solve.
 */
#ifndef OMEGA_BW_OM_IR_H
#define OMEGA_BW_OM_IR_H

#include "omega_blackwell_codegen.h"
#include <string.h>

static inline int omega_bw_ir_from_om(const uint64_t ins[8192], const uint64_t meta[512], BlackwellIRProgram *prog) {
    if (!ins || !meta || !prog) return -1;
    const uint64_t n = meta[0], nv = meta[1], nu = meta[2], nl = meta[3];
    if (n > BW_MAX_IR_INSNS || nv > BW_MAX_VREGS || nu > BW_MAX_UVREGS || nl > 16u) return -1;
    omega_bw_ir_init(prog);
    for (uint64_t v = 0; v < nv; v++) {
        uint64_t w = meta[64 + v];
        int r = (w == 4u) ? omega_bw_ir_alloc_vreg128(prog) : (w == 2u) ? omega_bw_ir_alloc_vreg64(prog) : omega_bw_ir_alloc_vreg(prog);
        if (r != (int)v) return -1;
    }
    for (uint64_t u = 0; u < nu; u++) {
        uint64_t w = meta[352 + u];
        int r = (w == 2u) ? omega_bw_ir_alloc_uvreg64(prog) : omega_bw_ir_alloc_uvreg(prog);
        if (r != (int)u) return -1;
    }
    for (uint64_t i = 0; i < n; i++) {
        const uint64_t *r = &ins[i * 8u];
        BlackwellIRInsn in;
        memset(&in, 0, sizeof in);
        in.op = (BlackwellIROpcode)(int)(int64_t)r[0];
        in.dst_vreg = (int)(int64_t)r[1];
        in.src1_vreg = (int)(int64_t)r[2];
        in.src2_vreg = (int)(int64_t)r[3];
        in.src3_vreg = (int)(int64_t)r[4];
        in.ureg = (int)(int64_t)r[5];
        in.imm = (uint32_t)(r[6] & 0xffffffffu);
        in.control = (uint32_t)(r[6] >> 32);
        in.is_uniform = (r[7] & 1u) != 0;
        in.predicate_p0 = ((r[7] >> 1) & 1u) != 0;
        in.predicate_not = ((r[7] >> 2) & 1u) != 0;
        in.bar_reg = (uint8_t)((r[7] >> 8) & 0xffu);
        in.dst_subreg = (uint8_t)((r[7] >> 16) & 0xffu);
        in.src1_subreg = (uint8_t)((r[7] >> 24) & 0xffu);
        in.src2_subreg = (uint8_t)((r[7] >> 32) & 0xffu);
        in.src3_subreg = (uint8_t)((r[7] >> 40) & 0xffu);
        if (omega_bw_ir_append(prog, &in) < 0) return -1;
    }
    for (uint64_t l = 0; l < nl; l++) {
        const int start = (int)meta[320 + 2u * l], end = (int)meta[320 + 2u * l + 1u];
        OmegaRegAlloc *ra = &prog->regalloc;
        for (int v = 0; v < ra->num_vregs; v++) {
            OmegaLiveInterval *iv = &ra->intervals[v];
            if (iv->first_def >= 0 && iv->first_def < start && iv->last_use >= start && iv->last_use < end) iv->last_use = end;
        }
    }
    return omega_bw_regalloc_solve(prog);
}

#endif /* OMEGA_BW_OM_IR_H */
