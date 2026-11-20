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

/*
 * osc_a64.c -- hardened AArch64 encoder + mirror decoder (OSC-1 back end).
 * OSC-1 slice; not a general Omega compiler; no self-hosting.
 * See osc_a64.h for the rules. Nothing here masks a field: every field is
 * range-checked and an out-of-range or wrong-kind operand is refused.
 */
#include "osc_a64.h"
#include "omega_api_decl.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

typedef enum {
    CLS_NONE = 0, CLS_RRR_SH, CLS_RI, CLS_R4, CLS_MULH, CLS_R3, CLS_BFM, CLS_CSINC,
    CLS_MOV16, CLS_MEM, CLS_PAIR, CLS_B26, CLS_BCOND, CLS_CB, CLS_BREG, CLS_BRK
} Cls;

/* operand kinds for rd / rn / rm / ra positions */
enum { K_NONE = 0, K_ZR, K_SP, K_X };

typedef struct {
    const char *name;
    uint32_t base;
    uint8_t cls;
    uint8_t kd, kn, km, ka;
} OpInfo;

static const OpInfo OPS[OSC_A64_NOPS] = {
    [OSC_A64_ADD_REG]  = {"add",   0x8B000000u, CLS_RRR_SH, K_ZR, K_ZR, K_ZR, K_NONE},
    [OSC_A64_SUB_REG]  = {"sub",   0xCB000000u, CLS_RRR_SH, K_ZR, K_ZR, K_ZR, K_NONE},
    [OSC_A64_ADDS_REG] = {"adds",  0xAB000000u, CLS_RRR_SH, K_ZR, K_ZR, K_ZR, K_NONE},
    [OSC_A64_SUBS_REG] = {"subs",  0xEB000000u, CLS_RRR_SH, K_ZR, K_ZR, K_ZR, K_NONE},
    [OSC_A64_ADD_IMM]  = {"add",   0x91000000u, CLS_RI,     K_SP, K_SP, K_NONE, K_NONE},
    [OSC_A64_SUB_IMM]  = {"sub",   0xD1000000u, CLS_RI,     K_SP, K_SP, K_NONE, K_NONE},
    [OSC_A64_ADDS_IMM] = {"adds",  0xB1000000u, CLS_RI,     K_ZR, K_SP, K_NONE, K_NONE},
    [OSC_A64_SUBS_IMM] = {"subs",  0xF1000000u, CLS_RI,     K_ZR, K_SP, K_NONE, K_NONE},
    [OSC_A64_MADD]     = {"madd",  0x9B000000u, CLS_R4,     K_ZR, K_ZR, K_ZR, K_ZR},
    [OSC_A64_MSUB]     = {"msub",  0x9B008000u, CLS_R4,     K_ZR, K_ZR, K_ZR, K_ZR},
    [OSC_A64_SMULH]    = {"smulh", 0x9B407C00u, CLS_MULH,   K_ZR, K_ZR, K_ZR, K_NONE},
    [OSC_A64_UMULH]    = {"umulh", 0x9BC07C00u, CLS_MULH,   K_ZR, K_ZR, K_ZR, K_NONE},
    [OSC_A64_SDIV]     = {"sdiv",  0x9AC00C00u, CLS_R3,     K_ZR, K_ZR, K_ZR, K_NONE},
    [OSC_A64_UDIV]     = {"udiv",  0x9AC00800u, CLS_R3,     K_ZR, K_ZR, K_ZR, K_NONE},
    [OSC_A64_LSLV]     = {"lslv",  0x9AC02000u, CLS_R3,     K_ZR, K_ZR, K_ZR, K_NONE},
    [OSC_A64_LSRV]     = {"lsrv",  0x9AC02400u, CLS_R3,     K_ZR, K_ZR, K_ZR, K_NONE},
    [OSC_A64_ASRV]     = {"asrv",  0x9AC02800u, CLS_R3,     K_ZR, K_ZR, K_ZR, K_NONE},
    [OSC_A64_AND_REG]  = {"and",   0x8A000000u, CLS_RRR_SH, K_ZR, K_ZR, K_ZR, K_NONE},
    [OSC_A64_ORR_REG]  = {"orr",   0xAA000000u, CLS_RRR_SH, K_ZR, K_ZR, K_ZR, K_NONE},
    [OSC_A64_EOR_REG]  = {"eor",   0xCA000000u, CLS_RRR_SH, K_ZR, K_ZR, K_ZR, K_NONE},
    [OSC_A64_ORN_REG]  = {"orn",   0xAA200000u, CLS_RRR_SH, K_ZR, K_ZR, K_ZR, K_NONE},
    [OSC_A64_SBFM]     = {"sbfm",  0x93400000u, CLS_BFM,    K_ZR, K_ZR, K_NONE, K_NONE},
    [OSC_A64_UBFM]     = {"ubfm",  0xD3400000u, CLS_BFM,    K_ZR, K_ZR, K_NONE, K_NONE},
    [OSC_A64_CSINC]    = {"csinc", 0x9A800400u, CLS_CSINC,  K_ZR, K_ZR, K_ZR, K_NONE},
    [OSC_A64_MOVZ]     = {"movz",  0xD2800000u, CLS_MOV16,  K_ZR, K_NONE, K_NONE, K_NONE},
    [OSC_A64_MOVN]     = {"movn",  0x92800000u, CLS_MOV16,  K_ZR, K_NONE, K_NONE, K_NONE},
    [OSC_A64_MOVK]     = {"movk",  0xF2800000u, CLS_MOV16,  K_ZR, K_NONE, K_NONE, K_NONE},
    [OSC_A64_LDR_UOFF] = {"ldr",   0xF9400000u, CLS_MEM,    K_ZR, K_SP, K_NONE, K_NONE},
    [OSC_A64_STR_UOFF] = {"str",   0xF9000000u, CLS_MEM,    K_ZR, K_SP, K_NONE, K_NONE},
    [OSC_A64_STP_OFF]  = {"stp",   0xA9000000u, CLS_PAIR,   K_ZR, K_SP, K_NONE, K_ZR},
    [OSC_A64_STP_PRE]  = {"stp!",  0xA9800000u, CLS_PAIR,   K_ZR, K_SP, K_NONE, K_ZR},
    [OSC_A64_STP_POST] = {"stp+",  0xA8800000u, CLS_PAIR,   K_ZR, K_SP, K_NONE, K_ZR},
    [OSC_A64_LDP_OFF]  = {"ldp",   0xA9400000u, CLS_PAIR,   K_ZR, K_SP, K_NONE, K_ZR},
    [OSC_A64_LDP_PRE]  = {"ldp!",  0xA9C00000u, CLS_PAIR,   K_ZR, K_SP, K_NONE, K_ZR},
    [OSC_A64_LDP_POST] = {"ldp+",  0xA8C00000u, CLS_PAIR,   K_ZR, K_SP, K_NONE, K_ZR},
    [OSC_A64_B]        = {"b",     0x14000000u, CLS_B26,    K_NONE, K_NONE, K_NONE, K_NONE},
    [OSC_A64_BL]       = {"bl",    0x94000000u, CLS_B26,    K_NONE, K_NONE, K_NONE, K_NONE},
    [OSC_A64_BCOND]    = {"b.cond",0x54000000u, CLS_BCOND,  K_NONE, K_NONE, K_NONE, K_NONE},
    [OSC_A64_CBZ]      = {"cbz",   0xB4000000u, CLS_CB,     K_ZR, K_NONE, K_NONE, K_NONE},
    [OSC_A64_CBNZ]     = {"cbnz",  0xB5000000u, CLS_CB,     K_ZR, K_NONE, K_NONE, K_NONE},
    [OSC_A64_BLR]      = {"blr",   0xD63F0000u, CLS_BREG,   K_NONE, K_X, K_NONE, K_NONE},
    [OSC_A64_RET]      = {"ret",   0xD65F0000u, CLS_BREG,   K_NONE, K_X, K_NONE, K_NONE},
    [OSC_A64_BRK]      = {"brk",   0xD4200000u, CLS_BRK,    K_NONE, K_NONE, K_NONE, K_NONE},
    [OSC_A64_LDRB_REG] = {"ldrb",  0x38606800u, CLS_R3,     K_ZR, K_SP, K_ZR, K_NONE},
};

