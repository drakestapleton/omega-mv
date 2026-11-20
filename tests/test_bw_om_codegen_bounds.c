/* SPDX-License-Identifier: Apache-2.0
 * Host boundary & metrics verification for pure OM-2 Blackwell codegen emitters:
 *   1) Negative / fail-closed boundary checks on omega_bw_ir_from_om
 *   2) Error-path checks through omega2_cg_gemm_emit and omega_blackwell_codegen_fp8gemm_prog
 *   3) Compiled kernel metrics (insns, peak/declared GPRs, occupancy, avg stalls, SM121 SASS SHA-256)
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "omega_bw_om_ir.h"
#include "omega_native.h"
#include "omega_blackwell_codegen_gemm.h"
#include "omega_blackwell_codegen_bf16.h"
#include "omega_blackwell_codegen_moe.h"
#include "omega_blackwell_codegen_moe2.h"
#include "omega_blackwell_codegen_pf.h"
#include "omega_blackwell_codegen_pfhost.h"
#include "omega_blackwell_codegen_qmma.h"
#include "omega_blackwell_codegen_tgemm.h"
#include "omega_blackwell_codegen_tc2.h"
#include "omega_blackwell_codegen_qg.h"
#include "omega_blackwell_codegen_tc.h"
#include "omega_blackwell_codegen_pattn256.h"
#include "omega_blackwell_codegen_router.h"
#include "omega_blackwell_codegen_pattn.h"
#include "omega_blackwell_codegen_attn.h"
#include "sha256.h"

static int g_pass = 0, g_fail = 0;
#define CHK(cond, msg) do { \
    if (cond) { g_pass++; } \
    else { g_fail++; printf("FAIL: %s\n", (msg)); } \
} while (0)

static void make_valid_minimal(uint64_t ins[8192], uint64_t meta[512]) {
    memset(ins, 0, 8192u * sizeof(uint64_t));
    memset(meta, 0, 512u * sizeof(uint64_t));
    meta[0] = 2; /* n = 2: EXIT + BRA self */
    meta[1] = 1; /* nv = 1 */
    meta[2] = 1; /* nu = 1 */
    meta[3] = 0; /* nl = 0 */
    meta[64] = 1;  /* v0 width 1 */
    meta[352] = 2; /* u0 width 2 */
    /* ins 0: EXIT */
    ins[0] = BW_IR_EXIT;
    for (int k = 1; k <= 5; k++) ins[k] = (uint64_t)-1;
    ins[6] = ((uint64_t)0x000fc000u << 32);
    ins[7] = 0;
    /* ins 1: BRA self */
    ins[8] = BW_IR_BRA;
    for (int k = 1; k <= 5; k++) ins[8 + k] = (uint64_t)-1;
    ins[14] = ((uint64_t)0x000fc000u << 32);
    ins[15] = 0;
}

static void test_unpacker_bounds(void) {
    static uint64_t ins[8192], meta[512];
    static BlackwellIRProgram prog;

    make_valid_minimal(ins, meta);
    CHK(omega_bw_ir_from_om(ins, meta, &prog) == 0 && prog.count == 2, "valid minimal unpack");

    /* NULL pointers */
    CHK(omega_bw_ir_from_om(NULL, meta, &prog) != 0, "reject NULL ins");
    CHK(omega_bw_ir_from_om(ins, NULL, &prog) != 0, "reject NULL meta");
    CHK(omega_bw_ir_from_om(ins, meta, NULL) != 0, "reject NULL prog");

    /* meta[5] error flag */
    make_valid_minimal(ins, meta);
    meta[5] = 1;
    CHK(omega_bw_ir_from_om(ins, meta, &prog) != 0, "reject meta[5] != 0");

    /* empty / overflow instruction count */
    make_valid_minimal(ins, meta);
    meta[0] = 0;
    CHK(omega_bw_ir_from_om(ins, meta, &prog) != 0, "reject n == 0");

    make_valid_minimal(ins, meta);
    meta[0] = BW_MAX_IR_INSNS + 1u;
    CHK(omega_bw_ir_from_om(ins, meta, &prog) != 0, "reject n > BW_MAX_IR_INSNS");

    /* vreg / uvreg / loop count overflow */
    make_valid_minimal(ins, meta);
    meta[1] = BW_MAX_VREGS + 1u;
    CHK(omega_bw_ir_from_om(ins, meta, &prog) != 0, "reject nv > BW_MAX_VREGS");

    make_valid_minimal(ins, meta);
    meta[2] = BW_MAX_UVREGS + 1u;
    CHK(omega_bw_ir_from_om(ins, meta, &prog) != 0, "reject nu > BW_MAX_UVREGS");

    make_valid_minimal(ins, meta);
    meta[3] = 17;
    CHK(omega_bw_ir_from_om(ins, meta, &prog) != 0, "reject nl > 16");

    /* invalid vreg / uvreg widths */
    make_valid_minimal(ins, meta);
    meta[64] = 3;
    CHK(omega_bw_ir_from_om(ins, meta, &prog) != 0, "reject invalid vreg width 3");

    make_valid_minimal(ins, meta);
    meta[64] = 0;
    CHK(omega_bw_ir_from_om(ins, meta, &prog) != 0, "reject invalid vreg width 0");

    make_valid_minimal(ins, meta);
    meta[352] = 4;
    CHK(omega_bw_ir_from_om(ins, meta, &prog) != 0, "reject invalid uvreg width 4");

    /* invalid opcode */
    make_valid_minimal(ins, meta);
    ins[0] = (uint64_t)-1;
    CHK(omega_bw_ir_from_om(ins, meta, &prog) != 0, "reject negative opcode");

    make_valid_minimal(ins, meta);
    ins[0] = (uint64_t)BW_IR_ATOMG_ADD_F32_STRONG_GPU + 1u;
    CHK(omega_bw_ir_from_om(ins, meta, &prog) != 0, "reject out-of-range opcode");

    /* out-of-range vreg, subreg, ureg, bar_reg, reserved flags */
    make_valid_minimal(ins, meta);
    ins[2] = 1; /* src1 = v1 >= nv(1) */
    CHK(omega_bw_ir_from_om(ins, meta, &prog) != 0, "reject src1 >= nv");

    make_valid_minimal(ins, meta);
    ins[2] = 0;
    ins[7] = ((uint64_t)1u << 24); /* src1_subreg = 1 >= width(1) */
    CHK(omega_bw_ir_from_om(ins, meta, &prog) != 0, "reject src1_subreg >= width");

    make_valid_minimal(ins, meta);
    ins[5] = 1; /* ureg = u1 >= nu(1) */
    CHK(omega_bw_ir_from_om(ins, meta, &prog) != 0, "reject ureg >= nu");

    make_valid_minimal(ins, meta);
    ins[7] = ((uint64_t)BW_RECONV_MAX_BAR << 8);
    CHK(omega_bw_ir_from_om(ins, meta, &prog) != 0, "reject bar_reg >= BW_RECONV_MAX_BAR");

    make_valid_minimal(ins, meta);
    ins[7] = ((uint64_t)1u << 48);
    CHK(omega_bw_ir_from_om(ins, meta, &prog) != 0, "reject reserved r[7] high bits");

    /* invalid loop bounds */
    make_valid_minimal(ins, meta);
    meta[3] = 1; meta[320] = 1; meta[321] = 0; /* start > end */
    CHK(omega_bw_ir_from_om(ins, meta, &prog) != 0, "reject loop start > end");

    make_valid_minimal(ins, meta);
    meta[3] = 1; meta[320] = 0; meta[321] = 2; /* end >= n */
    CHK(omega_bw_ir_from_om(ins, meta, &prog) != 0 && prog.count == 0 && prog.regalloc.num_vregs == 0,
        "reject loop end >= n without partial prog residue");

    /* mid-stream invalid opcode must leave prog completely cleared (no partial program accepted) */
    make_valid_minimal(ins, meta);
    ins[8] = (uint64_t)BW_IR_ATOMG_ADD_F32_STRONG_GPU + 99u; /* ins 0 valid, ins 1 invalid */
    CHK(omega_bw_ir_from_om(ins, meta, &prog) != 0 && prog.count == 0 && prog.regalloc.num_vregs == 0 && prog.regalloc.num_uvregs == 0,
        "reject mid-stream invalid opcode with zero partial residue");
}

