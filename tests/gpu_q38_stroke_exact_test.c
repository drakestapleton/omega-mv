/*
 * gpu_q38_stroke_exact_test: GB10 silicon qualification of the Qwen3.8-27B multi-head stroke, batched dense FP8 GEMM,
 * and HUM L314 exact two-pass lm_head (H=5120, I=17408, vocab=248320).
 * Caller holds the GB10 lock (spark-window).
 * Verdict line last: "gpu_q38_stroke_exact_test: N checks, F failed: PASS|FAIL".
 */
#include "omega_gpu_q38_graph.h"
#include "omega_gpu_fp8_api.h"
#include "omega_gpu_bf16_gemv_api.h"
#include "omega_gpu_session.h"
#include <inttypes.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define H OMEGA_GPU_Q38_HIDDEN
#define I OMEGA_GPU_Q38_INTER
#define VOCAB 248320u
#define LAYERS 2u
#define MASK 0x2ull /* layer 0: GDN, layer 1: full attention */
#define HEADS 4u
#define MAX_POS 256u
#define EPS 1e-6f
#define SCALE_2M64 5.42101086242752217e-20f

static int g_checks, g_failed;
#define CHECK(c, ...) do { g_checks++; if (!(c)) { g_failed++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } else { printf("ok: "); printf(__VA_ARGS__); printf("\n"); } } while (0)

static uint32_t lcg(uint32_t *s) { *s = *s * 1664525u + 1013904223u; return *s; }
static float frand(uint32_t *s, float lo, float hi) { return lo + (hi - lo) * ((float)(lcg(s) >> 8) / 16777216.0f); }
static uint16_t bf16_rne(float f) { uint32_t x; memcpy(&x, &f, 4); uint32_t r = x + 0x7fffu + ((x >> 16) & 1u); return (uint16_t)(r >> 16); }
static float bf16_f32(uint16_t b) { uint32_t x = (uint32_t)b << 16; float f; memcpy(&f, &x, 4); return f; }
static float e4m3_f32(uint8_t u) {
    int s = (u >> 7) & 1, e = (u >> 3) & 0xf, m = u & 7;
    float v = e == 0 ? ldexpf((float)m, -9) : ldexpf((float)(8 + m), e - 10);
    return s ? -v : v;
}
static int cmp_u64(const void *a, const void *b) { uint64_t x = *(const uint64_t *)a, y = *(const uint64_t *)b; return x < y ? -1 : x > y; }
static uint64_t median_u64(uint64_t *v, unsigned n) { qsort(v, n, sizeof *v, cmp_u64); return v[n / 2]; }

static int fp8_random(uint32_t seed, uint32_t n, uint32_t k, OmegaGpuFp8Tensor **out) {
    size_t wb = (size_t)n * k, sb = (size_t)(n / 128) * (k / 128);
    uint8_t *w = malloc(wb); uint16_t *s = malloc(sb * 2);
    if (!w || !s) { free(w); free(s); return -1; }
    uint32_t st = seed;
    for (size_t i = 0; i < wb; i += 4) { uint32_t r = lcg(&st); for (unsigned j = 0; j < 4 && i + j < wb; j++) w[i + j] = (uint8_t)((r >> (8 * j)) & 0xbfu); }
    const float sc = 1.5f / sqrtf((float)k);
    for (size_t i = 0; i < sb; i++) s[i] = bf16_rne(frand(&st, 0.5f * sc, sc));
    int rc = omega_gpu_fp8_tensor_upload(1, n, k, w, s, out);
    free(w); free(s);
    return rc;
}

static int bf16_random(uint32_t seed, uint32_t n, uint32_t k, float lo, float hi, float mul, OmegaGpuBf16Tensor **out, uint16_t **keep) {
    uint16_t *w = malloc((size_t)n * k * 2);
    if (!w) return -1;
    uint32_t st = seed;
    for (size_t i = 0; i < (size_t)n * k; i++) w[i] = bf16_rne(frand(&st, lo, hi) * mul);
    int rc = omega_gpu_bf16_tensor_upload(n, k, w, out);
    if (keep) *keep = w; else free(w);
    return rc;
}

typedef struct {
    OmegaGpuFp8Tensor *mix, *o, *gu, *dn;
    OmegaGpuBf16Tensor *ab;
    float in_norm[H], post_norm[H];
} LayerW;