/* variable-field mask per class (bits not fixed by the opcode) */
static uint32_t cls_varmask(int cls) {
    switch (cls) {
    case CLS_RRR_SH: return 0x00DFFFFFu;  /* shift 23:22, Rm 20:16, imm6 15:10, Rn, Rd */
    case CLS_RI:     return 0x007FFFFFu;  /* sh 22, imm12 21:10, Rn, Rd */
    case CLS_R4:     return 0x001F7FFFu;  /* Rm, Ra 14:10, Rn, Rd */
    case CLS_MULH:   return 0x001F03FFu;
    case CLS_R3:     return 0x001F03FFu;
    case CLS_BFM:    return 0x003FFFFFu;
    case CLS_CSINC:  return 0x001FF3FFu;  /* Rm, cond 15:12, Rn, Rd */
    case CLS_MOV16:  return 0x007FFFFFu;  /* hw 22:21, imm16 20:5, Rd */
    case CLS_MEM:    return 0x003FFFFFu;
    case CLS_PAIR:   return 0x003FFFFFu;  /* imm7 21:15, Rt2 14:10, Rn, Rt */
    case CLS_B26:    return 0x03FFFFFFu;
    case CLS_BCOND:  return 0x00FFFFEFu;  /* imm19 23:5, cond 3:0 (bit 4 fixed 0) */
    case CLS_CB:     return 0x00FFFFFFu;
    case CLS_BREG:   return 0x000003E0u;
    case CLS_BRK:    return 0x001FFFE0u;
    default:         return 0;
    }
}