static void test_qmma_and_pfhost_error_paths(void) {
    static BlackwellIRProgram prog;

    /* QMMA probe invalid specs */
    prog.count = 77;
    CHK(omega_blackwell_codegen_qmma_probe_prog(-1, 0, &prog) != 0 && prog.count == 0, "qmma_probe mutant=-1");
    prog.count = 77;
    CHK(omega_blackwell_codegen_qmma_probe_prog(2, 0, &prog) != 0 && prog.count == 0, "qmma_probe mutant=2");
    prog.count = 77;
    CHK(omega_blackwell_codegen_qmma_probe_prog(0, 17, &prog) != 0 && prog.count == 0, "qmma_probe wait_nops=17");

    /* QMMA peak invalid specs */
    struct { uint32_t iters, chains, stall, threads; const char *name; } qbad[] = {
        { 0, 4, 4, 256, "qmma_peak iters=0" },
        { 8, 0, 4, 256, "qmma_peak chains=0" },
        { 8, 17, 4, 256, "qmma_peak chains=17" },
        { 8, 4, 0, 256, "qmma_peak stall=0" },
        { 8, 4, 16, 256, "qmma_peak stall=16" },
        { 8, 4, 4, 0, "qmma_peak threads=0" },
        { 8, 4, 4, 33, "qmma_peak threads=33" },
        { 8, 4, 4, 1056, "qmma_peak threads=1056" },
    };
    for (size_t i = 0; i < sizeof(qbad) / sizeof(qbad[0]); i++) {
        prog.count = 77;
        CHK(omega_blackwell_codegen_qmma_peak_prog(qbad[i].iters, qbad[i].chains, qbad[i].stall, qbad[i].threads, &prog) != 0 && prog.count == 0,
            qbad[i].name);
    }

    /* pfhost router logits (rl) invalid specs */
    OmegaRlSpec rbad[] = {
        { .k = 0,     .e = 128,  .t = 4,  .mutant = 0 },
        { .k = 64,    .e = 128,  .t = 4,  .mutant = 0 },
        { .k = 16512, .e = 128,  .t = 4,  .mutant = 0 },
        { .k = 2048,  .e = 16,   .t = 4,  .mutant = 0 },
        { .k = 2048,  .e = 1056, .t = 4,  .mutant = 0 },
        { .k = 2048,  .e = 128,  .t = 0,  .mutant = 0 },
        { .k = 2048,  .e = 128,  .t = 17, .mutant = 0 },
        { .k = 2048,  .e = 128,  .t = 3,  .mutant = 0 }, /* t % (e/32) != 0 */
        { .k = 2048,  .e = 128,  .t = 4,  .mutant = 3 },
    };
    for (size_t i = 0; i < sizeof(rbad) / sizeof(rbad[0]); i++) {
        prog.count = 77;
        CHK(omega_blackwell_codegen_rl_prog(&rbad[i], &prog) != 0 && prog.count == 0, "rl rejects invalid spec cleanly");
        CHK(!omega_rl_spec_ok(&rbad[i]) && omega_rl_shared_bytes(&rbad[i]) == 0, "rl helpers refuse invalid spec");
    }

    /* pfhost MoE combine (mc) invalid specs */
    OmegaMcSpec mbad[] = {
        { .h = 0,    .top_k = 8,  .mutant = 0 },
        { .h = 2,    .top_k = 8,  .mutant = 0 },
        { .h = 2048, .top_k = 0,  .mutant = 0 },
        { .h = 2048, .top_k = 3,  .mutant = 0 },
        { .h = 2048, .top_k = 20, .mutant = 0 },
        { .h = 2048, .top_k = 8,  .mutant = 3 },
    };
    for (size_t i = 0; i < sizeof(mbad) / sizeof(mbad[0]); i++) {
        prog.count = 77;
        CHK(omega_blackwell_codegen_mc_prog(&mbad[i], &prog) != 0 && prog.count == 0, "mc rejects invalid spec cleanly");
        CHK(!omega_mc_spec_ok(&mbad[i]), "mc_spec_ok refuses invalid spec");
    }
}

