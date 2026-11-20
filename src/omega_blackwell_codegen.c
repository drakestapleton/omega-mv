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

#include "omega_blackwell_codegen.h"
#include "omega_blackwell_submit.h"
#include "omega_native.h"
#include "sha256.h"
#include "omega_path_check.h"
#include <string.h>
/* native v1 P07 cut A.2 (aienos#286, docs/numeric/OMEGA_GPU_NATIVE_BOUNDARY.md): with OMEGA_GPU_NO_POSIX this file
 * builds -ffreestanding. Code generation then runs only through the allocation-free entry points
 * (omega_blackwell_kernel_encode_into: the caller supplies the code buffer and its capacity); the allocating
 * generators, their diagnostics and the printing variation self-test exist only in the hosted build. */
#ifndef OMEGA_GPU_NO_POSIX
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#define BW_DIAG(...) fprintf(stderr, __VA_ARGS__)
#else
#define BW_DIAG(...) ((void)0)
#endif

void omega_bw_ir_init(BlackwellIRProgram *prog) {
    if (!prog) return;
    memset(prog, 0, sizeof(*prog));
}

int omega_bw_ir_alloc_vreg(BlackwellIRProgram *prog) {
    if (!prog || prog->regalloc.num_vregs >= BW_MAX_VREGS) return -1;
    int v = prog->regalloc.num_vregs++;
    prog->regalloc.intervals[v].vreg = v;
    prog->regalloc.intervals[v].first_def = -1;
    prog->regalloc.intervals[v].last_use = -1;
    prog->regalloc.intervals[v].phys_reg = -1;
    prog->regalloc.intervals[v].bundle_size = 1;
    prog->regalloc.intervals[v].is_pair = false;
    prog->regalloc.intervals[v].is_quad = false;
    prog->regalloc.intervals[v].active = false;
    prog->regalloc.vreg_to_phys[v] = -1;
    return v;
}

int omega_bw_ir_alloc_vreg64(BlackwellIRProgram *prog) {
    if (!prog || prog->regalloc.num_vregs >= BW_MAX_VREGS) return -1;
    int v = prog->regalloc.num_vregs++;
    prog->regalloc.intervals[v].vreg = v;
    prog->regalloc.intervals[v].first_def = -1;
    prog->regalloc.intervals[v].last_use = -1;
    prog->regalloc.intervals[v].phys_reg = -1;
    prog->regalloc.intervals[v].bundle_size = 2;
    prog->regalloc.intervals[v].is_pair = true;
    prog->regalloc.intervals[v].is_quad = false;
    prog->regalloc.intervals[v].active = false;
    prog->regalloc.vreg_to_phys[v] = -1;
    return v;
}

int omega_bw_ir_alloc_vreg128(BlackwellIRProgram *prog) {
    if (!prog || prog->regalloc.num_vregs >= BW_MAX_VREGS) return -1;
    int v = prog->regalloc.num_vregs++;
    prog->regalloc.intervals[v].vreg = v;
    prog->regalloc.intervals[v].first_def = -1;
    prog->regalloc.intervals[v].last_use = -1;
    prog->regalloc.intervals[v].phys_reg = -1;
    prog->regalloc.intervals[v].bundle_size = 4;
    prog->regalloc.intervals[v].is_pair = false;
    prog->regalloc.intervals[v].is_quad = true;
    prog->regalloc.intervals[v].active = false;
    prog->regalloc.vreg_to_phys[v] = -1;
    return v;
}

int omega_bw_ir_alloc_uvreg(BlackwellIRProgram *prog) {
    if (!prog || prog->regalloc.num_uvregs >= BW_MAX_UVREGS) return -1;
    int uv = prog->regalloc.num_uvregs++;
    prog->regalloc.uintervals[uv].vreg = uv;
    prog->regalloc.uintervals[uv].first_def = -1;
    prog->regalloc.uintervals[uv].last_use = -1;
    prog->regalloc.uintervals[uv].phys_reg = -1;
    prog->regalloc.uintervals[uv].is_pair = false;
    prog->regalloc.uintervals[uv].active = false;
    prog->regalloc.uvreg_to_phys[uv] = -1;
    return uv;
}

int omega_bw_ir_alloc_uvreg64(BlackwellIRProgram *prog) {
    if (!prog || prog->regalloc.num_uvregs >= BW_MAX_UVREGS) return -1;
    int uv = prog->regalloc.num_uvregs++;
    prog->regalloc.uintervals[uv].vreg = uv;
    prog->regalloc.uintervals[uv].first_def = -1;
    prog->regalloc.uintervals[uv].last_use = -1;
    prog->regalloc.uintervals[uv].phys_reg = -1;
    prog->regalloc.uintervals[uv].is_pair = true;
    prog->regalloc.uintervals[uv].active = false;
    prog->regalloc.uvreg_to_phys[uv] = -1;
    return uv;
}

int omega_bw_ir_append(BlackwellIRProgram *prog, const BlackwellIRInsn *insn) {
    if (!prog || !insn || prog->count >= BW_MAX_IR_INSNS) return -1;
    int idx = (int)prog->count++;
    prog->insns[idx] = *insn;

    /* Update live-interval def/use tracking */
    if (insn->dst_vreg >= 0 && insn->dst_vreg < prog->regalloc.num_vregs) {
        if (!insn->is_uniform) {
            OmegaLiveInterval *iv = &prog->regalloc.intervals[insn->dst_vreg];
            if (iv->first_def < 0) iv->first_def = idx;
            if (idx > iv->last_use) iv->last_use = idx;
        }
    }
    if (insn->src1_vreg >= 0 && insn->src1_vreg < prog->regalloc.num_vregs) {
        OmegaLiveInterval *iv = &prog->regalloc.intervals[insn->src1_vreg];
        if (iv->first_def < 0) iv->first_def = idx;
        if (idx > iv->last_use) iv->last_use = idx;
    }
    if (insn->src2_vreg >= 0 && insn->src2_vreg < prog->regalloc.num_vregs) {
        OmegaLiveInterval *iv = &prog->regalloc.intervals[insn->src2_vreg];
        if (iv->first_def < 0) iv->first_def = idx;
        if (idx > iv->last_use) iv->last_use = idx;
    }
    if (insn->src3_vreg >= 0 && insn->src3_vreg < prog->regalloc.num_vregs) {
        OmegaLiveInterval *iv = &prog->regalloc.intervals[insn->src3_vreg];
        if (iv->first_def < 0) iv->first_def = idx;
        if (idx > iv->last_use) iv->last_use = idx;
    }

    /* Uniform register def/use tracking */
    if (insn->is_uniform && insn->dst_vreg >= 0 && insn->dst_vreg < prog->regalloc.num_uvregs) {
        OmegaLiveInterval *uiv = &prog->regalloc.uintervals[insn->dst_vreg];
        if (uiv->first_def < 0) uiv->first_def = idx;
        if (idx > uiv->last_use) uiv->last_use = idx;
    }
    if (insn->ureg >= 0 && insn->ureg < prog->regalloc.num_uvregs) {
        OmegaLiveInterval *uiv = &prog->regalloc.uintervals[insn->ureg];
        if (uiv->first_def < 0) uiv->first_def = idx;
        if (idx > uiv->last_use) uiv->last_use = idx;
    }

    return idx;
}

int omega_bw_regalloc_solve(BlackwellIRProgram *prog) {
    if (!prog) return -1;
    OmegaRegAlloc *ra = &prog->regalloc;
    if (ra->num_vregs < 0 || ra->num_vregs > BW_MAX_VREGS) return -1;
    if (ra->num_uvregs < 0 || ra->num_uvregs > BW_MAX_UVREGS) return -1;

    uint64_t cfg[4] = { (uint64_t)ra->num_vregs, (uint64_t)ra->num_uvregs, (uint64_t)ra->gpr_limit, 0 };
    int64_t vinfo[BW_MAX_VREGS * 3];
    uint64_t uinfo[BW_MAX_UVREGS];
    int64_t res[290];
    memset(vinfo, 0, sizeof(vinfo));
    memset(uinfo, 0, sizeof(uinfo));
    memset(res, 0, sizeof(res));

    for (int v = 0; v < ra->num_vregs; v++) {
        const OmegaLiveInterval *iv = &ra->intervals[v];
        uint32_t bsize = iv->bundle_size ? iv->bundle_size : (iv->is_pair ? 2u : (iv->is_quad ? 4u : 1u));
        vinfo[v * 3 + 0] = (int64_t)iv->first_def;
        vinfo[v * 3 + 1] = (int64_t)iv->last_use;
        vinfo[v * 3 + 2] = (int64_t)bsize;
    }
    for (int uv = 0; uv < ra->num_uvregs; uv++) {
        uinfo[uv] = ra->uintervals[uv].is_pair ? 2u : 1u;
    }

    uint64_t rc = 1;
    if (omega2_bw_regalloc_solve(&rc, cfg, 4, vinfo, BW_MAX_VREGS * 3, uinfo, BW_MAX_UVREGS, res, 290) != OMEGA_OK ||
        rc != 0) {
        return -1;
    }

    for (int v = 0; v < ra->num_vregs; v++) {
        ra->intervals[v].phys_reg = (int)res[v];
        ra->vreg_to_phys[v] = (int)res[v];
    }
    for (int uv = 0; uv < ra->num_uvregs; uv++) {
        ra->uintervals[uv].phys_reg = (int)res[256 + uv];
        ra->uvreg_to_phys[uv] = (int)res[256 + uv];
    }
    ra->peak_gpr_usage = (uint32_t)res[288];
    ra->peak_ugpr_usage = (uint32_t)res[289];
    return 0;
}

/* ---- sm_121 instruction encoder (aien-dev/CUDApp#79) ---------------------------------------------------
 * The hosted build encodes through om/encoder/bw_enc_sm121.om: seeded Omega, compiled by the pinned omc and
 * linked through the omega-bridge native binding src/omega_om_units.c (generated by om/units.sh, never edited
 * by hand). The C encoder below is migration-pending: it is compiled only
 *   - in the freestanding build (OMEGA_GPU_NO_POSIX), because the bridge binding needs pthread and mmap and the
 *     freestanding binding is still a proposal (successor: the same .om unit behind a caller-stack binding);
 *   - with CUDAPP_MIGRATION_PENDING_C_ENCODER, the differential oracle build (make CUDAPP_ENCODER=c);
 *   - with CUDAPP_MIGRATION_PENDING_ENCODER_DIFF, which encodes every instruction and program both ways, aborts on
 *     any byte difference and logs each agreement to $CUDAPP_ENCODER_DIFF_LOG (make CUDAPP_ENCODER=diff).
 * Successor of the C body: bw_enc_sm121.om; it is deleted once the freestanding binding lands. */
