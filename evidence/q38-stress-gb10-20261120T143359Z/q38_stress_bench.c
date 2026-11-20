#include "omega_gpu_cmdlist.h"
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
#define LAYERS 4u
#define MASK 0x8ull /* 3 GDN (0,1,2) + 1 full attention (3) */
#define MAX_HEADS 8u
#define MAX_POS 256u
#define EPS 1e-6f
#define SCALE_2M64 5.42101086242752217e-20f

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
    uint32_t st = seed;
    for (size_t i = 0; i < wb; i += 4) { uint32_t r = lcg(&st); for (unsigned j = 0; j < 4 && i + j < wb; j++) w[i + j] = (uint8_t)((r >> (8 * j)) & 0xbfu); }
    const float sc = 1.5f / sqrtf((float)k);
    for (size_t i = 0; i < sb; i++) s[i] = bf16_rne(frand(&st, 0.5f * sc, sc));
    int rc = omega_gpu_fp8_tensor_upload(1, n, k, w, s, out);
    free(w); free(s); return rc;
}
static int bf16_random(uint32_t seed, uint32_t n, uint32_t k, float lo, float hi, float mul, OmegaGpuBf16Tensor **out, uint16_t **keep) {
    uint16_t *w = malloc((size_t)n * k * 2);
    uint32_t st = seed;
    for (size_t i = 0; i < (size_t)n * k; i++) w[i] = bf16_rne(frand(&st, lo, hi) * mul);
    int rc = omega_gpu_bf16_tensor_upload(n, k, w, out);
    if (keep) *keep = w; else free(w);
    return rc;
}
static int build_exact_screen(const uint16_t *lm_w, OmegaGpuFp8Tensor **screen_out, float **coef_out) {
    const uint32_t nb = VOCAB / 128u, kb = H / 128u;
    uint8_t *qw = malloc((size_t)VOCAB * H);
    uint16_t *qs = malloc((size_t)nb * kb * 2);
    float *coef = calloc(VOCAB, 4);
    for (uint32_t b0 = 0; b0 < nb; b0++) {
        for (uint32_t b1 = 0; b1 < kb; b1++) {
            float amax = 0.0f;
            for (uint32_t r = 0; r < 128; r++) {
                const uint16_t *row = lm_w + (size_t)(b0 * 128 + r) * H + b1 * 128;
                for (uint32_t c = 0; c < 128; c++) { float v = fabsf(bf16_f32(row[c])); if (v > amax) amax = v; }
            }
            float sc = amax > 0.0f ? amax / 448.0f : 1e-6f;
            uint16_t sc16 = bf16_rne(sc);
            sc = bf16_f32(sc16);
            qs[(size_t)b0 * kb + b1] = sc16;
            float inv = 1.0f / sc;
            for (uint32_t r = 0; r < 128; r++) {
                const uint16_t *row = lm_w + (size_t)(b0 * 128 + r) * H + b1 * 128;
                uint8_t *dst = qw + (size_t)(b0 * 128 + r) * H + b1 * 128;
                double err2 = 0.0;
                for (uint32_t c = 0; c < 128; c++) {
                    float vf = bf16_f32(row[c]), qf = vf * inv;
                    int neg = qf < 0.0f; float a = fabsf(qf);
                    uint8_t best = 0; float bd = a;
                    for (uint8_t code = 1; code < 127; code++) {
                        float ev = e4m3_f32(code); float d = fabsf(ev - a);
                        if (d < bd) { bd = d; best = code; }
                    }
                    uint8_t enc = (uint8_t)(best | (neg ? 0x80u : 0u));
                    dst[c] = enc;
                    double diff = (double)vf - (double)e4m3_f32(enc) * (double)sc;
                    err2 += diff * diff;
                }
                coef[b0 * 128 + r] += (float)err2;
            }
        }
    }
    for (uint32_t r = 0; r < VOCAB; r++) coef[r] = sqrtf(coef[r]) * 1.01f;
    int rc = omega_gpu_fp8_tensor_upload(1, VOCAB, H, qw, qs, screen_out);
    free(qw); free(qs); *coef_out = coef;
    return rc;
}