static void check_max_headroom(const char *name, const BlackwellIRProgram *p) {
    static uint8_t code[BW_MAX_IR_INSNS * 16];
    size_t len = 0;
    int enc = omega_bw_encode_program(p, code, sizeof code, &len);
    size_t want = omega_bw_program_code_bytes(p);
    CHK(enc == 0 && len == want && want >= p->count * 16u, name);
    printf("HEADROOM %-32s insns=%3zu/%d vregs=%3d/%d uvregs=%2d/%d\n",
           name, p->count, BW_MAX_IR_INSNS,
           p->regalloc.num_vregs, BW_MAX_VREGS,
           p->regalloc.num_uvregs, BW_MAX_UVREGS);
    CHK(p->count <= BW_MAX_IR_INSNS, "insns within BW_MAX_IR_INSNS");
    CHK(p->regalloc.num_vregs <= BW_MAX_VREGS, "vregs within BW_MAX_VREGS");
    CHK(p->regalloc.num_uvregs <= BW_MAX_UVREGS, "uvregs within BW_MAX_UVREGS");
}

static void test_max_size_legal_inputs(void) {
    static BlackwellIRProgram p;
    {
        OmegaFp8GemmSpec s = { .k = 32768, .lane_bytes = 16, .mt = 8, .warps = 16, .mutant = 0, .rowmap = 0 };
        CHK(omega_blackwell_codegen_fp8gemm_prog(&s, &p) == 0, "max legal gemm k32768 mt8");
        check_max_headroom("max_gemm_k32768_mt8", &p);
    }
    {
        OmegaBf16GemvSpec s = { .k = 5120, .rows = 1, .warps = 16, .depth = 5, .mutant = 0, .ystride = 248320, .xbatch = 4, .mask = 0 };
        CHK(omega_blackwell_codegen_bf16_gemv_prog(&s, &p) == 0, "max legal bf16 k5120 xb4");
        check_max_headroom("max_bf16_k5120_xb4", &p);
    }
    {
        OmegaBf16GemvSpec s = { .k = 5120, .rows = 1, .warps = 16, .depth = 5, .mutant = 0, .ystride = 0, .xbatch = 0, .mask = 1 };
        CHK(omega_blackwell_codegen_bf16_gemv_prog(&s, &p) == 0, "max legal bf16 k5120 mask");
        check_max_headroom("max_bf16_k5120_mask", &p);
    }
    {
        OmegaFp8GemvSpec s = { .k = 17408, .lane_bytes = 16, .rows = 1, .warps = 16, .mutant = 0, .depth = 2, .sched = 1, .coal = 1, .wfirst = 1 };
        CHK(omega_blackwell_codegen_fp8_gemv_prog(&s, &p) == 0, "max legal moe k17408");
        check_max_headroom("max_moe_k17408_d2_s1", &p);
    }
    {
        OmegaFp8GemvSpec s = { .k = 4096, .lane_bytes = 16, .rows = 1, .warps = 16, .mutant = 0 };
        CHK(omega_blackwell_codegen_fp8_gemv2_prog(&s, &p) == 0, "max legal moe2 k4096");
        check_max_headroom("max_moe2_k4096_w16", &p);
    }
    {
        CHK(omega_blackwell_codegen_qmma_probe_prog(0, 16, &p) == 0, "max legal qmma_probe wait16");
        check_max_headroom("max_qmma_probe_w16", &p);
    }
    {
        CHK(omega_blackwell_codegen_qmma_peak_prog(1024, 16, 15, 1024, &p) == 0, "max legal qmma_peak c16 t1024");
        check_max_headroom("max_qmma_peak_c16_t1024", &p);
    }
    {
        CHK(omega_blackwell_codegen_f2e4_probe_prog(&p) == 0, "legal f2e4_probe");
        check_max_headroom("f2e4_probe", &p);
    }
    {
        OmegaRlSpec s = { .k = 16384, .e = 32, .t = 16, .mutant = 0 };
        CHK(omega_blackwell_codegen_rl_prog(&s, &p) == 0, "max legal rl k16384 e32 t16");
        check_max_headroom("max_rl_k16384_e32_t16", &p);
    }
    {
        OmegaRlSpec s = { .k = 16384, .e = 512, .t = 16, .mutant = 0 };
        CHK(omega_blackwell_codegen_rl_prog(&s, &p) == 0, "max legal rl k16384 e512 t16");
        check_max_headroom("max_rl_k16384_e512_t16", &p);
    }
    {
        OmegaMcSpec s = { .h = 4096, .top_k = 16, .mutant = 0 };
        CHK(omega_blackwell_codegen_mc_prog(&s, &p) == 0, "max legal mc h4096 topk16");
        check_max_headroom("max_mc_h4096_topk16", &p);
    }
    {
        OmegaTgemmSpec s = { .k = 2304, .n = 768, .rt = 8, .ct = 2, .warps = 16, .kc = 32, .aqn = 1, .layout = 0, .epi = 0, .mutant = 0 };
        CHK(omega_blackwell_codegen_tgemm_prog(&s, &p) == 0, "max legal tgemm rt8 w16 aqn1");
        check_max_headroom("max_tgemm_k2304_rt8_w16", &p);
    }
    {
        OmegaTc2Spec s = { .k = 2048, .rt = 8, .ct = 2, .warps = 16, .aqn = 2, .epi = OMEGA_TC2_EPI_F32, .direct = 0, .n = 2048, .mutant = 0 };
        CHK(omega_blackwell_codegen_tc2_prog(&s, &p) == 0, "max legal tc2 f32 rt8 w16");
        check_max_headroom("max_tc2_f32_rt8_w16", &p);
    }
    {
        OmegaTc2Spec s = { .k = 2048, .rt = 8, .ct = 2, .warps = 16, .aqn = 2, .epi = OMEGA_TC2_EPI_SWIGLU, .direct = 0, .n = 1536, .mutant = 0 };
        CHK(omega_blackwell_codegen_tc2_prog(&s, &p) == 0, "max legal tc2 swiglu rt8 w16");
        check_max_headroom("max_tc2_swiglu_rt8_w16", &p);
    }
    {
        OmegaPqSpec s = { .k = 32768, .in_type = OMEGA_QG_IN_BF16, .mutant = 0, .groups = 32 };
        CHK(omega_blackwell_codegen_pq_prog(&s, &p) == 0, "max legal pq k32768 bf16 g32");
        check_max_headroom("max_pq_k32768_bf16_g32", &p);
    }
    {
        OmegaQgSpec s = { .k = 2048, .rt = 4, .warps = 8, .epi = OMEGA_QG_EPI_SWIGLU, .direct = 0, .n = 1536, .wait = 24, .mutant = 0 };
        CHK(omega_blackwell_codegen_qgemm_prog(&s, &p) == 0, "max legal qgemm swiglu rt4 w8");
        check_max_headroom("max_qgemm_swiglu_rt4_w8", &p);
    }
    {
        OmegaTcGemmSpec s = { .k = 2048, .rt = 4, .ct = 2, .warps = 8, .mutant = 0 };
        CHK(omega_blackwell_codegen_tcgemm_prog(&s, &p) == 0, "max legal tcgemm rt4 ct2 w8");
        check_max_headroom("max_tcgemm_rt4_ct2_w8", &p);
    }
}