#if defined(OMEGA_GPU_NO_POSIX) || defined(CUDAPP_MIGRATION_PENDING_C_ENCODER)
#define BW_ENC_C_PRIMARY 1
#endif
#if defined(BW_ENC_C_PRIMARY) && defined(CUDAPP_MIGRATION_PENDING_ENCODER_DIFF)
#error "CUDAPP_MIGRATION_PENDING_ENCODER_DIFF needs the .om encoder: not with OMEGA_GPU_NO_POSIX or the C encoder"
#endif
#if defined(BW_ENC_C_PRIMARY) || defined(CUDAPP_MIGRATION_PENDING_ENCODER_DIFF)
static int bw_c_encode_insn(const BlackwellIRInsn *insn, const OmegaRegAlloc *ra, uint32_t w[4]) {
    memset(w, 0, 16);

    int dst = (insn->dst_vreg >= 0) ? (ra->vreg_to_phys[insn->dst_vreg] + insn->dst_subreg) : 0;
    int src1 = (insn->src1_vreg >= 0) ? (ra->vreg_to_phys[insn->src1_vreg] + insn->src1_subreg) : 0;
    int src2 = (insn->src2_vreg >= 0) ? (ra->vreg_to_phys[insn->src2_vreg] + insn->src2_subreg) : 0;
    int src3 = (insn->src3_vreg >= 0) ? (ra->vreg_to_phys[insn->src3_vreg] + insn->src3_subreg) : 0xff; /* Default to RZ (0xff) */
    int ureg = (insn->ureg >= 0) ? ra->uvreg_to_phys[insn->ureg] : 0;

    if (insn->is_uniform && insn->dst_vreg >= 0) {
        dst = ra->uvreg_to_phys[insn->dst_vreg];
    }

    switch (insn->op) {
        case BW_IR_NOP:
            w[0] = 0x00007918;
            w[1] = 0x00000000;
            w[2] = 0x00000000;
            w[3] = insn->control ? insn->control : 0x000fc000; /* control: a timed pause (fragment matmul) */
            break;

        case BW_IR_MOV_RZ:
            /* MOV Rd, RZ */
            w[0] = 0x7202 | ((uint32_t)(dst & 0xff) << 16);
            w[1] = 0x000000ff;
            w[2] = 0x00000f00;
            w[3] = insn->control ? insn->control : 0x000fe200;
            break;

        case BW_IR_MOV_IMM:
            /* MOV Rd, imm32 */
            w[0] = 0x7802 | ((uint32_t)(dst & 0xff) << 16);
            w[1] = insn->imm;
            w[2] = 0x00000f00;
            w[3] = insn->control ? insn->control : 0x000fe200;
            break;

        case BW_IR_S2R:
            /* S2R Rd, SR */
            w[0] = 0x7919 | ((uint32_t)(dst & 0xff) << 16);
            w[1] = 0x0;
            w[2] = (insn->imm & 0xff) << 8;
            w[3] = insn->control ? insn->control : 0x000e2200;
            break;

        case BW_IR_LDC:
            /* LDC Rd, c[0x0][imm] */
            w[0] = 0xff007b82 | ((uint32_t)(dst & 0xff) << 16);
            w[1] = (insn->imm << 6) & 0x00ffff00;
            w[2] = 0x00000800;
            w[3] = insn->control ? insn->control : 0x000fe200;
            break;

        case BW_IR_LDC64:
            /* LDC.64 Rd:Rd+1, c[0x0][imm] */
            w[0] = 0xff007b82 | ((uint32_t)(dst & 0xff) << 16);
            w[1] = (insn->imm << 6) & 0x00ffff00;
            w[2] = 0x00000a00;
            w[3] = insn->control ? insn->control : 0x000e2200;
            break;

        case BW_IR_LDCU:
            /* LDCU URd, c[0x0][imm] */
            w[0] = 0xff0077ac | ((uint32_t)(dst & 0xff) << 16);
            w[1] = (insn->imm << 5) & 0x00ffff00;
            w[2] = 0x08000800;
            w[3] = insn->control ? insn->control : 0x000e2200;
            break;

        case BW_IR_LDCU64:
            /* LDCU.64 URd:URd+1, c[0x0][imm] */
            w[0] = 0xff0077ac | ((uint32_t)(dst & 0xff) << 16);
            w[1] = (insn->imm << 5) & 0x00ffff00;
            w[2] = 0x08000a00;
            w[3] = insn->control ? insn->control : 0x000e6e00;
            break;

        case BW_IR_IMAD:
            if (insn->src2_vreg >= 0) {
                /* Register-register: IMAD Rd, Ra, Rb, Rc (0x7224) */
                w[0] = 0x7224 | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
                w[1] = (uint32_t)(src2 & 0xff);
                w[2] = 0x078e0200 | (uint32_t)(src3 & 0xff);
                w[3] = insn->control ? insn->control : 0x001fca00;
            } else if (insn->is_uniform && insn->ureg >= 0) {
                /* Uniform register multiplier: IMAD Rd, Ra, URb, Rc (0x7c24) */
                w[0] = 0x7c24 | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
                w[1] = (uint32_t)(ureg & 0xff);
                w[2] = 0x0f8e0200 | (uint32_t)(src3 & 0xff);
                w[3] = insn->control ? insn->control : 0x001fca00;
            } else {
                /* Immediate multiplier: IMAD Rd, Ra, imm, Rc (0x7824) */
                w[0] = 0x7824 | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
                w[1] = insn->imm;
                w[2] = 0x078e0200 | (uint32_t)(src3 & 0xff);
                w[3] = insn->control ? insn->control : 0x001fca00;
            }
            break;

        case BW_IR_IMAD_WIDE:
            /* IMAD.WIDE.U32 Rd:Rd+1, Ra, imm, Rc:Rc+1 */
            w[0] = 0x7825 | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = insn->imm;
            w[2] = 0x078e0000 | (uint32_t)(src3 & 0xff);
            w[3] = insn->control ? insn->control : 0x001fcc00;
            break;

        case BW_IR_ISETP_GE:
            if (insn->is_uniform && insn->ureg >= 0) {
                w[0] = 0x7c0c | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
                w[1] = (uint32_t)(ureg & 0xff);
                w[2] = 0x0bf06070;
                w[3] = insn->control ? insn->control : 0x002fda00;
            } else {
                w[0] = 0x780c | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
                w[1] = insn->imm;
                w[2] = 0x03f06270;
                w[3] = insn->control ? insn->control : 0x001fda00;
            }
            break;

        case BW_IR_LDG_E: {
            /* LDG.E Rd, desc[URd][Ra.64+imm]: the 32-bit size (4) of the LDG.E.64 / LDG.E.128 words below; imm as there
             * (signed 24-bit byte offset at bits 40..63, w[1] bits 8..31), unchanged words when imm is 0. */
            int32_t off = (int32_t)insn->imm;
            if (off < -(1 << 23) || off >= (1 << 23)) return -1;
            w[0] = 0x7981 | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = (uint32_t)(ureg & 0xff) | (((uint32_t)off & 0xffffffU) << 8);
            w[2] = 0x0c1e1900;
            w[3] = insn->control ? insn->control : 0x000f2200;
            break;
        }

        case BW_IR_STG_E: {
            /* STG.E desc[URd][Ra.64+imm], Rb. imm = signed 24-bit byte offset at bits 40..63 (w[1] bits
             * 8..31), as for LDG; words from nvcc 13.0.88 -arch=sm_121 (omega_blackwell_verify_codegen_fixtures_fragmm,
             * 2026-10-12: STG.E desc[UR4][R4.64+0x4], R9 = 0x0000040904007986 0x000fe8000c101904). */
            int32_t off = (int32_t)insn->imm;
            if (off < -(1 << 23) || off >= (1 << 23)) return -1;
            w[0] = 0x7986 | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = (uint32_t)(src2 & 0xff) | (((uint32_t)off & 0xffffffU) << 8);
            w[2] = 0x0c101900 | (uint32_t)(ureg & 0xff);
            w[3] = insn->control ? insn->control : 0x000fe200;
            break;
        }

        case BW_IR_STG_EF:
            /* STG.E.MMIO.GPU. Uncached store, meant to be visible without a fence. */
            w[0] = 0x7986 | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = (uint32_t)(src2 & 0xff);
            w[2] = 0x0c111900 | (uint32_t)(ureg & 0xff);
            w[3] = insn->control ? insn->control : 0x000fe200;
            break;

        case BW_IR_IADD3:
            /* IADD3 Rd, PT, PT, Ra, Rb, Rc */
            w[0] = 0x7210 | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = (uint32_t)(src2 & 0xff);
            w[2] = 0x07ffe0ff;
            w[3] = insn->control ? insn->control : 0x010fca00; /* omega-mv#545: the emitter's waits, not a fixed SB4 wait */
            break;

        case BW_IR_HMMA_F16:
        case BW_IR_HMMA_BF16: {
            /* HMMA.16816.F32[.BF16] Rd, Ra, Rb, Rc */
            w[0] = 0x723c | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = (uint32_t)(src2 & 0xff);
            uint32_t prec_bit = (insn->op == BW_IR_HMMA_BF16) ? 0x00040000 : 0x00000000;
            w[2] = (uint32_t)(src3 & 0xff) | (0x18 << 8) | prec_bit;
            w[3] = insn->control ? insn->control : 0x000fe200;
            break;
        }

        case BW_IR_SHF_R:
            /* SHF.R.U32.HI Rd, RZ, imm, Ra */
            w[0] = 0x7819U | ((uint32_t)(dst & 0xff) << 16) | (0xffU << 24);
            w[1] = (uint32_t)insn->imm;
            w[2] = 0x00011600 | (uint32_t)(src1 & 0xff);
            w[3] = insn->control ? insn->control : 0x001fca00;
            break;

        case BW_IR_LOP3_AND:
            /* LOP3.LUT Rd, Ra, imm, RZ, 0xc0, !PT */
            w[0] = 0x7812U | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = (uint32_t)insn->imm;
            w[2] = 0x078ec0ff;
            w[3] = insn->control ? insn->control : 0x001fca00;
            break;

        case BW_IR_LDG_E_64:
        case BW_IR_LDG_E_128: {
            /* LDG.E.64 / LDG.E.128 Rd, desc[URd][Ra.64+imm]. imm = signed 24-bit byte offset at
             * bits 40..63 (w[1] bits 8..31); size field in w[2] bits 9..11 (32 = 4, 64 = 5, 128 = 6).
             * Words from nvcc 13.0.88 -arch=sm_121 (omega_blackwell_verify_codegen_fixtures_fragmm). */
            int32_t off = (int32_t)insn->imm;
            if (off < -(1 << 23) || off >= (1 << 23)) return -1;
            w[0] = 0x7981U | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = (uint32_t)(ureg & 0xff) | (((uint32_t)off & 0xffffffU) << 8);
            w[2] = insn->op == BW_IR_LDG_E_64 ? 0x0c1e1b00U : 0x0c1e1d00U;
            w[3] = insn->control ? insn->control : 0x000f2200;
            break;
        }

        case BW_IR_LDG_E_U16:
            /* LDG.E.U16 Rd, desc[URd][Ra.64] */
            w[0] = 0x7981U | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = (uint32_t)(ureg & 0xff);
            w[2] = 0x0c1e1500;
            w[3] = insn->control ? insn->control : 0x000f2200;
            break;

        case BW_IR_LDG_STRONG_SYS:
            /* LDG.E.STRONG.SYS. Same shape as LDG.E; w[2] carries the
             * system-scope bits (0x0c1e1900 -> 0x0c1f5900). */
            w[0] = 0x7981 | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = (uint32_t)(ureg & 0xff);
            w[2] = 0x0c1f5900;
            w[3] = insn->control ? insn->control : 0x000f2200;
            break;

        case BW_IR_LDG_MMIO:
            /* LDG.E.MMIO.GPU. Do not keep a stale cached copy.
             * 0x0c1f1900. 0x0c0e1900 is LDG.E.EF, the EF mutant, not this opcode. */
            w[0] = 0x7981 | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = (uint32_t)(ureg & 0xff);
            w[2] = 0x0c1f1900;
            w[3] = insn->control ? insn->control : 0x000f2200;
            break;

        case BW_IR_STG_STRONG_SYS:
            w[0] = 0x7986 | ((uint32_t)(src1 & 0xff) << 24);
            if (insn->predicate_p0) {
                uint32_t pred = insn->predicate_not ? 0x8u : 0x0u;
                w[0] = (w[0] & ~0xF000u) | (pred << 12);
            }
            w[1] = (uint32_t)(src2 & 0xff);
            w[2] = 0x0c115900 | (uint32_t)(ureg & 0xff);
            w[3] = insn->control ? insn->control : 0x000fe200;
            break;

        case BW_IR_MEMBAR_ALL_SYS:
            w[0] = 0x00007992;
            w[1] = 0x00000000;
            w[2] = 0x0000b000;
            w[3] = insn->control ? insn->control : 0x000fec00;
            break;

        case BW_IR_MEMBAR_SC_SYS:
            w[0] = 0x00007992;
            w[1] = 0x00000000;
            w[2] = 0x00003000;
            w[3] = insn->control ? insn->control : 0x000fec00;
            break;

        case BW_IR_CCTL_IVALL:
            w[0] = 0xff00798f;
            w[1] = 0x00000000;
            w[2] = 0x02000000;
            w[3] = insn->control ? insn->control : 0x000fe800;
            break;

        case BW_IR_ATOMG_ADD_STRONG_SYS:
            w[0] = 0x79a8 | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = (uint32_t)(src2 & 0xff) | 0x80000000u;
            w[2] = 0x081f5100 | (uint32_t)(ureg & 0xff);
            w[3] = insn->control ? insn->control : 0x00321e00;
            break;

        case BW_IR_ATOMG_EXCH_STRONG_SYS:
            w[0] = 0x79a8 | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = (uint32_t)(src2 & 0xff) | 0x80000000u;
            w[2] = 0x0c1f5100 | (uint32_t)(ureg & 0xff);
            w[3] = insn->control ? insn->control : 0x00321e00;
            break;

        case BW_IR_ATOMG_ADD_F32_STRONG_SYS:
        case BW_IR_ATOMG_ADD_F32_STRONG_GPU:
            /* ATOMG.E.ADD.F32.FTZ.RN.STRONG.{SYS,GPU} PT, Rd|RZ, desc[UR][Ra.64], Rb (omega_blackwell_verify_codegen_fixtures_atomf32).
             * Float opcode 0x9a3; w2 bit 26 selects the desc[] form, type 9 (w2 bits 9..12) is F32.FTZ.RN, order (w2 bits
             * 13..16) 0xa = SYS, 0x7 = GPU. No destination vreg encodes RZ (the generic default 0 would clobber R0). */
            w[0] = 0x79a3 | ((uint32_t)(insn->dst_vreg < 0 ? 0xff : (dst & 0xff)) << 16) | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = (uint32_t)(src2 & 0xff) | 0x80000000u;
            w[2] = (insn->op == BW_IR_ATOMG_ADD_F32_STRONG_GPU ? 0x0c1ef300u : 0x0c1f5300u) | (uint32_t)(ureg & 0xff);
            w[3] = insn->control ? insn->control : 0x00321e00;
            break;

        case BW_IR_ISETP_GE_U32:
            /* ISETP.GE.U32.AND P0, PT, Ra, Rb, PT. Checked with nvdisasm -b SM121. */
            w[0] = 0x720c | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = (uint32_t)(src2 & 0xff);
            w[2] = 0x03f06070;
            w[3] = insn->control ? insn->control : 0x001fda00;
            break;

        case BW_IR_LOP3_XOR:
            /* LOP3.LUT Rd, Ra, Rb, RZ, 0x3c, !PT. Checked with nvdisasm -b SM121. */
            w[0] = 0x7212 | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = (uint32_t)(src2 & 0xff);
            w[2] = 0x078e3cff;
            w[3] = insn->control ? insn->control : 0x001fca00;
            break;

        case BW_IR_FADD:
            /* FADD Rd, Ra, Rb */
            w[0] = 0x7221U | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = (uint32_t)(src2 & 0xff);
            w[2] = 0x00000000;
            w[3] = insn->control ? insn->control : 0x004fc400;
            break;

        case BW_IR_FSUB:
            /* FSUB Rd, Ra, Rb (FADD Rd, Ra, -Rb) */
            w[0] = 0x7221U | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = (uint32_t)(src2 & 0xff) | 0x80000000U;
            w[2] = 0x00000000;
            w[3] = insn->control ? insn->control : 0x004fc400;
            break;

        case BW_IR_FMUL:
            /* FMUL Rd, Ra, Rb */
            w[0] = 0x7220U | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = (uint32_t)(src2 & 0xff);
            w[2] = 0x00400000;
            w[3] = insn->control ? insn->control : 0x004fc400;
            break;

        case BW_IR_FFMA:
            /* FFMA Rd, Ra, Rb, Rc */
            w[0] = 0x7223U | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = (uint32_t)(src2 & 0xff);
            w[2] = (uint32_t)(src3 & 0xff);
            w[3] = insn->control ? insn->control : 0x004fc400;
            break;

        case BW_IR_FSETP:
            /* FSETP.cond.AND P0, PT, Ra, Rb, PT */
            w[0] = 0x720bU | ((uint32_t)(dst & 0x7) << 16) | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = (uint32_t)(src2 & 0xff);
            w[2] = insn->imm ? insn->imm : 0x03f06000; /* Default GE condition */
            w[3] = insn->control ? insn->control : 0x004fc400;
            break;

        case BW_IR_FSEL:
            /* FSEL Rd, Ra, Rb, P0 */
            w[0] = 0x7208U | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = (uint32_t)(src2 & 0xff);
            w[2] = (uint32_t)(src3 & 0x7);
            w[3] = insn->control ? insn->control : 0x000fca00;
            break;

        case BW_IR_FMNMX_MIN:
            /* FMNMX Rd, Ra, Rb, PT (minimum) */
            w[0] = 0x7209U | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = (uint32_t)(src2 & 0xff);
            w[2] = 0x03800000;
            w[3] = insn->control ? insn->control : 0x004fc400;
            break;

        case BW_IR_FMNMX_MAX:
            /* FMNMX Rd, Ra, Rb, !PT (maximum) */
            w[0] = 0x7209U | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = (uint32_t)(src2 & 0xff);
            w[2] = 0x07800000;
            w[3] = insn->control ? insn->control : 0x004fc400;
            break;

        case BW_IR_I2FP:
            /* I2FP.F32.S32 Rd, Ra */
            w[0] = 0x7245U | ((uint32_t)(dst & 0xff) << 16);
            w[1] = (uint32_t)(src1 & 0xff);
            w[2] = 0x00201400;
            w[3] = insn->control ? insn->control : 0x004fe200;
            break;

        case BW_IR_F2I:
            /* F2I.TRUNC.NTZ Rd, Ra */
            w[0] = 0x7305U | ((uint32_t)(dst & 0xff) << 16);
            w[1] = (uint32_t)(src1 & 0xff);
            w[2] = 0x0020f100;
            w[3] = insn->control ? insn->control : 0x004e2200;
            break;

        case BW_IR_MUFU_RCP:
            /* MUFU.RCP Rd, Ra */
            w[0] = 0x7308U | ((uint32_t)(dst & 0xff) << 16);
            w[1] = (uint32_t)(src1 & 0xff);
            w[2] = 0x00001000;
            w[3] = insn->control ? insn->control : 0x000e2400;
            break;

        case BW_IR_MUFU_LG2:
            /* MUFU.LG2 Rd, Ra (nvdisasm 13.0 -b SM121 decodes sub-op 0x0c00 as MUFU.LG2) */
            w[0] = 0x7308U | ((uint32_t)(dst & 0xff) << 16);
            w[1] = (uint32_t)(src1 & 0xff);
            w[2] = 0x00000c00;
            w[3] = insn->control ? insn->control : 0x000e2400;
            break;

        case BW_IR_MUFU_RSQ:
            /* MUFU.RSQ Rd, Ra */
            w[0] = 0x7308U | ((uint32_t)(dst & 0xff) << 16);
            w[1] = (uint32_t)(src1 & 0xff);
            w[2] = 0x00001400;
            w[3] = insn->control ? insn->control : 0x000e2400;
            break;

        case BW_IR_SHFL_DOWN:
            /* SHFL.DOWN PT, Rd, Ra, offset, 0x1f */
            w[0] = 0x7f89U | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = 0x08001f00U | (((uint32_t)insn->imm & 0x1f) << 21);
            w[2] = 0x000e0000;
            w[3] = insn->control ? insn->control : 0x000e2400;
            break;

        case BW_IR_SHFL_BFLY:
            /* SHFL.BFLY PT, Rd, Ra, lane, 0x1f: SHFL.DOWN with bit 58 (w[1] bit 26) set
             * (omega_blackwell_verify_codegen_fixtures_bfly_f2fp) */
            w[0] = 0x7f89U | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = 0x0c001f00U | (((uint32_t)insn->imm & 0x1f) << 21);
            w[2] = 0x000e0000;
            w[3] = insn->control ? insn->control : 0x000e2400;
            break;

        case BW_IR_F2FP_BF16_PACK:
            /* F2FP.BF16.F32.PACK_AB Rd, Ra, Rb (omega_blackwell_verify_codegen_fixtures_bfly_f2fp). The default control
             * is FMNMX's: the kernels emitted this as a patched FMNMX_MAX before R5 and their bytes must not move. */
            w[0] = 0x723eU | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = (uint32_t)(src2 & 0xff);
            w[2] = 0x000010ff;
            w[3] = insn->control ? insn->control : 0x004fc400;
            break;

        case BW_IR_LDS:
            /* LDS Rd, [Ra] */
            w[0] = 0x7984U | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = 0x00000000;
            w[2] = (uint32_t)(insn->imm & 0xffff);
            w[3] = insn->control ? insn->control : 0x000fe200;
            break;

        case BW_IR_STS:
            /* STS [Ra], Rb */
            w[0] = 0x7388U | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = (uint32_t)(src2 & 0xff);
            w[2] = (uint32_t)(insn->imm & 0xffff);
            w[3] = insn->control ? insn->control : 0x000fe200;
            break;

        case BW_IR_EXIT:
            w[0] = insn->predicate_p0 ? 0x0000094d : 0x0000794d;
            w[1] = 0x00000000;
            w[2] = 0x03800000;
            w[3] = insn->control ? insn->control : 0x000fea00;
            break;

        case BW_IR_BRA: {
            /* sm_121 BRA. Distance is (target - this) - 1, split across the
             * low six bits at instruction bits 18..23 and the rest at bit 34.
             * Predicate bits 12..15: 7 = always, 0 = @P0, 8 = @!P0.
             * A zero delta with no predicate keeps the self-branch word the
             * existing kernels already emit after EXIT. */
            int32_t delta = (int32_t)insn->imm;
            int32_t rel = delta - 1;
            uint32_t pred_field = 0x7u;
            if (insn->predicate_p0)
                pred_field = insn->predicate_not ? 0x8u : 0x0u;
            w[0] = 0x947u | (pred_field << 12) | (((uint32_t)rel & 0x3fu) << 18);
            w[1] = (uint32_t)(rel >> 6) << 2;
            w[2] = (rel < 0) ? 0x0383ffffu : 0x03800000u;
            if (insn->control)
                w[3] = insn->control;
            else if (delta == 0 && !insn->predicate_p0)
                w[3] = 0x000fc000u;
            else
                w[3] = 0x000fea00u;
            break;
        }

        case BW_IR_BSSY: {
            /* BSSY.RECONVERGENT Bn, target (omega #308). nvcc 13.0.88 -arch=sm_121:
             *   [0070] BSSY.RECONVERGENT B0, 0x140 ; 0x000000c000007945 0x000fe20003800200
             * opcode 0x945 (NAK sm70_encode.rs:4165), barrier id at bits 16..19 (set_bar_dst
             * 16..20), guard predicate at bits 12..15 like BRA, relative byte offset
             * target - (this + 16) at bit 32 (NAK: field 34.. in 4-byte units), the cond
             * predicate PT at bits 87..89 (0x0380 << 16 in w[2]) and bit 73 (0x200 in w[2]),
             * which the disassembler prints as .RECONVERGENT; nvcc sets it on every BSSY/BSYNC
             * for sm_121 and Mesa NAK does not. We follow nvcc. The target is the instruction
             * after the matching BSYNC, so the delta is at least 2; smaller is refused. */
            int32_t delta = (int32_t)insn->imm;
            if (delta < 2 || insn->bar_reg >= BW_RECONV_MAX_BAR) return -1;
            uint32_t pred_field = 0x7u;
            if (insn->predicate_p0)
                pred_field = insn->predicate_not ? 0x8u : 0x0u;
            w[0] = 0x945u | (pred_field << 12) | ((uint32_t)insn->bar_reg << 16);
            w[1] = (uint32_t)(delta - 1) * 16u;
            w[2] = 0x03800200u;
            w[3] = insn->control ? insn->control : 0x000fe200u;
            break;
        }

        case BW_IR_BSYNC: {
            /* BSYNC.RECONVERGENT Bn: [0130] BSYNC.RECONVERGENT B0 ; 0x0000000000007941 0x000fea0003800200
             * opcode 0x941 (NAK sm70_encode.rs:4179), barrier id bits 16..19, cond PT, bit 73. */
            if (insn->bar_reg >= BW_RECONV_MAX_BAR) return -1;
            uint32_t pred_field = 0x7u;
            if (insn->predicate_p0)
                pred_field = insn->predicate_not ? 0x8u : 0x0u;
            w[0] = 0x941u | (pred_field << 12) | ((uint32_t)insn->bar_reg << 16);
            w[1] = 0;
            w[2] = 0x03800200u;
            w[3] = insn->control ? insn->control : 0x000fea00u;
            break;
        }

        case BW_IR_MUFU_EX2:
            /* MUFU.EX2 Rd, Ra. nvdisasm 13.0 -b SM121: 0x7308 with sub-op 0x0800 decodes
             * "MUFU.EX2 R2, R4" (RCP is 0x1000, RSQ 0x1400 above). */
            w[0] = 0x7308U | ((uint32_t)(dst & 0xff) << 16);
            w[1] = (uint32_t)(src1 & 0xff);
            w[2] = 0x00000800;
            w[3] = insn->control ? insn->control : 0x000e2400;
            break;

        case BW_IR_BAR_SYNC:
            /* BAR.SYNC.DEFER_BLOCKING 0x0: the exact words src/omega_numeric.c:885 runs on
             * the chip (nvdisasm: "BAR.SYNC.DEFER_BLOCKING 0x0"). No registers. */
            w[0] = 0x00007b1dU;
            w[1] = 0x00000000;
            w[2] = 0x00010000;
            w[3] = insn->control ? insn->control : 0x000fec00;
            break;

        case BW_IR_LDS128: {
            /* LDS.128 Rd..Rd+3, [Ra+imm]. nvcc 13.0.88 -arch=sm_121 words (fixtures below):
             *   LDS.128 R4, [R20] ;        0x0000000014047984 0x000fe80000000c00
             *   LDS.128 R8, [R20+0x40] ;   0x0000400014087984 0x000e280000000c00
             * imm = byte offset at w[1] bits 8..31; size field 6 (128) at w[2] bits 9..11. */
            if (insn->imm >= (1u << 23)) return -1;
            w[0] = 0x7984U | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = (insn->imm & 0xffffffU) << 8;
            w[2] = 0x00000c00U;
            w[3] = insn->control ? insn->control : 0x000fe800;
            break;
        }

        case BW_IR_LDS32:
            /* LDS Rd, [Ra+URZ] (32-bit), the src/omega_numeric.c:886 form. */
            w[0] = 0x7984U | ((uint32_t)(dst & 0xff) << 16) | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = 0x000000ff;
            w[2] = 0x08000800;
            w[3] = insn->control ? insn->control : 0x000e2800;
            break;

        case BW_IR_STS32:
            /* STS [Ra+URZ], Rb (32-bit), the src/omega_numeric.c:884 form. */
            w[0] = 0x7988U | ((uint32_t)(src1 & 0xff) << 24);
            w[1] = (uint32_t)(src2 & 0xff);
            w[2] = 0x080008ffU;
            w[3] = insn->control ? insn->control : 0x000fe200;
            break;

        /* Prime race cut (2026-10-05). An absent operand is RZ for these three ops. */
        case BW_IR_LOP3_LUT: {
            /* LOP3.LUT Rd, Ra, Rb, Rc, imm8, !PT. LOP3_XOR above is this form with Rc = RZ, LUT 0x3c. */
            uint32_t a = (insn->src1_vreg >= 0) ? (uint32_t)(src1 & 0xff) : 0xffU;
            uint32_t b = (insn->src2_vreg >= 0) ? (uint32_t)(src2 & 0xff) : 0xffU;
            w[0] = 0x7212U | ((uint32_t)(dst & 0xff) << 16) | (a << 24);
            w[1] = b;
            w[2] = 0x078e0000U | ((insn->imm & 0xffU) << 8) | (uint32_t)(src3 & 0xff);
            w[3] = insn->control ? insn->control : 0x001fca00;
            break;
        }

        case BW_IR_SHF_L_U32: {
            /* SHF.L.U32 Rd, Ra, Rb, Rc: register-amount form (0x7219) of SHF_R's 0x7819, with the
             * .R (w[2] bit 12) and .HI (bit 16) flags clear. Rc is the funnel high word (RZ). */
            uint32_t a = (insn->src1_vreg >= 0) ? (uint32_t)(src1 & 0xff) : 0xffU;
            uint32_t b = (insn->src2_vreg >= 0) ? (uint32_t)(src2 & 0xff) : 0xffU;
            w[0] = 0x7219U | ((uint32_t)(dst & 0xff) << 16) | (a << 24);
            w[1] = b;
            w[2] = 0x00000600U | (uint32_t)(src3 & 0xff);
            w[3] = insn->control ? insn->control : 0x001fca00;
            break;
        }

        case BW_IR_IMAD_HI_U32: {
            /* IMAD.HI.U32 Rd, Ra, Rb, Rc: opcode 0x227 with the IMAD.WIDE.U32 modifier word. */
            uint32_t a = (insn->src1_vreg >= 0) ? (uint32_t)(src1 & 0xff) : 0xffU;
            uint32_t b = (insn->src2_vreg >= 0) ? (uint32_t)(src2 & 0xff) : 0xffU;
            w[0] = 0x7227U | ((uint32_t)(dst & 0xff) << 16) | (a << 24);
            w[1] = b;
            w[2] = 0x078e0000U | (uint32_t)(src3 & 0xff);
            w[3] = insn->control ? insn->control : 0x001fca00;
            break;
        }

        default:
            return -1;
    }
    return 0;
}
#endif /* C encoder, migration-pending */