static int fail(char *err, size_t n, const char *fmt, ...) {
    if (err && n) {
        va_list ap;
        va_start(ap, fmt);
        vsnprintf(err, n, fmt, ap);
        va_end(ap);
    }
    return -1;
}

/* map typed operand -> 5-bit field, refusing the wrong kind */
static int regfield(int kind, int r, uint32_t *f, const char *pos, const char *op, char *err, size_t n) {
    if (r >= 0 && r <= 30) { *f = (uint32_t)r; return 0; }
    if (kind == K_ZR && r == OSC_A64_XZR) { *f = 31; return 0; }
    if (kind == K_SP && r == OSC_A64_SP) { *f = 31; return 0; }
    if (r == OSC_A64_SP) return fail(err, n, "%s: %s cannot be SP", op, pos);
    if (r == OSC_A64_XZR) return fail(err, n, "%s: %s cannot be XZR", op, pos);
    return fail(err, n, "%s: %s register %d out of range", op, pos, r);
}

static int unreg(int kind, uint32_t f) {
    if (f < 31) return (int)f;
    if (kind == K_ZR) return OSC_A64_XZR;
    if (kind == K_SP) return OSC_A64_SP;
    return 255; /* not encodable: re-encode check refuses */
}

int osc_a64_encode(const OscA64Insn *in, uint32_t *word, char *err, size_t n) {
    if (!in || !word) return fail(err, n, "null");
    int op = in->op;
    if (op <= OSC_A64_INVALID || op >= OSC_A64_NOPS || !OPS[op].name)
        return fail(err, n, "unknown op %d", op);
    const OpInfo *oi = &OPS[op];
    const char *nm = oi->name;
    uint32_t rd = 0, rn = 0, rm = 0, ra = 0;
    /* unused register / field positions must be zero (canonical form) */
    if (oi->kd == K_NONE && in->rd) return fail(err, n, "%s: rd unused but set", nm);
    if (oi->kn == K_NONE && in->rn) return fail(err, n, "%s: rn unused but set", nm);
    if (oi->km == K_NONE && in->rm) return fail(err, n, "%s: rm unused but set", nm);
    if (oi->ka == K_NONE && in->ra) return fail(err, n, "%s: ra unused but set", nm);
    if (oi->kd != K_NONE && regfield(oi->kd, in->rd, &rd, "rd", nm, err, n)) return -1;
    if (oi->kn != K_NONE && regfield(oi->kn, in->rn, &rn, "rn", nm, err, n)) return -1;
    if (oi->km != K_NONE && regfield(oi->km, in->rm, &rm, "rm", nm, err, n)) return -1;
    if (oi->ka != K_NONE && regfield(oi->ka, in->ra, &ra, "ra", nm, err, n)) return -1;
    const OscA64Fields f = {.rd = rd, .rn = rn, .rm = rm, .ra = ra, .shift = in->shift,
                            .cond = in->cond, .imm = in->imm, .imm2 = in->imm2};
    int writeback = op == OSC_A64_STP_PRE || op == OSC_A64_STP_POST || op == OSC_A64_LDP_PRE || op == OSC_A64_LDP_POST;
    int loadpair = op == OSC_A64_LDP_OFF || op == OSC_A64_LDP_PRE || op == OSC_A64_LDP_POST;
    switch (osc_a64_check_fields(oi->cls, &f, writeback, loadpair)) {
    case 0: break;
    case OSC_A64_ERR_UNUSED_SHIFT:
        return fail(err, n, "%s: shift unused but set", nm);
    case OSC_A64_ERR_UNUSED_COND:
        return fail(err, n, "%s: cond unused but set", nm);
    case OSC_A64_ERR_UNUSED_IMM2:
        return fail(err, n, "%s: imm2 unused but set", nm);
    case OSC_A64_ERR_UNUSED_IMM:
        return fail(err, n, "%s: imm unused but set", nm);
    case OSC_A64_ERR_SHIFT_KIND:
        return fail(err, n, "%s: shift type %u refused", nm, in->shift);
    case OSC_A64_ERR_SHIFT_AMOUNT:
        return fail(err, n, "%s: shift amount %lld out of range", nm, (long long)in->imm);
    case OSC_A64_ERR_IMM12:
        return fail(err, n, "%s: imm12 %lld out of range", nm, (long long)in->imm);
    case OSC_A64_ERR_LSL12:
        return fail(err, n, "%s: lsl12 flag %lld invalid", nm, (long long)in->imm2);
    case OSC_A64_ERR_IMMR:
        return fail(err, n, "%s: immr %lld out of range", nm, (long long)in->imm);
    case OSC_A64_ERR_IMMS:
        return fail(err, n, "%s: imms %lld out of range", nm, (long long)in->imm2);
    case OSC_A64_ERR_COND:
        return fail(err, n, "%s: cond %u refused", nm, in->cond);
    case OSC_A64_ERR_IMM16:
        return fail(err, n, "%s: imm16 %lld out of range", nm, (long long)in->imm);
    case OSC_A64_ERR_MOV_SHIFT:
        return fail(err, n, "%s: shift %lld invalid", nm, (long long)in->imm2);
    case OSC_A64_ERR_MEM_OFFSET:
        return fail(err, n, "%s: offset %lld not a multiple of 8 in 0..32760", nm, (long long)in->imm);
    case OSC_A64_ERR_PAIR_OFFSET:
        return fail(err, n, "%s: offset %lld not a multiple of 8 in -512..504", nm, (long long)in->imm);
    case OSC_A64_ERR_WRITEBACK_ALIAS:
        return fail(err, n, "%s: writeback base equals a transfer register (unpredictable)", nm);
    case OSC_A64_ERR_LOAD_ALIAS:
        return fail(err, n, "%s: Rt == Rt2 (unpredictable)", nm);
    case OSC_A64_ERR_BRANCH_OFFSET:
        return fail(err, n, "%s: offset %lld out of range or misaligned", nm, (long long)in->imm);
    case OSC_A64_ERR_BRANCH_COND:
        return fail(err, n, "%s: cond %u refused (AL/NV not used)", nm, in->cond);
    default: return fail(err, n, "bad class");
    }
    *word = (uint32_t)osc_a64_pack_fields(oi->cls, oi->base, &f);
    return 0;
}