static void test_qg_and_tc_error_paths(void) {
    static BlackwellIRProgram prog;
    CHK(omega_blackwell_codegen_pq_prog(NULL, &prog) != 0 && prog.count == 0, "pq NULL spec");
    OmegaPqSpec pq_bad[] = {
        { .k = 64,   .in_type = 0, .mutant = 0,  .groups = 0 },
        { .k = 128,  .in_type = 2, .mutant = 0,  .groups = 0 },
        { .k = 128,  .in_type = 0, .mutant = -1, .groups = 0 },
        { .k = 128,  .in_type = 0, .mutant = 4,  .groups = 0 },
        { .k = 5120, .in_type = 0, .mutant = 0,  .groups = 0 },
    };
    for (size_t i = 0; i < sizeof(pq_bad) / sizeof(pq_bad[0]); i++) {
        prog.count = 44;
        CHK(omega_blackwell_codegen_pq_prog(&pq_bad[i], &prog) != 0 && prog.count == 0, "pq invalid spec");
    }
    CHK(omega_blackwell_codegen_qgemm_prog(NULL, &prog) != 0 && prog.count == 0, "qgemm NULL spec");
    OmegaQgSpec qg_bad[] = {
        { .k = 64,  .rt = 4, .warps = 8, .epi = 0, .direct = 0, .n = 256, .wait = 24, .mutant = 0 },
        { .k = 128, .rt = 8, .warps = 8, .epi = 0, .direct = 0, .n = 256, .wait = 24, .mutant = 0 },
        { .k = 128, .rt = 4, .warps = 4, .epi = 0, .direct = 0, .n = 256, .wait = 24, .mutant = 0 },
        { .k = 128, .rt = 4, .warps = 8, .epi = 2, .direct = 0, .n = 256, .wait = 24, .mutant = 0 },
        { .k = 128, .rt = 4, .warps = 8, .epi = 0, .direct = 0, .n = 256, .wait = 121,.mutant = 0 },
        { .k = 128, .rt = 4, .warps = 8, .epi = 0, .direct = 0, .n = 256, .wait = 24, .mutant = -1 },
    };
    for (size_t i = 0; i < sizeof(qg_bad) / sizeof(qg_bad[0]); i++) {
        prog.count = 45;
        CHK(omega_blackwell_codegen_qgemm_prog(&qg_bad[i], &prog) != 0 && prog.count == 0, "qgemm invalid spec");
        CHK(omega_qg_shared_bytes(&qg_bad[i]) == 0 && omega_qg_span(&qg_bad[i]) == 0, "qg helpers 0");
    }
    prog.count = 46;
    CHK(omega_blackwell_codegen_tc_probe_prog(-1, &prog) != 0 && prog.count == 0, "tc_probe mutant -1");
    prog.count = 46;
    CHK(omega_blackwell_codegen_tc_probe_prog(2, &prog) != 0 && prog.count == 0, "tc_probe mutant 2");
    prog.count = 47;
    CHK(omega_blackwell_codegen_tc_peak_prog(0, 4, 8, 32, &prog) != 0 && prog.count == 0, "tc_peak iters 0");
    prog.count = 47;
    CHK(omega_blackwell_codegen_tc_peak_prog(16, 17, 8, 32, &prog) != 0 && prog.count == 0, "tc_peak chains 17");
    prog.count = 48;
    CHK(omega_blackwell_codegen_tc_bw_prog(0, 1, 32, &prog) != 0 && prog.count == 0, "tc_bw iters 0");
    prog.count = 48;
    CHK(omega_blackwell_codegen_tc_bw_prog(16, 1, 16, &prog) != 0 && prog.count == 0, "tc_bw threads 16");
    CHK(omega_blackwell_codegen_tcgemm_prog(NULL, &prog) != 0 && prog.count == 0, "tcgemm NULL spec");
    OmegaTcGemmSpec tc_bad[] = {
        { .k = 64,  .rt = 2, .ct = 2, .warps = 4, .mutant = 0 },
        { .k = 128, .rt = 1, .ct = 2, .warps = 4, .mutant = 0 },
        { .k = 128, .rt = 2, .ct = 2, .warps = 4, .mutant = -1 },
        { .k = 128, .rt = 2, .ct = 2, .warps = 4, .mutant = 5 },
    };
    for (size_t i = 0; i < sizeof(tc_bad) / sizeof(tc_bad[0]); i++) {
        prog.count = 49;
        CHK(omega_blackwell_codegen_tcgemm_prog(&tc_bad[i], &prog) != 0 && prog.count == 0, "tcgemm invalid spec");
        CHK(omega_tcgemm_shared_bytes(&tc_bad[i]) == 0 && omega_tcgemm_span(&tc_bad[i]) == 0, "tcgemm helpers 0");
    }
}

