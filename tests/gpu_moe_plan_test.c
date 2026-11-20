/* SPDX-License-Identifier: Apache-2.0
 * Host + live GB10 silicon test for pure-OM-2 persistent MoE request queue and
 * unified single-submit MoE layer execution (om/gpu/moe_plan.om + omega_gpu_moe_plan.c).
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include "omega_gpu_moe_plan.h"
#include "omega_gpu_pfhost.h"
#include "omega_gpu_fp8gemm_api.h"
#include "omega_gpu_prefill.h"

static int g_pass = 0, g_fail = 0;
#define CHK(cond, msg) do { \
    if (cond) { g_pass++; } \
    else { g_fail++; printf("FAIL: %s\n", (msg)); } \
} while (0)

static uint64_t now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static uint32_t xorshift32(uint32_t *s) {
    uint32_t x = *s;
    x ^= x << 13; x ^= x >> 17; x ^= x << 5;
    return (*s = x);
}

static void test_host_queue_and_planner(void) {
    OmegaMoeQueue q;
    CHK(omega_moe_queue_init(&q, 0) != 0, "queue reject cap=0");
    CHK(omega_moe_queue_init(&q, 65) != 0, "queue reject cap=65");
    CHK(omega_moe_queue_init(&q, 4) == 0, "queue init cap=4");

    /* Invalid enqueue checks */
    uint32_t slot = 99;
    CHK(omega_moe_queue_enqueue(&q, 1, 0, 0, 0, &slot) != 0, "queue reject tokens=0");
    CHK(omega_moe_queue_enqueue(&q, 1, 1025, 0, 0, &slot) != 0, "queue reject tokens=1025");

    /* Fill to capacity 4, then overflow must fail */
    for (uint32_t i = 0; i < 4; i++) {
        CHK(omega_moe_queue_enqueue(&q, 100u + i, 16u, i, 0xfu, &slot) == 0 && slot == i, "queue enqueue 0..3");
    }
    CHK(omega_moe_queue_enqueue(&q, 104, 16, 4, 0xfu, &slot) != 0, "queue reject overflow when full");

    /* Claim batch with max_tokens=40 -> should claim 2 requests (32 tokens), not 3 (48 > 40) */
    uint32_t slots[64];
    uint32_t claimed = 0;
    CHK(omega_moe_queue_claim_batch(&q, 40, slots, &claimed) == 0 && claimed == 2, "claim batch respects max_tokens");
    CHK(slots[0] == 0 && slots[1] == 1, "claim batch FIFO order");
    CHK(q.words[4] == 1 && q.words[5] == 2, "epoch=1 active=2");

    /* Complete batch cleanly -> advances head by 2, frees 2 slots */
    CHK(omega_moe_queue_complete_batch(&q, claimed, slots, 0) == 0, "complete batch OK");
    CHK(q.words[2] == 2 && q.words[5] == 0 && q.words[6] == 2 && q.words[7] == 0, "head=2 active=0 done=2");

    /* Wrap-around stress: 100 cycles of enqueue + claim + complete (alternating OK and ERROR) */
    for (uint32_t r = 0; r < 100; r++) {
        CHK(omega_moe_queue_enqueue(&q, 200u + r, 8u, r & 31u, 0xfu, &slot) == 0, "wrap enqueue");
        CHK(omega_moe_queue_claim_batch(&q, 64u, slots, &claimed) == 0 && claimed >= 1, "wrap claim");
        CHK(omega_moe_queue_complete_batch(&q, claimed, slots, (r & 15u) == 15u ? 1u : 0u) == 0, "wrap complete");
    }
    CHK(q.words[2] == q.words[3] && q.words[5] == 0, "queue drained cleanly after wrap stress");

    /* Planner tests: T=1 selects GEMV, T=64 selects GEMM, QMMA+overlap marks ACT_QUANT independent */
    OmegaMoePlanOp ops[OMEGA_MOE_PLAN_MAX_OPS];
    uint32_t n_ops = 0;
    OmegaMoePlanConfig c1 = { .tokens = 1, .hidden = 2048, .inter = 768, .experts = 128, .top_k = 8,
                              .flags = OMEGA_MOE_FLAG_ROUTER | OMEGA_MOE_FLAG_GATEUP | OMEGA_MOE_FLAG_DOWN | OMEGA_MOE_FLAG_COMBINE };
    CHK(omega_moe_plan_layer(&c1, ops, &n_ops) == 0 && n_ops == 4, "plan T=1 emits 4 ops");
    CHK(ops[0].op == OMEGA_MOP_ROUTER_LOGITS && ops[1].op == OMEGA_MOP_EXPERT_GATEUP_GEMV &&
        ops[2].op == OMEGA_MOP_EXPERT_DOWN_GEMV && ops[3].op == OMEGA_MOP_MOE_COMBINE,
        "plan T=1 selects GEMV for experts");

    OmegaMoePlanConfig c64 = c1;
    c64.tokens = 64;
    CHK(omega_moe_plan_layer(&c64, ops, &n_ops) == 0 && n_ops == 4, "plan T=64 emits 4 ops");
    CHK(ops[1].op == OMEGA_MOP_EXPERT_GATEUP_GEMM && ops[2].op == OMEGA_MOP_EXPERT_DOWN_GEMM,
        "plan T=64 selects grouped GEMM for experts");

    OmegaMoePlanConfig cq = c64;
    cq.flags |= OMEGA_MOE_FLAG_USE_QMMA | OMEGA_MOE_FLAG_OVERLAP_RQ;
    CHK(omega_moe_plan_layer(&cq, ops, &n_ops) == 0 && n_ops == 5, "plan QMMA+overlap emits 5 ops");
    CHK(ops[1].op == OMEGA_MOP_ACT_QUANT && ops[1].mark_independent == 1, "ACT_QUANT marked independent beside router");

    /* Traffic estimator */
    OmegaMoeTraffic tr;
    CHK(omega_moe_plan_traffic(&c64, 126, &tr) == 0 && tr.total_bytes > 500000000ull, "traffic estimate valid");

    /* Invalid planner config refused */
    OmegaMoePlanConfig cbad = c64;
    cbad.top_k = 200; /* > experts */
    CHK(omega_moe_plan_layer(&cbad, ops, &n_ops) != 0, "plan refuses top_k > experts");
}

