/* omega_gpu_gemm.c -- matrix multiply of any shape on the GB10 tensor cores (C3). See the header. */
#include "omega_gpu_gemm.h"
#include "omega_bw_om_ir.h"
#include "omega_blackwell_codegen_qmma.h"
#include "omega_native.h"
#include "omega_gpu_session.h"

#include <stdlib.h>
#include <string.h>

#define POISON 0x7fa00badu /* a signalling NaN no tensor-core op writes: a word still holding it was never stored */
#define TIMEOUT_MS 60000ull
#define FRAG 512u          /* bytes of one warp fragment: 32 lanes x 16 */

static int pow124(uint32_t v) { return v == 1u || v == 2u || v == 4u; }

void omega_gpu_gemm_default_cfg(OmegaGpuGemmType type, OmegaGemmCfg *cfg) {
    memset(cfg, 0, sizeof *cfg);
    cfg->type = type; cfg->rt = 2; cfg->ct = 4; cfg->wm = 2; cfg->wn = 2; cfg->stall = type == OMEGA_GPU_GEMM_BF16 ? 4u : 2u;
}

int omega_gpu_gemm_cfg_ok(const OmegaGemmCfg *c) {
    return c && (c->type == OMEGA_GPU_GEMM_BF16 || c->type == OMEGA_GPU_GEMM_E4M3) && pow124(c->rt) && pow124(c->ct) &&
           pow124(c->wm) && pow124(c->wn) && c->stall >= 1u && c->stall <= 15u && c->mutant >= 0 && c->mutant <= 4 &&
           4u * (4u * c->rt + 2u * c->ct + c->rt * c->ct) <= 100u; /* registers: two operand sets + accumulators, R2..R127 in all */
}

int omega_gpu_gemm_codegen(const OmegaGemmCfg *cfg, OmegaGemmKind kind, BlackwellIRProgram *prog) {
    if (!cfg || !prog || (unsigned)kind >= OMEGA_GEMM_K_COUNT || cfg->mutant < 0) {
        if (prog) omega_bw_ir_init(prog);
        return -1;
    }
    uint64_t sp[8] = {
        (uint64_t)cfg->type, cfg->rt, cfg->ct, cfg->wm, cfg->wn, cfg->stall, (uint64_t)cfg->mutant, (uint64_t)kind
    };
    uint64_t ins[8192], meta[512];
    memset(ins, 0, sizeof(ins));
    memset(meta, 0, sizeof(meta));
    uint64_t rc = 1;
    if (omega2_cg_gpu_gemm_emit(&rc, sp, 8, ins, 8192, meta, 512) != OMEGA_OK || rc != 0) {
        omega_bw_ir_init(prog);
        return -1;
    }
    return omega_bw_ir_from_om(ins, meta, prog);
}

/* ------------------------------------------------------------------ plan and driver */

int omega_gpu_gemm_plan(const OmegaGemmCfg *c, uint32_t M, uint32_t N, uint32_t K, OmegaGemmPlan *p) {
    if (!c || !p || c->mutant < 0) return OMEGA_GPU_GEMM_BAD_ARGS;
    uint64_t sp[10] = {
        (uint64_t)c->type, c->rt, c->ct, c->wm, c->wn, c->stall, (uint64_t)c->mutant, M, N, K
    };
    uint64_t res[18];
    memset(res, 0, sizeof(res));
    uint64_t rc = 1;
    if (omega2_cg_gpu_gemm_plan(&rc, sp, 10, res, 18) != OMEGA_OK) return OMEGA_GPU_GEMM_BAD_ARGS;
    if (rc == 2u) return OMEGA_GPU_GEMM_TOO_LARGE;
    if (rc != 0u) return OMEGA_GPU_GEMM_BAD_ARGS;
    memset(p, 0, sizeof *p);
    p->Mp = (uint32_t)res[0];
    p->Np = (uint32_t)res[1];
    p->Kp = (uint32_t)res[2];
    p->KS2 = (uint32_t)res[3];
    p->a_bytes = res[4];
    p->b_bytes = res[5];
    p->ap_bytes = res[6];
    p->bp_bytes = res[7];
    p->grid[OMEGA_GEMM_K_PACK_A][0] = (uint32_t)res[8];
    p->grid[OMEGA_GEMM_K_PACK_A][1] = (uint32_t)res[9];
    p->grid[OMEGA_GEMM_K_PACK_B][0] = (uint32_t)res[10];
    p->grid[OMEGA_GEMM_K_PACK_B][1] = (uint32_t)res[11];
    p->grid[OMEGA_GEMM_K_MAIN][0] = (uint32_t)res[12];
    p->grid[OMEGA_GEMM_K_MAIN][1] = (uint32_t)res[13];
    p->threads[OMEGA_GEMM_K_PACK_A] = (uint32_t)res[14];
    p->threads[OMEGA_GEMM_K_PACK_B] = (uint32_t)res[15];
    p->threads[OMEGA_GEMM_K_MAIN] = (uint32_t)res[16];
    return OMEGA_GPU_GEMM_OK;
}

