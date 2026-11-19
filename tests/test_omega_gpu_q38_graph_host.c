/*
 * test_omega_gpu_q38_graph_host: host-only (no GPU opened) ABI, validation, permutation, and Blackwell codegen proof
 * for the Qwen3.8-27B multi-head stroke, batched dense FP8 GEMM, and exact two-pass head extensions in omega_gpu_q38_graph.
 * Verdict line last: "test_omega_gpu_q38_graph_host: N checks, F failed: PASS|FAIL".
 */
#include "omega_gpu_q38_graph.h"
#include "omega_blackwell_codegen_dec.h"
#include "omega_blackwell_codegen_gemm.h"
#include "omega_gpu_fp8gemm_api.h"
#include "omega_gpu_bf16_gemv_api.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned g_checks, g_failed;
#define CHECK(cond, ...) do { g_checks++; if (!(cond)) { g_failed++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

static void check_perm_width(uint32_t k) {
    uint32_t *tab = calloc(k, sizeof *tab);
    float *src = calloc(k, sizeof *src), *ref = calloc(k, sizeof *ref);
    CHECK(tab && src && ref, "alloc perm width %u", k);
    if (!tab || !src || !ref) { free(tab); free(src); free(ref); return; }
    omega_q38_perm_table(tab, k);
    for (uint32_t i = 0; i < k; i++) src[i] = (float)(i + 1u) * 0.25f;
    const uint32_t lb = (k % 512u == 0) ? 16u : 8u;
    omega_fp8gemm_permute_x(src, k, lb, ref);
    size_t bad = 0;
    for (uint32_t i = 0; i < k; i++) {
        if (tab[i] >= k) { bad++; continue; }
        const float got = src[tab[i]] * 0x1p64f;
        if (memcmp(&got, &ref[i], 4) != 0) bad++;
    }
    CHECK(bad == 0, "omega_q38_perm_table matches omega_fp8gemm_permute_x at k=%u (bad=%zu)", k, bad);
    free(tab); free(src); free(ref);
}

static void check_dec_codegen(const char *label, const OmegaDecSpec *sp, int expect_ok) {
    BlackwellIRProgram *p = calloc(1, sizeof *p);
    CHECK(p != NULL, "alloc IR program for %s", label);
    if (!p) return;
    int rc = omega_blackwell_codegen_dec_prog(sp, p);
    size_t bytes = rc == 0 ? omega_bw_program_code_bytes(p) : 0;
    if (expect_ok) {
        CHECK(rc == 0 && bytes > 0, "%s codegen ok (rc=%d, bytes=%zu)", label, rc, bytes);
        CHECK(omega_bw_gpr_declared(p->regalloc.peak_gpr_usage) <= 128u, "%s GPRs fit (%u peak)", label, p->regalloc.peak_gpr_usage);
    } else {
        CHECK(rc != 0, "%s codegen refused invalid spec", label);
    }
    free(p);
}

static void check_fp8gemm_27b(uint32_t k) {
    OmegaFp8GemmSpec sp; memset(&sp, 0, sizeof sp);
    sp.k = k;
    omega_gpu_fp8gemm_shape_for(k, &sp.mt, &sp.warps, &sp.lane_bytes);
    uint32_t decl = 0;
    int fits = omega_gpu_fp8gemm_kernel_fits(&sp, &decl);
    CHECK(fits == OMEGA_GPU_FP8GEMM_OK, "fp8gemm k=%u (mt=%u w=%u lb=%u decl=%u) fits register file (rc=%d)", k, sp.mt, sp.warps, sp.lane_bytes, decl, fits);
    BlackwellIRProgram *p = calloc(1, sizeof *p);
    if (p) {
        int rc = omega_blackwell_codegen_fp8gemm_prog(&sp, p);
        size_t bytes = rc == 0 ? omega_bw_program_code_bytes(p) : 0;
        CHECK(rc == 0 && bytes > 0, "fp8gemm k=%u codegen ok (rc=%d, bytes=%zu)", k, rc, bytes);
        free(p);
    }
}