static void print_ptimer(const char *label, OmegaGpuQ38Graph *g) {
    static uint64_t st[OMEGA_GPU_CMDLIST_MAX_LAUNCHES + 1];
    static uint8_t kd[OMEGA_GPU_CMDLIST_MAX_LAUNCHES];
    int n = omega_gpu_q38_graph_stamps(g, st, kd, OMEGA_GPU_CMDLIST_MAX_LAUNCHES + 1);
    double sum[OMEGA_GPU_Q38_K_COUNT] = { 0 };
    uint32_t cnt[OMEGA_GPU_Q38_K_COUNT] = { 0 };
    double total = 0, trunk = 0;
    for (int i = 0; i < n; i++) {
        double us = (double)(st[i + 1] - st[i]) / 1e3;
        sum[kd[i]] += us; cnt[kd[i]]++; total += us;
        if (kd[i] != OMEGA_GPU_Q38_K_LM_HEAD && kd[i] != OMEGA_GPU_Q38_K_ARGMAX) trunk += us;
    }
    printf("PTIMER [%s]: launches=%d total=%.1f us trunk=%.1f us\n", label, n, total, trunk);
    for (uint8_t k = 0; k < OMEGA_GPU_Q38_K_COUNT; k++)
        if (cnt[k]) printf("  %-10s %3u launches %9.1f us\n", omega_gpu_q38_graph_kind_name(k), cnt[k], sum[k]);
}