static int alloc_state(uint32_t seed_gdn, uint32_t seed_att, OmegaGpuGdn **gdn, OmegaGpuDecodeAttn256Cache **attn) {
    if (omega_gpu_gdn_alloc(1, gdn) != 0) { printf("gdn_alloc: %s\n", omega_gpu_gdn_last_error()); return -1; }
    if (omega_gpu_decode_attn256_cache_alloc(1, MAX_POS, 10000000.0, OMEGA_GPU_Q38_ROTARY, attn) != 0) { printf("attn_alloc: %s\n", omega_gpu_decode_attn_last_error()); return -1; }
    uint32_t st = seed_gdn;
    float conv[OMEGA_GDN_CONV_DIM * 4], alog[48], dt[48], nw[128];
    for (size_t i = 0; i < sizeof conv / 4; i++) conv[i] = frand(&st, -0.25f, 0.25f);
    for (unsigned i = 0; i < 48; i++) { alog[i] = frand(&st, -2.0f, 0.2f); dt[i] = frand(&st, -1.0f, 1.0f); }
    for (unsigned i = 0; i < 128; i++) nw[i] = frand(&st, 0.5f, 1.5f);
    if (omega_gpu_gdn_set_layer(*gdn, 0, conv, alog, dt, nw) != 0) return -1;
    st = seed_att;
    float qn[256], kn[256];
    for (unsigned i = 0; i < 256; i++) { qn[i] = frand(&st, 0.5f, 1.5f); kn[i] = frand(&st, 0.5f, 1.5f); }
    if (omega_gpu_decode_attn256_set_norms(*attn, 0, qn, kn) != 0) return -1;
    return 0;
}