#ifdef BW_ENC_C_PRIMARY
static int encode_single_insn(const BlackwellIRInsn *insn, const OmegaRegAlloc *ra, uint32_t w[4]) {
    return bw_c_encode_insn(insn, ra, w);
}
#else
#include "omega_native.h"
/* The .om unit reads the IR as 8 ulongs per instruction and the allocation as one 288-entry table; these are the
 * layouts its source documents (om/encoder/bw_enc_sm121.om), so the enum values and sizes are pinned here. */
#define BW_OM_INS_LEN 8192u  /* BW_MAX_IR_INSNS * 8 */
#define BW_OM_PHYS_LEN 288u  /* BW_MAX_VREGS + BW_MAX_UVREGS */
#define BW_OM_CODE_LEN 16384u /* BW_MAX_IR_INSNS * 16 */
_Static_assert(BW_MAX_IR_INSNS == 1024 && BW_MAX_VREGS == 256 && BW_MAX_UVREGS == 32, "bw_enc_sm121.om array sizes");
_Static_assert(BW_IR_NOP == 0 && BW_IR_MOV_RZ == 1 && BW_IR_MOV_IMM == 2 && BW_IR_S2R == 3 && BW_IR_LDC == 4 &&
               BW_IR_LDC64 == 5 && BW_IR_LDCU == 6 && BW_IR_LDCU64 == 7 && BW_IR_IMAD == 8 && BW_IR_IMAD_WIDE == 9 &&
               BW_IR_ISETP_GE == 10 && BW_IR_LDG_E == 11 && BW_IR_STG_E == 12 && BW_IR_STG_EF == 13 &&
               BW_IR_IADD3 == 14 && BW_IR_HMMA_F16 == 15 && BW_IR_HMMA_BF16 == 16 && BW_IR_SHF_R == 17 &&
               BW_IR_LOP3_AND == 18 && BW_IR_LDG_E_U16 == 19 && BW_IR_LDG_STRONG_SYS == 20 && BW_IR_LDG_MMIO == 21 &&
               BW_IR_STG_STRONG_SYS == 22 && BW_IR_MEMBAR_ALL_SYS == 23 && BW_IR_MEMBAR_SC_SYS == 24 &&
               BW_IR_CCTL_IVALL == 25 && BW_IR_ATOMG_ADD_STRONG_SYS == 26 && BW_IR_ATOMG_EXCH_STRONG_SYS == 27 &&
               BW_IR_ISETP_GE_U32 == 28 && BW_IR_LOP3_XOR == 29, "bw_enc_sm121.om opcode numbers 0-29");
_Static_assert(BW_IR_FADD == 30 && BW_IR_FSUB == 31 && BW_IR_FMUL == 32 && BW_IR_FFMA == 33 && BW_IR_FSETP == 34 &&
               BW_IR_FSEL == 35 && BW_IR_FMNMX_MIN == 36 && BW_IR_FMNMX_MAX == 37 && BW_IR_I2FP == 38 &&
               BW_IR_F2I == 39 && BW_IR_MUFU_RCP == 40 && BW_IR_MUFU_RSQ == 41 && BW_IR_SHFL_DOWN == 42 &&
               BW_IR_LDS == 43 && BW_IR_STS == 44 && BW_IR_EXIT == 45 && BW_IR_BRA == 46 && BW_IR_MUFU_EX2 == 47 &&
               BW_IR_BAR_SYNC == 48 && BW_IR_LDS32 == 49 && BW_IR_STS32 == 50 && BW_IR_LOP3_LUT == 51 &&
               BW_IR_SHF_L_U32 == 52 && BW_IR_IMAD_HI_U32 == 53 && BW_IR_BSSY == 54 && BW_IR_BSYNC == 55 &&
               BW_IR_LDG_E_64 == 56 && BW_IR_LDG_E_128 == 57 && BW_IR_LDS128 == 58 && BW_IR_MUFU_LG2 == 59,
               "bw_enc_sm121.om opcode numbers 30-59");
_Static_assert(BW_IR_SHFL_BFLY == 60 && BW_IR_F2FP_BF16_PACK == 61 && BW_IR_ATOMG_ADD_F32_STRONG_SYS == 62 &&
               BW_IR_ATOMG_ADD_F32_STRONG_GPU == 63, "bw_enc_sm121.om opcode numbers 60-63");

/* Encodes n instructions through the .om unit into code (BW_OM_CODE_LEN bytes). pad != 0 is program mode (NOP
 * padding to a multiple of 8, at least 32). Returns the bytes written; 0 = refused. */
static size_t bw_om_encode(const BlackwellIRInsn *insns, size_t n, const OmegaRegAlloc *ra, int pad, uint8_t *code) {
    if (n > BW_MAX_IR_INSNS) return 0;
    uint64_t ins[BW_OM_INS_LEN], phys[BW_OM_PHYS_LEN];
    for (size_t i = 0; i < n; i++) {
        const BlackwellIRInsn *in = &insns[i];
        uint64_t *r = &ins[i * 8];
        r[0] = (uint64_t)(int64_t)(int)in->op;
        r[1] = (uint64_t)(int64_t)in->dst_vreg;
        r[2] = (uint64_t)(int64_t)in->src1_vreg;
        r[3] = (uint64_t)(int64_t)in->src2_vreg;
        r[4] = (uint64_t)(int64_t)in->src3_vreg;
        r[5] = (uint64_t)(int64_t)in->ureg;
        r[6] = (uint64_t)in->imm | (uint64_t)in->control << 32;
        r[7] = (uint64_t)in->is_uniform | (uint64_t)in->predicate_p0 << 1 | (uint64_t)in->predicate_not << 2 |
               (uint64_t)in->bar_reg << 8 | (uint64_t)in->dst_subreg << 16 | (uint64_t)in->src1_subreg << 24 |
               (uint64_t)in->src2_subreg << 32 | (uint64_t)in->src3_subreg << 40;
    }
    for (size_t i = n * 8; i < BW_OM_INS_LEN; i++) ins[i] = 0;
    for (int i = 0; i < BW_MAX_VREGS; i++) phys[i] = (uint64_t)(int64_t)ra->vreg_to_phys[i];
    for (int i = 0; i < BW_MAX_UVREGS; i++) phys[BW_MAX_VREGS + i] = (uint64_t)(int64_t)ra->uvreg_to_phys[i];
    uint64_t bytes = 0;
    if (omega_bw_enc_sm121(&bytes, ins, BW_OM_INS_LEN, phys, BW_OM_PHYS_LEN, (uint64_t)n, pad ? 1u : 0u, code,
                           BW_OM_CODE_LEN) != OMEGA_OK)
        return 0;
    return (size_t)bytes;
}

#ifdef CUDAPP_MIGRATION_PENDING_ENCODER_DIFF
/* One line per agreement, appended; any disagreement aborts the process after naming it. */
static void bw_enc_diff_note(const char *what, size_t insns, const uint8_t *code, size_t len, int agree) {
    char hex[17] = "-";
    if (len) {
        uint8_t d[SHA256_DIGEST_SIZE]; sha256_hash(code, len, d);
        for (int i = 0; i < 8; i++) snprintf(hex + 2 * i, 3, "%02x", (unsigned)d[i]);
    }
    const char *path = getenv("CUDAPP_ENCODER_DIFF_LOG");
    if (path && path[0]) {
        int fd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0600);
        if (fd >= 0) {
            char line[160];
            int k = snprintf(line, sizeof line, "%s insns=%zu bytes=%zu sha16=%s %s\n", what, insns, len, hex,
                             agree ? "SAME" : "DIFFER");
            if (k > 0 && write(fd, line, (size_t)k) != k) BW_DIAG("encoder diff: short log write\n");
            close(fd);
        }
    }
    if (!agree) {
        BW_DIAG("ENCODER DIFF: .om and C encoders disagree (%s, %zu insns)\n", what, insns);
        abort();
    }
}
#endif

static int encode_single_insn(const BlackwellIRInsn *insn, const OmegaRegAlloc *ra, uint32_t w[4]) {
    uint8_t code[BW_OM_CODE_LEN];
    int rc = bw_om_encode(insn, 1, ra, 0, code) == 16 ? 0 : -1;
    memset(w, 0, 16);
    if (rc == 0)
        for (int k = 0; k < 4; k++)
            w[k] = (uint32_t)code[4 * k] | (uint32_t)code[4 * k + 1] << 8 | (uint32_t)code[4 * k + 2] << 16 |
                   (uint32_t)code[4 * k + 3] << 24;
#ifdef CUDAPP_MIGRATION_PENDING_ENCODER_DIFF
    uint32_t c[4];
    int crc = bw_c_encode_insn(insn, ra, c);
    bw_enc_diff_note("insn", 1, rc == 0 ? code : NULL, rc == 0 ? 16 : 0,
                     crc == rc && (rc != 0 || memcmp(c, w, 16) == 0));
#endif
    return rc;
}
#endif

/* Prime race cut (2026-10-05): golden words for LOP3_LUT, SHF_L_U32 and IMAD_HI_U32.
 * Each expected (w0, w1, w2) is the low 96 bits of an instruction nvcc 13.0.88 emitted
 * for sm_121 (nvcc -arch=sm_121 -cubin, cuobjdump -sass; source and dump in
 * bench/prime_race/tests/encoding_oracle.md). Control words (w3) are scheduler output and
 * not compared. nvcc is an offline oracle only; nothing here links CUDA. 0 = all good. */
