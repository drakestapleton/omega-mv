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
    uint8_t kd, kn, km, ka, flags; /* bit 0 writeback, bit 1 load pair */
} OpInfo;

static const OpInfo OPS[OSC_A64_NOPS] = {
    [OSC_A64_ADD_REG]  = {"add",   0x8B000000u, CLS_RRR_SH, K_ZR, K_ZR, K_ZR, K_NONE, 0},
    [OSC_A64_SUB_REG]  = {"sub",   0xCB000000u, CLS_RRR_SH, K_ZR, K_ZR, K_ZR, K_NONE, 0},
    [OSC_A64_ADDS_REG] = {"adds",  0xAB000000u, CLS_RRR_SH, K_ZR, K_ZR, K_ZR, K_NONE, 0},
    [OSC_A64_SUBS_REG] = {"subs",  0xEB000000u, CLS_RRR_SH, K_ZR, K_ZR, K_ZR, K_NONE, 0},
    [OSC_A64_ADD_IMM]  = {"add",   0x91000000u, CLS_RI,     K_SP, K_SP, K_NONE, K_NONE, 0},
    [OSC_A64_SUB_IMM]  = {"sub",   0xD1000000u, CLS_RI,     K_SP, K_SP, K_NONE, K_NONE, 0},
    [OSC_A64_ADDS_IMM] = {"adds",  0xB1000000u, CLS_RI,     K_ZR, K_SP, K_NONE, K_NONE, 0},
    [OSC_A64_SUBS_IMM] = {"subs",  0xF1000000u, CLS_RI,     K_ZR, K_SP, K_NONE, K_NONE, 0},
    [OSC_A64_MADD]     = {"madd",  0x9B000000u, CLS_R4,     K_ZR, K_ZR, K_ZR, K_ZR, 0},
    [OSC_A64_MSUB]     = {"msub",  0x9B008000u, CLS_R4,     K_ZR, K_ZR, K_ZR, K_ZR, 0},
    [OSC_A64_SMULH]    = {"smulh", 0x9B407C00u, CLS_MULH,   K_ZR, K_ZR, K_ZR, K_NONE, 0},
    [OSC_A64_UMULH]    = {"umulh", 0x9BC07C00u, CLS_MULH,   K_ZR, K_ZR, K_ZR, K_NONE, 0},
    [OSC_A64_SDIV]     = {"sdiv",  0x9AC00C00u, CLS_R3,     K_ZR, K_ZR, K_ZR, K_NONE, 0},
    [OSC_A64_UDIV]     = {"udiv",  0x9AC00800u, CLS_R3,     K_ZR, K_ZR, K_ZR, K_NONE, 0},
    [OSC_A64_LSLV]     = {"lslv",  0x9AC02000u, CLS_R3,     K_ZR, K_ZR, K_ZR, K_NONE, 0},
    [OSC_A64_LSRV]     = {"lsrv",  0x9AC02400u, CLS_R3,     K_ZR, K_ZR, K_ZR, K_NONE, 0},
    [OSC_A64_ASRV]     = {"asrv",  0x9AC02800u, CLS_R3,     K_ZR, K_ZR, K_ZR, K_NONE, 0},
    [OSC_A64_AND_REG]  = {"and",   0x8A000000u, CLS_RRR_SH, K_ZR, K_ZR, K_ZR, K_NONE, 0},
    [OSC_A64_ORR_REG]  = {"orr",   0xAA000000u, CLS_RRR_SH, K_ZR, K_ZR, K_ZR, K_NONE, 0},
    [OSC_A64_EOR_REG]  = {"eor",   0xCA000000u, CLS_RRR_SH, K_ZR, K_ZR, K_ZR, K_NONE, 0},
    [OSC_A64_ORN_REG]  = {"orn",   0xAA200000u, CLS_RRR_SH, K_ZR, K_ZR, K_ZR, K_NONE, 0},
    [OSC_A64_SBFM]     = {"sbfm",  0x93400000u, CLS_BFM,    K_ZR, K_ZR, K_NONE, K_NONE, 0},
    [OSC_A64_UBFM]     = {"ubfm",  0xD3400000u, CLS_BFM,    K_ZR, K_ZR, K_NONE, K_NONE, 0},
    [OSC_A64_CSINC]    = {"csinc", 0x9A800400u, CLS_CSINC,  K_ZR, K_ZR, K_ZR, K_NONE, 0},
    [OSC_A64_MOVZ]     = {"movz",  0xD2800000u, CLS_MOV16,  K_ZR, K_NONE, K_NONE, K_NONE, 0},
    [OSC_A64_MOVN]     = {"movn",  0x92800000u, CLS_MOV16,  K_ZR, K_NONE, K_NONE, K_NONE, 0},
    [OSC_A64_MOVK]     = {"movk",  0xF2800000u, CLS_MOV16,  K_ZR, K_NONE, K_NONE, K_NONE, 0},
    [OSC_A64_LDR_UOFF] = {"ldr",   0xF9400000u, CLS_MEM,    K_ZR, K_SP, K_NONE, K_NONE, 0},
    [OSC_A64_STR_UOFF] = {"str",   0xF9000000u, CLS_MEM,    K_ZR, K_SP, K_NONE, K_NONE, 0},
    [OSC_A64_STP_OFF]  = {"stp",   0xA9000000u, CLS_PAIR,   K_ZR, K_SP, K_NONE, K_ZR, 0},
    [OSC_A64_STP_PRE]  = {"stp!",  0xA9800000u, CLS_PAIR,   K_ZR, K_SP, K_NONE, K_ZR, 1},
    [OSC_A64_STP_POST] = {"stp+",  0xA8800000u, CLS_PAIR,   K_ZR, K_SP, K_NONE, K_ZR, 1},
    [OSC_A64_LDP_OFF]  = {"ldp",   0xA9400000u, CLS_PAIR,   K_ZR, K_SP, K_NONE, K_ZR, 2},
    [OSC_A64_LDP_PRE]  = {"ldp!",  0xA9C00000u, CLS_PAIR,   K_ZR, K_SP, K_NONE, K_ZR, 3},
    [OSC_A64_LDP_POST] = {"ldp+",  0xA8C00000u, CLS_PAIR,   K_ZR, K_SP, K_NONE, K_ZR, 3},
    [OSC_A64_B]        = {"b",     0x14000000u, CLS_B26,    K_NONE, K_NONE, K_NONE, K_NONE, 0},
    [OSC_A64_BL]       = {"bl",    0x94000000u, CLS_B26,    K_NONE, K_NONE, K_NONE, K_NONE, 0},
    [OSC_A64_BCOND]    = {"b.cond",0x54000000u, CLS_BCOND,  K_NONE, K_NONE, K_NONE, K_NONE, 0},
    [OSC_A64_CBZ]      = {"cbz",   0xB4000000u, CLS_CB,     K_ZR, K_NONE, K_NONE, K_NONE, 0},
    [OSC_A64_CBNZ]     = {"cbnz",  0xB5000000u, CLS_CB,     K_ZR, K_NONE, K_NONE, K_NONE, 0},
    [OSC_A64_BLR]      = {"blr",   0xD63F0000u, CLS_BREG,   K_NONE, K_X, K_NONE, K_NONE, 0},
    [OSC_A64_RET]      = {"ret",   0xD65F0000u, CLS_BREG,   K_NONE, K_X, K_NONE, K_NONE, 0},
    [OSC_A64_BRK]      = {"brk",   0xD4200000u, CLS_BRK,    K_NONE, K_NONE, K_NONE, K_NONE, 0},
    [OSC_A64_LDRB_REG] = {"ldrb",  0x38606800u, CLS_R3,     K_ZR, K_SP, K_ZR, K_NONE, 0},
};

