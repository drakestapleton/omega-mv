#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
# Rebuilds the gfx942 tables from one instruction list.
# check.sh does not run this file. It assembles the .s with llvm-mc and packs the .isa
# with hsaco.om, and those two byte strings have to match.

import os
import struct
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))


def u32(x):
    return struct.pack("<I", x & 0xFFFFFFFF)


def flat(offset, sc0, nt, op, sc1, vaddr, vdata, saddr, vdst, sve=0, seg=2, acc=0):
    w0 = (
        (offset & 0x1FFF)
        | ((sve & 1) << 13)
        | ((seg & 3) << 14)
        | ((sc0 & 1) << 16)
        | ((nt & 1) << 17)
        | ((op & 0x7F) << 18)
        | ((sc1 & 1) << 25)
        | (0x37 << 26)
    )
    w1 = (
        (vaddr & 0xFF)
        | ((vdata & 0xFF) << 8)
        | ((saddr & 0x7F) << 16)
        | ((acc & 1) << 23)
        | ((vdst & 0xFF) << 24)
    )
    return u32(w0) + u32(w1)


def mubuf(op, offen, sc0, sc1, nt, vaddr, vdata, srsrc, soffset, offset=0, idxen=0):
    w0 = (
        (offset & 0xFFF)
        | ((offen & 1) << 12)
        | ((idxen & 1) << 13)
        | ((sc0 & 1) << 14)
        | ((sc1 & 1) << 15)
        | ((nt & 1) << 17)
        | ((op & 0x7F) << 18)
        | (0x38 << 26)
    )
    w1 = (
        (vaddr & 0xFF)
        | ((vdata & 0xFF) << 8)
        | ((srsrc & 0x1F) << 16)
        | ((soffset & 0xFF) << 24)
    )
    return u32(w0) + u32(w1)


def sop2(op, a, b, dst):
    w = (a & 0xFF) | ((b & 0xFF) << 8) | ((dst & 0x7F) << 16) | ((op & 0x7F) << 23) | (2 << 30)
    return u32(w)


def sop1(op, src, dst):
    w = (src & 0xFF) | ((op & 0xFF) << 8) | ((dst & 0x7F) << 16) | (0x17D << 23)
    return u32(w)


def sopc(op, a, b):
    w = (a & 0xFF) | ((b & 0xFF) << 8) | ((op & 0x7F) << 16) | (0x17E << 23)
    return u32(w)


def sopp(op, simm):
    w = (simm & 0xFFFF) | ((op & 0x7F) << 16) | (0x17F << 23)
    return u32(w)


def smem(sdata, op, offset, sbase=0):
    w0 = (sbase & 0x3F) | ((sdata & 0x7F) << 6) | (1 << 17) | ((op & 0xFF) << 18) | (0x30 << 26)
    w1 = offset & 0x1FFFFF
    return u32(w0) + u32(w1)


def vop2(src0, vsrc1, vdst, op):
    w = (src0 & 0x1FF) | ((vsrc1 & 0xFF) << 9) | ((vdst & 0xFF) << 17) | ((op & 0x3F) << 25)
    return u32(w)


def vop1(src, op, vdst):
    w = (src & 0x1FF) | ((op & 0xFF) << 9) | ((vdst & 0xFF) << 17) | (0x3F << 25)
    return u32(w)


def vop3(vdst, op, src0, src1, src2):
    w0 = (vdst & 0xFF) | ((op & 0x3FF) << 16) | (0x34 << 26)
    w1 = (src0 & 0x1FF) | ((src1 & 0x1FF) << 9) | ((src2 & 0x1FF) << 18)
    return u32(w0) + u32(w1)


def dpp(vsrc1, vdst, op, src, ctrl):
    w0 = 250 | ((vsrc1 & 0xFF) << 9) | ((vdst & 0xFF) << 17) | ((op & 0x3F) << 25)
    w1 = (src & 0xFF) | ((ctrl & 0x1FF) << 8) | (0xF << 24) | (0xF << 28)
    return u32(w0) + u32(w1)