int omega_blackwell_verify_codegen_fixtures_intops(void) {
    OmegaRegAlloc ra;
    memset(&ra, 0, sizeof(ra));
    static const int phys[] = { 0, 2, 6, 7, 9, 11, 13 };
    for (int i = 0; i < (int)(sizeof phys / sizeof phys[0]); i++) ra.vreg_to_phys[i] = phys[i];
    enum { R0 = 0, R2, R6, R7, R9, R11, R13, RZ = -1 };
    static const struct {
        BlackwellIROpcode op; int d, a, b, c; uint32_t imm; uint32_t w0, w1, w2; const char *text;
    } fx[] = {
        { BW_IR_LOP3_LUT, R9, R7, R0, RZ, 0xfc, 0x07097212U, 0x00000000U, 0x078efcffU, "LOP3.LUT R9, R7, R0, RZ, 0xfc, !PT" },
        { BW_IR_LOP3_LUT, R11, R6, R7, R0, 0x78, 0x060b7212U, 0x00000007U, 0x078e7800U, "LOP3.LUT R11, R6, R7, R0, 0x78, !PT" },
        { BW_IR_LOP3_LUT, R13, R6, R7, R0, 0x10, 0x060d7212U, 0x00000007U, 0x078e1000U, "LOP3.LUT R13, R6, R7, R0, 0x10, !PT" },
        { BW_IR_LOP3_LUT, R7, RZ, R9, RZ, 0x33, 0xff077212U, 0x00000009U, 0x078e33ffU, "LOP3.LUT R7, RZ, R9, RZ, 0x33, !PT" },
        { BW_IR_SHF_L_U32, R7, R9, R2, RZ, 0, 0x09077219U, 0x00000002U, 0x000006ffU, "SHF.L.U32 R7, R9, R2, RZ" },
        { BW_IR_SHF_L_U32, R7, R0, R7, RZ, 0, 0x00077219U, 0x00000007U, 0x000006ffU, "SHF.L.U32 R7, R0, R7, RZ" },
        { BW_IR_IMAD_HI_U32, R9, R9, R0, R6, 0, 0x09097227U, 0x00000000U, 0x078e0006U, "IMAD.HI.U32 R9, R9, R0, R6" },
        { BW_IR_IMAD_HI_U32, R7, R0, R7, RZ, 0, 0x00077227U, 0x00000007U, 0x078e00ffU, "IMAD.HI.U32 R7, R0, R7, RZ" },
    };
    for (int i = 0; i < (int)(sizeof fx / sizeof fx[0]); i++) {
        BlackwellIRInsn in;
        memset(&in, 0, sizeof in);
        in.op = fx[i].op; in.dst_vreg = fx[i].d; in.src1_vreg = fx[i].a; in.src2_vreg = fx[i].b;
        in.src3_vreg = fx[i].c; in.ureg = -1; in.imm = fx[i].imm;
        uint32_t w[4];
        if (encode_single_insn(&in, &ra, w) != 0) return -(2 * i + 1);
        if (w[0] != fx[i].w0 || w[1] != fx[i].w1 || w[2] != fx[i].w2) return -(2 * i + 2);
    }
    return 0;
}

int omega_blackwell_encode_one(const BlackwellIRInsn *insn, uint32_t w[4]) {
    if (!insn || !w) return -1;
    OmegaRegAlloc ra;
    memset(&ra, 0, sizeof ra);
    for (int i = 0; i < BW_MAX_VREGS; i++) ra.vreg_to_phys[i] = i;
    for (int i = 0; i < BW_MAX_UVREGS; i++) ra.uvreg_to_phys[i] = i;
    return encode_single_insn(insn, &ra, w);
}

/* omega #328: golden words for the fragment-major matmul. Oracle: nvcc 13.0.88 -arch=sm_121
 * -cubin -O3, cuobjdump -sass, on a kernel with uint2 / uint4 loads at immediate offsets and a
 * dependent mma.m16n8k16 bf16 chain (source and dump sealed in
 * ~/workspace/investigations/2026-10-07-qwen3-decode-matmul/oracle/frag_plain.{cu,sass}):
 *   LDG.E.64 R2, desc[UR8][R30.64] ;            0x000000081e027981 0x000ea8000c1e1b00
 *   LDG.E.64 R28, desc[UR8][R30.64+0x100] ;     0x000100081e1c7981 0x000ee8000c1e1b00
 *   LDG.E.128 R8, desc[UR8][R32.64] ;           0x0000000820087981 0x000ea8000c1e1d00
 *   LDG.E.128 R20, desc[UR8][R32.64+0x1000] ;   0x0010000820147981 0x000e9e000c1e1d00
 *   HMMA.16816.F32.BF16 R8, R12, R6, R8 ;       0x000000060c08723c 0x010fe20000041808
 *   NOP ;                                       0x0000000000007918 0x000fdc0000000000
 * The dependent HMMA chain nvcc emits is HMMA (stall 15) then NOP (stall 14): 29 cycles from
 * one HMMA to the next that reads its accumulator. w3 is compared for the NOP only (it is the
 * whole point of that instruction). 0 = all good. */
int omega_blackwell_verify_codegen_fixtures_fragmm(void) {
    static const struct {
        BlackwellIROpcode op; int d, a, b, c, u; uint32_t imm, control; uint32_t w0, w1, w2, w3; const char *text;
    } fx[] = {
        { BW_IR_LDG_E_64, 2, 30, -1, -1, 8, 0, 0, 0x1e027981U, 0x00000008U, 0x0c1e1b00U, 0, "LDG.E.64 R2, desc[UR8][R30.64]" },
        { BW_IR_LDG_E_64, 28, 30, -1, -1, 8, 0x100, 0, 0x1e1c7981U, 0x00010008U, 0x0c1e1b00U, 0, "LDG.E.64 R28, desc[UR8][R30.64+0x100]" },
        { BW_IR_LDG_E_128, 8, 32, -1, -1, 8, 0, 0, 0x20087981U, 0x00000008U, 0x0c1e1d00U, 0, "LDG.E.128 R8, desc[UR8][R32.64]" },
        { BW_IR_LDG_E_128, 20, 32, -1, -1, 8, 0x1000, 0, 0x20147981U, 0x00100008U, 0x0c1e1d00U, 0, "LDG.E.128 R20, desc[UR8][R32.64+0x1000]" },
        { BW_IR_HMMA_BF16, 8, 12, 6, 8, -1, 0, 0, 0x0c08723cU, 0x00000006U, 0x00041808U, 0, "HMMA.16816.F32.BF16 R8, R12, R6, R8" },
        { BW_IR_NOP, -1, -1, -1, -1, -1, 0, 0x000fdc00U, 0x00007918U, 0, 0, 0x000fdc00U, "NOP (stall 14)" },
        /* LDS.128 with an immediate offset (attention batched loads, 2026-10-12): nvcc 13.0.88 -arch=sm_121 on
         * float4 shared reads at register + constant offsets (fixture source in the omega speed/attention-batched-loads PR) */
        { BW_IR_LDS128, 4, 20, -1, -1, -1, 0, 0, 0x14047984U, 0x00000000U, 0x00000c00U, 0, "LDS.128 R4, [R20]" },
        { BW_IR_LDS128, 8, 20, -1, -1, -1, 0x40, 0, 0x14087984U, 0x00004000U, 0x00000c00U, 0, "LDS.128 R8, [R20+0x40]" },
        { BW_IR_LDS128, 12, 20, -1, -1, -1, 0x100, 0, 0x140c7984U, 0x00010000U, 0x00000c00U, 0, "LDS.128 R12, [R20+0x100]" },
        /* STG.E with an immediate offset (blocked prefill matmul, 2026-10-12): nvcc 13.0.88 -arch=sm_121 on float stores
         * at register + constant offsets (~/.claude/jobs/ade3c837/tmp/stg-oracle/stg.cu); the second word is the
         * offset-free STG word with UR4 */
        { BW_IR_STG_E, -1, 4, 8, -1, 4, 0, 0, 0x04007986U, 0x00000008U, 0x0c101904U, 0, "STG.E desc[UR4][R4.64], R8" },
        { BW_IR_STG_E, -1, 4, 9, -1, 4, 0x4, 0, 0x04007986U, 0x00000409U, 0x0c101904U, 0, "STG.E desc[UR4][R4.64+0x4], R9" },
        { BW_IR_STG_E, -1, 4, 10, -1, 4, 0x4000, 0, 0x04007986U, 0x0040000aU, 0x0c101904U, 0, "STG.E desc[UR4][R4.64+0x4000], R10" },
        { BW_IR_STG_E, -1, 6, 11, -1, 4, 0xfff00000u, 0, 0x06007986U, 0xf000000bU, 0x0c101904U, 0, "STG.E desc[UR4][R6.64+-0x100000], R11" },
    };
    for (int i = 0; i < (int)(sizeof fx / sizeof fx[0]); i++) {
        BlackwellIRInsn in;
        memset(&in, 0, sizeof in);
        in.op = fx[i].op; in.dst_vreg = fx[i].d; in.src1_vreg = fx[i].a; in.src2_vreg = fx[i].b;
        in.src3_vreg = fx[i].c; in.ureg = fx[i].u; in.imm = fx[i].imm; in.control = fx[i].control;
        uint32_t w[4];
        if (omega_blackwell_encode_one(&in, w) != 0) return -(2 * i + 1);
        if (w[0] != fx[i].w0 || w[1] != fx[i].w1 || w[2] != fx[i].w2 || (fx[i].w3 && w[3] != fx[i].w3)) return -(2 * i + 2);
    }
    /* offsets outside the signed 24-bit field are refused, not wrapped */
    BlackwellIRInsn big;
    memset(&big, 0, sizeof big);
    big.op = BW_IR_LDG_E_64; big.dst_vreg = 2; big.src1_vreg = 30; big.src2_vreg = -1; big.src3_vreg = -1; big.ureg = 8;
    big.imm = 1u << 23;
    uint32_t w[4];
    if (omega_blackwell_encode_one(&big, w) == 0) return -100;
    big.imm = (uint32_t)-(1 << 23);
    if (omega_blackwell_encode_one(&big, w) != 0) return -101;
    return 0;
}

/* omega #308: BSSY / BSYNC golden words. Oracle: nvcc 13.0.88 -arch=sm_121 -cubin -O3 on the
 * kernels in docs/gpu-reconvergence-308.md, cuobjdump -sass (low 64-bit word, then high; the
 * top 23 bits of the high word are the control word and are not compared here):
 *   k_loop   [0070] BSSY.RECONVERGENT B0, 0x140 ; 0x000000c000007945 0x000fe20003800200  (delta 13)
 *   k_nested [0070] BSSY.RECONVERGENT B0, 0x300 ; 0x0000028000007945 0x000fe20003800200  (delta 41)
 *   k_break  [0070] BSSY.RECONVERGENT B0, 0x110 ; 0x0000009000007945 0x000fe20003800200  (delta 10)
 *   k_loop   [0130] BSYNC.RECONVERGENT B0 ;        0x0000000000007941 0x000fea0003800200
 * Barrier ids other than B0 and the predicated forms are decoded by tools/reconv_nvdisasm_check.sh
 * (nvdisasm -b SM121 text), not by this table. */
int omega_blackwell_verify_codegen_fixtures_reconv(void) {
    static const struct { BlackwellIROpcode op; int delta; int bar; uint32_t w0, w1, w2; } fx[] = {
        { BW_IR_BSSY, 13, 0, 0x00007945U, 0x000000c0U, 0x03800200U },
        { BW_IR_BSSY, 41, 0, 0x00007945U, 0x00000280U, 0x03800200U },
        { BW_IR_BSSY, 10, 0, 0x00007945U, 0x00000090U, 0x03800200U },
        { BW_IR_BSYNC, 0, 0, 0x00007941U, 0x00000000U, 0x03800200U },
    };
    for (int i = 0; i < (int)(sizeof fx / sizeof fx[0]); i++) {
        BlackwellIRInsn in;
        memset(&in, 0, sizeof in);
        in.op = fx[i].op; in.dst_vreg = -1; in.src1_vreg = -1; in.src2_vreg = -1; in.src3_vreg = -1; in.ureg = -1;
        in.imm = (uint32_t)fx[i].delta; in.bar_reg = (uint8_t)fx[i].bar;
        uint32_t w[4];
        if (omega_blackwell_encode_one(&in, w) != 0) return -(2 * i + 1);
        if (w[0] != fx[i].w0 || w[1] != fx[i].w1 || w[2] != fx[i].w2) return -(2 * i + 2);
        /* control word defaults mirror nvcc's: BSSY 0x000fe200, BSYNC 0x000fea00 */
        if (w[3] != (fx[i].op == BW_IR_BSSY ? 0x000fe200U : 0x000fea00U)) return -(2 * i + 2);
    }
    /* refusals: a BSSY must name a later instruction (delta >= 2), barrier ids stop at B15 */
    BlackwellIRInsn bad; uint32_t w[4];
    memset(&bad, 0, sizeof bad); bad.op = BW_IR_BSSY; bad.dst_vreg = bad.src1_vreg = bad.src2_vreg = bad.src3_vreg = bad.ureg = -1;
    bad.imm = 1; bad.bar_reg = 0;
    if (omega_blackwell_encode_one(&bad, w) == 0) return -101;
    bad.imm = (uint32_t)-3;
    if (omega_blackwell_encode_one(&bad, w) == 0) return -102;
    bad.imm = 5; bad.bar_reg = 16;
    if (omega_blackwell_encode_one(&bad, w) == 0) return -103;
    bad.op = BW_IR_BSYNC; bad.imm = 0; bad.bar_reg = 16;
    if (omega_blackwell_encode_one(&bad, w) == 0) return -104;
    bad.bar_reg = 15;
    if (omega_blackwell_encode_one(&bad, w) != 0 || w[0] != (0x00007941U | (15U << 16))) return -105;
    return 0;
}


/* Training R5 (2026-10-15): golden words for SHFL.BFLY and F2FP.BF16.F32.PACK_AB, the two instructions the prefill
 * kernels emitted as placeholders patched after encoding until R5. Oracle: nvcc 13.0.88 -arch=sm_121, cuobjdump -sass,
 * sealed in evidence/OWN30B-T3-TC-PEAK-BW-5faa0f70-20261013T2236Z/fa_ops.{cu,sass} (low 64-bit word, then high; the top
 * 23 bits of the high word are the control word and are not compared):
 *   SHFL.BFLY PT, R5, R0, 0x1, 0x1f ;      0x0c201f0000057f89 0x004e2800000e0000
 *   SHFL.BFLY PT, R7, R8, 0x1, 0x1f ;      0x0c201f0008077f89 0x008e6200000e0000
 *   SHFL.BFLY PT, R4, R9, 0x2, 0x1f ;      0x0c401f0009047f89 0x000e2800000e0000
 *   SHFL.BFLY PT, R6, R11, 0x2, 0x1f ;     0x0c401f000b067f89 0x000e6200000e0000
 *   F2FP.BF16.F32.PACK_AB R9, R3, R0 ;     0x000000000309723e 0x000fe200000010ff
 *   F2FP.BF16.F32.PACK_AB R13, R13, R10 ;  0x0000000a0d0d723e 0x000fe400000010ff
 * SHFL.BFLY is SHFL.DOWN (oracle words in omega_numeric.c, lanes 16 .. 1) with bit 58 set (Mesa NAK mode field 58..59: Idx 0,
 * Up 1, Down 2, Bfly 3; same lane field 53..57); the lane check below covers every lane 0 .. 31 against that rule. 0 = all good. */
int omega_blackwell_verify_codegen_fixtures_bfly_f2fp(void) {
    static const struct {
        BlackwellIROpcode op; int d, a, b; uint32_t imm; uint32_t w0, w1, w2; const char *text;
    } fx[] = {
        { BW_IR_SHFL_BFLY, 5, 0, -1, 1, 0x00057f89U, 0x0c201f00U, 0x000e0000U, "SHFL.BFLY PT, R5, R0, 0x1, 0x1f" },
        { BW_IR_SHFL_BFLY, 7, 8, -1, 1, 0x08077f89U, 0x0c201f00U, 0x000e0000U, "SHFL.BFLY PT, R7, R8, 0x1, 0x1f" },
        { BW_IR_SHFL_BFLY, 4, 9, -1, 2, 0x09047f89U, 0x0c401f00U, 0x000e0000U, "SHFL.BFLY PT, R4, R9, 0x2, 0x1f" },
        { BW_IR_SHFL_BFLY, 6, 11, -1, 2, 0x0b067f89U, 0x0c401f00U, 0x000e0000U, "SHFL.BFLY PT, R6, R11, 0x2, 0x1f" },
        { BW_IR_F2FP_BF16_PACK, 9, 3, 0, 0, 0x0309723eU, 0x00000000U, 0x000010ffU, "F2FP.BF16.F32.PACK_AB R9, R3, R0" },
        { BW_IR_F2FP_BF16_PACK, 13, 13, 10, 0, 0x0d0d723eU, 0x0000000aU, 0x000010ffU, "F2FP.BF16.F32.PACK_AB R13, R13, R10" },
    };
    uint32_t w[4];
    for (int i = 0; i < (int)(sizeof fx / sizeof fx[0]); i++) {
        BlackwellIRInsn in;
        memset(&in, 0, sizeof in);
        in.op = fx[i].op; in.dst_vreg = fx[i].d; in.src1_vreg = fx[i].a; in.src2_vreg = fx[i].b;
        in.src3_vreg = -1; in.ureg = -1; in.imm = fx[i].imm;
        if (omega_blackwell_encode_one(&in, w) != 0) return -(2 * i + 1);
        if (w[0] != fx[i].w0 || w[1] != fx[i].w1 || w[2] != fx[i].w2) return -(2 * i + 2);
    }
    for (uint32_t lane = 0; lane < 32; lane++) {
        BlackwellIRInsn in; uint32_t d[4];
        memset(&in, 0, sizeof in);
        in.op = BW_IR_SHFL_DOWN; in.dst_vreg = 9; in.src1_vreg = 2; in.src2_vreg = in.src3_vreg = in.ureg = -1; in.imm = lane;
        if (omega_blackwell_encode_one(&in, d) != 0) return -100;
        in.op = BW_IR_SHFL_BFLY;
        if (omega_blackwell_encode_one(&in, w) != 0) return -101;
        if (w[0] != d[0] || w[1] != (d[1] | 0x04000000U) || w[2] != d[2] || w[3] != d[3]) return -102;
    }
    return 0;
}