int main(void) {
    /* 1. Exact head admission reserve */
    const uint64_t extra = omega_gpu_q38_exact_extra_bytes();
    CHECK(extra > (1ull << 30), "exact_extra_bytes > 1 GiB (got %llu)", (unsigned long long)extra);

    /* 2. Host-only BAD_ARGS guards (never touch the GPU) */
    OmegaGpuQ38Graph *g = (OmegaGpuQ38Graph *)0x1;
    OmegaGpuQ38GraphConfig cfg; memset(&cfg, 0, sizeof cfg);
    CHECK(omega_gpu_q38_graph_create_heads(&cfg, 0, &g) == OMEGA_GPU_DGRAPH_BAD_ARGS && !g, "create_heads refuses heads=0");
    CHECK(omega_gpu_q38_graph_create_heads(&cfg, OMEGA_GPU_Q38_MAX_HEADS + 1u, &g) == OMEGA_GPU_DGRAPH_BAD_ARGS && !g, "create_heads refuses heads>MAX");
    CHECK(omega_gpu_q38_graph_create_heads(NULL, 2, &g) == OMEGA_GPU_DGRAPH_BAD_ARGS && !g, "create_heads refuses NULL cfg");
    CHECK(omega_gpu_q38_graph_set_head_state(NULL, 0, NULL, NULL) == OMEGA_GPU_DGRAPH_BAD_ARGS, "set_head_state refuses NULL");
    CHECK(omega_gpu_q38_graph_begin_stroke(NULL, NULL, 1) == OMEGA_GPU_DGRAPH_BAD_ARGS, "begin_stroke refuses NULL");
    CHECK(omega_gpu_q38_graph_record_head_layer(NULL, 0, 0, 0) == OMEGA_GPU_DGRAPH_BAD_ARGS, "record_head_layer refuses NULL");
    CHECK(omega_gpu_q38_graph_record_head_final(NULL, 0) == OMEGA_GPU_DGRAPH_BAD_ARGS, "record_head_final refuses NULL");
    CHECK(omega_gpu_q38_graph_end_stroke(NULL, NULL, NULL) == OMEGA_GPU_DGRAPH_BAD_ARGS, "end_stroke refuses NULL");
    CHECK(omega_gpu_q38_graph_stroke(NULL, NULL, NULL, 1, NULL, NULL) == OMEGA_GPU_DGRAPH_BAD_ARGS, "stroke refuses NULL");
    CHECK(omega_gpu_q38_graph_read_head(NULL, 0, NULL, NULL, NULL) == OMEGA_GPU_DGRAPH_BAD_ARGS, "read_head refuses NULL");
    CHECK(omega_gpu_q38_graph_set_batch(NULL, 1) == OMEGA_GPU_DGRAPH_BAD_ARGS, "set_batch refuses NULL");
    CHECK(omega_gpu_q38_graph_batch(NULL) == 0, "batch(NULL) == 0");
    CHECK(omega_gpu_q38_graph_record_layer_heads(NULL, 0, NULL) == OMEGA_GPU_DGRAPH_BAD_ARGS, "record_layer_heads refuses NULL");
    CHECK(omega_gpu_q38_graph_set_exact_head(NULL, NULL, NULL, 0) == OMEGA_GPU_DGRAPH_BAD_ARGS, "set_exact_head refuses NULL");
    CHECK(omega_gpu_q38_graph_exact_head_active(NULL) == 0, "exact_head_active(NULL) == 0");
    CHECK(omega_gpu_q38_graph_exact_head_active_head(NULL, 0) == 0, "exact_head_active_head(NULL, 0) == 0");
    omega_gpu_q38_graph_set_exact_head_on(NULL, 1);
    omega_gpu_q38_graph_set_head_exact_head_on(NULL, 0, 1);
    CHECK(strcmp(omega_gpu_q38_graph_kind_name(OMEGA_GPU_Q38_K_PERM), "perm") == 0, "kind_name(K_PERM) == perm");

    /* 3. Permutation tables for 27B (H=5120, mout=6144, I=17408), 9B (4096, 12288), and lb=8 (256) */
    check_perm_width(5120u);
    check_perm_width(6144u);
    check_perm_width(17408u);
    check_perm_width(4096u);
    check_perm_width(256u);

    /* 4. 27B glue kernel codegen (NORM|ROWS, ADD|NORM|ROWS, XBOUND H=5120, XBOUND invalid width) */
    {
        OmegaDecSpec s; memset(&s, 0, sizeof s);
        s.kind = OMEGA_DEC_RES; s.mode = OMEGA_DEC_RES_NORM | OMEGA_DEC_RES_ROWS; s.width = 5120u;
        check_dec_codegen("RES NORM|ROWS H=5120", &s, 1);
        s.mode = OMEGA_DEC_RES_ADD | OMEGA_DEC_RES_NORM | OMEGA_DEC_RES_ROWS;
        check_dec_codegen("RES ADD|NORM|ROWS H=5120", &s, 1);
        memset(&s, 0, sizeof s);
        s.kind = OMEGA_DEC_XBOUND; s.width = 5120u;
        check_dec_codegen("XBOUND H=5120", &s, 1);
        s.width = 4096u;
        check_dec_codegen("XBOUND H=4096", &s, 1);
        s.width = 1536u;
        check_dec_codegen("XBOUND invalid H=1536", &s, 0);
    }

    /* 5. 27B batched FP8 GEMM codegen (mix/gate_up K=5120, o K=6144, down K=17408) */
    check_fp8gemm_27b(5120u);
    check_fp8gemm_27b(6144u);
    check_fp8gemm_27b(17408u);

    /* 6. 27B exact-head bf16 MASK kernel register-file check at K=5120 */
    {
        OmegaBf16GemvSpec sp; memset(&sp, 0, sizeof sp);
        uint32_t ctas = 0, decl = 0;
        sp.k = 5120u; sp.mask = 1u;
        omega_gpu_bf16_shape_for(5120u, &sp.rows, &sp.warps, &sp.depth, &ctas);
        int fits = omega_gpu_bf16_kernel_fits(&sp, &decl);
        CHECK(fits == OMEGA_GPU_BF16_OK, "bf16 MASK k=5120 fits register file (decl=%u, rc=%d)", decl, fits);
    }

    printf("test_omega_gpu_q38_graph_host: %u checks, %u failed: %s\n", g_checks, g_failed, g_failed ? "FAIL" : "PASS");
    return g_failed ? 1 : 0;
}