class Prog:
    def __init__(self):
        self.ops = []
        self.labels = {}

    def add(self, blob, asm, kind="i", extra=None):
        self.ops.append({"blob": blob, "asm": asm, "kind": kind, "extra": extra, "at": None})

    def label(self, name):
        self.ops.append({"blob": b"", "asm": name + ":", "kind": "label", "extra": name, "at": None})

    def branch(self, op, name, mnemonic):
        self.ops.append({"blob": None, "asm": mnemonic + " " + name, "kind": "br", "extra": (op, name), "at": None})

    def layout(self):
        at = 0
        for op in self.ops:
            op["at"] = at
            if op["kind"] == "label":
                self.labels[op["extra"]] = at
            elif op["kind"] == "br":
                at += 4
            else:
                at += len(op["blob"])
        raw = b""
        isa = []
        asm = []
        ids = {}
        nlab = 0
        for op in self.ops:
            if op["kind"] == "label":
                nlab += 1
                ids[op["extra"]] = nlab
        for op in self.ops:
            if op["kind"] == "label":
                isa.append("T %d" % ids[op["extra"]])
                asm.append(op["asm"])
                continue
            if op["kind"] == "br":
                bop, name = op["extra"]
                nxt = op["at"] + 4
                d = (self.labels[name] - nxt) // 4
                if d < 0:
                    simm = d + 65536
                else:
                    simm = d
                if simm < 0 or simm > 65535:
                    raise SystemExit("branch %s out of range" % name)
                raw += sopp(bop, simm)
                isa.append("I 4 @%d %d" % (ids[name], bop))
                asm.append(op["asm"])
                continue
            raw += op["blob"]
            isa.append(op["extra"])
            asm.append(op["asm"])
        return raw, isa, asm


# SOP2 opcodes are the 7-bit field in CDNA3 ISA §12.1 (S_AND_B32 is 12, not 6).
SOP2_ADD = 0
SOP2_ADDC = 4
SOP2_AND = 12
SOP2_LSHL = 28
SOP2_LSHR = 30
SOP2_MUL = 36
SOP2_MULHI = 44


def sop2e(p, op, a, b, dst, text):
    p.add(sop2(op, a, b, dst), text, "isa", "I 2 %d %d %d %d" % (a, b, dst, op))


def sop1e(p, op, src, dst, text, lit=None):
    blob = sop1(op, src, dst)
    line = "I 3 %d %d %d" % (src, op, dst)
    if lit is not None:
        blob += u32(lit)
        line += "\nL %d" % lit
    p.add(blob, text, "isa", line)


def sopce(p, op, a, b, text):
    p.add(sopc(op, a, b), text, "isa", "I 11 %d %d %d" % (a, b, op))


def vope(p, src0, vsrc1, vdst, op, text, lit=None):
    blob = vop2(src0, vsrc1, vdst, op)
    line = "I 5 %d %d %d %d" % (src0, vsrc1, vdst, op)
    if lit is not None:
        blob += u32(lit)
        line += "\nL %d" % lit
    p.add(blob, text, "isa", line)


def v1e(p, src, op, vdst, text):
    p.add(vop1(src, op, vdst), text, "isa", "I 8 %d %d %d" % (src, op, vdst))


def v3e(p, vdst, op, s0, s1, s2, text):
    p.add(vop3(vdst, op, s0, s1, s2), text, "isa", "I 9 %d %d %d %d %d" % (vdst, op, s0, s1, s2))


def dppe(p, vsrc1, vdst, op, src, ctrl, text):
    p.add(dpp(vsrc1, vdst, op, src, ctrl), text, "isa", "I 10 250 %d %d %d %d %d 15 15" % (vsrc1, vdst, op, src, ctrl))


def flate(p, offset, sc0, nt, op, sc1, vaddr, vdata, saddr, vdst, text):
    p.add(
        flat(offset, sc0, nt, op, sc1, vaddr, vdata, saddr, vdst),
        text,
        "isa",
        "I 7 %d 0 2 %d %d %d %d %d %d %d 0 %d" % (offset, sc0, nt, op, sc1, vaddr, vdata, saddr, vdst),
    )


def mube(p, op, offen, sc0, sc1, nt, vaddr, vdata, srsrc, soffset, text):
    p.add(
        mubuf(op, offen, sc0, sc1, nt, vaddr, vdata, srsrc, soffset),
        text,
        "isa",
        "I 12 0 %d 0 %d %d %d %d %d %d %d %d" % (offen, sc0, sc1, nt, op, vaddr, vdata, srsrc, soffset),
    )