/* Training R5 part 2: f32 global atomic add. Starting map from Mesa NAK sm70_encode.rs (a08a0b9, sm >= 90 float ATOMG;
 * Mesa ranges are half-open): opcode 0x9a3, op 87..90 (Add 0, Min 2, Max 4), type 73..76 (F32 = 9, which is .FTZ.RN;
 * 12 decodes as .RN without FTZ), order 77..80 (Strong System 0xa, Strong GPU 0x7), pred-dst 81..83 = PT, eviction
 * 84..86 = 1, bit 63 = Ra.64, bit 91 = UR form. Then every word below was decoded offline with nvdisasm -b SM121
 * (CUDA 13.0) to the text shown. Where Mesa and the decoder disagree the decoder (and the chip probe) win: this word
 * sets bit 90 (w2 bit 26), which falls inside Mesa's op field, yet it decodes as .ADD with desc[UR][R.64]; without it
 * the same word decodes as [R.64+UR]. (Bit 88 decodes as .MIN, so the op field is there.)
 *   0x80000005020479a3 0x00321e000c1f5306  ATOMG.E.ADD.F32.FTZ.RN.STRONG.SYS PT, R4, desc[UR6][R2.64], R5 ;
 *   0x800000070a0979a3 0x00321e000c1f5304  ATOMG.E.ADD.F32.FTZ.RN.STRONG.SYS PT, R9, desc[UR4][R10.64], R7 ;
 *   0x8000000502ff79a3 0x00321e000c1f5306  ATOMG.E.ADD.F32.FTZ.RN.STRONG.SYS PT, RZ, desc[UR6][R2.64], R5 ;
 *   0x80000005020479a3 0x00321e000c1ef306  ATOMG.E.ADD.F32.FTZ.RN.STRONG.GPU PT, R4, desc[UR6][R2.64], R5 ;
 *   0x800000070a0979a3 0x00321e000c1ef304  ATOMG.E.ADD.F32.FTZ.RN.STRONG.GPU PT, R9, desc[UR4][R10.64], R7 ;
 *   0x8000000502ff79a3 0x00321e000c1ef306  ATOMG.E.ADD.F32.FTZ.RN.STRONG.GPU PT, RZ, desc[UR6][R2.64], R5 ;
 * Rows with d = -1 (no destination vreg) must encode RZ, not R0. Chip proof: tests/gpu_atomf32_probe_test.c. 0 = all good. */
int omega_blackwell_verify_codegen_fixtures_atomf32(void) {
    static const struct { BlackwellIROpcode op; int d, a, b, u; uint32_t w0, w1, w2; } fx[] = {
        { BW_IR_ATOMG_ADD_F32_STRONG_SYS, 4, 2, 5, 6, 0x020479a3U, 0x80000005U, 0x0c1f5306U },
        { BW_IR_ATOMG_ADD_F32_STRONG_SYS, 9, 10, 7, 4, 0x0a0979a3U, 0x80000007U, 0x0c1f5304U },
        { BW_IR_ATOMG_ADD_F32_STRONG_SYS, 255, 2, 5, 6, 0x02ff79a3U, 0x80000005U, 0x0c1f5306U },
        { BW_IR_ATOMG_ADD_F32_STRONG_SYS, -1, 2, 5, 6, 0x02ff79a3U, 0x80000005U, 0x0c1f5306U },
        { BW_IR_ATOMG_ADD_F32_STRONG_GPU, 4, 2, 5, 6, 0x020479a3U, 0x80000005U, 0x0c1ef306U },
        { BW_IR_ATOMG_ADD_F32_STRONG_GPU, 9, 10, 7, 4, 0x0a0979a3U, 0x80000007U, 0x0c1ef304U },
        { BW_IR_ATOMG_ADD_F32_STRONG_GPU, -1, 2, 5, 6, 0x02ff79a3U, 0x80000005U, 0x0c1ef306U },
    };
    uint32_t w[4];
    for (int i = 0; i < (int)(sizeof fx / sizeof fx[0]); i++) {
        BlackwellIRInsn in;
        memset(&in, 0, sizeof in);
        in.op = fx[i].op; in.dst_vreg = fx[i].d; in.src1_vreg = fx[i].a; in.src2_vreg = fx[i].b;
        in.src3_vreg = -1; in.ureg = fx[i].u;
        if (omega_blackwell_encode_one(&in, w) != 0) return -(2 * i + 1);
        if (w[0] != fx[i].w0 || w[1] != fx[i].w1 || w[2] != fx[i].w2 || w[3] != 0x00321e00U) return -(2 * i + 2);
    }
    return 0;
}
/* FB-1 cut 4: word-level fixtures for the four additive ops (checked against the
 * nvdisasm decodes recorded in docs/numeric/FB1_CUT4_ELEMENTWISE.md). 0 = all good. */
int omega_blackwell_verify_codegen_fixtures_fb1cut4(void) {
    OmegaRegAlloc ra;
    memset(&ra, 0, sizeof(ra));
    ra.vreg_to_phys[0] = 2;  /* R2 */
    ra.vreg_to_phys[1] = 4;  /* R4 */
    ra.vreg_to_phys[2] = 9;  /* R9 */
    ra.vreg_to_phys[3] = 10; /* R10 */
    ra.vreg_to_phys[4] = 8;  /* R8 */
    uint32_t w[4];

    /* MUFU.EX2 R2, R4 */
    BlackwellIRInsn ex2 = { .op = BW_IR_MUFU_EX2, .dst_vreg = 0, .src1_vreg = 1 };
    if (encode_single_insn(&ex2, &ra, w) != 0) return -1;
    if (w[0] != 0x00027308U || w[1] != 4 || w[2] != 0x00000800U) return -2;
    /* BAR.SYNC.DEFER_BLOCKING 0x0 */
    BlackwellIRInsn bar = { .op = BW_IR_BAR_SYNC };
    if (encode_single_insn(&bar, &ra, w) != 0) return -3;
    if (w[0] != 0x00007b1dU || w[1] != 0 || w[2] != 0x00010000U || w[3] != 0x000fec00U) return -4;
    /* LDS R9, [R10+URZ] */
    BlackwellIRInsn lds = { .op = BW_IR_LDS32, .dst_vreg = 2, .src1_vreg = 3 };
    if (encode_single_insn(&lds, &ra, w) != 0) return -5;
    if (w[0] != 0x0a097984U || w[1] != 0xff || w[2] != 0x08000800U) return -6;
    /* STS [R8+URZ], R2 */
    BlackwellIRInsn sts = { .op = BW_IR_STS32, .src1_vreg = 4, .src2_vreg = 0 };
    if (encode_single_insn(&sts, &ra, w) != 0) return -7;
    if (w[0] != 0x08007988U || w[1] != 2 || w[2] != 0x080008ffU) return -8;
    return 0;
}

/* Kernel capture (C6 of docs/OMEGA.md, tools/sm121dis): with OMEGA_KERNEL_DUMP_DIR set, every encoded kernel is written
 * there as <first 16 hex of its SHA-256>.bin, once per distinct body, so the disassembler can be checked against nvdisasm on
 * every kernel the library builds. Unset (the normal case) it does nothing; the freestanding build has no files. */
void omega_kernel_dump(const uint8_t *code, size_t len) {
#ifndef OMEGA_GPU_NO_POSIX
    const char *env = getenv("OMEGA_KERNEL_DUMP_DIR");
    if (!env || !env[0] || !code || !len) return;
    /* Only the checked copy (src/omega_path_check.h) is opened; a refused directory is a diagnostic, which
     * tools/sm121dis/corpus.sh fails on, never a silent skip. */
    char dir[4000];
    if (omega_path_copy(dir, sizeof dir, env) != 0) {
        BW_DIAG("omega_kernel_dump: OMEGA_KERNEL_DUMP_DIR refused (src/omega_path_check.h)\n");
        return;
    }
    uint8_t d[SHA256_DIGEST_SIZE]; sha256_hash(code, len, d);
    char path[4096];
    int n = snprintf(path, sizeof path, "%s/%02x%02x%02x%02x%02x%02x%02x%02x.bin",
                     dir, (unsigned)d[0], (unsigned)d[1], (unsigned)d[2], (unsigned)d[3],
                     (unsigned)d[4], (unsigned)d[5], (unsigned)d[6], (unsigned)d[7]);
    if (n < 0 || (size_t)n >= sizeof path) return;
    /* Private, exclusive creation: an existing body or symlink is left alone. */
    int fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (fd < 0) return;
    FILE *f = fdopen(fd, "wb");
    if (!f) { close(fd); unlink(path); BW_DIAG("omega_kernel_dump: write failed, removed %s\n", path); return; }
    /* A body cut short (a full disk) must not stay under its full-content name: it would be compared as a smaller kernel
     * and, created O_EXCL, never rewritten. tools/sm121dis/corpus.sh fails on these diagnostics. */
    int bad = fwrite(code, 1, len, f) != len;
    if (fclose(f) != 0) bad = 1;
    if (bad) { unlink(path); BW_DIAG("omega_kernel_dump: write failed, removed %s\n", path); }
#else
    (void)code; (void)len;
#endif
}

#ifdef BW_ENC_C_PRIMARY
static int bw_encode_program_bytes(const BlackwellIRProgram *prog, uint8_t *code_buf, size_t req_bytes) {
    size_t padded_insns = req_bytes / 16;
    uint8_t *p = code_buf;
    for (size_t i = 0; i < padded_insns; i++) {
        uint32_t w[4];
        if (i < prog->count) {
            if (encode_single_insn(&prog->insns[i], &prog->regalloc, w) != 0) {
                return -1;
            }
        } else {
            /* Pad with NOP */
            w[0] = 0x00007918;
            w[1] = 0x00000000;
            w[2] = 0x00000000;
            w[3] = 0x000fc000;
        }
        for (int k = 0; k < 4; k++) {
            p[4 * k] = (uint8_t)(w[k] & 0xff);
            p[4 * k + 1] = (uint8_t)((w[k] >> 8) & 0xff);
            p[4 * k + 2] = (uint8_t)((w[k] >> 16) & 0xff);
            p[4 * k + 3] = (uint8_t)((w[k] >> 24) & 0xff);
        }
        p += 16;
    }
    return 0;
}
#else
static int bw_encode_program_bytes(const BlackwellIRProgram *prog, uint8_t *code_buf, size_t req_bytes) {
    uint8_t code[BW_OM_CODE_LEN];
    size_t got = bw_om_encode(prog->insns, prog->count, &prog->regalloc, 1, code);
    int rc = (got == req_bytes && got != 0) ? 0 : -1;
#ifdef CUDAPP_MIGRATION_PENDING_ENCODER_DIFF
    /* The C oracle encodes the same program, instruction by instruction, NOP-padded the same way. */
#ifdef CUDAPP_ENCODER_DIFF_SELFTEST
    if (rc == 0) code[0] ^= 1; /* red check of the comparison itself: one flipped bit must abort */
#endif
    uint8_t ref[BW_OM_CODE_LEN];
    int crc = 0;
    for (size_t i = 0; i < req_bytes / 16 && crc == 0; i++) {
        uint32_t w[4] = { 0x00007918, 0, 0, 0x000fc000 };
        if (i < prog->count) crc = bw_c_encode_insn(&prog->insns[i], &prog->regalloc, w);
        for (int k = 0; k < 16; k++) ref[16 * i + (size_t)k] = (uint8_t)(w[k / 4] >> (8 * (k % 4)));
    }
    bw_enc_diff_note("program", prog->count, rc == 0 ? code : NULL, rc == 0 ? req_bytes : 0,
                     crc == rc && (rc != 0 || memcmp(code, ref, req_bytes) == 0));
#endif
    if (rc == 0) memcpy(code_buf, code, req_bytes);
    return rc;
}
#endif

int omega_bw_encode_program(const BlackwellIRProgram *prog, uint8_t *code_buf, size_t max_len, size_t *out_len) {
    if (!prog || !code_buf || !out_len) return -1;

    size_t padded_insns = (prog->count + 7) & ~7ULL;
    if (padded_insns < 32) padded_insns = 32;

    size_t req_bytes = padded_insns * 16;
    if (max_len < req_bytes) return -1;

    if (bw_encode_program_bytes(prog, code_buf, req_bytes) != 0) return -1;

    omega_kernel_dump(code_buf, req_bytes);
    *out_len = req_bytes;
    return 0;
}