typedef struct {
    uint64_t w_va, s_va;
    uint32_t row0, cnt, pad0, pad1;
} GemmSeg;
_Static_assert(sizeof(GemmSeg) == OMEGA_GEMM_SEG_BYTES, "GemmSeg == 32B");

static int run_chip_ab(void) {
    /* Qwen3-30B/35B-A3B MoE layer shape: H=2048, I=768 (gate_up N=1536), E=128, top_k=8, T=64 tokens (512 rows) */
    const uint32_t T = 64, H = 2048, I = 768, N_GU = 1536, E = 128, TOPK = 8;
    const uint32_t M = T * TOPK;
    uint32_t rng = 0x12345678u;

    /* 1. Host inputs & weights */
    float *h_x = calloc((size_t)T * H, sizeof(float));
    float *h_rw = calloc((size_t)E * H, sizeof(float));
    size_t rw_packed_bytes = omega_gpu_pf_router_packed_bytes(E, H);
    float *h_rwq = calloc(rw_packed_bytes / sizeof(float), sizeof(float));
    uint8_t *h_gu_w = malloc((size_t)E * N_GU * H);
    uint16_t *h_gu_s = malloc((size_t)E * (N_GU / 128u) * (H / 128u) * sizeof(uint16_t));
    uint8_t *h_dn_w = malloc((size_t)E * H * I);
    uint16_t *h_dn_s = malloc((size_t)E * (H / 128u) * (I / 128u) * sizeof(uint16_t));
    float *h_act = calloc((size_t)M * I, sizeof(float));
    uint32_t *h_exp_ids = calloc(M, sizeof(uint32_t));
    uint32_t *h_tok_rows = calloc(M, sizeof(uint32_t));
    uint32_t *h_inv = calloc(M, sizeof(uint32_t));
    float *h_wt = calloc(M, sizeof(float));

    for (size_t i = 0; i < (size_t)T * H; i++) h_x[i] = ((int)(xorshift32(&rng) & 255u) - 128) * 0.01f;
    for (size_t i = 0; i < (size_t)E * H; i++) h_rw[i] = ((int)(xorshift32(&rng) & 255u) - 128) * 0.01f;
    omega_gpu_pf_router_pack(E, H, h_rw, h_rwq);
    for (size_t i = 0; i < (size_t)E * N_GU * H; i++) h_gu_w[i] = (uint8_t)(0x38u + (xorshift32(&rng) & 7u));
    for (size_t i = 0; i < (size_t)E * (N_GU / 128u) * (H / 128u); i++) h_gu_s[i] = 0x3c00u; /* ~0.0078 bf16 */
    for (size_t i = 0; i < (size_t)E * H * I; i++) h_dn_w[i] = (uint8_t)(0x38u + (xorshift32(&rng) & 7u));
    for (size_t i = 0; i < (size_t)E * (H / 128u) * (I / 128u); i++) h_dn_s[i] = 0x3c00u;
    for (size_t i = 0; i < (size_t)M * I; i++) h_act[i] = ((int)(xorshift32(&rng) & 255u) - 128) * 0.01f;

    /* Deterministic balanced routing: 4 rows per expert across 128 experts = 512 rows (sorted by expert) */
    for (uint32_t p = 0; p < M; p++) {
        h_exp_ids[p] = p / 4u;
        h_tok_rows[p] = (p * 7u) % T;
    }
    /* Inverse map for combine: token t slot s -> sorted row (t * TOPK + s) */
    for (uint32_t t = 0; t < T; t++) {
        for (uint32_t s = 0; s < TOPK; s++) {
            h_inv[t * TOPK + s] = (t * TOPK + s);
            h_wt[t * TOPK + s] = 1.0f / (float)TOPK;
        }
    }

    /* 2. Upload FP8 expert tensors */
    OmegaGpuFp8Tensor *t_gu = NULL, *t_dn = NULL;
    CHK(omega_gpu_fp8_tensor_upload(E, N_GU, H, h_gu_w, h_gu_s, &t_gu) == 0, "upload gate_up FP8 tensor");
    CHK(omega_gpu_fp8_tensor_upload(E, H, I, h_dn_w, h_dn_s, &t_dn) == 0, "upload down FP8 tensor");
    CHK(omega_gpu_fp8gemm_prepare_shape(H, E, 4, 0) == 0, "prepare gate_up gemm shape");
    CHK(omega_gpu_fp8gemm_prepare_shape(I, E, 4, 0) == 0, "prepare down gemm shape");

    /* 3. Allocate device buffers for unified execution */
    OmegaGpuMem d_x, d_rwq, d_logits_ref, d_logits_uni;
    OmegaGpuMem d_gu_seg, d_gu_xp, d_gu_y;
    OmegaGpuMem d_dn_seg, d_dn_xp, d_dn_y;
    OmegaGpuMem d_inv, d_wt, d_out_ref, d_out_uni;
    CHK(omega_gpu_pf_alloc_host((size_t)T * H * 4u, &d_x) == 0, "alloc d_x");
    CHK(omega_gpu_pf_alloc_host(rw_packed_bytes, &d_rwq) == 0, "alloc d_rwq");
    CHK(omega_gpu_pf_alloc_host((size_t)T * E * 4u, &d_logits_ref) == 0, "alloc d_logits_ref");
    CHK(omega_gpu_pf_alloc_host((size_t)T * E * 4u, &d_logits_uni) == 0, "alloc d_logits_uni");
    CHK(omega_gpu_pf_alloc_host((size_t)E * OMEGA_GEMM_SEG_BYTES, &d_gu_seg) == 0, "alloc d_gu_seg");
    CHK(omega_gpu_pf_alloc_host((size_t)(M + 8u) * H * 4u, &d_gu_xp) == 0, "alloc d_gu_xp");
    CHK(omega_gpu_pf_alloc_host((size_t)M * N_GU * 4u, &d_gu_y) == 0, "alloc d_gu_y");
    CHK(omega_gpu_pf_alloc_host((size_t)E * OMEGA_GEMM_SEG_BYTES, &d_dn_seg) == 0, "alloc d_dn_seg");
    CHK(omega_gpu_pf_alloc_host((size_t)(M + 8u) * I * 4u, &d_dn_xp) == 0, "alloc d_dn_xp");
    CHK(omega_gpu_pf_alloc_host((size_t)M * H * 4u, &d_dn_y) == 0, "alloc d_dn_y");
    CHK(omega_gpu_pf_alloc_host((size_t)M * 4u, &d_inv) == 0, "alloc d_inv");
    CHK(omega_gpu_pf_alloc_host((size_t)M * 4u, &d_wt) == 0, "alloc d_wt");
    CHK(omega_gpu_pf_alloc_host((size_t)T * H * 4u, &d_out_ref) == 0, "alloc d_out_ref");
    CHK(omega_gpu_pf_alloc_host((size_t)T * H * 4u, &d_out_uni) == 0, "alloc d_out_uni");

    memcpy(d_x.cpu, h_x, (size_t)T * H * 4u);
    memcpy(d_rwq.cpu, h_rwq, rw_packed_bytes);
    memcpy(d_inv.cpu, h_inv, (size_t)M * 4u);
    memcpy(d_wt.cpu, h_wt, (size_t)M * 4u);

    /* Build segment tables + permuted x' rows once in device-visible buffers */
    GemmSeg *gu_segs = (GemmSeg *)d_gu_seg.cpu;
    GemmSeg *dn_segs = (GemmSeg *)d_dn_seg.cpu;
    for (uint32_t e = 0; e < E; e++) {
        uint64_t wva = 0, sva = 0;
        omega_gpu_fp8_tensor_entry(t_gu, e, &wva, &sva);
        gu_segs[e] = (GemmSeg){ .w_va = wva, .s_va = sva, .row0 = e * 4u, .cnt = 4u };
        omega_gpu_fp8_tensor_entry(t_dn, e, &wva, &sva);
        dn_segs[e] = (GemmSeg){ .w_va = wva, .s_va = sva, .row0 = e * 4u, .cnt = 4u };
    }
    uint32_t gu_mt, gu_w, gu_lb, dn_mt, dn_w, dn_lb;
    omega_gpu_fp8gemm_shape_for(H, &gu_mt, &gu_w, &gu_lb);
    omega_gpu_fp8gemm_shape_for(I, &dn_mt, &dn_w, &dn_lb);
    for (uint32_t p = 0; p < M; p++) {
        omega_fp8gemm_permute_x(h_x + (size_t)h_tok_rows[p] * H, H, gu_lb, (float *)d_gu_xp.cpu + (size_t)p * H);
        omega_fp8gemm_permute_x(h_act + (size_t)p * I, I, dn_lb, (float *)d_dn_xp.cpu + (size_t)p * I);
    }

    float *h_gu_ref = calloc((size_t)M * N_GU, sizeof(float));
    float *h_dn_ref = calloc((size_t)M * H, sizeof(float));

    /* ---- Arm A: Separate synchronous launches (warmup + 3 timed reps) ---- */
    uint64_t sep_wall_ns = 0, sep_rl_ns = 0, sep_gu_ns = 0, sep_dn_ns = 0, sep_mc_ns = 0;
    for (int rep = 0; rep < 4; rep++) {
        uint64_t t0 = now_ns();
        uint64_t rl_ns = 0, mc_ns = 0;
        OmegaGpuFp8GemmInfo gi_gu, gi_dn;
        CHK(omega_gpu_pf_router_logits(H, E, T, d_x.va, d_rwq.va, d_logits_ref.va, &rl_ns) == 0, "sep router_logits");
        CHK(omega_gpu_fp8gemm_f32(t_gu, M, h_exp_ids, h_tok_rows, h_x, T, h_gu_ref, &gi_gu) == 0, "sep gate_up");
        uint32_t identity_rows[512];
        for (uint32_t p = 0; p < M; p++) identity_rows[p] = p;
        CHK(omega_gpu_fp8gemm_f32(t_dn, M, h_exp_ids, identity_rows, h_act, M, h_dn_ref, &gi_dn) == 0, "sep down");
        memcpy(d_dn_y.cpu, h_dn_ref, (size_t)M * H * 4u);
        CHK(omega_gpu_pf_moe_combine(H, TOPK, T, d_dn_y.va, d_inv.va, d_wt.va, d_out_ref.va, &mc_ns) == 0, "sep combine");
        uint64_t t1 = now_ns();
        if (rep == 3) {
            sep_wall_ns = t1 - t0;
            sep_rl_ns = rl_ns;
            sep_gu_ns = gi_gu.elapsed_ns;
            sep_dn_ns = gi_dn.elapsed_ns;
            sep_mc_ns = mc_ns;
        }
    }

    /* ---- Arm B: Unified .om-planned single-submit OmegaGpuCmdList with PTIMER stamps ---- */
    OmegaGpuCmdList *cl = NULL;
    CHK(omega_gpu_cmdlist_create(32, &cl) == 0, "create cmdlist");

    OmegaMoeQueue q;
    CHK(omega_moe_queue_init(&q, 16) == 0, "init persistent MoE queue");

    OmegaGpuMoeExecArgs ea;
    memset(&ea, 0, sizeof ea);
    ea.cfg = (OmegaMoePlanConfig){
        .tokens = T, .hidden = H, .inter = I, .experts = E, .top_k = TOPK,
        .flags = OMEGA_MOE_FLAG_ROUTER | OMEGA_MOE_FLAG_GATEUP | OMEGA_MOE_FLAG_DOWN | OMEGA_MOE_FLAG_COMBINE
    };
    ea.distinct_experts = E;
    ea.x_va = d_x.va; ea.router_wq_va = d_rwq.va; ea.logits_va = d_logits_uni.va;
    ea.gateup_t = t_gu; ea.gateup_segs = E; ea.gateup_seg_va = d_gu_seg.va; ea.gateup_xp_va = d_gu_xp.va; ea.gateup_y_va = d_gu_y.va;
    ea.down_t = t_dn; ea.down_segs = E; ea.down_seg_va = d_dn_seg.va; ea.down_xp_va = d_dn_xp.va; ea.down_y_va = d_dn_y.va;
    ea.inv_va = d_inv.va; ea.wt_va = d_wt.va; ea.out_va = d_out_uni.va;
    ea.barrier = OMEGA_GPU_CMDLIST_BARRIER_WFI_DATA;

    OmegaGpuMoeExecStats ust;
    uint64_t uni_wall_ns = 0;
    for (int rep = 0; rep < 4; rep++) {
        uint32_t slot = 0, slots[64], claimed = 0;
        CHK(omega_moe_queue_enqueue(&q, (uint32_t)(rep + 1), T, 0, ea.cfg.flags, &slot) == 0, "queue enqueue batch");
        CHK(omega_moe_queue_claim_batch(&q, T, slots, &claimed) == 0 && claimed == 1, "queue claim batch");
        memset(d_logits_uni.cpu, 0, (size_t)T * E * 4u);
        memset(d_gu_y.cpu, 0, (size_t)M * N_GU * 4u);
        memset(d_dn_y.cpu, 0, (size_t)M * H * 4u);
        memset(d_out_uni.cpu, 0, (size_t)T * H * 4u);
        uint64_t t0 = now_ns();
        int rc = omega_gpu_moe_plan_exec(cl, &ea, &ust);
        uint64_t t1 = now_ns();
        CHK(rc == 0, "unified moe_plan_exec");
        CHK(omega_moe_queue_complete_batch(&q, claimed, slots, rc == 0 ? 0u : 1u) == 0, "queue complete batch");
        if (rep == 3) uni_wall_ns = t1 - t0;
    }

    /* ---- Bit-exact equivalence check across ALL 4 stages ---- */
    CHK(memcmp(d_logits_ref.cpu, d_logits_uni.cpu, (size_t)T * E * 4u) == 0, "bit-exact router logits (64x128)");
    CHK(memcmp(h_gu_ref, d_gu_y.cpu, (size_t)M * N_GU * 4u) == 0, "bit-exact expert gate_up (512x1536)");
    CHK(memcmp(h_dn_ref, d_dn_y.cpu, (size_t)M * H * 4u) == 0, "bit-exact expert down (512x2048)");
    CHK(memcmp(d_out_ref.cpu, d_out_uni.cpu, (size_t)T * H * 4u) == 0, "bit-exact weighted combine out (64x2048)");

    printf("MOE_PLAN_AB T=%u H=%u I=%u E=%u top_k=%u (M=%u rows):\n", T, H, I, E, TOPK, M);
    printf("  SEPARATE (4 sync launches): wall=%.3f ms  chip_sum=%.3f ms (rl=%.3f gu=%.3f dn=%.3f mc=%.3f)\n",
           (double)sep_wall_ns / 1e6,
           (double)(sep_rl_ns + sep_gu_ns + sep_dn_ns + sep_mc_ns) / 1e6,
           (double)sep_rl_ns / 1e6, (double)sep_gu_ns / 1e6, (double)sep_dn_ns / 1e6, (double)sep_mc_ns / 1e6);
    printf("  UNIFIED  (1 PCAS submit, %u launches): wall=%.3f ms  chip=%.3f ms  host_build=%.3f ms\n",
           ust.launches, (double)uni_wall_ns / 1e6, (double)ust.chip_ns / 1e6, (double)ust.host_build_ns / 1e6);
    printf("  PTIMER   per-stage: rl=%.3f ms  gu=%.3f ms  dn=%.3f ms  mc=%.3f ms  (sum=%.3f ms)\n",
           (double)ust.stage_ns[0] / 1e6, (double)ust.stage_ns[1] / 1e6,
           (double)ust.stage_ns[2] / 1e6, (double)ust.stage_ns[3] / 1e6,
           (double)(ust.stage_ns[0] + ust.stage_ns[1] + ust.stage_ns[2] + ust.stage_ns[3]) / 1e6);
    printf("  TRAFFIC  total=%.1f MB (rl=%.1f gu=%.1f dn=%.1f mc=%.1f)  effective=%.1f GB/s\n",
           (double)ust.traffic.total_bytes / 1e6,
           (double)ust.traffic.router_bytes / 1e6, (double)ust.traffic.gateup_bytes / 1e6,
           (double)ust.traffic.down_bytes / 1e6, (double)ust.traffic.combine_bytes / 1e6,
           ust.effective_gbps);
    printf("  SPEEDUP  wall=%.2fx (saved %.3f ms/layer)  chip=%.2fx\n",
           uni_wall_ns ? (double)sep_wall_ns / (double)uni_wall_ns : 0.0,
           (double)((int64_t)sep_wall_ns - (int64_t)uni_wall_ns) / 1e6,
           ust.chip_ns ? (double)(sep_rl_ns + sep_gu_ns + sep_dn_ns + sep_mc_ns) / (double)ust.chip_ns : 0.0);

    omega_gpu_cmdlist_free(cl);
    omega_gpu_pf_free(&d_x); omega_gpu_pf_free(&d_rwq); omega_gpu_pf_free(&d_logits_ref); omega_gpu_pf_free(&d_logits_uni);
    omega_gpu_pf_free(&d_gu_seg); omega_gpu_pf_free(&d_gu_xp); omega_gpu_pf_free(&d_gu_y);
    omega_gpu_pf_free(&d_dn_seg); omega_gpu_pf_free(&d_dn_xp); omega_gpu_pf_free(&d_dn_y);
    omega_gpu_pf_free(&d_inv); omega_gpu_pf_free(&d_wt); omega_gpu_pf_free(&d_out_ref); omega_gpu_pf_free(&d_out_uni);
    omega_gpu_fp8_tensor_free(t_gu); omega_gpu_fp8_tensor_free(t_dn);
    free(h_x); free(h_rw); free(h_rwq); free(h_gu_w); free(h_gu_s); free(h_dn_w); free(h_dn_s);
    free(h_act); free(h_exp_ids); free(h_tok_rows); free(h_inv); free(h_wt); free(h_gu_ref); free(h_dn_ref);
    return 0;
}

int main(int argc, char **argv) {
    int host_only = 0;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--host-only") == 0) host_only = 1;
    }
    test_host_queue_and_planner();
    if (!host_only) run_chip_ab();
    printf("gpu_moe_plan_test: %d passed, %d failed: %s\n", g_pass, g_fail, g_fail ? "FAIL" : "PASS");
    return g_fail ? 1 : 0;
}