def smeme(p, sdata, op, offset, text):
    p.add(smem(sdata, op, offset), text, "isa", "I 1 0 %d 0 1 %d %d" % (sdata, op, offset))


INLINE0 = 128


def issue_tile(p, k, w, x):
    sop2e(p, SOP2_MUL, 20, 18, 22, "s_mul_i32 s22, s20, s18")
    sop2e(p, SOP2_MULHI, 20, 18, 23, "s_mul_hi_u32 s23, s20, s18")
    sop2e(p, SOP2_ADD, 22, k, 22, "s_add_u32 s22, s22, s%d" % k)
    sop2e(p, SOP2_ADDC, 23, INLINE0, 23, "s_addc_u32 s23, s23, 0")
    sop2e(p, SOP2_ADD, 4, 22, 22, "s_add_u32 s22, s4, s22")
    sop2e(p, SOP2_ADDC, 5, 23, 23, "s_addc_u32 s23, s5, s23")
    flate(p, 0, 0, 1, 23, 0, 2, 0, 22, w, "global_load_dwordx4 v[%d:%d], v2, s[22:23] nt" % (w, w + 3))
    sop2e(p, SOP2_LSHL, k, 130, 24, "s_lshl_b32 s24, s%d, 2" % k)
    sop2e(p, SOP2_LSHR, k, 158, 25, "s_lshr_b32 s25, s%d, 30" % k)
    sop2e(p, SOP2_ADD, 6, 24, 24, "s_add_u32 s24, s6, s24")
    sop2e(p, SOP2_ADDC, 7, 25, 25, "s_addc_u32 s25, s7, s25")
    for i, off in enumerate((0, 16, 32, 48)):
        vd = x + 4 * i
        flate(
            p, off, 0, 0, 23, 0, 3, 0, 24, vd,
            "global_load_dwordx4 v[%d:%d], v3, s[24:25]%s" % (vd, vd + 3, "" if off == 0 else " offset:%d" % off),
        )


def fma4(p, w, a0, a1, a2, a3):
    v1e(p, 256 + w, 86, 6, "v_cvt_pk_f32_fp8_e32 v[6:7], v%d" % w)
    v3e(p, 4, 459, 262, 256 + a0, 260, "v_fma_f32 v4, v6, v%d, v4" % a0)
    v3e(p, 4, 459, 263, 256 + a1, 260, "v_fma_f32 v4, v7, v%d, v4" % a1)
    vope(p, 144, w, 1, 16, "v_lshrrev_b32_e32 v1, 16, v%d" % w)
    v1e(p, 257, 86, 6, "v_cvt_pk_f32_fp8_e32 v[6:7], v1")
    v3e(p, 4, 459, 262, 256 + a2, 260, "v_fma_f32 v4, v6, v%d, v4" % a2)
    v3e(p, 4, 459, 263, 256 + a3, 260, "v_fma_f32 v4, v7, v%d, v4" % a3)


def compute_tile(p, w, x):
    for i in range(4):
        fma4(p, w + i, x + 4 * i, x + 4 * i + 1, x + 4 * i + 2, x + 4 * i + 3)


def wait(p, simm, text):
    p.add(sopp(12, simm), text, "isa", "I 4 %d 12" % simm)