int omega_blackwell_codegen_matmul_i32_prog(const OmegaMatMulSpec *spec, BlackwellIRProgram *prog) {
    if (!spec || !prog) return -1;
    if (spec->m == 0 || spec->k == 0 || spec->n == 0) return -1;

    /* Fail closed loudly if K exceeds bounded unroll limit */
    if (spec->k > 32) {
        BW_DIAG("ERROR: MatMul integer codegen exceeds bounded unroll limit (K=%u > 32)\n", spec->k);
        return -1;
    }

    omega_bw_ir_init(prog);

    /* 1. Allocate virtual registers */
    /* 64-bit base pointers */
    int v_ptr_a   = omega_bw_ir_alloc_vreg64(prog);
    int v_ptr_b   = omega_bw_ir_alloc_vreg64(prog);
    int v_ptr_c   = omega_bw_ir_alloc_vreg64(prog);
    int uv_desc   = omega_bw_ir_alloc_uvreg64(prog);

    /* 32-bit CTA / Thread indexing */
    int v_ctaid_x = omega_bw_ir_alloc_vreg(prog);
    int v_ctaid_y = omega_bw_ir_alloc_vreg(prog);
    int v_tid_x   = omega_bw_ir_alloc_vreg(prog);
    int v_tid_y   = omega_bw_ir_alloc_vreg(prog);

    /* 2D Coordinates & loop invariants */
    int v_col     = omega_bw_ir_alloc_vreg(prog);
    int v_row     = omega_bw_ir_alloc_vreg(prog);
    int v_row_k   = omega_bw_ir_alloc_vreg(prog);
    int v_const_1 = omega_bw_ir_alloc_vreg(prog);
    int v_acc     = omega_bw_ir_alloc_vreg(prog);

    /* Working registers for memory address and operands */
    int v_idx_a   = omega_bw_ir_alloc_vreg(prog);
    int v_off_a   = omega_bw_ir_alloc_vreg64(prog);
    int v_val_a   = omega_bw_ir_alloc_vreg(prog);

    int v_idx_b   = omega_bw_ir_alloc_vreg(prog);
    int v_off_b   = omega_bw_ir_alloc_vreg64(prog);
    int v_val_b   = omega_bw_ir_alloc_vreg(prog);

    int v_idx_c   = omega_bw_ir_alloc_vreg(prog);
    int v_off_c   = omega_bw_ir_alloc_vreg64(prog);

    if (v_off_c < 0) return -1;

    /* 2. Load 64-bit global memory descriptor into uniform register pair */
    /* LDCU.64 uv_desc, c[0x0][0x358] */
    BlackwellIRInsn insn_desc = { .op = BW_IR_LDCU64, .dst_vreg = uv_desc, .imm = 0x358, .is_uniform = true };
    omega_bw_ir_append(prog, &insn_desc);

    /* 3. Load 64-bit base pointers from Constant Bank 0 */
    /* LDC.64 v_ptr_a, c[0x0][0x380] */
    BlackwellIRInsn insn_ptra = { .op = BW_IR_LDC64, .dst_vreg = v_ptr_a, .imm = 0x380 };
    omega_bw_ir_append(prog, &insn_ptra);

    /* LDC.64 v_ptr_b, c[0x0][0x388] */
    BlackwellIRInsn insn_ptrb = { .op = BW_IR_LDC64, .dst_vreg = v_ptr_b, .imm = 0x388 };
    omega_bw_ir_append(prog, &insn_ptrb);

    /* LDC.64 v_ptr_c, c[0x0][0x390] */
    BlackwellIRInsn insn_ptrc = { .op = BW_IR_LDC64, .dst_vreg = v_ptr_c, .imm = 0x390 };
    omega_bw_ir_append(prog, &insn_ptrc);

    /* 4. Query 2D CTA and Thread coordinates */
    /* S2R v_ctaid_x, SR_CTAID.X */
    BlackwellIRInsn insn_ctax = { .op = BW_IR_S2R, .dst_vreg = v_ctaid_x, .imm = BW_SR_CTAID_X };
    omega_bw_ir_append(prog, &insn_ctax);

    /* S2R v_ctaid_y, SR_CTAID.Y */
    BlackwellIRInsn insn_ctay = { .op = BW_IR_S2R, .dst_vreg = v_ctaid_y, .imm = BW_SR_CTAID_Y };
    omega_bw_ir_append(prog, &insn_ctay);

    /* S2R v_tid_x, SR_TID.X */
    BlackwellIRInsn insn_tidx = { .op = BW_IR_S2R, .dst_vreg = v_tid_x, .imm = BW_SR_TID_X };
    omega_bw_ir_append(prog, &insn_tidx);

    /* S2R v_tid_y, SR_TID.Y */
    BlackwellIRInsn insn_tidy = { .op = BW_IR_S2R, .dst_vreg = v_tid_y, .imm = BW_SR_TID_Y };
    omega_bw_ir_append(prog, &insn_tidy);

    /* 5. Compute 2D (row, col) coordinates */
    /* Standard 16x16 tile threads: col = ctaid_x * 16 + tid_x */
    BlackwellIRInsn insn_col = { .op = BW_IR_IMAD, .dst_vreg = v_col, .src1_vreg = v_ctaid_x, .src2_vreg = -1, .imm = 16, .src3_vreg = v_tid_x };
    omega_bw_ir_append(prog, &insn_col);

    /* row = ctaid_y * 16 + tid_y */
    BlackwellIRInsn insn_row = { .op = BW_IR_IMAD, .dst_vreg = v_row, .src1_vreg = v_ctaid_y, .src2_vreg = -1, .imm = 16, .src3_vreg = v_tid_y };
    omega_bw_ir_append(prog, &insn_row);

    /* 6. Precompute row base index: v_row_k = v_row * K + RZ */
    BlackwellIRInsn insn_row_k = { .op = BW_IR_IMAD, .dst_vreg = v_row_k, .src1_vreg = v_row, .src2_vreg = -1, .imm = spec->k, .src3_vreg = -1 };
    omega_bw_ir_append(prog, &insn_row_k);

    /* 7. Initialize v_const_1 = 1 for immediate linear indexing */
    BlackwellIRInsn insn_c1 = { .op = BW_IR_MOV_IMM, .dst_vreg = v_const_1, .imm = 1 };
    omega_bw_ir_append(prog, &insn_c1);

    /* 8. Initialize accumulator to zero: MOV v_acc, RZ */
    BlackwellIRInsn insn_init_acc = { .op = BW_IR_MOV_RZ, .dst_vreg = v_acc };
    omega_bw_ir_append(prog, &insn_init_acc);

    /* 9. Synthesize inner accumulation loop across K iterations */
    for (uint32_t step = 0; step < spec->k; step++) {
        /* A[row, step]: idx_a = v_row_k + step = v_const_1 * step + v_row_k */
        BlackwellIRInsn insn_idxa = { .op = BW_IR_IMAD, .dst_vreg = v_idx_a, .src1_vreg = v_const_1, .src2_vreg = -1, .imm = step, .src3_vreg = v_row_k };
        omega_bw_ir_append(prog, &insn_idxa);

        /* off_a = v_ptr_a + idx_a * 4 */
        BlackwellIRInsn insn_offa = { .op = BW_IR_IMAD_WIDE, .dst_vreg = v_off_a, .src1_vreg = v_idx_a, .src2_vreg = -1, .imm = 4, .src3_vreg = v_ptr_a };
        omega_bw_ir_append(prog, &insn_offa);

        /* Load A[row, step]: LDG.E v_val_a, desc[uv_desc][v_off_a.64] */
        BlackwellIRInsn insn_lda = { .op = BW_IR_LDG_E, .dst_vreg = v_val_a, .src1_vreg = v_off_a, .src2_vreg = -1, .src3_vreg = -1, .ureg = uv_desc, .control = 0x001ea800 };
        omega_bw_ir_append(prog, &insn_lda);

        /* B[step, col]: idx_b = step * N + col = v_const_1 * (step * N) + v_col */
        uint32_t step_n = step * spec->n;
        BlackwellIRInsn insn_idxb = { .op = BW_IR_IMAD, .dst_vreg = v_idx_b, .src1_vreg = v_const_1, .src2_vreg = -1, .imm = step_n, .src3_vreg = v_col };
        omega_bw_ir_append(prog, &insn_idxb);

        /* off_b = v_ptr_b + idx_b * 4 */
        BlackwellIRInsn insn_offb = { .op = BW_IR_IMAD_WIDE, .dst_vreg = v_off_b, .src1_vreg = v_idx_b, .src2_vreg = -1, .imm = 4, .src3_vreg = v_ptr_b };
        omega_bw_ir_append(prog, &insn_offb);

        /* Load B[step, col]: LDG.E v_val_b, desc[uv_desc][v_off_b.64] */
        BlackwellIRInsn insn_ldb = { .op = BW_IR_LDG_E, .dst_vreg = v_val_b, .src1_vreg = v_off_b, .src2_vreg = -1, .src3_vreg = -1, .ureg = uv_desc, .control = 0x002ea800 };
        omega_bw_ir_append(prog, &insn_ldb);

        /* Multiply and accumulate: IMAD v_acc, v_val_a, v_val_b, v_acc */
        BlackwellIRInsn insn_acc = { .op = BW_IR_IMAD, .dst_vreg = v_acc, .src1_vreg = v_val_a, .src2_vreg = v_val_b, .src3_vreg = v_acc, .control = 0x004fca00 };
        omega_bw_ir_append(prog, &insn_acc);
    }

    /* 10. Compute output index: idx_c = row * N + col */
    BlackwellIRInsn insn_idxc = { .op = BW_IR_IMAD, .dst_vreg = v_idx_c, .src1_vreg = v_row, .src2_vreg = -1, .imm = spec->n, .src3_vreg = v_col };
    omega_bw_ir_append(prog, &insn_idxc);

    /* off_c = v_ptr_c + idx_c * 4 */
    BlackwellIRInsn insn_offc = { .op = BW_IR_IMAD_WIDE, .dst_vreg = v_off_c, .src1_vreg = v_idx_c, .src2_vreg = -1, .imm = 4, .src3_vreg = v_ptr_c };
    omega_bw_ir_append(prog, &insn_offc);

    /* Store C[row, col]: STG.E desc[uv_desc][v_off_c.64], v_acc */
    BlackwellIRInsn insn_stc = { .op = BW_IR_STG_E, .src1_vreg = v_off_c, .src2_vreg = v_acc, .src3_vreg = -1, .ureg = uv_desc };
    omega_bw_ir_append(prog, &insn_stc);

    /* 11. Kernel termination */
    BlackwellIRInsn insn_exit = { .op = BW_IR_EXIT, .predicate_p0 = false };
    omega_bw_ir_append(prog, &insn_exit);

    BlackwellIRInsn insn_bra = { .op = BW_IR_BRA };
    omega_bw_ir_append(prog, &insn_bra);

    /* 12. Solve bounded deterministic register allocation */
    if (omega_bw_regalloc_solve(prog) != 0) {
        return -1;
    }
    return 0;
}

/* ---- native v1 P07 cut A.2: allocation-free kernel encoding ---------------------------------
 * The one place a solved IR program becomes a kernel. Hosted and freestanding builds both encode
 * through it, so the two produce the same bytes for the same program (make test-codegen-freestanding
 * compares them). */
size_t omega_bw_program_code_bytes(const BlackwellIRProgram *prog) {
    if (!prog) return 0;
    size_t padded_insns = (prog->count + 7) & ~(size_t)7;
    if (padded_insns < 32) padded_insns = 32;
    return padded_insns * 16;
}

int omega_blackwell_kernel_encode_into(const BlackwellIRProgram *prog, uint8_t *code_buf, size_t code_cap,
                                       OmegaBlackwellKernel *kernel) {
    if (!kernel) return -1;
    memset(kernel, 0, sizeof *kernel);
    if (!prog || !code_buf) return -1;
    size_t need = omega_bw_program_code_bytes(prog);
    if (code_cap < need) return OMEGA_BW_CODE_BUFFER_TOO_SMALL; /* refused before any byte is written */
    size_t emitted_size = 0;
    if (omega_bw_encode_program(prog, code_buf, code_cap, &emitted_size) != 0) return -1;
    kernel->code = code_buf;
    kernel->code_size = emitted_size;
    kernel->insn_count = emitted_size / 16;
    kernel->gpr_count = prog->regalloc.peak_gpr_usage;
    kernel->uniform_gpr_count = prog->regalloc.peak_ugpr_usage;
    sha256_hash(kernel->code, kernel->code_size, kernel->code_digest);
    return 0;
}

#ifndef OMEGA_GPU_NO_POSIX
/* Hosted only: the allocating generators keep their names, caps and behavior. Each builds the program,
 * mallocs max_bytes (the cap each generator always had) and encodes through omega_blackwell_kernel_encode_into;
 * omega_blackwell_kernel_free releases the buffer. */
static int bw_kernel_alloc_encode(const BlackwellIRProgram *prog, size_t max_bytes, OmegaBlackwellKernel *kernel) {
    uint8_t *buf = (uint8_t *)malloc(max_bytes);
    if (!buf) { kernel->code = NULL; return -1; }
    if (omega_blackwell_kernel_encode_into(prog, buf, max_bytes, kernel) != 0) {
        free(buf);
        kernel->code = NULL;
        return -1;
    }
    return 0;
}

int omega_blackwell_codegen_matmul_i32(const OmegaMatMulSpec *spec, OmegaBlackwellKernel *kernel) {
    if (!spec || !kernel) return -1;
    BlackwellIRProgram prog;
    if (omega_blackwell_codegen_matmul_i32_prog(spec, &prog) != 0) return -1;
    /* 13. the code buffer is exactly the padded program (the i32 generator never had a fixed cap) */
    return bw_kernel_alloc_encode(&prog, omega_bw_program_code_bytes(&prog), kernel);
}
#endif

static int bw_om_check_reg_local(int64_t r64, uint8_t sub, uint64_t limit, const uint64_t *widths) {
    if (r64 == -1) return sub == 0 ? 0 : -1;
    if (r64 < 0 || (uint64_t)r64 >= limit) return -1;
    if (sub >= widths[(uint64_t)r64]) return -1;
    return 0;
}

static int bw_ir_unpack_raw(const uint64_t ins[8192], const uint64_t meta[512], BlackwellIRProgram *prog) {
    if (!prog) return -1;
    omega_bw_ir_init(prog);
    if (!ins || !meta || meta[5] != 0) return -1;
    const uint64_t n = meta[0], nv = meta[1], nu = meta[2];
    if (n == 0 || n > BW_MAX_IR_INSNS || nv > BW_MAX_VREGS || nu > BW_MAX_UVREGS) return -1;
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
        const uint64_t *wtab = is_u ? &meta[352] : &meta[64];
        uint64_t lim = is_u ? nu : nv;
        if (bw_om_check_reg_local((int64_t)r[1], dsub, lim, wtab) != 0) goto fail;
        if (bw_om_check_reg_local((int64_t)r[2], s1sub, lim, wtab) != 0) goto fail;
        if (bw_om_check_reg_local((int64_t)r[3], s2sub, lim, wtab) != 0) goto fail;
        if (bw_om_check_reg_local((int64_t)r[4], s3sub, lim, wtab) != 0) goto fail;
        if (bw_om_check_reg_local((int64_t)r[5], 0, nu, &meta[352]) != 0) goto fail;

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
    return 0;
fail:
    omega_bw_ir_init(prog);
    return -1;
}

static void bw_keep_alive(BlackwellIRProgram *prog, int from_idx, int to_idx, int last_idx) {
    /* every vreg first defined in [from_idx, to_idx) stays live until last_idx */
    for (int v = 0; v < prog->regalloc.num_vregs; v++) {
        OmegaLiveInterval *iv = &prog->regalloc.intervals[v];
        if (iv->first_def >= from_idx && iv->first_def < to_idx && iv->last_use < last_idx)
            iv->last_use = last_idx;
    }
}

static void bw_live_until(BlackwellIRProgram *prog, int vreg, int last_idx) {
    if (vreg >= 0 && vreg < prog->regalloc.num_vregs && prog->regalloc.intervals[vreg].last_use < last_idx)
        prog->regalloc.intervals[vreg].last_use = last_idx;
}

int omega_blackwell_codegen_matmul_tensor_prog(const OmegaMatMulSpec *spec, BlackwellIRProgram *prog) {
    if (!spec || !prog) return -1;
    uint64_t sp[12] = { spec->m, spec->k, spec->n, (uint64_t)spec->precision, 0 };
    uint64_t ins[8192], meta[512];
    memset(ins, 0, sizeof(ins));
    memset(meta, 0, sizeof(meta));
    uint64_t rc = 1;
    if (omega2_cg_matmul_tensor(&rc, sp, 12, ins, 8192, meta, 512) != OMEGA_OK || rc != 0) {
        omega_bw_ir_init(prog);
        return -1;
    }
    if (bw_ir_unpack_raw(ins, meta, prog) != 0) return -1;
    if (omega_bw_regalloc_solve(prog) != 0) {
        omega_bw_ir_init(prog);
        return -1;
    }
    return 0;
}

#ifndef OMEGA_GPU_NO_POSIX
int omega_blackwell_codegen_matmul_tensor(const OmegaMatMulSpec *spec, OmegaBlackwellKernel *kernel) {
    if (!spec || !kernel) return -1;
    BlackwellIRProgram prog;
    if (omega_blackwell_codegen_matmul_tensor_prog(spec, &prog) != 0) {
        return -1;
    }

    return bw_kernel_alloc_encode(&prog, OMEGA_BW_CODE_CAP_SMALL, kernel);
}
#endif

int omega_blackwell_codegen_matmul_tensor_loop_prog(const OmegaMatMulSpec *spec, uint32_t grid_x,
                                                    int mutant, BlackwellIRProgram *prog) {
    if (!spec || !prog) return -1;
    uint64_t sp[12] = { spec->m, spec->k, spec->n, (uint64_t)spec->precision, grid_x, (uint64_t)(mutant != 0), 0 };
    uint64_t ins[8192], meta[512];
    memset(ins, 0, sizeof(ins));
    memset(meta, 0, sizeof(meta));
    uint64_t rc = 1;
    if (omega2_cg_matmul_tensor_loop(&rc, sp, 12, ins, 8192, meta, 512) != OMEGA_OK || rc != 0) {
        omega_bw_ir_init(prog);
        return -1;
    }
    if (bw_ir_unpack_raw(ins, meta, prog) != 0) return -1;
    const int L_col = (int)meta[480], L_k = (int)meta[481], L_k_end = (int)meta[482], L_col_end = (int)meta[483];
    const int v_rd = (int)meta[484];
    bw_keep_alive(prog, 0, L_col, L_col_end);
    bw_keep_alive(prog, L_col, L_k, L_k_end);
    bw_keep_alive(prog, L_k, L_k_end, L_k_end);
    bw_live_until(prog, v_rd, L_col_end);
    if (omega_bw_regalloc_solve(prog) != 0) {
        omega_bw_ir_init(prog);
        return -1;
    }
    return 0;
}

#ifndef OMEGA_GPU_NO_POSIX
int omega_blackwell_codegen_matmul_tensor_loop(const OmegaMatMulSpec *spec, uint32_t grid_x,
                                               int mutant, OmegaBlackwellKernel *kernel) {
    if (!spec || !kernel) return -1;
    BlackwellIRProgram prog;
    if (omega_blackwell_codegen_matmul_tensor_loop_prog(spec, grid_x, mutant, &prog) != 0) return -1;
    return bw_kernel_alloc_encode(&prog, OMEGA_BW_CODE_CAP_SMALL, kernel);
}
#endif

int omega_blackwell_codegen_matmul_frag_prog(const OmegaMatMulSpec *spec, uint32_t grid_x, uint32_t unroll,
                                             int mutant, BlackwellIRProgram *prog) {
    if (!spec || !prog) return -1;
    uint64_t sp[12] = { spec->m, spec->k, spec->n, (uint64_t)spec->precision, grid_x, unroll, (uint64_t)(mutant != 0), 0 };
    uint64_t ins[8192], meta[512];
    memset(ins, 0, sizeof(ins));
    memset(meta, 0, sizeof(meta));
    uint64_t rc = 1;
    if (omega2_cg_matmul_frag(&rc, sp, 12, ins, 8192, meta, 512) != OMEGA_OK || rc != 0) {
        omega_bw_ir_init(prog);
        return -1;
    }
    if (bw_ir_unpack_raw(ins, meta, prog) != 0) return -1;
    const int L_k = (int)meta[481], L_k_end = (int)meta[482], L_col_end = (int)meta[483];
    for (int i = 484; i <= 490; i++) bw_live_until(prog, (int)meta[i], L_col_end);
    for (int i = 491; i <= 493; i++) bw_live_until(prog, (int)meta[i], L_k_end);
    bw_keep_alive(prog, L_k, L_k_end, L_k_end);
    if (omega_bw_regalloc_solve(prog) != 0) {
        omega_bw_ir_init(prog);
        return -1;
    }
    return 0;
}