static void test_tgemm_and_tc2_error_paths(void) {
    static BlackwellIRProgram prog;
    CHK(omega_blackwell_codegen_tgemm_prog(NULL, &prog) != 0 && prog.count == 0, "tgemm NULL spec");
    OmegaTgemmSpec tg_bad[] = {
        { .k = 64,   .n = 256, .rt = 4, .ct = 2, .warps = 8,  .kc = 32, .aqn = 2, .layout = 0, .epi = 0, .mutant = 0 },
        { .k = 128,  .n = 256, .rt = 3, .ct = 2, .warps = 8,  .kc = 32, .aqn = 2, .layout = 0, .epi = 0, .mutant = 0 },
        { .k = 128,  .n = 256, .rt = 4, .ct = 1, .warps = 8,  .kc = 32, .aqn = 2, .layout = 0, .epi = 0, .mutant = 0 },
        { .k = 128,  .n = 256, .rt = 4, .ct = 2, .warps = 4,  .kc = 32, .aqn = 2, .layout = 0, .epi = 0, .mutant = 0 },
        { .k = 128,  .n = 256, .rt = 4, .ct = 2, .warps = 8,  .kc = 32, .aqn = 2, .layout = 0, .epi = 0, .mutant = -1 },
        { .k = 128,  .n = 256, .rt = 4, .ct = 2, .warps = 8,  .kc = 32, .aqn = 2, .layout = 0, .epi = 0, .mutant = 6 },
    };
    for (size_t i = 0; i < sizeof(tg_bad) / sizeof(tg_bad[0]); i++) {
        prog.count = 55;
        CHK(omega_blackwell_codegen_tgemm_prog(&tg_bad[i], &prog) != 0 && prog.count == 0, "tgemm invalid spec");
        CHK(omega_tgemm_shared_bytes(&tg_bad[i]) == 0 && omega_tgemm_span(&tg_bad[i]) == 0 && omega_tgemm_bm(&tg_bad[i]) == 0, "tgemm helpers 0");
    }
    CHK(omega_blackwell_codegen_tc2_prog(NULL, &prog) != 0 && prog.count == 0, "tc2 NULL spec");
    OmegaTc2Spec tc_bad[] = {
        { .k = 64,   .rt = 4, .ct = 2, .warps = 8,  .aqn = 2, .epi = 0, .direct = 0, .n = 256, .mutant = 0 },
        { .k = 128,  .rt = 3, .ct = 2, .warps = 8,  .aqn = 2, .epi = 0, .direct = 0, .n = 256, .mutant = 0 },
        { .k = 128,  .rt = 4, .ct = 1, .warps = 8,  .aqn = 2, .epi = 0, .direct = 0, .n = 256, .mutant = 0 },
        { .k = 128,  .rt = 4, .ct = 2, .warps = 2,  .aqn = 2, .epi = 0, .direct = 0, .n = 256, .mutant = 0 },
        { .k = 128,  .rt = 4, .ct = 2, .warps = 8,  .aqn = 2, .epi = 2, .direct = 0, .n = 256, .mutant = 0 },
        { .k = 128,  .rt = 4, .ct = 2, .warps = 8,  .aqn = 2, .epi = 0, .direct = 2, .n = 256, .mutant = 0 },
        { .k = 128,  .rt = 4, .ct = 2, .warps = 8,  .aqn = 2, .epi = 0, .direct = 0, .n = 256, .mutant = -1 },
        { .k = 128,  .rt = 4, .ct = 2, .warps = 8,  .aqn = 2, .epi = 0, .direct = 0, .n = 256, .mutant = 5 },
    };
    for (size_t i = 0; i < sizeof(tc_bad) / sizeof(tc_bad[0]); i++) {
        prog.count = 66;
        CHK(omega_blackwell_codegen_tc2_prog(&tc_bad[i], &prog) != 0 && prog.count == 0, "tc2 invalid spec");
        CHK(omega_tc2_shared_bytes(&tc_bad[i]) == 0 && omega_tc2_span(&tc_bad[i]) == 0, "tc2 helpers 0");
    }
}

static void test_gemm_error_paths(void) {
    static BlackwellIRProgram prog;
    static uint64_t ins[8192], meta[512];

    CHK(omega_blackwell_codegen_fp8gemm_prog(NULL, &prog) != 0, "gemm NULL spec");
    OmegaFp8GemmSpec ok = { .k = 2048, .lane_bytes = 16, .mt = 8, .warps = 16, .mutant = 0, .rowmap = 0 };
    CHK(omega_blackwell_codegen_fp8gemm_prog(&ok, NULL) != 0, "gemm NULL prog");

    /* Every invalid spec mutation must fail both omega2_cg_gemm_emit and C wrapper, leaving prog.count == 0 */
    OmegaFp8GemmSpec bads[] = {
        { .k = 0,     .lane_bytes = 16, .mt = 8, .warps = 16, .mutant = 0, .rowmap = 0 }, /* k == 0 */
        { .k = 32896, .lane_bytes = 16, .mt = 8, .warps = 16, .mutant = 0, .rowmap = 0 }, /* k > 32768 */
        { .k = 2000,  .lane_bytes = 16, .mt = 8, .warps = 16, .mutant = 0, .rowmap = 0 }, /* k % 128 != 0 */
        { .k = 2560,  .lane_bytes = 16, .mt = 8, .warps = 16, .mutant = 0, .rowmap = 0 }, /* odd ks = 5 > 3 */
        { .k = 2048,  .lane_bytes = 4,  .mt = 8, .warps = 16, .mutant = 0, .rowmap = 0 }, /* bad lane_bytes */
        { .k = 2048,  .lane_bytes = 16, .mt = 0, .warps = 16, .mutant = 0, .rowmap = 0 }, /* mt == 0 */
        { .k = 2048,  .lane_bytes = 16, .mt = 6, .warps = 16, .mutant = 0, .rowmap = 0 }, /* non-pow2 mt */
        { .k = 2048,  .lane_bytes = 16, .mt = 16,.warps = 16, .mutant = 0, .rowmap = 0 }, /* shm > 16384 */
        { .k = 2048,  .lane_bytes = 16, .mt = 8, .warps = 0,  .mutant = 0, .rowmap = 0 }, /* warps == 0 */
        { .k = 2048,  .lane_bytes = 16, .mt = 8, .warps = 12, .mutant = 0, .rowmap = 0 }, /* non-pow2 warps */
        { .k = 2048,  .lane_bytes = 16, .mt = 8, .warps = 16, .mutant = -1,.rowmap = 0 }, /* negative mutant */
        { .k = 2048,  .lane_bytes = 16, .mt = 8, .warps = 16, .mutant = 5, .rowmap = 0 }, /* mutant > 4 */
        { .k = 2048,  .lane_bytes = 16, .mt = 8, .warps = 16, .mutant = 0, .rowmap = 1 }, /* rowmap + mt > 4 */
        { .k = 2048,  .lane_bytes = 16, .mt = 4, .warps = 16, .mutant = 0, .rowmap = 2 }, /* rowmap > 1 */
    };
    for (size_t i = 0; i < sizeof(bads) / sizeof(bads[0]); i++) {
        uint64_t sp[8] = { bads[i].k, bads[i].lane_bytes, bads[i].mt, bads[i].warps, (uint64_t)(uint32_t)bads[i].mutant, bads[i].rowmap, 0, 0 };
        uint64_t rc = 0;
        uint32_t st = omega2_cg_gemm_emit(&rc, sp, 8u, ins, 8192u, meta, 512u);
        CHK(st == 0 && rc != 0, "omega2_cg_gemm_emit refuses invalid spec");
        prog.count = 77;
        CHK(omega_blackwell_codegen_fp8gemm_prog(&bads[i], &prog) != 0 && prog.count == 0, "C wrapper refuses invalid spec cleanly");
        CHK(omega_fp8gemm_steps(&bads[i]) == 0 && omega_fp8gemm_shared_bytes(&bads[i]) == 0, "gemm helpers return 0 on invalid spec");
    }
}