def build_kernel():
    p = Prog()
    smeme(p, 4, 2, 0, "s_load_dwordx4 s[4:7], s[0:1], 0x0")
    smeme(p, 8, 2, 16, "s_load_dwordx4 s[8:11], s[0:1], 0x10")
    smeme(p, 12, 2, 32, "s_load_dwordx4 s[12:15], s[0:1], 0x20")
    smeme(p, 16, 2, 48, "s_load_dwordx4 s[16:19], s[0:1], 0x30")
    wait(p, 0xC07F, "s_waitcnt lgkmcnt(0)")
    vope(p, 255, 0, 0, 0x13, "v_and_b32_e32 v0, 0x3ff, v0", 0x3FF)
    sop2e(p, SOP2_AND, 19, 129, 22, "s_and_b32 s22, s19, 1")
    sopce(p, 6, 22, INLINE0, "s_cmp_eq_u32 s22, 0")
    p.branch(5, "linear", "s_cbranch_scc1")
    sop2e(p, SOP2_AND, 2, 135, 22, "s_and_b32 s22, s2, 7")
    sop2e(p, SOP2_LSHR, 2, 131, 23, "s_lshr_b32 s23, s2, 3")
    sop2e(p, SOP2_ADD, 17, 135, 24, "s_add_u32 s24, s17, 7")
    sop2e(p, SOP2_LSHR, 24, 131, 24, "s_lshr_b32 s24, s24, 3")
    sop2e(p, SOP2_MUL, 22, 24, 20, "s_mul_i32 s20, s22, s24")
    sop2e(p, SOP2_ADD, 20, 23, 20, "s_add_u32 s20, s20, s23")
    p.branch(2, "haverow", "s_branch")
    p.label("linear")
    sop1e(p, 0, 2, 20, "s_mov_b32 s20, s2")
    p.label("haverow")
    sopce(p, 9, 20, 17, "s_cmp_ge_u32 s20, s17")
    p.branch(5, "done", "s_cbranch_scc1")
    v1e(p, INLINE0, 1, 4, "v_mov_b32_e32 v4, 0")
    sop1e(p, 0, INLINE0, 21, "s_mov_b32 s21, 0")
    sop1e(p, 0, 255, 31, "s_mov_b32 s31, 0x400", 1024)
    vope(p, 132, 0, 2, 0x12, "v_lshlrev_b32_e32 v2, 4, v0")
    vope(p, 134, 0, 3, 0x12, "v_lshlrev_b32_e32 v3, 6, v0")
    p.label("pairs")
    sop2e(p, SOP2_ADD, 31, 31, 22, "s_add_u32 s22, s31, s31")
    sop2e(p, SOP2_ADD, 21, 22, 22, "s_add_u32 s22, s21, s22")
    sopce(p, 8, 22, 18, "s_cmp_gt_u32 s22, s18")
    p.branch(5, "single", "s_cbranch_scc1")
    issue_tile(p, 21, 8, 16)
    sop2e(p, SOP2_ADD, 21, 31, 30, "s_add_u32 s30, s21, s31")
    issue_tile(p, 30, 32, 36)
    wait(p, 0x0F75, "s_waitcnt vmcnt(5)")
    compute_tile(p, 8, 16)
    wait(p, 0x0F70, "s_waitcnt vmcnt(0)")
    compute_tile(p, 32, 36)
    sop2e(p, SOP2_ADD, 21, 31, 21, "s_add_u32 s21, s21, s31")
    sop2e(p, SOP2_ADD, 21, 31, 21, "s_add_u32 s21, s21, s31")
    p.branch(2, "pairs", "s_branch")
    p.label("single")
    sop2e(p, SOP2_ADD, 21, 31, 22, "s_add_u32 s22, s21, s31")
    sopce(p, 8, 22, 18, "s_cmp_gt_u32 s22, s18")
    p.branch(5, "tail", "s_cbranch_scc1")
    issue_tile(p, 21, 8, 16)
    wait(p, 0x0F70, "s_waitcnt vmcnt(0)")
    compute_tile(p, 8, 16)
    sop2e(p, SOP2_ADD, 21, 31, 21, "s_add_u32 s21, s21, s31")
    p.label("tail")
    sop1e(p, 0, INLINE0, 28, "s_mov_b32 s28, 0")
    p.label("tloop")
    sopce(p, 6, 28, 144, "s_cmp_eq_u32 s28, 16")
    p.branch(5, "reduce", "s_cbranch_scc1")
    vope(p, 21, 2, 1, 0x34, "v_add_u32_e32 v1, s21, v2")
    vope(p, 28, 1, 1, 0x34, "v_add_u32_e32 v1, s28, v1")
    v3e(p, 106, 201, 257, 18, 0, "v_cmp_lt_u32_e64 vcc, v1, s18")
    sop1e(p, 0x20, 106, 26, "s_and_saveexec_b64 s[26:27], vcc")
    sop2e(p, SOP2_MUL, 20, 18, 22, "s_mul_i32 s22, s20, s18")
    sop2e(p, SOP2_MULHI, 20, 18, 23, "s_mul_hi_u32 s23, s20, s18")
    sop2e(p, SOP2_ADD, 4, 22, 22, "s_add_u32 s22, s4, s22")
    sop2e(p, SOP2_ADDC, 5, 23, 23, "s_addc_u32 s23, s5, s23")
    vope(p, 22, 1, 8, 0x19, "v_add_co_u32_e32 v8, vcc, s22, v1")
    v1e(p, INLINE0, 1, 12, "v_mov_b32_e32 v12, 0")
    v1e(p, 23, 1, 13, "v_mov_b32_e32 v13, s23")
    vope(p, 269, 12, 9, 0x1C, "v_addc_co_u32_e32 v9, vcc, v13, v12, vcc")
    flate(p, 0, 0, 1, 16, 0, 8, 0, 127, 10, "global_load_ubyte v10, v[8:9], off nt")
    vope(p, 130, 1, 8, 0x12, "v_lshlrev_b32_e32 v8, 2, v1")
    vope(p, 158, 1, 9, 0x10, "v_lshrrev_b32_e32 v9, 30, v1")
    vope(p, 6, 8, 8, 0x19, "v_add_co_u32_e32 v8, vcc, s6, v8")
    v1e(p, 7, 1, 13, "v_mov_b32_e32 v13, s7")
    v1e(p, INLINE0, 1, 12, "v_mov_b32_e32 v12, 0")
    vope(p, 269, 9, 9, 0x1C, "v_addc_co_u32_e32 v9, vcc, v13, v9, vcc")
    flate(p, 0, 0, 0, 20, 0, 8, 0, 127, 11, "global_load_dword v11, v[8:9], off")
    wait(p, 0x0F70, "s_waitcnt vmcnt(0)")
    v1e(p, 266, 86, 6, "v_cvt_pk_f32_fp8_e32 v[6:7], v10")
    v3e(p, 4, 459, 262, 267, 260, "v_fma_f32 v4, v6, v11, v4")
    sop1e(p, 1, 26, 126, "s_mov_b64 exec, s[26:27]")
    sop2e(p, SOP2_ADD, 28, 129, 28, "s_add_u32 s28, s28, 1")
    p.branch(2, "tloop", "s_branch")
    p.label("reduce")
    for ctrl, n in ((0x118, 8), (0x114, 4), (0x112, 2), (0x111, 1)):
        dppe(p, 4, 4, 1, 4, ctrl, "v_add_f32_dpp v4, v4, v4 row_shr:%d row_mask:0xf bank_mask:0xf" % n)
    for lane, reg in ((15, 143), (31, 159), (47, 175), (63, 191)):
        v3e(p, 28 + lane // 16, 649, 260, reg, 0, "v_readlane_b32 s%d, v4, %d" % (28 + lane // 16, lane))
    v1e(p, 28, 1, 5, "v_mov_b32_e32 v5, s28")
    v1e(p, 29, 1, 6, "v_mov_b32_e32 v6, s29")
    vope(p, 261, 6, 5, 1, "v_add_f32_e32 v5, v5, v6")
    v1e(p, 30, 1, 6, "v_mov_b32_e32 v6, s30")
    v1e(p, 31, 1, 7, "v_mov_b32_e32 v7, s31")
    vope(p, 262, 7, 6, 1, "v_add_f32_e32 v6, v6, v7")
    vope(p, 261, 6, 4, 1, "v_add_f32_e32 v4, v5, v6")
    sop2e(p, SOP2_LSHL, 20, 130, 22, "s_lshl_b32 s22, s20, 2")
    sop2e(p, SOP2_ADD, 8, 22, 22, "s_add_u32 s22, s8, s22")
    sop2e(p, SOP2_ADDC, 9, INLINE0, 23, "s_addc_u32 s23, s9, 0")
    v1e(p, 22, 1, 8, "v_mov_b32_e32 v8, s22")
    v1e(p, 23, 1, 9, "v_mov_b32_e32 v9, s23")
    flate(p, 0, 0, 0, 20, 0, 8, 0, 127, 5, "global_load_dword v5, v[8:9], off")
    wait(p, 0x0F70, "s_waitcnt vmcnt(0)")
    vope(p, 260, 5, 4, 5, "v_mul_f32_e32 v4, v4, v5")
    sop2e(p, SOP2_AND, 19, 130, 22, "s_and_b32 s22, s19, 2")
    sopce(p, 6, 22, INLINE0, "s_cmp_eq_u32 s22, 0")
    p.branch(5, "nofuse", "s_cbranch_scc1")
    sop2e(p, SOP2_LSHL, 20, 130, 22, "s_lshl_b32 s22, s20, 2")
    sop2e(p, SOP2_ADD, 12, 22, 22, "s_add_u32 s22, s12, s22")
    sop2e(p, SOP2_ADDC, 13, INLINE0, 23, "s_addc_u32 s23, s13, 0")
    v1e(p, 22, 1, 8, "v_mov_b32_e32 v8, s22")
    v1e(p, 23, 1, 9, "v_mov_b32_e32 v9, s23")
    flate(p, 0, 0, 0, 20, 0, 8, 0, 127, 5, "global_load_dword v5, v[8:9], off")
    sop2e(p, SOP2_LSHL, 20, 130, 22, "s_lshl_b32 s22, s20, 2")
    sop2e(p, SOP2_ADD, 14, 22, 22, "s_add_u32 s22, s14, s22")
    sop2e(p, SOP2_ADDC, 15, INLINE0, 23, "s_addc_u32 s23, s15, 0")
    v1e(p, 22, 1, 8, "v_mov_b32_e32 v8, s22")
    v1e(p, 23, 1, 9, "v_mov_b32_e32 v9, s23")
    flate(p, 0, 0, 0, 20, 0, 8, 0, 127, 6, "global_load_dword v6, v[8:9], off")
    wait(p, 0x0F70, "s_waitcnt vmcnt(0)")
    vope(p, 260, 5, 4, 1, "v_add_f32_e32 v4, v4, v5")
    vope(p, 16, 4, 4, 5, "v_mul_f32_e32 v4, s16, v4")
    vope(p, 260, 6, 4, 5, "v_mul_f32_e32 v4, v4, v6")
    p.label("nofuse")
    sop2e(p, SOP2_AND, 19, 132, 22, "s_and_b32 s22, s19, 4")
    sopce(p, 6, 22, INLINE0, "s_cmp_eq_u32 s22, 0")
    p.branch(5, "store32", "s_cbranch_scc1")
    vope(p, 144, 4, 5, 16, "v_lshrrev_b32_e32 v5, 16, v4")
    vope(p, 129, 5, 6, 0x13, "v_and_b32_e32 v6, 1, v5")
    vope(p, 255, 6, 6, 0x34, "v_add_u32_e32 v6, 0x7fff, v6", 0x7FFF)
    vope(p, 260, 6, 6, 0x34, "v_add_u32_e32 v6, v4, v6")
    vope(p, 144, 6, 5, 16, "v_lshrrev_b32_e32 v5, 16, v6")
    v3e(p, 106, 202, 256, INLINE0, 0, "v_cmp_eq_u32_e64 vcc, v0, 0")
    sop1e(p, 0x20, 106, 26, "s_and_saveexec_b64 s[26:27], vcc")
    sop2e(p, SOP2_LSHL, 20, 129, 22, "s_lshl_b32 s22, s20, 1")
    sop2e(p, SOP2_ADD, 10, 22, 22, "s_add_u32 s22, s10, s22")
    sop2e(p, SOP2_ADDC, 11, INLINE0, 23, "s_addc_u32 s23, s11, 0")
    v1e(p, 22, 1, 8, "v_mov_b32_e32 v8, s22")
    v1e(p, 23, 1, 9, "v_mov_b32_e32 v9, s23")
    flate(p, 0, 0, 0, 26, 0, 8, 5, 127, 0, "global_store_short v[8:9], v5, off")
    sop1e(p, 1, 26, 126, "s_mov_b64 exec, s[26:27]")
    p.branch(2, "done", "s_branch")
    p.label("store32")
    v3e(p, 106, 202, 256, INLINE0, 0, "v_cmp_eq_u32_e64 vcc, v0, 0")
    sop1e(p, 0x20, 106, 26, "s_and_saveexec_b64 s[26:27], vcc")
    sop2e(p, SOP2_LSHL, 20, 130, 22, "s_lshl_b32 s22, s20, 2")
    sop2e(p, SOP2_ADD, 10, 22, 22, "s_add_u32 s22, s10, s22")
    sop2e(p, SOP2_ADDC, 11, INLINE0, 23, "s_addc_u32 s23, s11, 0")
    v1e(p, 22, 1, 8, "v_mov_b32_e32 v8, s22")
    v1e(p, 23, 1, 9, "v_mov_b32_e32 v9, s23")
    flate(p, 0, 0, 0, 28, 0, 8, 4, 127, 0, "global_store_dword v[8:9], v4, off")
    sop1e(p, 1, 26, 126, "s_mov_b64 exec, s[26:27]")
    p.label("done")
    p.add(sopp(1, 0), "s_endpgm", "isa", "I 4 0 1")
    return p


def build_probe():
    p = Prog()
    combos = [(0, 0, 0), (1, 0, 0), (0, 0, 1), (0, 1, 0), (1, 0, 1), (1, 1, 0), (0, 1, 1), (1, 1, 1)]
    for sc0, nt, sc1 in combos:
        mods = " ".join(x for x, b in (("sc0", sc0), ("nt", nt), ("sc1", sc1)) if b)
        flate(
            p, 0, sc0, nt, 23, sc1, 0, 0, 127, 0,
            "global_load_dwordx4 v[0:3], v[0:1], off" + ((" " + mods) if mods else ""),
        )
    flate(p, 0, 0, 0, 23, 0, 0, 0, 0, 0, "global_load_dwordx4 v[0:3], v0, s[0:1]")
    flate(p, 0, 0, 1, 23, 0, 0, 0, 0, 0, "global_load_dwordx4 v[0:3], v0, s[0:1] nt")
    flate(p, 16, 0, 0, 23, 0, 1, 0, 2, 4, "global_load_dwordx4 v[4:7], v1, s[2:3] offset:16")
    flate(p, 16, 0, 1, 23, 0, 1, 0, 2, 4, "global_load_dwordx4 v[4:7], v1, s[2:3] offset:16 nt")
    for sc0, nt, sc1 in combos:
        mods = " ".join(x for x, b in (("sc0", sc0), ("nt", nt), ("sc1", sc1)) if b)
        mube(
            p, 23, 1, sc0, sc1, nt, 0, 0, 0, 0x80,
            "buffer_load_dwordx4 v[0:3], v0, s[0:3], 0 offen" + ((" " + mods) if mods else ""),
        )
    for sc0, sc1 in ((0, 0), (1, 0), (0, 1), (1, 1)):
        mods = " ".join(x for x, b in (("sc0", sc0), ("sc1", sc1)) if b)
        mube(p, 40, 0, sc0, sc1, 0, 0, 0, 0, 0, "buffer_wbl2" + ((" " + mods) if mods else ""))
        mube(p, 41, 0, sc0, sc1, 0, 0, 0, 0, 0, "buffer_inv" + ((" " + mods) if mods else ""))
    for sc0, nt, sc1 in ((1, 0, 0), (1, 0, 1), (1, 1, 0), (1, 1, 1)):
        mods = " ".join(x for x, b in (("sc0", sc0), ("nt", nt), ("sc1", sc1)) if b)
        flate(p, 0, sc0, nt, 66, sc1, 0, 2, 127, 0, "global_atomic_add v0, v[0:1], v2, off " + mods)
    for nt, sc1 in ((0, 0), (0, 1), (1, 0), (1, 1)):
        mods = " ".join(x for x, b in (("nt", nt), ("sc1", sc1)) if b)
        text = "global_atomic_add v4, v2, s[6:7]" + ((" " + mods) if mods else "")
        flate(p, 0, 0, nt, 66, sc1, 4, 2, 6, 0, text)
    p.add(sopp(1, 0), "s_endpgm", "isa", "I 4 0 1")
    return p


HEAD_KERNEL = """# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
# fp8gemv_stream. Packed by gpu/amd/gfx942/hsaco.om. Bytes must match fp8gemv_stream.s
# assembled by llvm-mc-18 -triple=amdgcn -mcpu=gfx942.
# One wave, one row. Lane L owns columns k+L*16 .. +15. Weight loads are
# global_load_dwordx4 nt=1. Activation loads set no sc/nt bit. A pair of 1024-column
# tiles is issued before either tile's FMAs. Tail columns use the same lane map.
# DPP row_shr 8,4,2,1 with the assembler default row_mask and bank_mask, bound_ctrl clear.
# Then (lane15+lane31)+(lane47+lane63). y = scale[row]*acc, and if flags bit1 is set
# y = (y+residual[row])*inv_rms*gamma[row]. Bit0 remaps the workgroup id, bit2 stores bf16.
K fp8gemv_stream 64 8 0 0 32 52 0 64 64 12 0xaf0106 0x84 8
A W 0 8 0
A x 8 8 0
A scale 16 8 0
A y 24 8 0
A residual 32 8 0
A gamma 40 8 0
A inv_rms 48 4 1
A M 52 4 1
A K 56 4 1
A flags 60 4 1
"""

FMTS = """
F 1 2
B 1 0 26 6 0x30
D 1 0 0 0 6
D 1 1 0 6 7
D 1 2 0 16 1
D 1 3 0 17 1
D 1 4 0 18 8
D 1 5 1 0 21
F 2 1
B 2 0 30 2 2
D 2 0 0 0 8
D 2 1 0 8 8
D 2 2 0 16 7
D 2 3 0 23 7
F 3 1
B 3 0 23 9 0x17d
D 3 0 0 0 8
D 3 1 0 8 8
D 3 2 0 16 7
F 4 1
B 4 0 23 9 0x17f
D 4 0 0 0 16
D 4 1 0 16 7
F 5 1
B 5 0 31 1 0
D 5 0 0 0 9
D 5 1 0 9 8
D 5 2 0 17 8
D 5 3 0 25 6
F 7 2
B 7 0 26 6 0x37
D 7 0 0 0 13
D 7 1 0 13 1
D 7 2 0 14 2
D 7 3 0 16 1
D 7 4 0 17 1
D 7 5 0 18 7
D 7 6 0 25 1
D 7 7 1 0 8
D 7 8 1 8 8
D 7 9 1 16 7
D 7 10 1 23 1
D 7 11 1 24 8
F 8 1
B 8 0 25 7 0x3f
D 8 0 0 0 9
D 8 1 0 9 8
D 8 2 0 17 8
F 9 2
B 9 0 26 6 0x34
D 9 0 0 0 8
D 9 1 0 16 10
D 9 2 1 0 9
D 9 3 1 9 9
D 9 4 1 18 9
F 10 2
B 10 0 31 1 0
D 10 0 0 0 9
D 10 1 0 9 8
D 10 2 0 17 8
D 10 3 0 25 6
D 10 4 1 0 8
D 10 5 1 8 9
D 10 6 1 24 4
D 10 7 1 28 4
F 11 1
B 11 0 23 9 0x17e
D 11 0 0 0 8
D 11 1 0 8 8
D 11 2 0 16 7
F 12 2
B 12 0 26 6 0x38
D 12 0 0 0 12
D 12 1 0 12 1
D 12 2 0 13 1
D 12 3 0 14 1
D 12 4 0 15 1
D 12 5 0 17 1
D 12 6 0 18 7
D 12 7 1 0 8
D 12 8 1 8 8
D 12 9 1 16 5
D 12 10 1 24 8
"""

HEAD_PROBE = """# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
# Every cache-policy encoding the writer emits for this kernel family.
# Field positions are the ones that reproduce llvm-mc-18 -mcpu=gfx942.
K encprobe 8 8 0 0 16 8 0 64 64 2 0xaf0081 0x84 8
A p 0 8 0
"""


def write_pair(stem, header, prog, asm_header):
    raw, isa, asm = prog.layout()
    isa_path = os.path.join(ROOT, stem + ".isa")
    s_path = os.path.join(ROOT, stem + ".s")
    with open(isa_path, "w") as f:
        f.write(header)
        f.write(FMTS)
        f.write("\n".join(isa))
        f.write("\n")
    with open(s_path, "w") as f:
        f.write(asm_header)
        f.write(".text\n")
        f.write("\n".join(asm))
        f.write("\n")
    return raw


def main():
    k = write_pair(
        "fp8gemv_stream",
        HEAD_KERNEL,
        build_kernel(),
        "// fp8gemv_stream, gfx942. Same words as fp8gemv_stream.isa.\n",
    )
    e = write_pair(
        "encprobe",
        HEAD_PROBE,
        build_probe(),
        "// encprobe, gfx942. Same words as encprobe.isa.\n",
    )
    print("kernel", len(k), "probe", len(e))


if __name__ == "__main__":
    main()