#ifndef OMEGA_GPU_NO_POSIX
int omega_blackwell_codegen_matmul_frag(const OmegaMatMulSpec *spec, uint32_t grid_x, uint32_t unroll,
                                        int mutant, OmegaBlackwellKernel *kernel) {
    if (!spec || !kernel) return -1;
    BlackwellIRProgram prog;
    if (omega_blackwell_codegen_matmul_frag_prog(spec, grid_x, unroll, mutant, &prog) != 0) return -1;
    return bw_kernel_alloc_encode(&prog, OMEGA_BW_CODE_CAP_SMALL, kernel);
}
#endif

int omega_blackwell_codegen_matmul_frag_block_prog(const OmegaMatMulSpec *spec, uint32_t grid_x, uint32_t unroll,
                                                   uint32_t rt, uint32_t ct, int mutant, BlackwellIRProgram *prog) {
    if (!spec || !prog) return -1;
    uint64_t sp[12] = { spec->m, spec->k, spec->n, (uint64_t)spec->precision, grid_x, unroll, rt, ct, (uint64_t)(mutant != 0), 0 };
    uint64_t ins[8192], meta[512];
    memset(ins, 0, sizeof(ins));
    memset(meta, 0, sizeof(meta));
    uint64_t rc = 1;
    if (omega2_cg_matmul_frag_block(&rc, sp, 12, ins, 8192, meta, 512) != OMEGA_OK || rc != 0) {
        omega_bw_ir_init(prog);
        return -1;
    }
    if (bw_ir_unpack_raw(ins, meta, prog) != 0) return -1;
    const int L_k = (int)meta[481], L_k_end = (int)meta[482], L_col_end = (int)meta[483];
    for (int i = 484; i <= 489; i++) bw_live_until(prog, (int)meta[i], L_col_end);
    for (uint32_t t = 0; t < rt * ct; t++) bw_live_until(prog, (int)meta[408 + t], L_col_end);
    for (int i = 490; i <= 492; i++) bw_live_until(prog, (int)meta[i], L_k_end);
    bw_keep_alive(prog, L_k, L_k_end, L_k_end);
    if (omega_bw_regalloc_solve(prog) != 0) {
        omega_bw_ir_init(prog);
        return -1;
    }
    return 0;
}

#ifndef OMEGA_GPU_NO_POSIX
int omega_blackwell_codegen_matmul_frag_block(const OmegaMatMulSpec *spec, uint32_t grid_x, uint32_t unroll,
                                              uint32_t rt, uint32_t ct, int mutant, OmegaBlackwellKernel *kernel) {
    if (!spec || !kernel) return -1;
    BlackwellIRProgram prog;
    if (omega_blackwell_codegen_matmul_frag_block_prog(spec, grid_x, unroll, rt, ct, mutant, &prog) != 0) return -1;
    return bw_kernel_alloc_encode(&prog, OMEGA_BW_CODE_CAP_MAX, kernel);
}
#endif

void omega_matmul_frag_block_shape(uint32_t mt, uint32_t nt, uint32_t *rt, uint32_t *ct) {
    uint64_t res[4] = { 1, 1, 1, 1 }, rc = 1;
    omega2_cg_matmul_frag_shape(&rc, mt, nt, 16, res, 4);
    *rt = (uint32_t)res[0];
    *ct = (uint32_t)res[1];
}

uint32_t omega_matmul_frag_block_unroll(uint32_t kp, uint32_t rt, uint32_t ct) {
    const uint32_t ks = kp / 16u;
    return (ks % 2u == 0 && 2u * (rt + ct) <= 8u) ? 2u : 1u;
}

uint32_t omega_matmul_frag_unroll(uint32_t kp) {
    uint64_t res[4] = { 1, 1, 1, 1 }, rc = 1;
    omega2_cg_matmul_frag_shape(&rc, 1, 1, kp, res, 4);
    return (uint32_t)res[3];
}

/* A block (mt, ks) holds rows 16mt..16mt+15 and columns 16ks..16ks+15 as 256 bf16 at element
 * (mt*KS + ks)*256; inside the block, element (rr, cc) sits at lane*8 + e with lane = (rr%8)*4 + (cc%8)/2
 * and e = (cc/8)*4 + (rr/8)*2 + cc%2 (the HMMA.16816 A fragment order, header comment). The 256-entry
 * table makes the pack a tile loop with no per-element division (2026-10-12: the per-element form with
 * six divisions and a conversion call per element was ~2.5 ms per MB of activations at m = 128). */
static uint16_t g_frag_a_tab[256];
static void frag_a_tab_init(void) {
    if (g_frag_a_tab[255]) return;
    for (uint32_t rr = 0; rr < 16; rr++)
        for (uint32_t cc = 0; cc < 16; cc++)
            g_frag_a_tab[rr * 16 + cc] = (uint16_t)((((rr & 7u) * 4u + ((cc & 7u) >> 1)) * 8u) + (cc >> 3) * 4u + (rr >> 3) * 2u + (cc & 1u));
}
/* bit for bit what the compiler's (__bf16)f cast gives (gpu_matmul_api_test checks it against
 * omega_fp32_to_bf16 on ties, denormals, inf and NaN payloads): round to nearest even, a NaN keeps
 * its top payload bits and is made quiet. gcc 13 on aarch64 emits the cast as a call to the
 * soft-float routine __truncsfbf2 per element, which was most of the packing cost. */
static inline uint16_t frag_f32_to_bf16(float f) {
    uint32_t u;
    memcpy(&u, &f, 4);
    if ((u & 0x7f800000u) == 0x7f800000u) return (uint16_t)((u >> 16) | ((u & 0x007fffffu) ? 0x0040u : 0u));
    return (uint16_t)((u + 0x7fffu + ((u >> 16) & 1u)) >> 16);
}
#define FRAG_PACK_A_BODY(LOAD)                                                                          \
    do {                                                                                                \
        const uint32_t KS = kp / 16u;                                                                   \
        frag_a_tab_init();                                                                              \
        memset(dst, 0, (size_t)mp * kp * sizeof *dst);                                                  \
        for (uint32_t mt = 0; mt < (m + 15u) / 16u; mt++) {                                             \
            const uint32_t r1 = m - mt * 16u < 16u ? m - mt * 16u : 16u;                                \
            for (uint32_t ks = 0; ks < (k + 15u) / 16u; ks++) {                                         \
                const uint32_t c1 = k - ks * 16u < 16u ? k - ks * 16u : 16u;                            \
                uint16_t *blk = dst + ((size_t)mt * KS + ks) * 256u;                                    \
                for (uint32_t rr = 0; rr < r1; rr++) {                                                  \
                    const uint16_t *tab = g_frag_a_tab + rr * 16u;                                      \
                    const size_t src = (size_t)(mt * 16u + rr) * k + ks * 16u;                          \
                    for (uint32_t cc = 0; cc < c1; cc++) blk[tab[cc]] = LOAD(a[src + cc]);              \
                }                                                                                       \
            }                                                                                           \
        }                                                                                               \
    } while (0)
#define FRAG_ID(x) (x)
void omega_matmul_frag_pack_a(const uint16_t *a, uint32_t m, uint32_t k, uint32_t mp, uint32_t kp, uint16_t *dst) {
    FRAG_PACK_A_BODY(FRAG_ID);
}
void omega_matmul_frag_pack_a_f32(const float *a, uint32_t m, uint32_t k, uint32_t mp, uint32_t kp, uint16_t *dst) {
    FRAG_PACK_A_BODY(frag_f32_to_bf16);
}

/* Row 0 only, every column of every K block (zeros past k): for a one-row call whose buffer already
 * holds zeros in rows 1..15 of every block from an earlier full pack of the same width. */
#define FRAG_PACK_A_ROW0_BODY(LOAD)                                                                     \
    do {                                                                                                \
        const uint32_t KS = kp / 16u;                                                                   \
        frag_a_tab_init();                                                                              \
        const uint16_t *tab = g_frag_a_tab;                                                             \
        for (uint32_t ks = 0; ks < KS; ks++) {                                                          \
            uint16_t *blk = dst + (size_t)ks * 256u;                                                    \
            const uint32_t c0 = ks * 16u, c1 = k - c0 < 16u ? k - c0 : 16u;                             \
            for (uint32_t cc = 0; cc < c1; cc++) blk[tab[cc]] = LOAD(a[c0 + cc]);                       \
            for (uint32_t cc = c1; cc < 16u; cc++) blk[tab[cc]] = 0;                                    \
        }                                                                                               \
    } while (0)
void omega_matmul_frag_pack_a_row0(const uint16_t *a, uint32_t k, uint32_t kp, uint16_t *dst) {
    FRAG_PACK_A_ROW0_BODY(FRAG_ID);
}
size_t omega_matmul_result_sentinels(float *cd, uint32_t m, uint32_t n, uint32_t np, float poison, int set) {
    /* one word per 16 x 8 fragment tile that holds a real output word: the tile's last real row and column */
    size_t count = 0;
    if (m == 0 || n == 0) return 0;
    const uint32_t mt = (m + 15u) / 16u, nt = (n + 7u) / 8u;
    for (uint32_t ti = 0; ti < mt; ti++) {
        uint32_t r = ti * 16u + 15u; if (r >= m) r = m - 1u;
        float *row = cd + (size_t)r * np;
        for (uint32_t tj = 0; tj < nt; tj++) {
            uint32_t c = tj * 8u + 7u; if (c >= n) c = n - 1u;
            if (set) { row[c] = poison; count++; }
            else if (row[c] == poison) count++;
        }
    }
    return count;
}

void omega_matmul_frag_pack_a_row0_f32(const float *a, uint32_t k, uint32_t kp, uint16_t *dst) {
    FRAG_PACK_A_ROW0_BODY(frag_f32_to_bf16);
}

void omega_matmul_frag_pack_b(const uint16_t *b, uint32_t k, uint32_t n, uint32_t kp,
                              uint32_t nt0, uint32_t nt1, uint16_t *dst) {
    const uint32_t KS = kp / 16u;
    memset(dst, 0, (size_t)(nt1 - nt0) * KS * 128u * sizeof *dst);
    for (uint32_t row = 0; row < k; row++) {
        const uint32_t ks = row / 16u, rr = row % 16u, khi = rr / 8u, tig = (rr % 8u) / 2u, lo = rr % 2u;
        const uint16_t *src = &b[(size_t)row * n];
        for (uint32_t nt = nt0; nt < nt1; nt++) {
            const uint32_t c0 = nt * 8u;
            for (uint32_t group = 0; group < 8u && c0 + group < n; group++) {
                const size_t lane = group * 4u + tig;
                dst[(((size_t)(nt - nt0) * KS + ks) * 32u + lane) * 4u + khi * 2u + lo] = src[c0 + group];
            }
        }
    }
}