int main(void) {
    struct { OmegaGpuFp8Tensor *mix, *o, *gu, *dn; OmegaGpuBf16Tensor *ab; float in_n[H], po_n[H]; } L[LAYERS];
    uint32_t seed = 1337;
    for (uint32_t l = 0; l < LAYERS; l++) {
        int attn = (int)((MASK >> l) & 1u);
        if (fp8_random(seed++, attn ? 14336u : 16384u, H, &L[l].mix) != 0) return 2;
        if (fp8_random(seed++, H, 6144u, &L[l].o) != 0) return 2;
        if (fp8_random(seed++, 2 * I, H, &L[l].gu) != 0) return 2;
        if (fp8_random(seed++, H, I, &L[l].dn) != 0) return 2;
        L[l].ab = NULL;
        if (!attn && bf16_random(seed++, 96u, H, -0.5f, 0.5f, SCALE_2M64, &L[l].ab, NULL) != 0) return 2;
        for (unsigned i = 0; i < H; i++) { L[l].in_n[i] = frand(&seed, 0.5f, 1.5f); L[l].po_n[i] = frand(&seed, 0.5f, 1.5f); }
    }
    OmegaGpuBf16Tensor *lm = NULL; uint16_t *lm_w = NULL;
    if (bf16_random(seed++, VOCAB, H, -0.05f, 0.05f, 1.0f, &lm, &lm_w) != 0) return 2;
    OmegaGpuFp8Tensor *screen = NULL; float *coef = NULL;
    if (build_exact_screen(lm_w, &screen, &coef) != 0) return 2;
    free(lm_w);
    float fnorm[H]; for (unsigned i = 0; i < H; i++) fnorm[i] = frand(&seed, 0.5f, 1.5f);

    OmegaGpuGdn *gdn[MAX_HEADS]; OmegaGpuDecodeAttn256Cache *att[MAX_HEADS];
    for (uint32_t h = 0; h < MAX_HEADS; h++) {
        if (omega_gpu_gdn_alloc(3, &gdn[h]) != 0) return 3;
        if (omega_gpu_decode_attn256_cache_alloc(1, MAX_POS, 10000000.0, OMEGA_GPU_Q38_ROTARY, &att[h]) != 0) return 3;
        float conv[OMEGA_GDN_CONV_DIM * 4], alog[48], dt[48], nw[128], qn[256], kn[256];
        for (size_t i = 0; i < sizeof conv / 4; i++) conv[i] = frand(&seed, -0.25f, 0.25f);
        for (unsigned i = 0; i < 48; i++) { alog[i] = frand(&seed, -2.0f, 0.2f); dt[i] = frand(&seed, -1.0f, 1.0f); }
        for (unsigned i = 0; i < 128; i++) nw[i] = frand(&seed, 0.5f, 1.5f);
        for (uint32_t g = 0; g < 3; g++) omega_gpu_gdn_set_layer(gdn[h], g, conv, alog, dt, nw);
        for (unsigned i = 0; i < 256; i++) { qn[i] = frand(&seed, 0.5f, 1.5f); kn[i] = frand(&seed, 0.5f, 1.5f); }
        omega_gpu_decode_attn256_set_norms(att[h], 0, qn, kn);
    }

    OmegaGpuQ38GraphConfig cfg; memset(&cfg, 0, sizeof cfg);
    cfg.layers = LAYERS; cfg.attn_mask = MASK; cfg.vocab = VOCAB; cfg.eps = EPS; cfg.eps_l2 = EPS;
    cfg.gdn = gdn[0]; cfg.attn = att[0]; cfg.lm_head = lm;
    OmegaGpuQ38Graph *g = NULL;
    if (omega_gpu_q38_graph_create_heads(&cfg, MAX_HEADS, &g) != 0) { printf("create_heads fail: %s\n", omega_gpu_session_last_error()); return 4; }
    for (uint32_t h = 0; h < MAX_HEADS; h++) omega_gpu_q38_graph_set_head_state(g, h, gdn[h], att[h]);
    for (uint32_t l = 0; l < LAYERS; l++) omega_gpu_q38_graph_set_layer(g, l, L[l].mix, L[l].ab, L[l].o, L[l].gu, L[l].dn, L[l].in_n, L[l].po_n);
    omega_gpu_q38_graph_set_final_norm(g, fnorm);
    if (omega_gpu_q38_graph_set_exact_head(g, screen, coef, 10384u) != 0) return 5;
    omega_gpu_q38_graph_set_exact_head_on(g, 0);

    float *x = malloc((size_t)MAX_HEADS * H * 4);
    for (size_t i = 0; i < (size_t)MAX_HEADS * H; i++) x[i] = frand(&seed, -1.0f, 1.0f);
    uint32_t pos[MAX_HEADS] = { 1, 1, 1, 1, 1, 1, 1, 1 }, tok[MAX_HEADS] = { 0 }, tok_ref[MAX_HEADS] = { 0 };

    /* Parity check: N=8 batched exact_head vs plain bf16 */
    omega_gpu_q38_graph_set_batch(g, 0); omega_gpu_q38_graph_set_exact_head_on(g, 0);
    for (uint32_t h = 0; h < MAX_HEADS; h++) omega_gpu_gdn_reset(gdn[h]);
    if (omega_gpu_q38_graph_stroke(g, x, pos, MAX_HEADS, tok_ref, NULL) != 0) { printf("ref stroke fail: %s\n", omega_gpu_session_last_error()); return 6; }

    omega_gpu_q38_graph_set_batch(g, 1); omega_gpu_q38_graph_set_exact_head_on(g, 0);
    for (uint32_t h = 0; h < MAX_HEADS; h++) omega_gpu_gdn_reset(gdn[h]);
    if (omega_gpu_q38_graph_stroke(g, x, pos, MAX_HEADS, tok, NULL) != 0) { printf("bat plain fail: %s\n", omega_gpu_session_last_error()); return 6; }
    int bad_plain = 0; for (uint32_t h = 0; h < MAX_HEADS; h++) if (tok[h] != tok_ref[h]) bad_plain++;
    printf("PARITY N=8 batched plain bf16 (XB=4) vs unbatched: %d/8 exact\n", 8 - bad_plain);

    omega_gpu_q38_graph_set_batch(g, 1); omega_gpu_q38_graph_set_exact_head_on(g, 1);
    for (uint32_t h = 0; h < MAX_HEADS; h++) omega_gpu_gdn_reset(gdn[h]);
    if (omega_gpu_q38_graph_stroke(g, x, pos, MAX_HEADS, tok, NULL) != 0) { printf("bat exact fail: %s\n", omega_gpu_session_last_error()); return 6; }
    int bad_ex = 0; for (uint32_t h = 0; h < MAX_HEADS; h++) if (tok[h] != tok_ref[h]) bad_ex++;
    printf("PARITY N=8 batched exact_head vs plain bf16: %d/8 exact\n", 8 - bad_ex);
    if (bad_plain || bad_ex) return 7;

    /* Sweep N = 1, 2, 4, 6, 8: plain bf16 unbatched vs batched + exact_head batched */
    const uint32_t ns[] = { 1, 2, 4, 6, 8 };
    for (unsigned ni = 0; ni < 5; ni++) {
        uint32_t N = ns[ni];
        uint64_t tu[7], tb[7], te[7];
        omega_gpu_q38_graph_set_exact_head_on(g, 0); omega_gpu_q38_graph_set_batch(g, 0);
        for (unsigned r = 0; r < 7; r++) { OmegaGpuDecodeGraphStats st; omega_gpu_q38_graph_stroke(g, x, pos, N, tok, &st); tu[r] = st.chip_ns; }
        omega_gpu_q38_graph_set_batch(g, 1);
        for (unsigned r = 0; r < 7; r++) { OmegaGpuDecodeGraphStats st; omega_gpu_q38_graph_stroke(g, x, pos, N, tok, &st); tb[r] = st.chip_ns; }
        omega_gpu_q38_graph_set_exact_head_on(g, 1);
        for (unsigned r = 0; r < 7; r++) { OmegaGpuDecodeGraphStats st; omega_gpu_q38_graph_stroke(g, x, pos, N, tok, &st); te[r] = st.chip_ns; }
        printf("SWEEP N=%u: unb_bf16=%.3f ms | bat_bf16=%.3f ms (%.2fx) | bat_exact=%.3f ms (%.2fx)\n",
               N, median_u64(tu, 7)/1e6, median_u64(tb, 7)/1e6, (double)median_u64(tu,7)/(double)median_u64(tb,7),
               median_u64(te, 7)/1e6, (double)median_u64(tu,7)/(double)median_u64(te,7));
    }

    /* PTIMER breakdowns */
    omega_gpu_q38_graph_set_stamps(g, 1);
    omega_gpu_q38_graph_set_batch(g, 0); omega_gpu_q38_graph_set_exact_head_on(g, 0);
    omega_gpu_q38_graph_stroke(g, x, pos, 1, tok, NULL); print_ptimer("N=1 unb plain_bf16", g);
    omega_gpu_q38_graph_set_exact_head_on(g, 1);
    omega_gpu_q38_graph_stroke(g, x, pos, 1, tok, NULL); print_ptimer("N=1 unb exact_head", g);
    omega_gpu_q38_graph_set_batch(g, 1); omega_gpu_q38_graph_set_exact_head_on(g, 0);
    omega_gpu_q38_graph_stroke(g, x, pos, 8, tok, NULL); print_ptimer("N=8 bat plain_bf16", g);
    omega_gpu_q38_graph_set_exact_head_on(g, 1);
    omega_gpu_q38_graph_stroke(g, x, pos, 8, tok, NULL); print_ptimer("N=8 bat exact_head", g);
    omega_gpu_q38_graph_set_stamps(g, 0);

    /* Sustained 64 x 8 stress (batched + exact_head ON) */
    uint64_t ts[64], sum_ns = 0;
    for (unsigned s = 0; s < 64; s++) {
        uint32_t ps[MAX_HEADS]; for (uint32_t h = 0; h < MAX_HEADS; h++) ps[h] = 2u + (s % 64u);
        OmegaGpuDecodeGraphStats st;
        if (omega_gpu_q38_graph_stroke(g, x, ps, MAX_HEADS, tok, &st) != 0) { printf("stress step %u fail\n", s); return 8; }
        ts[s] = st.chip_ns; sum_ns += st.chip_ns;
    }
    qsort(ts, 64, sizeof *ts, cmp_u64);
    printf("STRESS 64x8 (bat_exact): min=%.3f p50=%.3f p95=%.3f max=%.3f mean=%.3f ms (%.2f tok/s)\n",
           ts[0]/1e6, ts[32]/1e6, ts[60]/1e6, ts[63]/1e6, (sum_ns/64.0)/1e6, 8.0 / ((sum_ns/64.0)/1e9));
    printf("Q38_STRESS_BENCH: PASS\n");
    return 0;
}