static void report_kernel(const char *name, const BlackwellIRProgram *p, uint32_t warps_per_cta) {
    static uint8_t code[BW_MAX_IR_INSNS * 16];
    size_t len = 0;
    if (omega_bw_encode_program(p, code, sizeof code, &len) != 0) {
        printf("METRIC %-36s ENCODE_FAIL\n", name);
        g_fail++;
        return;
    }
    uint8_t digest[32];
    sha256_hash(code, len, digest);
    uint32_t peak = p->regalloc.peak_gpr_usage;
    uint32_t decl = ((peak + 7u) / 8u) * 8u;
    if (decl < 24u) decl = 24u;
    /* SM121: 65536 32-bit regs/SM, max 48 warps/SM, CTA regs = warps * 32 * decl */
    uint32_t max_ctas = (65536u / (warps_per_cta * 32u * decl));
    uint32_t occ_warps = max_ctas * warps_per_cta;
    if (occ_warps > 48u) occ_warps = 48u;
    uint64_t sum_stall = 0;
    for (size_t i = 0; i < p->count; i++) sum_stall += (p->insns[i].control >> 9) & 0xfu;
    double avg_stall = p->count ? (double)sum_stall / (double)p->count : 0.0;
    printf("METRIC %-36s insns=%3zu gpr=%3u decl=%3u occ=%2u/48 avg_stall=%.2f sha256=%02x%02x%02x%02x%02x%02x%02x%02x\n",
           name, p->count, peak, decl, occ_warps, avg_stall,
           digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7]);
}