int main(void) {
    LayerW L[LAYERS]; memset(L, 0, sizeof L);
    float fnorm[H];
    uint32_t st = 4242u;
    for (uint32_t l = 0; l < LAYERS; l++) {
        int attn = (int)((MASK >> l) & 1u);
        if (fp8_random(100 + l * 10, attn ? OMEGA_GPU_Q38_ATT_MIX : OMEGA_GPU_Q38_GDN_MIX, H, &L[l].mix) != 0 ||
            fp8_random(101 + l * 10, H, OMEGA_GPU_Q38_MIXER_OUT, &L[l].o) != 0 ||
            fp8_random(102 + l * 10, 2 * I, H, &L[l].gu) != 0 ||
            fp8_random(103 + l * 10, H, I, &L[l].dn) != 0) { printf("FAIL: fp8 upload\n"); return 1; }
        if (!attn && bf16_random(104 + l * 10, OMEGA_GPU_Q38_AB, H, -0.05f, 0.05f, SCALE_2M64, &L[l].ab, NULL) != 0) { printf("FAIL: ab upload\n"); return 1; }
        for (unsigned i = 0; i < H; i++) { L[l].in_norm[i] = frand(&st, 0.5f, 1.5f); L[l].post_norm[i] = frand(&st, 0.5f, 1.5f); }
    }
    for (unsigned i = 0; i < H; i++) fnorm[i] = frand(&st, 0.5f, 1.5f);

    /* bf16 lm_head [VOCAB][H] + FP8 screen + exact-head row bound coefficients */
    OmegaGpuBf16Tensor *lm = NULL;
    uint16_t *lm_raw = NULL;
    if (bf16_random(999, VOCAB, H, -0.04f, 0.04f, 1.0f, &lm, &lm_raw) != 0) { printf("FAIL: lm_head upload\n"); return 1; }
    size_t w8_n = (size_t)VOCAB * H, s8_n = (size_t)(VOCAB / 128) * (H / 128);
    uint8_t *w8 = malloc(w8_n); uint16_t *s8 = malloc(s8_n * 2); float *coef = malloc((size_t)VOCAB * 4);
    if (!w8 || !s8 || !coef) { printf("FAIL: host alloc\n"); return 1; }
    if (omega_gpu_fp8_quantize_bf16(VOCAB, H, lm_raw, w8, s8) != 0) { printf("FAIL: quantize_bf16\n"); return 1; }
    /* Conservative L2 row error bound: ||w_r - w~_r||_2 + gamma(10384) * (||w_r||_2 + ||w~_r||_2) */
    const double gamma = 10384.0 * 0x1p-23 / (1.0 - 10384.0 * 0x1p-23);
    for (uint32_t r = 0; r < VOCAB; r++) {
        double d2 = 0, w2 = 0, q2 = 0;
        const uint32_t rb = r / 128u;
        for (uint32_t c = 0; c < H; c++) {
            double wf = (double)bf16_f32(lm_raw[(size_t)r * H + c]);
            double sf = (double)bf16_f32(s8[(size_t)rb * (H / 128u) + c / 128u]);
            double qf = (double)e4m3_f32(w8[(size_t)r * H + c]) * sf;
            double df = wf - qf;
            d2 += df * df; w2 += wf * wf; q2 += qf * qf;
        }
        coef[r] = (float)((sqrt(d2) + gamma * (sqrt(w2) + sqrt(q2))) * 1.001 + 1e-6);
    }
    free(lm_raw);
    OmegaGpuFp8Tensor *screen = NULL;
    if (omega_gpu_fp8_tensor_upload(1, VOCAB, H, w8, s8, &screen) != 0) { printf("FAIL: screen upload\n"); return 1; }
    free(w8); free(s8);

    /* Allocate 4 head state pairs for single-head ref and 4 for stroke */
    OmegaGpuGdn *gdn_ref[HEADS], *gdn_st[HEADS];
    OmegaGpuDecodeAttn256Cache *att_ref[HEADS], *att_st[HEADS];
    for (uint32_t h = 0; h < HEADS; h++) {
        if (alloc_state(500, 600, &gdn_ref[h], &att_ref[h]) != 0 || alloc_state(500, 600, &gdn_st[h], &att_st[h]) != 0) {
            printf("FAIL: alloc_state\n"); return 1;
        }
    }

    /* Distinct embeddings for 2 steps x HEADS */
    float *x_step0 = malloc((size_t)HEADS * H * 4), *x_step1 = malloc((size_t)HEADS * H * 4);
    for (size_t i = 0; i < (size_t)HEADS * H; i++) { x_step0[i] = frand(&st, -1.5f, 1.5f); x_step1[i] = frand(&st, -1.5f, 1.5f); }

    /* ---- 1. Single-head reference (4 conversations separately) ---- */
    uint32_t ref_tok0[HEADS], ref_tok1[HEADS];
    float *ref_lg1[HEADS];
    for (uint32_t h = 0; h < HEADS; h++) {
        ref_lg1[h] = malloc((size_t)VOCAB * 4);
        OmegaGpuQ38GraphConfig c; memset(&c, 0, sizeof c);
        c.layers = LAYERS; c.attn_mask = MASK; c.vocab = VOCAB; c.eps = EPS; c.eps_l2 = EPS;
        c.gdn = gdn_ref[h]; c.attn = att_ref[h]; c.lm_head = lm;
        OmegaGpuQ38Graph *g1 = NULL;
        CHECK(omega_gpu_q38_graph_create(&c, &g1) == 0, "ref create head %u", h);
        for (uint32_t l = 0; l < LAYERS; l++)
            CHECK(omega_gpu_q38_graph_set_layer(g1, l, L[l].mix, L[l].ab, L[l].o, L[l].gu, L[l].dn, L[l].in_norm, L[l].post_norm) == 0, "ref set_layer %u", l);
        CHECK(omega_gpu_q38_graph_set_final_norm(g1, fnorm) == 0, "ref final_norm");
        CHECK(omega_gpu_q38_graph_token(g1, x_step0 + (size_t)h * H, 0, &ref_tok0[h], NULL) == 0, "ref token0 head %u", h);
        CHECK(omega_gpu_q38_graph_token(g1, x_step1 + (size_t)h * H, 1, &ref_tok1[h], NULL) == 0, "ref token1 head %u", h);
        CHECK(omega_gpu_q38_graph_read(g1, NULL, NULL, ref_lg1[h]) == 0, "ref read head %u", h);
        omega_gpu_q38_graph_free(g1);
    }

    /* ---- 2. Multi-head graph: unbatched stroke vs batched stroke ---- */
    OmegaGpuQ38GraphConfig cfg; memset(&cfg, 0, sizeof cfg);
    cfg.layers = LAYERS; cfg.attn_mask = MASK; cfg.vocab = VOCAB; cfg.eps = EPS; cfg.eps_l2 = EPS;
    cfg.gdn = gdn_st[0]; cfg.attn = att_st[0]; cfg.lm_head = lm;
    OmegaGpuQ38Graph *g = NULL;
    CHECK(omega_gpu_q38_graph_create_heads(&cfg, HEADS, &g) == 0, "create_heads(%u)", HEADS);
    for (uint32_t h = 0; h < HEADS; h++)
        CHECK(omega_gpu_q38_graph_set_head_state(g, h, gdn_st[h], att_st[h]) == 0, "set_head_state %u", h);
    for (uint32_t l = 0; l < LAYERS; l++)
        CHECK(omega_gpu_q38_graph_set_layer(g, l, L[l].mix, L[l].ab, L[l].o, L[l].gu, L[l].dn, L[l].in_norm, L[l].post_norm) == 0, "stroke set_layer %u", l);
    CHECK(omega_gpu_q38_graph_set_final_norm(g, fnorm) == 0, "stroke final_norm");

    /* 2a. Unbatched stroke (batch=0) */
    uint32_t pos0[HEADS] = { 0, 0, 0, 0 }, pos1[HEADS] = { 1, 1, 1, 1 };
    uint32_t tok0[HEADS] = { 0 }, tok1[HEADS] = { 0 };
    OmegaGpuDecodeGraphStats st_unb;
    CHECK(omega_gpu_q38_graph_stroke(g, x_step0, pos0, HEADS, tok0, NULL) == 0, "unbatched stroke step 0");
    CHECK(omega_gpu_q38_graph_stroke(g, x_step1, pos1, HEADS, tok1, &st_unb) == 0, "unbatched stroke step 1");
    float *got_lg = malloc((size_t)VOCAB * 4);
    for (uint32_t h = 0; h < HEADS; h++) {
        CHECK(tok0[h] == ref_tok0[h] && tok1[h] == ref_tok1[h], "unbatched head %u tokens exact (%u/%u vs %u/%u)", h, tok0[h], tok1[h], ref_tok0[h], ref_tok1[h]);
        CHECK(omega_gpu_q38_graph_read_head(g, h, NULL, NULL, got_lg) == 0, "unbatched read_head %u", h);
        CHECK(memcmp(got_lg, ref_lg1[h], (size_t)VOCAB * 4) == 0, "unbatched head %u logits bit-identical to single-head", h);
    }

    /* 2b. Batched stroke (set_batch(1): single weight read per layer for all 4 heads!) */
    for (uint32_t h = 0; h < HEADS; h++) omega_gpu_gdn_reset(gdn_st[h]);
    CHECK(omega_gpu_q38_graph_set_batch(g, 1) == 0 && omega_gpu_q38_graph_batch(g) == 1, "set_batch(1) ok");
    CHECK(omega_gpu_q38_graph_stroke(g, x_step0, pos0, HEADS, tok0, NULL) == 0, "batched stroke step 0");
    CHECK(omega_gpu_q38_graph_stroke(g, x_step1, pos1, HEADS, tok1, NULL) == 0, "batched stroke step 1");
    for (uint32_t h = 0; h < HEADS; h++) {
        CHECK(tok0[h] == ref_tok0[h] && tok1[h] == ref_tok1[h], "batched head %u tokens exact (%u/%u vs %u/%u)", h, tok0[h], tok1[h], ref_tok0[h], ref_tok1[h]);
        CHECK(omega_gpu_q38_graph_read_head(g, h, NULL, NULL, got_lg) == 0, "batched read_head %u", h);
        CHECK(memcmp(got_lg, ref_lg1[h], (size_t)VOCAB * 4) == 0, "batched head %u logits bit-identical to single-head", h);
    }

    /* Timing: 7 reps batched vs unbatched (4 heads, 2 layers 27B shape) */
    uint64_t t_unb[7], t_bat[7];
    uint32_t p_t[HEADS] = { 2, 2, 2, 2 };
    omega_gpu_q38_graph_set_batch(g, 0);
    for (unsigned r = 0; r < 7; r++) {
        OmegaGpuDecodeGraphStats st0;
        omega_gpu_q38_graph_stroke(g, x_step1, p_t, HEADS, tok1, &st0);
        t_unb[r] = st0.chip_ns;
    }
    omega_gpu_q38_graph_set_batch(g, 1);
    for (unsigned r = 0; r < 7; r++) {
        OmegaGpuDecodeGraphStats st0;
        omega_gpu_q38_graph_stroke(g, x_step1, p_t, HEADS, tok1, &st0);
        t_bat[r] = st0.chip_ns;
    }
    uint64_t med_unb = median_u64(t_unb, 7), med_bat = median_u64(t_bat, 7);
    printf("TIMING 4-head 2-layer 27B stroke: unbatched=%.3f ms, batched=%.3f ms (%.2fx)\n",
           med_unb / 1e6, med_bat / 1e6, (double)med_unb / (double)med_bat);
    CHECK(med_bat < med_unb, "batched 4-head stroke faster than unbatched (%.3f < %.3f ms)", med_bat / 1e6, med_unb / 1e6);

    /* ---- 3. Exact two-pass lm_head at H=5120, VOCAB=248320 ---- */
    omega_gpu_q38_graph_set_batch(g, 0);
    CHECK(omega_gpu_q38_graph_set_exact_head(g, screen, coef, 10384u) == 0 && omega_gpu_q38_graph_exact_head_active(g) == 1, "set_exact_head(screen, coef, 10384)");
    omega_gpu_gdn_reset(gdn_st[0]);
    uint32_t xh_tok0 = 0, xh_tok1 = 0;
    CHECK(omega_gpu_q38_graph_token(g, x_step0, 0, &xh_tok0, NULL) == 0, "exact_head token 0");
    CHECK(omega_gpu_q38_graph_token(g, x_step1, 1, &xh_tok1, NULL) == 0, "exact_head token 1");
    CHECK(xh_tok0 == ref_tok0[0] && xh_tok1 == ref_tok1[0], "exact_head tokens match plain bf16 (%u/%u vs %u/%u)", xh_tok0, xh_tok1, ref_tok0[0], ref_tok1[0]);

    /* Mutant 5 (MASK inverted) must be caught */
    omega_gpu_q38_graph_test_set_mutant(g, 5);
    omega_gpu_gdn_reset(gdn_st[0]);
    uint32_t m5_tok0 = 0;
    CHECK(omega_gpu_q38_graph_token(g, x_step0, 0, &m5_tok0, NULL) == 0 && m5_tok0 != ref_tok0[0], "exact_head mutant 5 (MASK inverted) caught (%u != %u)", m5_tok0, ref_tok0[0]);
    omega_gpu_q38_graph_test_set_mutant(g, 0);

    /* Exact-head timing: 7 reps OFF vs ON */
    uint64_t t_plain[7], t_xh[7];
    omega_gpu_q38_graph_set_exact_head_on(g, 0);
    for (unsigned r = 0; r < 7; r++) { OmegaGpuDecodeGraphStats st0; omega_gpu_q38_graph_token(g, x_step1, 2, &xh_tok1, &st0); t_plain[r] = st0.chip_ns; }
    omega_gpu_q38_graph_set_exact_head_on(g, 1);
    for (unsigned r = 0; r < 7; r++) { OmegaGpuDecodeGraphStats st0; omega_gpu_q38_graph_token(g, x_step1, 2, &xh_tok1, &st0); t_xh[r] = st0.chip_ns; }
    uint64_t med_p = median_u64(t_plain, 7), med_x = median_u64(t_xh, 7);
    printf("TIMING 1-head 2-layer 27B token: plain_bf16=%.3f ms, exact_two_pass=%.3f ms (saved %.3f ms)\n",
           med_p / 1e6, med_x / 1e6, (double)((int64_t)med_p - (int64_t)med_x) / 1e6);

    omega_gpu_q38_graph_free(g);
    for (uint32_t h = 0; h < HEADS; h++) {
        omega_gpu_gdn_free(gdn_ref[h]); omega_gpu_decode_attn256_cache_free(att_ref[h]);
        omega_gpu_gdn_free(gdn_st[h]); omega_gpu_decode_attn256_cache_free(att_st[h]);
        free(ref_lg1[h]);
    }
    free(got_lg); free(x_step0); free(x_step1); free(coef);
    omega_gpu_fp8_tensor_free(screen);
    omega_gpu_bf16_tensor_free(lm);
    for (uint32_t l = 0; l < LAYERS; l++) {
        omega_gpu_fp8_tensor_free(L[l].mix); omega_gpu_fp8_tensor_free(L[l].o);
        omega_gpu_fp8_tensor_free(L[l].gu); omega_gpu_fp8_tensor_free(L[l].dn);
        if (L[l].ab) omega_gpu_bf16_tensor_free(L[l].ab);
    }
    printf("gpu_q38_stroke_exact_test: %d checks, %d failed: %s\n", g_checks, g_failed, g_failed ? "FAIL" : "PASS");
    return g_failed ? 1 : 0;
}