/* The seeded codec reads these two fixed records as byte spans. */
_Static_assert(sizeof(OpInfo) == 24 && offsetof(OpInfo, base) == 8 &&
               offsetof(OpInfo, cls) == 12 && offsetof(OpInfo, kd) == 13 &&
               offsetof(OpInfo, kn) == 14 && offsetof(OpInfo, km) == 15 &&
               offsetof(OpInfo, ka) == 16 && offsetof(OpInfo, flags) == 17, "AArch64 opcode descriptor ABI");
_Static_assert(sizeof(OscA64Insn) == 24 && offsetof(OscA64Insn, op) == 0 &&
               offsetof(OscA64Insn, rd) == 1 && offsetof(OscA64Insn, rn) == 2 &&
               offsetof(OscA64Insn, rm) == 3 && offsetof(OscA64Insn, ra) == 4 &&
               offsetof(OscA64Insn, shift) == 5 && offsetof(OscA64Insn, cond) == 6 &&
               offsetof(OscA64Insn, imm) == 8 && offsetof(OscA64Insn, imm2) == 16,
               "AArch64 instruction ABI");
_Static_assert(OSC_A64_XZR == 32 && OSC_A64_SP == 33, "AArch64 typed register values");

static int fail(char *err, size_t n, const char *fmt, ...) {
    if (err && n) {
        va_list ap;
        va_start(ap, fmt);
        vsnprintf(err, n, fmt, ap);
        va_end(ap);
    }
    return -1;
}

int osc_a64_encode(const OscA64Insn *in, uint32_t *word, char *err, size_t n) {
    if (!in || !word) return fail(err, n, "null");
    int op = in->op;
    if (op <= OSC_A64_INVALID || op >= OSC_A64_NOPS || !OPS[op].name)
        return fail(err, n, "unknown op %d", op);
    const OpInfo *oi = &OPS[op];
    const char *nm = oi->name;
    uint64_t packed = osc_a64_write((const uint8_t *)oi, (const uint8_t *)in);
    unsigned code = (unsigned)(packed >> 32);
    if (code >= OSC_A64_ERR_UNUSED_REG && code < OSC_A64_ERR_BAD_REG + 4) {
        const char *const positions[] = {"rd", "rn", "rm", "ra"};
        const unsigned regs[] = {in->rd, in->rn, in->rm, in->ra};
        unsigned i = (code - OSC_A64_ERR_UNUSED_REG) % 4;
        if (code < OSC_A64_ERR_REG_SP) return fail(err, n, "%s: %s unused but set", nm, positions[i]);
        if (code < OSC_A64_ERR_REG_ZR) return fail(err, n, "%s: %s cannot be SP", nm, positions[i]);
        if (code < OSC_A64_ERR_BAD_REG) return fail(err, n, "%s: %s cannot be XZR", nm, positions[i]);
        return fail(err, n, "%s: %s register %u out of range", nm, positions[i], regs[i]);
    }
    switch (packed >> 32) {
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
    *word = (uint32_t)packed;
    return 0;
}

int osc_a64_reencode(const OscA64Insn *in, uint32_t *word) {
    return osc_a64_encode(in, word, NULL, 0);
}

int osc_a64_decode(uint32_t w, OscA64Insn *out) {
    OscA64Insn decoded = {0};
    if (!osc_a64_read(w, (const uint8_t *)OPS, sizeof OPS, (uint8_t *)&decoded)) return -1;
    if (out) *out = decoded;
    return 0;
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