int osc_a64_reencode(const OscA64Insn *in, uint32_t *word) {
    return osc_a64_encode(in, word, NULL, 0);
}

int osc_a64_decode(uint32_t w, OscA64Insn *out) {
    for (int op = 1; op < OSC_A64_NOPS; op++) {
        const OpInfo *oi = &OPS[op];
        if (!oi->name) continue;
        if ((w & ~cls_varmask(oi->cls)) != oi->base) continue;
        OscA64Insn d;
        memset(&d, 0, sizeof d);
        d.op = (uint8_t)op;
        OscA64Fields f;
        osc_a64_unpack_fields(oi->cls, w, &f);
        if (oi->kd != K_NONE) d.rd = (uint8_t)unreg(oi->kd, f.rd);
        if (oi->kn != K_NONE) d.rn = (uint8_t)unreg(oi->kn, f.rn);
        if (oi->km != K_NONE) d.rm = (uint8_t)unreg(oi->km, f.rm);
        if (oi->ka != K_NONE) d.ra = (uint8_t)unreg(oi->ka, f.ra);
        d.shift = (uint8_t)f.shift;
        d.cond = (uint8_t)f.cond;
        d.imm = f.imm;
        d.imm2 = f.imm2;
        uint32_t re;
        if (osc_a64_encode(&d, &re, NULL, 0) != 0 || re != w) continue;
        if (out) *out = d;
        return 0;
    }
    return -1;
}