static void put64(uint32_t *a, unsigned w, uint64_t v) { a[w] = (uint32_t)v; a[w + 1] = (uint32_t)(v >> 32); }

int omega_gpu_gemm_drive(const OmegaGemmCfg *c, unsigned layout, uint32_t M, uint32_t N, uint32_t K, uint64_t a_va,
                         uint64_t b_va, uint64_t ap_va, uint64_t bp_va, uint64_t c_va, OmegaGemmLaunchFn launch, void *ctx) {
    if (!launch || (layout & ~3u)) return OMEGA_GPU_GEMM_BAD_ARGS;
    OmegaGemmPlan p;
    int rc = omega_gpu_gemm_plan(c, M, N, K, &p);
    if (rc != OMEGA_GPU_GEMM_OK) return rc;
    uint32_t a[OMEGA_GPU_GEMM_ARGS_WORDS];
    /* A element (m, k): row-major m K + k, column-major k M + m */
    memset(a, 0, sizeof a);
    put64(a, 0, a_va); put64(a, 2, ap_va); a[4] = M; a[5] = K;
    const unsigned acol = (layout & OMEGA_GPU_GEMM_A_COL) ^ (c->mutant == 4 ? OMEGA_GPU_GEMM_A_COL : 0u); /* 4: wrong transpose */
    a[6] = acol ? 1u : K; a[7] = acol ? M : 1u; a[8] = p.KS2;
    if (launch(ctx, OMEGA_GEMM_K_PACK_A, a, p.grid[0][0], p.grid[0][1], p.threads[0]) != 0) return OMEGA_GPU_GEMM_CHIP_FAIL;
    /* B element (k, n) as packed row n: row-major k N + n, column-major n K + k */
    memset(a, 0, sizeof a);
    put64(a, 0, b_va); put64(a, 2, bp_va); a[4] = N; a[5] = K;
    a[6] = layout & OMEGA_GPU_GEMM_B_COL ? K : 1u; a[7] = layout & OMEGA_GPU_GEMM_B_COL ? 1u : N; a[8] = p.KS2;
    if (launch(ctx, OMEGA_GEMM_K_PACK_B, a, p.grid[1][0], p.grid[1][1], p.threads[1]) != 0) return OMEGA_GPU_GEMM_CHIP_FAIL;
    memset(a, 0, sizeof a);
    put64(a, 0, ap_va); put64(a, 2, bp_va); put64(a, 4, c_va); a[6] = M; a[7] = N; a[8] = p.KS2;
    if (launch(ctx, OMEGA_GEMM_K_MAIN, a, p.grid[2][0], p.grid[2][1], p.threads[2]) != 0) return OMEGA_GPU_GEMM_CHIP_FAIL;
    return OMEGA_GPU_GEMM_OK;
}

/* ------------------------------------------------------------------ the chip */

static struct {
    int set[2];
    OmegaGemmCfg cfg[2];
    OmegaGpuMem code[2][OMEGA_GEMM_K_COUNT];
    uint32_t gpr[2][OMEGA_GEMM_K_COUNT];
    int hooked;
} g;

/* lock held; the session calls it right before it closes the device (also in omega_gpu_session_recover): the kernels go
 * with the device, the next call builds them again on the new one */
static void on_session_close(void) {
    for (unsigned t = 0; t < 2; t++)
        for (unsigned k = 0; k < OMEGA_GEMM_K_COUNT; k++) if (g.code[t][k].cpu) omega_gpu_session_free(&g.code[t][k]);
    memset(g.code, 0, sizeof g.code);
}