static void dump_metrics(void) {
    static BlackwellIRProgram p;
    {
        OmegaBf16GemvSpec s = { .k = 5120, .rows = 1, .warps = 16, .depth = 5, .mutant = 0, .ystride = 0, .xbatch = 0, .mask = 0 };
        CHK(omega_blackwell_codegen_bf16_gemv_prog(&s, &p) == 0, "bf16 plain k5120");
        report_kernel("bf16_plain_k5120_w16_d5", &p, 16);
    }
    {
        OmegaBf16GemvSpec s = { .k = 5120, .rows = 1, .warps = 16, .depth = 5, .mutant = 0, .ystride = 248320, .xbatch = 4, .mask = 0 };
        CHK(omega_blackwell_codegen_bf16_gemv_prog(&s, &p) == 0, "bf16 xb4 k5120");
        report_kernel("bf16_xb4_k5120_w16_d5", &p, 16);
    }
    {
        OmegaFp8GemmSpec s = { .k = 5120, .lane_bytes = 16, .mt = 8, .warps = 16, .mutant = 0, .rowmap = 0 };
        CHK(omega_blackwell_codegen_fp8gemm_prog(&s, &p) == 0, "fp8gemm k5120 mt8");
        report_kernel("fp8gemm_k5120_mt8_w16", &p, 16);
    }
    {
        OmegaFp8GemmSpec s = { .k = 17408, .lane_bytes = 16, .mt = 4, .warps = 16, .mutant = 0, .rowmap = 1 };
        CHK(omega_blackwell_codegen_fp8gemm_prog(&s, &p) == 0, "fp8gemm rowmap k17408");
        report_kernel("fp8gemm_rm_k17408_mt4_w16", &p, 16);
    }
    {
        OmegaFp8GemvSpec s = { .k = 5120, .lane_bytes = 16, .rows = 1, .warps = 8, .mutant = 0, .depth = 5, .sched = 1, .coal = 0, .wfirst = 0 };
        CHK(omega_blackwell_codegen_fp8_gemv_prog(&s, &p) == 0, "fp8_gemv sched1 k5120");
        report_kernel("fp8_gemv_k5120_w8_d5_s1", &p, 8);
    }
    {
        OmegaFp8GemvSpec s = { .k = 17408, .lane_bytes = 16, .rows = 1, .warps = 16, .mutant = 0, .depth = 2, .sched = 1, .coal = 0, .wfirst = 0 };
        CHK(omega_blackwell_codegen_fp8_gemv_prog(&s, &p) == 0, "fp8_gemv sched1 k17408");
        report_kernel("fp8_gemv_k17408_w16_d2_s1", &p, 16);
    }
    {
        OmegaFp8GemvSpec s = { .k = 2048, .lane_bytes = 16, .rows = 1, .warps = 8, .mutant = 0 };
        CHK(omega_blackwell_codegen_fp8_gemv2_prog(&s, &p) == 0, "fp8_gemv2 k2048");
        report_kernel("fp8_gemv2_k2048_w8", &p, 8);
    }
    {
        CHK(omega_blackwell_codegen_pf_copy_prog(&p) == 0, "pf_copy");
        report_kernel("pf_copy", &p, 8);
    }
    {
        OmegaRlSpec s = { .k = 2048, .e = 128, .t = 4, .mutant = 0 };
        CHK(omega_blackwell_codegen_rl_prog(&s, &p) == 0, "rl k2048 e128 t4");
        report_kernel("pfhost_rl_k2048_e128_t4", &p, 4);
    }
    {
        OmegaMcSpec s = { .h = 2048, .top_k = 8, .mutant = 0 };
        CHK(omega_blackwell_codegen_mc_prog(&s, &p) == 0, "mc h2048 topk8");
        report_kernel("pfhost_mc_h2048_k8", &p, 16);
    }
    {
        OmegaTgemmSpec s = { .k = 2304, .n = 768, .rt = 8, .ct = 2, .warps = 16, .kc = 32, .aqn = 1, .layout = 0, .epi = 0, .mutant = 0 };
        CHK(omega_blackwell_codegen_tgemm_prog(&s, &p) == 0, "tgemm k2304 rt8 w16");
        report_kernel("tgemm_k2304_n768_rt8_w16", &p, 16);
    }
    {
        OmegaTc2Spec s = { .k = 2048, .rt = 8, .ct = 2, .warps = 16, .aqn = 2, .epi = OMEGA_TC2_EPI_F32, .direct = 0, .n = 2048, .mutant = 0 };
        CHK(omega_blackwell_codegen_tc2_prog(&s, &p) == 0, "tc2 f32 k2048 rt8 w16");
        report_kernel("tc2_f32_k2048_rt8_w16", &p, 16);
    }
    {
        OmegaTc2Spec s = { .k = 2048, .rt = 8, .ct = 2, .warps = 16, .aqn = 2, .epi = OMEGA_TC2_EPI_SWIGLU, .direct = 1, .n = 1536, .mutant = 0 };
        CHK(omega_blackwell_codegen_tc2_prog(&s, &p) == 0, "tc2 swiglu direct k2048 rt8 w16");
        report_kernel("tc2_swiglu_d1_k2048_rt8_w16", &p, 16);
    }
    {
        OmegaPqSpec s = { .k = 2048, .in_type = OMEGA_QG_IN_BF16, .mutant = 0, .groups = 0 };
        CHK(omega_blackwell_codegen_pq_prog(&s, &p) == 0, "pq bf16 k2048");
        report_kernel("qg_pq_bf16_k2048", &p, 16);
    }
    {
        OmegaQgSpec s = { .k = 2048, .rt = 4, .warps = 8, .epi = OMEGA_QG_EPI_F32, .direct = 0, .n = 2048, .wait = 24, .mutant = 0 };
        CHK(omega_blackwell_codegen_qgemm_prog(&s, &p) == 0, "qgemm f32 k2048 rt4 w8");
        report_kernel("qg_qgemm_f32_k2048_rt4_w8", &p, 8);
    }
    {
        OmegaQgSpec s = { .k = 2048, .rt = 4, .warps = 8, .epi = OMEGA_QG_EPI_SWIGLU, .direct = 1, .n = 1536, .wait = 24, .mutant = 0 };
        CHK(omega_blackwell_codegen_qgemm_prog(&s, &p) == 0, "qgemm swiglu d1 k2048 rt4 w8");
        report_kernel("qg_qgemm_swiglu_d1_k2048", &p, 8);
    }
    {
        CHK(omega_blackwell_codegen_tc_probe_prog(0, &p) == 0, "tc_probe");
        report_kernel("tc_probe_m0", &p, 1);
    }
    {
        OmegaTcGemmSpec s = { .k = 2048, .rt = 4, .ct = 2, .warps = 8, .mutant = 0 };
        CHK(omega_blackwell_codegen_tcgemm_prog(&s, &p) == 0, "tcgemm k2048 rt4 ct2 w8");
        report_kernel("tc_tcgemm_k2048_rt4_ct2_w8", &p, 8);
    }
    {
        CHK(omega_blackwell_codegen_tc_peak_prog(64, 8, 8, 256, &p) == 0, "tc_peak");
        report_kernel("tc_peak_c8_s8_t256", &p, 8);
    }
    {
        CHK(omega_blackwell_codegen_tc_bw_prog(64, 4, 256, &p) == 0, "tc_bw");
        report_kernel("tc_bw_g4_t256", &p, 8);
    }
    {
        OmegaPrefillAttn256Spec s = { .mutant = 0, .q_heads = 24, .kv_heads = 4 };
        CHK(omega_blackwell_codegen_prefill_attn256_prog(&s, &p) == 0, "pattn256 q24 kv4");
        report_kernel("pattn256_q24_kv4", &p, 8);
    }
    {
        OmegaPrefillAttn256Spec s = { .mutant = 0, .q_heads = 16, .kv_heads = 2 };
        CHK(omega_blackwell_codegen_prefill_attn256_prog(&s, &p) == 0, "pattn256 q16 kv2");
        report_kernel("pattn256_q16_kv2", &p, 8);
    }
    {
        OmegaRouterSpec s = { .warps = 8, .depth = 4, .mutant = 0, .experts = 128, .shared = 0, .xstride = 0, .lbstride = 0 };
        CHK(omega_blackwell_codegen_router_prog(&s, &p) == 0, "router w8 d4 e128");
        report_kernel("router_w8_d4_e128", &p, 8);
    }
    {
        OmegaRouterSpec s = { .warps = 8, .depth = 4, .mutant = 0, .experts = 256, .shared = 1, .xstride = 8192, .lbstride = 16384 };
        CHK(omega_blackwell_codegen_router_prog(&s, &p) == 0, "router w8 d4 e256 sh1 rows");
        report_kernel("router_w8_d4_e256_sh1_rows", &p, 8);
    }
    {
        OmegaPrefillAttnSpec s = { .warps = 8, .mutant = 0, .mode = OMEGA_PATTN_MODE_FUSED, .mirror = 0 };
        CHK(omega_blackwell_codegen_prefill_attn_prog(&s, &p) == 0, "pattn w8 fused");
        report_kernel("pattn_w8_fused", &p, 8);
    }
    {
        OmegaPrefillAttnSpec s = { .warps = 4, .mutant = 0, .mode = OMEGA_PATTN_MODE_ATTEND, .mirror = 0 };
        CHK(omega_blackwell_codegen_prefill_attn_prog(&s, &p) == 0, "pattn w4 attend");
        report_kernel("pattn_w4_attend", &p, 4);
    }
    {
        OmegaPrefillAttnSpec s = { .warps = 8, .mutant = 0, .mode = OMEGA_PATTN_MODE_APPEND, .mirror = 1 };
        CHK(omega_blackwell_codegen_prefill_attn_prog(&s, &p) == 0, "pattn w8 append mirror");
        report_kernel("pattn_w8_append_mirror", &p, 8);
    }
    {
        OmegaDecodeAttnSpec s = { .depth = 2, .mutant = 0 };
        CHK(omega_blackwell_codegen_decode_attn_prog(&s, &p) == 0, "attn d2");
        report_kernel("attn_d2", &p, 8);
    }
    {
        OmegaDecodeAttnSpec s = { .depth = 4, .mutant = 0 };
        CHK(omega_blackwell_codegen_decode_attn_prog(&s, &p) == 0, "attn d4");
        report_kernel("attn_d4", &p, 8);
    }
}

