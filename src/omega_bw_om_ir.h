/* SPDX-License-Identifier: Apache-2.0
 * Shared unpacker for pure-OM-2 Blackwell IR emitters (om/gpu/cg_*.om).
 * Strictly validates every metadata field, register/subregister bound, opcode,
 * and loop back-edge before unpacking into BlackwellIRProgram and running
 * omega_bw_regalloc_solve. Fails closed on any error or out-of-range field.
 */
#ifndef OMEGA_BW_OM_IR_H
#define OMEGA_BW_OM_IR_H

#include "omega_blackwell_codegen.h"
#include <string.h>

static inline int omega_bw_om_check_reg(int64_t r64, uint8_t sub, uint64_t limit, const uint64_t *widths) {
    if (r64 == -1) return sub == 0 ? 0 : -1;
    if (r64 < 0 || (uint64_t)r64 >= limit) return -1;
    uint64_t w = widths[(uint64_t)r64];
    if (sub >= w) return -1;
    return 0;
}

static inline int omega_bw_ir_from_om_limit(const uint64_t ins[8192], const uint64_t meta[512], BlackwellIRProgram *prog, uint32_t gpr_limit) {
    if (!prog) return -1;
    omega_bw_ir_init(prog);
    if (gpr_limit != 0u && omega_bw_ir_set_gpr_limit(prog, gpr_limit) != 0) return -1;
    if (!ins || !meta) return -1;
    if (meta[5] != 0) return -1; /* emitter recorded an internal overflow or validation error */
    const uint64_t n = meta[0], nv = meta[1], nu = meta[2], nl = meta[3];
    if (n == 0 || n > BW_MAX_IR_INSNS || nv > BW_MAX_VREGS || nu > BW_MAX_UVREGS || nl > 16u) return -1;
    for (uint64_t v = 0; v < nv; v++) {
        uint64_t w = meta[64u + v];
        if (w != 1u && w != 2u && w != 4u) goto fail;
        int r = (w == 4u) ? omega_bw_ir_alloc_vreg128(prog) : (w == 2u) ? omega_bw_ir_alloc_vreg64(prog) : omega_bw_ir_alloc_vreg(prog);
        if (r != (int)v) goto fail;
    }
    for (uint64_t u = 0; u < nu; u++) {
        uint64_t w = meta[352u + u];
        if (w != 1u && w != 2u) goto fail;
        int r = (w == 2u) ? omega_bw_ir_alloc_uvreg64(prog) : omega_bw_ir_alloc_uvreg(prog);
        if (r != (int)u) goto fail;
    }
    for (uint64_t i = 0; i < n; i++) {
        const uint64_t *r = &ins[i * 8u];
        int64_t op64 = (int64_t)r[0];
        if (op64 < 0 || op64 > (int64_t)BW_IR_ATOMG_ADD_F32_STRONG_GPU) goto fail;
        if ((r[7] >> 48) != 0) goto fail;
        bool is_u = (r[7] & 1u) != 0;
        uint8_t dsub = (uint8_t)((r[7] >> 16) & 0xffu);
        uint8_t s1sub = (uint8_t)((r[7] >> 24) & 0xffu);
        uint8_t s2sub = (uint8_t)((r[7] >> 32) & 0xffu);
        uint8_t s3sub = (uint8_t)((r[7] >> 40) & 0xffu);
        uint8_t bar = (uint8_t)((r[7] >> 8) & 0xffu);
        if (bar >= BW_RECONV_MAX_BAR) goto fail;
        if (is_u) {
            if (omega_bw_om_check_reg((int64_t)r[1], dsub, nu, &meta[352]) != 0) goto fail;
            if (omega_bw_om_check_reg((int64_t)r[2], s1sub, nu, &meta[352]) != 0) goto fail;
            if (omega_bw_om_check_reg((int64_t)r[3], s2sub, nu, &meta[352]) != 0) goto fail;
            if (omega_bw_om_check_reg((int64_t)r[4], s3sub, nu, &meta[352]) != 0) goto fail;
        } else {
            if (omega_bw_om_check_reg((int64_t)r[1], dsub, nv, &meta[64]) != 0) goto fail;
            if (omega_bw_om_check_reg((int64_t)r[2], s1sub, nv, &meta[64]) != 0) goto fail;
            if (omega_bw_om_check_reg((int64_t)r[3], s2sub, nv, &meta[64]) != 0) goto fail;
            if (omega_bw_om_check_reg((int64_t)r[4], s3sub, nv, &meta[64]) != 0) goto fail;
        }
        if (omega_bw_om_check_reg((int64_t)r[5], 0, nu, &meta[352]) != 0) goto fail;

        BlackwellIRInsn in;
        memset(&in, 0, sizeof in);
        in.op = (BlackwellIROpcode)(int)op64;
        in.dst_vreg = (int)(int64_t)r[1];
        in.src1_vreg = (int)(int64_t)r[2];
        in.src2_vreg = (int)(int64_t)r[3];
        in.src3_vreg = (int)(int64_t)r[4];
        in.ureg = (int)(int64_t)r[5];
        in.imm = (uint32_t)(r[6] & 0xffffffffu);
        in.control = (uint32_t)(r[6] >> 32);
        in.is_uniform = is_u;
        in.predicate_p0 = ((r[7] >> 1) & 1u) != 0;
        in.predicate_not = ((r[7] >> 2) & 1u) != 0;
        in.bar_reg = bar;
        in.dst_subreg = dsub;
        in.src1_subreg = s1sub;
        in.src2_subreg = s2sub;
        in.src3_subreg = s3sub;
        if (omega_bw_ir_append(prog, &in) < 0) goto fail;
    }
    for (uint64_t l = 0; l < nl; l++) {
        const uint64_t s = meta[320u + 2u * l], e = meta[320u + 2u * l + 1u];
        if (s > e || e >= n) goto fail;
        const int start = (int)s, end = (int)e;
        OmegaRegAlloc *ra = &prog->regalloc;
        for (int v = 0; v < ra->num_vregs; v++) {
            OmegaLiveInterval *iv = &ra->intervals[v];
            if (iv->first_def >= 0 && iv->first_def < start && iv->last_use >= start && iv->last_use < end) iv->last_use = end;
        }
    }
    if (omega_bw_regalloc_solve(prog) != 0) goto fail;
    return 0;
fail:
    omega_bw_ir_init(prog);
    return -1;
}

static inline int omega_bw_ir_from_om(const uint64_t ins[8192], const uint64_t meta[512], BlackwellIRProgram *prog) {
    return omega_bw_ir_from_om_limit(ins, meta, prog, 0u);
}

#endif /* OMEGA_BW_OM_IR_H */