static const OmegaGemmCfg *cfg_of(OmegaGpuGemmType t) {
    if (!g.set[t]) { omega_gpu_gemm_default_cfg(t, &g.cfg[t]); g.set[t] = 1; }
    return &g.cfg[t];
}

int omega_gpu_gemm_test_set_cfg(OmegaGpuGemmType type, const OmegaGemmCfg *cfg) {
    if ((unsigned)type > OMEGA_GPU_GEMM_E4M3 || (cfg && (!omega_gpu_gemm_cfg_ok(cfg) || cfg->type != type))) return OMEGA_GPU_GEMM_BAD_ARGS;
    omega_gpu_session_lock();
    for (unsigned k = 0; k < OMEGA_GEMM_K_COUNT; k++) if (g.code[type][k].cpu) omega_gpu_session_free(&g.code[type][k]);
    memset(g.code[type], 0, sizeof g.code[type]);
    if (cfg) g.cfg[type] = *cfg; else omega_gpu_gemm_default_cfg(type, &g.cfg[type]);
    g.set[type] = 1;
    omega_gpu_session_unlock();
    return OMEGA_GPU_GEMM_OK;
}

const char *omega_gpu_gemm_rc_name(int rc) {
    switch (rc) {
    case OMEGA_GPU_GEMM_OK: return "OK";
    case OMEGA_GPU_GEMM_BAD_ARGS: return "BAD_ARGS";
    case OMEGA_GPU_GEMM_TOO_LARGE: return "TOO_LARGE";
    case OMEGA_GPU_GEMM_CODEGEN_FAIL: return "CODEGEN_FAIL";
    case OMEGA_GPU_GEMM_CHIP_FAIL: return "CHIP_FAIL";
    default: return "?";
    }
}

/* lock held */
static int kernel_locked(OmegaGpuGemmType t, OmegaGemmKind k) {
    if (g.code[t][k].cpu) return OMEGA_GPU_GEMM_OK;
    if (!g.hooked) { /* without the hook a kernel would outlive its device */
        if (omega_gpu_session_on_close(on_session_close) != 0) return OMEGA_GPU_GEMM_CHIP_FAIL;
        g.hooked = 1;
    }
    BlackwellIRProgram *prog = omega_gpu_host_calloc(1, sizeof *prog);
    if (!prog) return OMEGA_GPU_GEMM_CODEGEN_FAIL;
    int rc = OMEGA_GPU_GEMM_OK;
    size_t need = 0;
    if (omega_gpu_gemm_codegen(cfg_of(t), k, prog) != 0 || (need = omega_bw_program_code_bytes(prog)) == 0) rc = OMEGA_GPU_GEMM_CODEGEN_FAIL;
    else if (omega_gpu_session_alloc_code(need, &g.code[t][k]) != 0) rc = OMEGA_GPU_GEMM_CHIP_FAIL;
    else {
        OmegaBlackwellKernel kk;
        if (omega_blackwell_kernel_encode_into(prog, g.code[t][k].cpu, need, &kk) != 0 || kk.code_size != need ||
            omega_qmma_patch_code(prog, g.code[t][k].cpu, need) < 0) rc = OMEGA_GPU_GEMM_CODEGEN_FAIL;
        else if ((g.gpr[t][k] = omega_bw_gpr_declared(kk.gpr_count)) > 255u) rc = OMEGA_GPU_GEMM_CODEGEN_FAIL;
        else if (omega_gpu_session_sync_to_gpu(&g.code[t][k]) != 0) rc = OMEGA_GPU_GEMM_CHIP_FAIL;
        if (g.gpr[t][k] < 64u) g.gpr[t][k] = 64u;
        if (rc != OMEGA_GPU_GEMM_OK) { omega_gpu_session_free(&g.code[t][k]); memset(&g.code[t][k], 0, sizeof g.code[t][k]); }
    }
    if (rc == OMEGA_GPU_GEMM_CODEGEN_FAIL) omega_gpu_session_set_error("gemm: our codegen refused a kernel");
    omega_gpu_host_free(prog);
    return rc;
}

typedef struct { OmegaGpuGemmType t; uint64_t pack_ns, main_ns; } ChipCtx;