static void test_pattn_and_attn_error_paths(void) {
    static BlackwellIRProgram prog;
    CHK(omega_blackwell_codegen_prefill_attn_prog(NULL, &prog) != 0 && prog.count == 0, "pattn NULL spec");
    OmegaPrefillAttnSpec pa_bad[] = {
        { .warps = 2, .mutant = 0,  .mode = 0, .mirror = 0 },
        { .warps = 8, .mutant = -1, .mode = 0, .mirror = 0 },
        { .warps = 8, .mutant = 5,  .mode = 0, .mirror = 0 },
        { .warps = 8, .mutant = 0,  .mode = 3, .mirror = 0 },
        { .warps = 8, .mutant = 0,  .mode = 0, .mirror = 1 },
        { .warps = 8, .mutant = 0,  .mode = 1, .mirror = 2 },
    };
    for (size_t i = 0; i < sizeof(pa_bad) / sizeof(pa_bad[0]); i++) {
        prog.count = 53;
        CHK(omega_blackwell_codegen_prefill_attn_prog(&pa_bad[i], &prog) != 0 && prog.count == 0, "pattn invalid spec");
        CHK(omega_pattn_spec_ok(&pa_bad[i]) == 0, "pattn_spec_ok 0");
    }
    CHK(omega_blackwell_codegen_decode_attn_prog(NULL, &prog) != 0 && prog.count == 0, "attn NULL spec");
    OmegaDecodeAttnSpec da_bad[] = {
        { .depth = 0, .mutant = 0 },
        { .depth = 5, .mutant = 0 },
        { .depth = 2, .mutant = -1 },
        { .depth = 2, .mutant = 5 },
    };
    for (size_t i = 0; i < sizeof(da_bad) / sizeof(da_bad[0]); i++) {
        prog.count = 54;
        CHK(omega_blackwell_codegen_decode_attn_prog(&da_bad[i], &prog) != 0 && prog.count == 0, "attn invalid spec");
    }
}

static void test_pattn256_and_router_error_paths(void) {
    static BlackwellIRProgram prog;
    CHK(omega_blackwell_codegen_prefill_attn256_prog(NULL, &prog) != 0 && prog.count == 0, "pattn256 NULL spec");
    OmegaPrefillAttn256Spec pa_bad[] = {
        { .mutant = -1, .q_heads = 24, .kv_heads = 4 },
        { .mutant = 3,  .q_heads = 24, .kv_heads = 4 },
        { .mutant = 0,  .q_heads = 25, .kv_heads = 4 },
        { .mutant = 0,  .q_heads = 36, .kv_heads = 4 },
    };
    for (size_t i = 0; i < sizeof(pa_bad) / sizeof(pa_bad[0]); i++) {
        prog.count = 51;
        CHK(omega_blackwell_codegen_prefill_attn256_prog(&pa_bad[i], &prog) != 0 && prog.count == 0, "pattn256 invalid spec");
        CHK(omega_pattn256_spec_ok(&pa_bad[i]) == 0, "pattn256_spec_ok 0");
    }
    CHK(omega_blackwell_codegen_router_prog(NULL, &prog) != 0 && prog.count == 0, "router NULL spec");
    OmegaRouterSpec rt_bad[] = {
        { .warps = 4,  .depth = 4, .mutant = 0,  .experts = 128, .shared = 0, .xstride = 0,    .lbstride = 0 },
        { .warps = 8,  .depth = 3, .mutant = 0,  .experts = 128, .shared = 0, .xstride = 0,    .lbstride = 0 },
        { .warps = 8,  .depth = 4, .mutant = -1, .experts = 128, .shared = 0, .xstride = 0,    .lbstride = 0 },
        { .warps = 8,  .depth = 4, .mutant = 7,  .experts = 128, .shared = 0, .xstride = 0,    .lbstride = 0 },
        { .warps = 8,  .depth = 4, .mutant = 5,  .experts = 128, .shared = 0, .xstride = 0,    .lbstride = 0 },
        { .warps = 8,  .depth = 4, .mutant = 6,  .experts = 128, .shared = 0, .xstride = 0,    .lbstride = 0 },
        { .warps = 8,  .depth = 4, .mutant = 0,  .experts = 64,  .shared = 0, .xstride = 0,    .lbstride = 0 },
        { .warps = 8,  .depth = 4, .mutant = 0,  .experts = 128, .shared = 2, .xstride = 0,    .lbstride = 0 },
        { .warps = 8,  .depth = 4, .mutant = 0,  .experts = 128, .shared = 0, .xstride = 8192, .lbstride = 0 },
        { .warps = 8,  .depth = 4, .mutant = 0,  .experts = 128, .shared = 0, .xstride = 4096, .lbstride = 16 },
    };
    for (size_t i = 0; i < sizeof(rt_bad) / sizeof(rt_bad[0]); i++) {
        prog.count = 52;
        CHK(omega_blackwell_codegen_router_prog(&rt_bad[i], &prog) != 0 && prog.count == 0, "router invalid spec");
    }
}

int main(void) {
    test_unpacker_bounds();
    test_gemm_error_paths();
    test_qmma_and_pfhost_error_paths();
    test_tgemm_and_tc2_error_paths();
    test_qg_and_tc_error_paths();
    test_pattn256_and_router_error_paths();
    test_pattn_and_attn_error_paths();
    test_max_size_legal_inputs();
    dump_metrics();
    printf("test_bw_om_codegen_bounds: %d passed, %d failed: %s\n", g_pass, g_fail, g_fail ? "FAIL" : "PASS");
    return g_fail ? 1 : 0;
}