int omega_blackwell_verify_codegen_fixtures(void) {
    OmegaRegAlloc ra;
    memset(&ra, 0, sizeof(ra));
    ra.vreg_to_phys[0] = 2;
    ra.vreg_to_phys[1] = 4;
    ra.vreg_to_phys[2] = 6;
    ra.vreg_to_phys[3] = 7;
    ra.uvreg_to_phys[0] = 4;

    uint32_t w[4];

    /* 1. MOV R7, RZ */
    BlackwellIRInsn insn_mov_rz = { .op = BW_IR_MOV_RZ, .dst_vreg = 3 };
    if (encode_single_insn(&insn_mov_rz, &ra, w) != 0) return -1;
    if (w[0] != (0x7202 | (7 << 16)) || w[1] != 0xff || w[2] != 0x00000f00) return -2;

    /* 2. MOV R2, 1 */
    BlackwellIRInsn insn_mov_imm = { .op = BW_IR_MOV_IMM, .dst_vreg = 0, .imm = 1 };
    if (encode_single_insn(&insn_mov_imm, &ra, w) != 0) return -3;
    if (w[0] != (0x7802 | (2 << 16)) || w[1] != 1 || w[2] != 0x00000f00) return -4;

    /* 3. Register-Register IMAD: IMAD R7, R2, R6, R7 */
    BlackwellIRInsn insn_imad_rr = { .op = BW_IR_IMAD, .dst_vreg = 3, .src1_vreg = 0, .src2_vreg = 2, .src3_vreg = 3 };
    if (encode_single_insn(&insn_imad_rr, &ra, w) != 0) return -5;
    if (w[0] != (0x7224 | (7 << 16) | (2 << 24)) || w[1] != 6 || w[2] != (0x078e0200 | 7)) return -6;

    /* 4. Immediate IMAD: IMAD R6, R2, 16, RZ */
    BlackwellIRInsn insn_imad_imm = { .op = BW_IR_IMAD, .dst_vreg = 2, .src1_vreg = 0, .src2_vreg = -1, .imm = 16, .src3_vreg = -1 };
    if (encode_single_insn(&insn_imad_imm, &ra, w) != 0) return -7;
    if (w[0] != (0x7824 | (6 << 16) | (2 << 24)) || w[1] != 16 || w[2] != 0x078e02ff) return -8;

    /* 5. IMAD.WIDE: IMAD.WIDE R4, R2, 4, R4 */
    BlackwellIRInsn insn_imad_wide = { .op = BW_IR_IMAD_WIDE, .dst_vreg = 1, .src1_vreg = 0, .imm = 4, .src3_vreg = 1 };
    if (encode_single_insn(&insn_imad_wide, &ra, w) != 0) return -9;
    if (w[0] != (0x7825 | (4 << 16) | (2 << 24)) || w[1] != 4 || w[2] != (0x078e0000 | 4)) return -10;

    /* 6. LDC.64 R4, c[0x0][0x380] */
    BlackwellIRInsn insn_ldc64 = { .op = BW_IR_LDC64, .dst_vreg = 1, .imm = 0x380 };
    if (encode_single_insn(&insn_ldc64, &ra, w) != 0) return -11;
    if (w[0] != (0xff007b82 | (4 << 16)) || w[1] != ((0x380 << 6) & 0x00ffff00) || w[2] != 0x00000a00) return -12;

    /* 7. LDCU.64 UR4, c[0x0][0x358] */
    BlackwellIRInsn insn_ldcu64 = { .op = BW_IR_LDCU64, .dst_vreg = 0, .imm = 0x358, .is_uniform = true };
    if (encode_single_insn(&insn_ldcu64, &ra, w) != 0) return -13;
    if (w[0] != (0xff0077ac | (4 << 16)) || w[1] != ((0x358 << 5) & 0x00ffff00) || w[2] != 0x08000a00) return -14;

    /* 8. LDG.E R2, desc[UR4][R4.64] */
    BlackwellIRInsn insn_ldg = { .op = BW_IR_LDG_E, .dst_vreg = 0, .src1_vreg = 1, .ureg = 0 };
    if (encode_single_insn(&insn_ldg, &ra, w) != 0) return -15;
    if (w[0] != (0x7981 | (2 << 16) | (4 << 24)) || w[1] != 4 || w[2] != 0x0c1e1900) return -16;

    /* 9. STG.E desc[UR4][R4.64], R7 */
    BlackwellIRInsn insn_stg = { .op = BW_IR_STG_E, .src1_vreg = 1, .src2_vreg = 3, .ureg = 0 };
    if (encode_single_insn(&insn_stg, &ra, w) != 0) return -17;
    if (w[0] != (0x7986 | (4 << 24)) || w[1] != 7 || w[2] != (0x0c101900 | 4)) return -18;

    /* 10. S2R R2, SR_CTAID.X */
    BlackwellIRInsn insn_s2r = { .op = BW_IR_S2R, .dst_vreg = 0, .imm = BW_SR_CTAID_X };
    if (encode_single_insn(&insn_s2r, &ra, w) != 0) return -19;
    if (w[0] != (0x7919 | (2 << 16)) || w[2] != (BW_SR_CTAID_X << 8)) return -20;

    /* 11. HMMA.16816.F32 R4, R4, R2, RZ */
    BlackwellIRInsn insn_hmma_f16 = { .op = BW_IR_HMMA_F16, .dst_vreg = 1, .src1_vreg = 1, .src2_vreg = 0, .src3_vreg = -1 };
    if (encode_single_insn(&insn_hmma_f16, &ra, w) != 0) return -21;
    if (w[0] != 0x0404723c || w[1] != 0x00000002 || w[2] != 0x000018ff || w[3] != 0x000fe200) return -22;

    /* 12. HMMA.16816.F32.BF16 R4, R4, R2, RZ */
    BlackwellIRInsn insn_hmma_bf16 = { .op = BW_IR_HMMA_BF16, .dst_vreg = 1, .src1_vreg = 1, .src2_vreg = 0, .src3_vreg = -1 };
    uint32_t w_bf16[4];
    if (encode_single_insn(&insn_hmma_bf16, &ra, w_bf16) != 0) return -23;
    if (w_bf16[0] != 0x0404723c || w_bf16[1] != 0x00000002 || w_bf16[2] != 0x000418ff || w_bf16[3] != 0x000fe200) return -24;

    /* 13. Differential Invariant: w[2] bit 18 toggles strictly between FP16 and BF16 */
    if ((w[2] ^ w_bf16[2]) != 0x00040000) return -25;
    if (w[0] != w_bf16[0] || w[1] != w_bf16[1] || w[3] != w_bf16[3]) return -26;

    /* 14. SHF.R.U32.HI R4, RZ, 2, R2 */
    BlackwellIRInsn insn_shf = { .op = BW_IR_SHF_R, .dst_vreg = 1, .src1_vreg = 0, .imm = 2 };
    if (encode_single_insn(&insn_shf, &ra, w) != 0) return -27;
    if (w[0] != 0xff047819 || w[1] != 2 || w[2] != 0x00011602 || w[3] != 0x001fca00) return -28;

    /* 15. LOP3.LUT R4, R2, 3, RZ, 0xc0, !PT */
    BlackwellIRInsn insn_lop3 = { .op = BW_IR_LOP3_AND, .dst_vreg = 1, .src1_vreg = 0, .imm = 3 };
    if (encode_single_insn(&insn_lop3, &ra, w) != 0) return -29;
    if (w[0] != 0x02047812 || w[1] != 3 || w[2] != 0x078ec0ff || w[3] != 0x001fca00) return -30;

    /* 16. LDG.E.U16 R2, desc[UR4][R4.64] */
    BlackwellIRInsn insn_ldg16 = { .op = BW_IR_LDG_E_U16, .dst_vreg = 0, .src1_vreg = 1, .ureg = 0 };
    if (encode_single_insn(&insn_ldg16, &ra, w) != 0) return -31;
    if (w[0] != 0x04027981 || w[1] != 4 || w[2] != 0x0c1e1500 || w[3] != 0x000f2200) return -32;

    /* A zero-delta branch stays the self-branch the matmul kernels already emit. */
    BlackwellIRInsn insn_bra0 = { .op = BW_IR_BRA };
    if (encode_single_insn(&insn_bra0, &ra, w) != 0) return -33;
    if (w[0] != 0x00fc7947 || w[1] != 0xfffffffc || w[2] != 0x0383ffff || w[3] != 0x000fc000) return -34;

    BlackwellIRInsn insn_ge = { .op = BW_IR_ISETP_GE_U32, .src1_vreg = 1, .src2_vreg = 2 };
    if (encode_single_insn(&insn_ge, &ra, w) != 0) return -35;
    if (w[0] != (0x720c | (4 << 24)) || w[1] != 6 || w[2] != 0x03f06070) return -36;

    BlackwellIRInsn insn_xor = { .op = BW_IR_LOP3_XOR, .dst_vreg = 1, .src1_vreg = 0, .src2_vreg = 2 };
    if (encode_single_insn(&insn_xor, &ra, w) != 0) return -37;
    if (w[0] != (0x7212 | (4 << 16) | (2 << 24)) || w[1] != 6 || w[2] != 0x078e3cff) return -38;

    BlackwellIRInsn insn_ldg_ss = { .op = BW_IR_LDG_STRONG_SYS, .dst_vreg = 0, .src1_vreg = 1, .ureg = 0 };
    if (encode_single_insn(&insn_ldg_ss, &ra, w) != 0) return -39;
    if (w[0] != (0x7981 | (2 << 16) | (4 << 24)) || w[1] != 4 || w[2] != 0x0c1f5900) return -40;
    /* 17. FADD R7, R2, R4 */
    BlackwellIRInsn insn_fadd = { .op = BW_IR_FADD, .dst_vreg = 3, .src1_vreg = 0, .src2_vreg = 1 };
    if (encode_single_insn(&insn_fadd, &ra, w) != 0) return -133;
    if (w[0] != 0x02077221 || w[1] != 4 || w[2] != 0 || w[3] != 0x004fc400) return -134;

    /* 18. FSUB R7, R2, R4 (negated src2) */
    BlackwellIRInsn insn_fsub = { .op = BW_IR_FSUB, .dst_vreg = 3, .src1_vreg = 0, .src2_vreg = 1 };
    if (encode_single_insn(&insn_fsub, &ra, w) != 0) return -135;
    if (w[0] != 0x02077221 || w[1] != 0x80000004 || w[2] != 0 || w[3] != 0x004fc400) return -136;

    /* 19. FMUL R7, R2, R4 */
    BlackwellIRInsn insn_fmul = { .op = BW_IR_FMUL, .dst_vreg = 3, .src1_vreg = 0, .src2_vreg = 1 };
    if (encode_single_insn(&insn_fmul, &ra, w) != 0) return -137;
    if (w[0] != 0x02077220 || w[1] != 4 || w[2] != 0x00400000 || w[3] != 0x004fc400) return -138;

    /* 20. FFMA R7, R2, R4, R6 */
    BlackwellIRInsn insn_ffma = { .op = BW_IR_FFMA, .dst_vreg = 3, .src1_vreg = 0, .src2_vreg = 1, .src3_vreg = 2 };
    if (encode_single_insn(&insn_ffma, &ra, w) != 0) return -139;
    if (w[0] != 0x02077223 || w[1] != 4 || w[2] != 6 || w[3] != 0x004fc400) return -140;

    /* 21. FMNMX_MIN R7, R2, R4 */
    BlackwellIRInsn insn_min = { .op = BW_IR_FMNMX_MIN, .dst_vreg = 3, .src1_vreg = 0, .src2_vreg = 1 };
    if (encode_single_insn(&insn_min, &ra, w) != 0) return -141;
    if (w[0] != 0x02077209 || w[1] != 4 || w[2] != 0x03800000 || w[3] != 0x004fc400) return -142;

    /* 22. FMNMX_MAX R7, R2, R4 */
    BlackwellIRInsn insn_max = { .op = BW_IR_FMNMX_MAX, .dst_vreg = 3, .src1_vreg = 0, .src2_vreg = 1 };
    if (encode_single_insn(&insn_max, &ra, w) != 0) return -143;
    if (w[0] != 0x02077209 || w[1] != 4 || w[2] != 0x07800000 || w[3] != 0x004fc400) return -144;

    /* 23. I2FP R7, R2 */
    BlackwellIRInsn insn_i2f = { .op = BW_IR_I2FP, .dst_vreg = 3, .src1_vreg = 0 };
    if (encode_single_insn(&insn_i2f, &ra, w) != 0) return -145;
    if (w[0] != 0x00077245 || w[1] != 2 || w[2] != 0x00201400 || w[3] != 0x004fe200) return -146;

    /* 24. F2I R7, R2 */
    BlackwellIRInsn insn_f2i = { .op = BW_IR_F2I, .dst_vreg = 3, .src1_vreg = 0 };
    if (encode_single_insn(&insn_f2i, &ra, w) != 0) return -147;
    if (w[0] != 0x00077305 || w[1] != 2 || w[2] != 0x0020f100 || w[3] != 0x004e2200) return -148;

    /* 25. MUFU_RCP R7, R2 */
    BlackwellIRInsn insn_mufu_rcp = { .op = BW_IR_MUFU_RCP, .dst_vreg = 3, .src1_vreg = 0 };
    if (encode_single_insn(&insn_mufu_rcp, &ra, w) != 0) return -149;
    if (w[0] != 0x00077308 || w[1] != 2 || w[2] != 0x00001000 || w[3] != 0x000e2400) return -150;

    /* 26. MUFU_RSQ R7, R2 */
    BlackwellIRInsn insn_mufu_rsq = { .op = BW_IR_MUFU_RSQ, .dst_vreg = 3, .src1_vreg = 0 };
    if (encode_single_insn(&insn_mufu_rsq, &ra, w) != 0) return -151;
    if (w[0] != 0x00077308 || w[1] != 2 || w[2] != 0x00001400 || w[3] != 0x000e2400) return -152;

    /* 27. SHFL_DOWN R7, R2, 16 */
    BlackwellIRInsn insn_shfl = { .op = BW_IR_SHFL_DOWN, .dst_vreg = 3, .src1_vreg = 0, .imm = 16 };
    if (encode_single_insn(&insn_shfl, &ra, w) != 0) return -153;
    if (w[0] != 0x02077f89 || w[1] != 0x0a001f00 || w[2] != 0x000e0000 || w[3] != 0x000e2400) return -154;

    /* 28. LDS R7, [R2] */
    BlackwellIRInsn insn_lds = { .op = BW_IR_LDS, .dst_vreg = 3, .src1_vreg = 0, .imm = 0 };
    if (encode_single_insn(&insn_lds, &ra, w) != 0) return -155;
    if (w[0] != 0x02077984 || w[1] != 0 || w[2] != 0 || w[3] != 0x000fe200) return -156;

    /* 29. STS [R2], R4 */
    BlackwellIRInsn insn_sts = { .op = BW_IR_STS, .src1_vreg = 0, .src2_vreg = 1, .imm = 0 };
    if (encode_single_insn(&insn_sts, &ra, w) != 0) return -157;
    if (w[0] != 0x02007388 || w[1] != 4 || w[2] != 0 || w[3] != 0x000fe200) return -158;

    return 0;
}

int omega_blackwell_test_regalloc_bounds(void) {
    BlackwellIRProgram prog;
    omega_bw_ir_init(&prog);

    int v0 = omega_bw_ir_alloc_vreg64(&prog);
    int v1 = omega_bw_ir_alloc_vreg(&prog);
    int v2 = omega_bw_ir_alloc_vreg64(&prog);
    int v3 = omega_bw_ir_alloc_vreg128(&prog); /* Test 128-bit quad allocation */

    BlackwellIRInsn i0 = { .op = BW_IR_LDC64, .dst_vreg = v0, .imm = 0x380 };
    omega_bw_ir_append(&prog, &i0);
    BlackwellIRInsn i1 = { .op = BW_IR_MOV_IMM, .dst_vreg = v1, .imm = 10 };
    omega_bw_ir_append(&prog, &i1);
    BlackwellIRInsn i2 = { .op = BW_IR_LDC64, .dst_vreg = v2, .imm = 0x388 };
    omega_bw_ir_append(&prog, &i2);
    BlackwellIRInsn i3 = { .op = BW_IR_HMMA_F16, .dst_vreg = v3, .src1_vreg = v3, .src2_vreg = v0, .src3_vreg = -1 };
    omega_bw_ir_append(&prog, &i3);
    /* i4 uses v1, v2, v3 simultaneously so all intervals are concurrently active */
    int v_sink = omega_bw_ir_alloc_vreg(&prog);
    BlackwellIRInsn i4 = { .op = BW_IR_IADD3, .dst_vreg = v_sink, .src1_vreg = v1, .src2_vreg = v2, .src3_vreg = v3 };
    omega_bw_ir_append(&prog, &i4);

    if (omega_bw_regalloc_solve(&prog) != 0) return -1;

    int phys_v0 = prog.regalloc.vreg_to_phys[v0];
    int phys_v1 = prog.regalloc.vreg_to_phys[v1];
    int phys_v2 = prog.regalloc.vreg_to_phys[v2];
    int phys_v3 = prog.regalloc.vreg_to_phys[v3];

    if (phys_v0 % 2 != 0) return -2;
    if (phys_v2 % 2 != 0) return -3;
    if (phys_v3 % 4 != 0) return -4; /* 4-alignment for 128-bit quad */
    if (phys_v1 == phys_v0 || phys_v1 == phys_v0 + 1) return -5;
    if (phys_v2 == phys_v0 || phys_v2 == phys_v0 + 1) return -6;
    for (int k = 0; k < 4; k++) {
        if (phys_v3 + k == phys_v0 || phys_v3 + k == phys_v0 + 1) return -7;
        if (phys_v3 + k == phys_v2 || phys_v3 + k == phys_v2 + 1) return -8;
        if (phys_v3 + k == phys_v1) return -9;
    }

    /* Test bounds refusal: intentionally attempt to allocate more registers than hardware capacity */
    BlackwellIRProgram overflow_prog;
    omega_bw_ir_init(&overflow_prog);
    for (int i = 0; i < BW_PHYS_GPR_MAX + 5; i++) {
        int v = omega_bw_ir_alloc_vreg(&overflow_prog);
        if (v < 0) break;
        BlackwellIRInsn insn = { .op = BW_IR_MOV_IMM, .dst_vreg = v, .imm = (uint32_t)i };
        omega_bw_ir_append(&overflow_prog, &insn);
    }
    for (size_t i = 0; i < overflow_prog.count; i++) {
        for (int v = 0; v < overflow_prog.regalloc.num_vregs; v++) {
            overflow_prog.regalloc.intervals[v].last_use = (int)overflow_prog.count - 1;
        }
    }
    if (omega_bw_regalloc_solve(&overflow_prog) == 0) {
        return -6;
    }

    return 0;
}

#ifndef OMEGA_GPU_NO_POSIX /* prints: hosted only (the freestanding build has no stdio) */
int omega_blackwell_test_codegen_variation(void) {
    OmegaMatMulSpec spec1, spec2;
    if (omega_matmul_spec_init(&spec1, 16, 16, 16, OMEGA_MATMUL_PRECISION_INT32) != 0) {
        printf("FAIL: spec1 init failed\n");
        return -1;
    }
    if (omega_matmul_spec_init(&spec2, 32, 16, 64, OMEGA_MATMUL_PRECISION_INT32) != 0) {
        printf("FAIL: spec2 init failed\n");
        return -1;
    }

    OmegaBlackwellKernel k1, k2;
    memset(&k1, 0, sizeof(k1));
    memset(&k2, 0, sizeof(k2));

    if (omega_blackwell_codegen_matmul(&spec1, &k1) != 0) {
        printf("FAIL: k1 codegen failed\n");
        return -1;
    }
    if (omega_blackwell_codegen_matmul(&spec2, &k2) != 0) {
        printf("FAIL: k2 codegen failed\n");
        omega_blackwell_kernel_free(&k1);
        return -1;
    }

    OmegaBlackwellRealizationIdentity id1, id2;
    omega_blackwell_bind_matmul_realization(&spec1, &k1, &id1);
    omega_blackwell_bind_matmul_realization(&spec2, &k2, &id2);

    printf("================================================================================\n");
    printf("    OMEGA BLACKWELL CODEGEN VARIATION DEMONSTRATION (GATE 7 STAGE-1)\n");
    printf("================================================================================\n");
    printf("Config 1: 16x16x16 INT32\n");
    printf("  Instructions: %zu (%zu bytes, %u GPRs, %u UGPRs)\n", k1.insn_count, k1.code_size, k1.gpr_count, k1.uniform_gpr_count);
    printf("  Spec ID:      ");
    for (int i = 0; i < 16; i++) printf("%02x", spec1.spec_id[i]);
    printf("...\n");
    printf("  Code Digest:  ");
    for (int i = 0; i < 16; i++) printf("%02x", k1.code_digest[i]);
    printf("...\n");
    printf("  Realization:  ");
    for (int i = 0; i < 16; i++) printf("%02x", id1.realization_id[i]);
    printf("...\n\n");

    printf("Config 2: 32x16x64 INT32\n");
    printf("  Instructions: %zu (%zu bytes, %u GPRs, %u UGPRs)\n", k2.insn_count, k2.code_size, k2.gpr_count, k2.uniform_gpr_count);
    printf("  Spec ID:      ");
    for (int i = 0; i < 16; i++) printf("%02x", spec2.spec_id[i]);
    printf("...\n");
    printf("  Code Digest:  ");
    for (int i = 0; i < 16; i++) printf("%02x", k2.code_digest[i]);
    printf("...\n");
    printf("  Realization:  ");
    for (int i = 0; i < 16; i++) printf("%02x", id2.realization_id[i]);
    printf("...\n");
    printf("================================================================================\n");

    /* Validation checks */
    if (memcmp(spec1.spec_id, spec2.spec_id, 32) == 0) {
        printf("FAIL: spec IDs match (expected distinct)\n");
        return -2;
    }
    if (memcmp(k1.code_digest, k2.code_digest, 32) == 0) {
        printf("FAIL: code digests match (expected distinct)\n");
        return -3;
    }
    if (memcmp(id1.realization_id, id2.realization_id, 32) == 0) {
        printf("FAIL: realization IDs match (expected distinct)\n");
        return -4;
    }

    printf("PASS: Dynamic codegen variation verified (distinct specifications, code digests, and realization IDs).\n");

    omega_blackwell_kernel_free(&k1);
    omega_blackwell_kernel_free(&k2);
    return 0;
}
#endif

/* Declared registers: peak + 2 rounded up to 8 (see omega_blackwell_codegen.h for the chip evidence). */
uint32_t omega_bw_gpr_declared(uint32_t peak) { return ((peak + 2u + 7u) / 8u) * 8u; }
int omega_bw_gpr_declared_ok(uint32_t declared, uint32_t peak) { return declared % 8u == 0u && declared >= peak + 2u; }

int omega_bw_ir_set_gpr_limit(BlackwellIRProgram *prog, uint32_t limit) {
    if (!prog || limit <= BW_PHYS_GPR_MAX || limit > BW_PHYS_GPR_HW_LIMIT) return -1;
    prog->regalloc.gpr_limit = limit;
    return 0;
}