/* lock held */
static int chip_launch(void *ctx, OmegaGemmKind k, const uint32_t args[OMEGA_GPU_GEMM_ARGS_WORDS], uint32_t gx, uint32_t gy, uint32_t threads) {
    ChipCtx *c = ctx;
    if (kernel_locked(c->t, k) != OMEGA_GPU_GEMM_OK) return -1;
    OmegaGpuLaunch L = {
        .code_va = g.code[c->t][k].va, .gpr_count = g.gpr[c->t][k], .threads_x = threads, .threads_y = 1,
        .grid_x = gx, .grid_y = gy, .num_elements = (size_t)gx * gy * threads,
        .args = args, .n_args = OMEGA_GPU_GEMM_ARGS_WORDS, .timeout_ms = TIMEOUT_MS,
    };
    uint64_t ns = 0;
    if (omega_gpu_session_launch(&L, &ns, NULL) != 0) return -1;
    if (k == OMEGA_GEMM_K_MAIN) c->main_ns += ns; else c->pack_ns += ns;
    return 0;
}

static uint64_t up16(uint64_t v) { return (v + 255u) & ~(uint64_t)255u; }

int omega_gpu_gemm(OmegaGpuGemmType type, unsigned layout, uint32_t M, uint32_t N, uint32_t K, const void *A, const void *B,
                   float *C, OmegaGpuGemmInfo *info) {
    uint64_t t0 = omega_gpu_session_now_ns();
    if (info) memset(info, 0, sizeof *info);
    if ((unsigned)type > OMEGA_GPU_GEMM_E4M3 || (layout & ~3u) || !A || !B || !C) return OMEGA_GPU_GEMM_BAD_ARGS;
    omega_gpu_session_lock();
    const OmegaGemmCfg *cfg = cfg_of(type);
    OmegaGemmPlan p;
    int rc = omega_gpu_gemm_plan(cfg, M, N, K, &p);
    if (rc != OMEGA_GPU_GEMM_OK) { omega_gpu_session_unlock(); return rc; }
    /* one buffer: A | B | packed A | packed B | C (each 256-byte aligned; A and B carry 16 bytes of readable slack) */
    const uint64_t oa = 0, ob = up16(p.a_bytes + 16u), oap = ob + up16(p.b_bytes + 16u), obp = oap + up16(p.ap_bytes),
                   oc = obp + up16(p.bp_bytes), total = oc + (uint64_t)M * N * 4u;
    OmegaGpuMem m;
    if (!omega_gpu_session_open() || omega_gpu_session_alloc(total, &m) != 0) { omega_gpu_session_unlock(); return OMEGA_GPU_GEMM_CHIP_FAIL; }
    uint8_t *base = m.cpu;
    memcpy(base + oa, A, p.a_bytes); memcpy(base + ob, B, p.b_bytes);
    uint32_t *cw = (uint32_t *)(base + oc);
    for (uint64_t i = 0; i < (uint64_t)M * N; i++) cw[i] = POISON;
    ChipCtx cc = { type, 0, 0 };
    if (omega_gpu_session_sync_to_gpu(&m) != 0) rc = OMEGA_GPU_GEMM_CHIP_FAIL;
    else rc = omega_gpu_gemm_drive(cfg, layout, M, N, K, m.va + oa, m.va + ob, m.va + oap, m.va + obp, m.va + oc, chip_launch, &cc);
    if (rc == OMEGA_GPU_GEMM_OK && omega_gpu_session_sync_to_cpu(&m) != 0) rc = OMEGA_GPU_GEMM_CHIP_FAIL;
    if (rc == OMEGA_GPU_GEMM_OK) {
        uint64_t unwritten = 0;
        for (uint64_t i = 0; i < (uint64_t)M * N; i++) unwritten += cw[i] == POISON;
        if (unwritten) { omega_gpu_session_set_error("gemm: output words never written"); rc = OMEGA_GPU_GEMM_CHIP_FAIL; }
        else memcpy(C, cw, (size_t)M * N * 4u);
    }
    if (info) {
        info->pack_ns = cc.pack_ns; info->main_ns = cc.main_ns;
        for (unsigned k = 0; k < OMEGA_GEMM_K_COUNT; k++) info->gpr[k] = g.gpr[type][k];
    }
    omega_gpu_session_free(&m);
    omega_gpu_session_unlock();
    if (info) info->call_ns = omega_gpu_session_now_ns() - t0;
    return rc;
}