const char *osc_a64_op_name(int op) {
    if (op <= 0 || op >= OSC_A64_NOPS || !OPS[op].name) return "?";
    return OPS[op].name;
}

int osc_a64_equal(const OscA64Insn *x, const OscA64Insn *y) {
    return x->op == y->op && x->rd == y->rd && x->rn == y->rn && x->rm == y->rm &&
           x->ra == y->ra && x->shift == y->shift && x->cond == y->cond &&
           x->imm == y->imm && x->imm2 == y->imm2;
}

/* ---- constructors ----------------------------------------------------- */
static OscA64Insn mk(int op) {
    OscA64Insn i;
    memset(&i, 0, sizeof i);
    i.op = (uint8_t)op;
    return i;
}
/* registers are passed as int; values outside uint8 are clamped to 255
 * (never a valid operand) so the encoder refuses them rather than wrapping */
static uint8_t r8(int r) { return (r < 0 || r > 254) ? 255 : (uint8_t)r; }

OscA64Insn osc_a64_r3(OscA64Op op, int rd, int rn, int rm) {
    OscA64Insn i = mk(op); i.rd = r8(rd); i.rn = r8(rn); i.rm = r8(rm); return i;
}
OscA64Insn osc_a64_r3s(OscA64Op op, int rd, int rn, int rm, OscA64Shift sh, int amount) {
    OscA64Insn i = osc_a64_r3(op, rd, rn, rm); i.shift = (uint8_t)sh; i.imm = amount; return i;
}
OscA64Insn osc_a64_ri(OscA64Op op, int rd, int rn, int64_t imm12, int lsl12) {
    OscA64Insn i = mk(op); i.rd = r8(rd); i.rn = r8(rn); i.imm = imm12; i.imm2 = lsl12; return i;
}
OscA64Insn osc_a64_r4(OscA64Op op, int rd, int rn, int rm, int ra) {
    OscA64Insn i = osc_a64_r3(op, rd, rn, rm); i.ra = r8(ra); return i;
}
OscA64Insn osc_a64_bfm(OscA64Op op, int rd, int rn, int immr, int imms) {
    OscA64Insn i = mk(op); i.rd = r8(rd); i.rn = r8(rn); i.imm = immr; i.imm2 = imms; return i;
}
OscA64Insn osc_a64_csinc(int rd, int rn, int rm, OscA64Cond c) {
    OscA64Insn i = osc_a64_r3(OSC_A64_CSINC, rd, rn, rm); i.cond = (uint8_t)c; return i;
}
OscA64Insn osc_a64_mov16(OscA64Op op, int rd, int64_t imm16, int shift) {
    OscA64Insn i = mk(op); i.rd = r8(rd); i.imm = imm16; i.imm2 = shift; return i;
}
OscA64Insn osc_a64_mem(OscA64Op op, int rt, int rn, int64_t off) {
    OscA64Insn i = mk(op); i.rd = r8(rt); i.rn = r8(rn); i.imm = off; return i;
}
OscA64Insn osc_a64_pair(OscA64Op op, int rt, int rt2, int rn, int64_t off) {
    OscA64Insn i = mk(op); i.rd = r8(rt); i.ra = r8(rt2); i.rn = r8(rn); i.imm = off; return i;
}
OscA64Insn osc_a64_br(OscA64Op op, int64_t off) { OscA64Insn i = mk(op); i.imm = off; return i; }
OscA64Insn osc_a64_bcond(OscA64Cond c, int64_t off) {
    OscA64Insn i = mk(OSC_A64_BCOND); i.cond = (uint8_t)c; i.imm = off; return i;
}
OscA64Insn osc_a64_cb(OscA64Op op, int rt, int64_t off) { OscA64Insn i = mk(op); i.rd = r8(rt); i.imm = off; return i; }
OscA64Insn osc_a64_breg(OscA64Op op, int rn) { OscA64Insn i = mk(op); i.rn = r8(rn); return i; }
OscA64Insn osc_a64_brk(int64_t imm16) { OscA64Insn i = mk(OSC_A64_BRK); i.imm = imm16; return i; }
