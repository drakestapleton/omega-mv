/*
 * omega_gpu_q38_graph.c: Qwen3.8-27B (and 9B) dense decode graph as one command list (see the header). Records the FP8 /
 * bf16 GEMV (and grouped FP8 GEMM for batched multi-head strokes), GDN and hd256 attention APIs' *_record launches and the
 * omega_blackwell_codegen_dec glue kernels at width H into an omega_gpu_cmdlist. Buffers: buf from omega_gpu_session_alloc
 * (GPU-uncached, nvos.h:1117) holds every region the host touches: x (before), token and logits (after), the tables; dbuf
 * (GPU-cached, omega_gpu_mem_cached.h) holds the chip-only intermediates (see Layout).
 */
#include "omega_gpu_q38_graph.h"
#include "omega_gpu_cmdlist.h"
#include "omega_blackwell_codegen_dec.h"
#include "omega_blackwell_qmd.h"
#include "omega_gpu_session.h"
#include "omega_gpu_fmt.h"
#include "omega_gpu_mem_cached.h"
#include "omega_gpu_fp8gemm_api.h"
#include "omega_native.h"
#include <stdlib.h>
#include <string.h>

#define TIMEOUT_MS 20000ull
#define SCALE_2P64 18446744073709551616.0f
#define NEG_PAD (-1e30f)
#define TOKEN_POISON 0xffffffffu
#define TOKEN_STRIDE 256u /* bytes per head's token slot (two u32, 256-aligned) */
#define SEGD_ROWS 4u      /* dense segment entries per layer in the batch: mix, o, gate_up, down */
#define H (g->hd)         /* the model shape (config; 27B defaults): every use has the graph g in scope */
#define I (g->in)

/* glue kernels */
enum {
    K_NORM, K_ADDNORM, K_SW, K_GATHER, K_GATE, K_AM0, K_AM1, K_SW_M1, K_GATHER_M1, K_GATE_M1, K_ADDNORM_M1, K_COPY, K_ADD,
    K_NORM_R, K_ADDNORM_R, K_ADDNORM_R_M1, K_PERM_XQ, K_PERM_O, K_PERM_ACT, K_XS, K_XB, K_XB_M1, K_COUNT
};
#define COPY_ROW 256u /* K_COPY: GATHER rows of 256 floats through the identity table */

typedef struct { OmegaGpuMem code; uint32_t gpr; } Kern;

/* byte offsets into two buffers, every region 256-byte aligned (RES loads 16-byte vectors). [0, split): buf, GPU-uncached,
 * every region the host writes or reads. [split, bytes): dbuf, the chip-only intermediates, GPU-cached unless
 * AIEN_OMEGA_Q38_BUF_CACHED=0. read_buf copies a dbuf region into stage with a chip launch (K_COPY) before the host reads it. */
typedef struct {
    size_t x, ab, hidden, logits, am_v, am_i, token, norms, fnorm, tabs, gtab, idtab, stage, segd, xh_seg, ptab, split;
    size_t xq, mix, agg, att, o, gu, act;
    /* batched dense decode (v2): N = heads laid out */
    size_t xp, mixN, abN, aggN, attN, op, oN, guN, actN, actp, bytes;
} Layout;

struct OmegaGpuQ38Graph {
    OmegaGpuQ38GraphConfig cfg;
    /* the shape, resolved: hidden, inter, attention q / kv heads, GDN value heads; GDN qkv and qkv|z widths, a|b width,
     * attention mix (q_proj|k_proj|v_proj) and kernel-row widths, mixer output width (see the header) */
    uint32_t hd, in, qh, kvh, gh, gqkv, gmix, ab, amix, aqkv, mout;
    uint32_t am_ctas;                    /* stage-1 ARGMAX CTAs = ceil(vocab / 2048) */
    Layout lo;
    OmegaGpuMem buf, dbuf;               /* the host-visible regions; the chip-only regions (see Layout) */
    Kern k[K_COUNT];
    OmegaGpuCmdList *cl;
    /* bf16 set (set_layer_bf16): mix / o / gu / dn are bf16 tensors (bmix ...) recorded with the bf16 GEMV, else FP8;
     * bdn2: the down projection's second K half (bdn then holds the first) */
    struct { const OmegaGpuFp8Tensor *mix, *o, *gu, *dn; const OmegaGpuBf16Tensor *ab, *bmix, *bo, *bgu, *bdn, *bdn2; uint32_t kind_index; int attn, set, bf16; } layer[OMEGA_GPU_Q38_MAX_LAYERS];
    int final_set;
    const OmegaGpuFp8Tensor *head8;      /* set_lm_head_fp8: FP8 lm_head (hidden is then written x 2^64, read() undoes it) */
    /* heads (strokes): slot h of x, hidden, xq, logits and token; head 0's state objects are cfg.gdn / cfg.attn */
    uint32_t heads;                      /* slots laid out (create_heads); 1 = the plain graph */
    OmegaGpuGdn *gdn_h[OMEGA_GPU_Q38_MAX_HEADS];
    OmegaGpuDecodeAttn256Cache *attn_h[OMEGA_GPU_Q38_MAX_HEADS];
    struct {                             /* set_exact_head: the HUM L314 two-pass head (bf16 lm_head only) */
        const OmegaGpuFp8Tensor *screen; /* fp8b copy of lm_head (128 x 128 block scales) */
        OmegaGpuMem mem;                 /* h8 | s | c | hi | lo (am_ctas * 2048, padded) | tau | tab */
        uint64_t h8, s, c, hi, lo, tau, tab;
        uint32_t roundings;
        uint8_t on[OMEGA_GPU_Q38_MAX_HEADS];
    } xh;
    /* token / stroke state */
    int in_token, failed;
    uint32_t stroke_heads;               /* heads in the open stroke */
    int xq_layer[OMEGA_GPU_Q38_MAX_HEADS]; /* per head: layer whose input-norm x' sits in head h's xq slot, -1 none */
    int hidden_ready[OMEGA_GPU_Q38_MAX_HEADS];
    uint64_t t_begin;
    OmegaGpuDecodeGraphStats acc;
    int flush_each, mutant;
    int batch;                           /* 1: stroke() records each FP8 layer for every head at once (v2); set_batch */
    int stamps;
    uint32_t n_kind, tagged_in_list, n_stamp;
    uint8_t kind[OMEGA_GPU_CMDLIST_MAX_LAUNCHES];
    uint64_t stamp[OMEGA_GPU_CMDLIST_MAX_LAUNCHES + 1];
};

static size_t al(size_t v) { return (v + 255u) & ~(size_t)255u; }
static uint64_t va_of(const OmegaGpuQ38Graph *g, size_t off) { return off < g->lo.split ? g->buf.va + off : g->dbuf.va + (off - g->lo.split); }
static void *cpu_of(const OmegaGpuQ38Graph *g, size_t off) { return (uint8_t *)g->buf.cpu + off; } /* host regions only (off < split) */
static size_t x_of(const OmegaGpuQ38Graph *g, uint32_t h) { return g->lo.x + (size_t)h * H * 4u; }
static size_t hidden_of(const OmegaGpuQ38Graph *g, uint32_t h) { return g->lo.hidden + (size_t)h * H * 4u; }
static size_t xq_of(const OmegaGpuQ38Graph *g, uint32_t h) { return g->lo.xq + (size_t)h * H * 4u; }
static size_t logits_of(const OmegaGpuQ38Graph *g, uint32_t h) { return g->lo.logits + (size_t)h * g->am_ctas * OMEGA_DEC_ARGMAX_SPAN * 4u; }
static size_t amv_of(const OmegaGpuQ38Graph *g, uint32_t h) { return g->lo.am_v + (size_t)h * OMEGA_DEC_ARGMAX_SPAN * 4u; }
static size_t ami_of(const OmegaGpuQ38Graph *g, uint32_t h) { return g->lo.am_i + (size_t)h * OMEGA_DEC_ARGMAX_SPAN * 4u; }
static size_t token_of(const OmegaGpuQ38Graph *g, uint32_t h) { return g->lo.token + (size_t)h * TOKEN_STRIDE; }
static void put64(uint32_t *a, unsigned off, uint64_t v) { a[(off - 0x380) / 4] = (uint32_t)v; a[(off - 0x380) / 4 + 1] = (uint32_t)(v >> 32); }
static void putf(uint32_t *a, unsigned off, float f) { memcpy(&a[(off - 0x380) / 4], &f, 4); }
static int fail(OmegaGpuQ38Graph *g, const char *what, int rc) {
    if (g) g->failed = 1;
    if (what) omega_gpu_session_set_error(what);
    return rc;
}

int omega_q38_gather_table(uint32_t q_heads, uint32_t kv_heads, uint32_t *tab) {
    if (!tab || q_heads == 0 || q_heads > 24u || kv_heads == 0 || q_heads % kv_heads != 0) return -1;
    const uint32_t R = OMEGA_GPU_Q38_ROTARY, QP = q_heads * 512u, KP = QP + kv_heads * 256u;
    const uint32_t qn = q_heads * 256u, kn = kv_heads * 256u, qkv = qn + 2u * kn, mix = (q_heads + kv_heads) * 512u;
    for (uint32_t n = 0; n < mix; n++) {
        uint32_t s;
        if (n < qn) s = (n / 256u) * 512u + omega_dattn256_perm_slot(n % 256u, R);                      /* q, permuted */
        else if (n < qn + kn) s = QP + ((n - qn) / 256u) * 256u + omega_dattn256_perm_slot(n % 256u, R); /* k, permuted */
        else if (n < qkv) s = KP + (n - qn - kn);                                                        /* v */
        else s = ((n - qkv) / 256u) * 512u + 256u + (n - qkv) % 256u;                                    /* gate */
        tab[n] = s;
    }
    return 0;
}

/* GATHER table of the FP8 GEMM's x' lane layout (omega_fp8gemm_permute_x: lane_bytes 16 when k % 512 == 0 else 8):
 * permuted index i = s0 + (w*32 + L)*4 + e holds source column c = s0 + L*lb + w*4 + e, so tab[i] = c. */
void omega_q38_perm_table(uint32_t *tab, uint32_t k) {
    if (!tab || k == 0 || k % 256u != 0) return;
    const uint32_t lb = (k % 512u == 0) ? 16u : 8u;
    const uint32_t step = 32u * lb, words = lb / 4u;
    for (uint32_t s0 = 0; s0 < k; s0 += step)
        for (uint32_t L = 0; L < 32u; L++)
            for (uint32_t w = 0; w < words; w++)
                for (uint32_t e = 0; e < 4u; e++) tab[s0 + (w * 32u + L) * 4u + e] = s0 + L * lb + w * 4u + e;
}

static void write_dense_segments(OmegaGpuQ38Graph *g, uint32_t heads);

/* lock held */
static int kern_build(Kern *k, const OmegaDecSpec *s) {
    BlackwellIRProgram *prog = omega_gpu_host_calloc(1, sizeof *prog);
    if (!prog) return OMEGA_GPU_DGRAPH_CODEGEN_FAIL;
    int rc = OMEGA_GPU_DGRAPH_OK;
    size_t need = 0;
    if (omega_blackwell_codegen_dec_prog(s, prog) != 0 || (need = omega_bw_program_code_bytes(prog)) == 0) rc = OMEGA_GPU_DGRAPH_CODEGEN_FAIL;
    else if (omega_gpu_session_alloc_code(need, &k->code) != 0) rc = OMEGA_GPU_DGRAPH_CHIP_FAIL;
    else {
        OmegaBlackwellKernel kk;
        if (omega_blackwell_kernel_encode_into(prog, k->code.cpu, need, &kk) != 0 || kk.code_size != need) rc = OMEGA_GPU_DGRAPH_CODEGEN_FAIL;
        else if (omega_gpu_session_sync_to_gpu(&k->code) != 0) rc = OMEGA_GPU_DGRAPH_CHIP_FAIL;
        else { k->gpr = omega_bw_gpr_declared(kk.gpr_count); if (k->gpr < 64u) k->gpr = 64u; } /* as the decode graph */
        if (rc != OMEGA_GPU_DGRAPH_OK) { omega_gpu_session_free(&k->code); memset(k, 0, sizeof *k); }
    }
    omega_gpu_host_free(prog);
    return rc;
}

void omega_gpu_q38_graph_free(OmegaGpuQ38Graph *g) {
    if (!g) return;
    if (g->cl) omega_gpu_cmdlist_free(g->cl);
    omega_gpu_session_lock();
    for (unsigned i = 0; i < K_COUNT; i++) if (g->k[i].code.cpu) omega_gpu_session_free(&g->k[i].code);
    if (g->buf.cpu) omega_gpu_session_free(&g->buf);
    if (g->dbuf.cpu) omega_gpu_session_free(&g->dbuf);
    if (g->xh.mem.cpu) omega_gpu_session_free(&g->xh.mem);
    omega_gpu_session_unlock();
    omega_gpu_host_free(g);
}

int omega_gpu_q38_graph_create(const OmegaGpuQ38GraphConfig *cfg, OmegaGpuQ38Graph **out) {
    return omega_gpu_q38_graph_create_heads(cfg, 1, out);
}

int omega_gpu_q38_graph_create_heads(const OmegaGpuQ38GraphConfig *cfg, uint32_t heads, OmegaGpuQ38Graph **out) {
    if (out) *out = NULL;
    if (heads == 0 || heads > OMEGA_GPU_Q38_MAX_HEADS) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    if (!cfg || !out || cfg->layers == 0 || cfg->layers > OMEGA_GPU_Q38_MAX_LAYERS || !cfg->gdn || !cfg->attn || !cfg->lm_head ||
        cfg->vocab == 0 || cfg->vocab > OMEGA_DEC_ARGMAX_SPAN * OMEGA_DEC_ARGMAX_SPAN) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    if (cfg->layers < 64u && (cfg->attn_mask >> cfg->layers) != 0) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    /* the shape: zero fields take the 27B values; the widths are capped at the 27B ones (the RES kernel's 1024-lane rows,
     * the SWIGLU / GATE 256-lane grids, the attention kernel's q / kv group) */
    const uint32_t hd = cfg->hidden ? cfg->hidden : OMEGA_GPU_Q38_HIDDEN, in = cfg->inter ? cfg->inter : OMEGA_GPU_Q38_INTER;
    const uint32_t qh = cfg->q_heads ? cfg->q_heads : 24u, kvh = cfg->kv_heads ? cfg->kv_heads : 4u, gh = cfg->gdn_heads ? cfg->gdn_heads : 48u;
    if (hd % 1024u || hd > OMEGA_GPU_Q38_HIDDEN || in == 0 || in % 256u || in > OMEGA_GPU_Q38_INTER || qh > 24u || qh % kvh ||
        qh / kvh > 8u || (gh != 32u && gh != 48u) || qh * 256u != gh * 128u) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    OmegaGpuDecodeAttn256CacheView av;
    if (omega_gpu_decode_attn256_cache_view(cfg->attn, 0, &av) != 0 || av.q_heads != qh || av.kv_heads != kvh) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    uint32_t n = 0, k = 0;
    omega_gpu_bf16_tensor_shape(cfg->lm_head, &n, &k);
    if (n != cfg->vocab || k != hd) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    OmegaGpuQ38Graph *g = omega_gpu_host_calloc(1, sizeof *g);
    if (!g) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    g->cfg = *cfg;
    g->hd = hd; g->in = in; g->qh = qh; g->kvh = kvh; g->gh = gh;
    g->gqkv = (32u + gh) * 128u; g->gmix = g->gqkv + gh * 128u; g->ab = 2u * gh;
    g->amix = (qh + kvh) * 512u; g->aqkv = qh * 256u + kvh * 512u; g->mout = qh * 256u;
    g->am_ctas = (cfg->vocab + OMEGA_DEC_ARGMAX_SPAN - 1) / OMEGA_DEC_ARGMAX_SPAN;
    g->heads = heads; g->gdn_h[0] = cfg->gdn; g->attn_h[0] = cfg->attn;
    for (uint32_t h = 0; h < OMEGA_GPU_Q38_MAX_HEADS; h++) g->xq_layer[h] = -1;
    for (uint32_t l = 0, na = 0, ng = 0; l < cfg->layers; l++) {
        g->layer[l].attn = (int)((cfg->attn_mask >> l) & 1u);
        g->layer[l].kind_index = g->layer[l].attn ? na++ : ng++;
    }
    Layout *L = &g->lo; size_t o = 0;
#define REG(f, bytes) do { L->f = o; o = al(o + (bytes)); } while (0)
    REG(x, (size_t)H * 4 * heads); REG(ab, g->ab * 4); REG(hidden, (size_t)H * 4 * heads);
    REG(logits, (size_t)g->am_ctas * OMEGA_DEC_ARGMAX_SPAN * 4 * heads);
    REG(am_v, (size_t)OMEGA_DEC_ARGMAX_SPAN * 4 * heads); REG(am_i, (size_t)OMEGA_DEC_ARGMAX_SPAN * 4 * heads);
    REG(token, (size_t)TOKEN_STRIDE * heads); REG(norms, (size_t)cfg->layers * 2 * H * 4); REG(fnorm, H * 4);
    REG(tabs, (size_t)cfg->layers * 4 * 16 + 16); /* + the FP8 lm_head entry */
    REG(gtab, g->amix * 4); REG(idtab, COPY_ROW * 4); REG(stage, (size_t)2 * I * 4);
    REG(segd, (size_t)cfg->layers * SEGD_ROWS * OMEGA_GEMM_SEG_BYTES);
    REG(xh_seg, OMEGA_GEMM_SEG_BYTES);
    REG(ptab, (size_t)(H + g->mout + I) * 4);
    L->split = o;
    REG(xq, (size_t)H * 4 * heads); REG(mix, g->gmix * 4); REG(agg, g->amix * 4);
    REG(att, g->mout * 4); REG(o, H * 4); REG(gu, (size_t)2 * I * 4); REG(act, (size_t)I * 4);
    {   /* batch regions: N rows each, plus M8 padding rows on fp8gemm inputs */
        const size_t N = heads, NP = (size_t)heads + OMEGA_GPU_Q38_MAX_HEADS;
        REG(xp, NP * H * 4); REG(mixN, N * g->gmix * 4); REG(abN, N * g->ab * 4); REG(aggN, N * g->amix * 4);
        REG(attN, N * g->mout * 4); REG(op, NP * g->mout * 4); REG(oN, N * H * 4);
        REG(guN, N * 2 * I * 4); REG(actN, N * I * 4); REG(actp, NP * I * 4);
    }
#undef REG
    L->bytes = o;
    int rc = OMEGA_GPU_DGRAPH_OK;
    if (omega_gpu_cmdlist_create(OMEGA_GPU_CMDLIST_MAX_LAUNCHES, &g->cl) != 0) { omega_gpu_q38_graph_free(g); return OMEGA_GPU_DGRAPH_CHIP_FAIL; }
    omega_gpu_session_lock();
    const char *pbc = getenv("AIEN_OMEGA_Q38_BUF_CACHED");
    int (*const dalloc)(size_t, OmegaGpuMem *) = (pbc && pbc[0] == '0' && pbc[1] == 0) ? omega_gpu_session_alloc : omega_gpu_session_alloc_cached;
    if (!omega_gpu_session_open() || omega_gpu_session_alloc(L->split, &g->buf) != 0 || dalloc(L->bytes - L->split, &g->dbuf) != 0)
        rc = OMEGA_GPU_DGRAPH_CHIP_FAIL;
    const OmegaDecSpec spec[K_COUNT] = {
        [K_NORM] = { .kind = OMEGA_DEC_RES, .mode = OMEGA_DEC_RES_NORM, .width = H },
        [K_ADDNORM] = { .kind = OMEGA_DEC_RES, .mode = OMEGA_DEC_RES_ADD | OMEGA_DEC_RES_NORM, .width = H },
        [K_SW] = { .kind = OMEGA_DEC_SWIGLU, .width = I },
        [K_GATHER] = { .kind = OMEGA_DEC_GATHER, .width = g->amix, .stride = g->amix },
        [K_GATE] = { .kind = OMEGA_DEC_GATE },
        [K_AM0] = { .kind = OMEGA_DEC_ARGMAX, .mode = 0 },
        [K_AM1] = { .kind = OMEGA_DEC_ARGMAX, .mode = 1 },
        [K_SW_M1] = { .kind = OMEGA_DEC_SWIGLU, .width = I, .mutant = 1 },
        [K_GATHER_M1] = { .kind = OMEGA_DEC_GATHER, .width = g->amix, .stride = g->amix, .mutant = 1 },
        [K_GATE_M1] = { .kind = OMEGA_DEC_GATE, .mutant = 1 },
        [K_ADDNORM_M1] = { .kind = OMEGA_DEC_RES, .mode = OMEGA_DEC_RES_ADD | OMEGA_DEC_RES_NORM, .width = H, .mutant = 1 },
        [K_COPY] = { .kind = OMEGA_DEC_GATHER, .width = COPY_ROW, .stride = COPY_ROW },
        [K_ADD] = { .kind = OMEGA_DEC_RES, .mode = OMEGA_DEC_RES_ADD, .width = H },
        [K_NORM_R] = { .kind = OMEGA_DEC_RES, .mode = OMEGA_DEC_RES_NORM | OMEGA_DEC_RES_ROWS, .width = H },
        [K_ADDNORM_R] = { .kind = OMEGA_DEC_RES, .mode = OMEGA_DEC_RES_ADD | OMEGA_DEC_RES_NORM | OMEGA_DEC_RES_ROWS, .width = H },
        [K_ADDNORM_R_M1] = { .kind = OMEGA_DEC_RES, .mode = OMEGA_DEC_RES_ADD | OMEGA_DEC_RES_NORM | OMEGA_DEC_RES_ROWS, .width = H, .mutant = 1 },
        [K_PERM_XQ] = { .kind = OMEGA_DEC_GATHER, .width = H, .stride = H },
        [K_PERM_O] = { .kind = OMEGA_DEC_GATHER, .width = g->mout, .stride = g->mout },
        [K_PERM_ACT] = { .kind = OMEGA_DEC_GATHER, .width = I, .stride = I },
        [K_XS] = { .kind = OMEGA_DEC_XBOUND, .mode = 1 },
        [K_XB] = { .kind = OMEGA_DEC_XBOUND, .width = H },
        [K_XB_M1] = { .kind = OMEGA_DEC_XBOUND, .width = H, .mutant = 1 },
    };
    for (unsigned i = 0; i < K_COUNT && rc == OMEGA_GPU_DGRAPH_OK; i++) rc = kern_build(&g->k[i], &spec[i]);
    if (rc == OMEGA_GPU_DGRAPH_OK) {
        memset(g->buf.cpu, 0, L->split);
        memset(g->dbuf.cpu, 0, L->bytes - L->split); /* fresh; every region is written by the chip before a launch reads it */
        uint32_t *id = cpu_of(g, L->idtab);
        for (uint32_t i = 0; i < COPY_ROW; i++) id[i] = i;
        for (uint32_t h = 0; h < heads; h++) {
            float *lg = cpu_of(g, logits_of(g, h));
            for (size_t i = cfg->vocab; i < (size_t)g->am_ctas * OMEGA_DEC_ARGMAX_SPAN; i++) lg[i] = NEG_PAD; /* lm_head writes [0, vocab) only */
            float *av = cpu_of(g, amv_of(g, h));
            for (size_t i = 0; i < OMEGA_DEC_ARGMAX_SPAN; i++) av[i] = NEG_PAD; /* stage 1 writes [0, ctas) only */
        }
        (void)omega_q38_gather_table(qh, kvh, cpu_of(g, L->gtab)); /* the shape was checked above */
        {
            uint32_t *pt = cpu_of(g, L->ptab);
            omega_q38_perm_table(pt, H);
            omega_q38_perm_table(pt + H, g->mout);
            omega_q38_perm_table(pt + H + g->mout, I);
        }
        if (omega_gpu_session_sync_to_gpu(&g->buf) != 0 || omega_gpu_session_sync_to_gpu(&g->dbuf) != 0) rc = OMEGA_GPU_DGRAPH_CHIP_FAIL;
    }
    omega_gpu_session_unlock();
    if (rc != OMEGA_GPU_DGRAPH_OK) { omega_gpu_q38_graph_free(g); return rc; }
    {
        const char *e = getenv("AIEN_OMEGA_Q38_BATCH");
        if (e && e[0] == '1' && e[1] == 0 && omega_gpu_q38_graph_set_batch(g, 1) != OMEGA_GPU_DGRAPH_OK) {
            omega_gpu_q38_graph_free(g);
            return OMEGA_GPU_DGRAPH_CHIP_FAIL;
        }
    }
    *out = g;
    return OMEGA_GPU_DGRAPH_OK;
}

int omega_gpu_q38_graph_set_head_state(OmegaGpuQ38Graph *g, uint32_t head, OmegaGpuGdn *gdn, OmegaGpuDecodeAttn256Cache *attn) {
    if (!g || head >= g->heads || !gdn || !attn || g->in_token) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    OmegaGpuDecodeAttn256CacheView av;
    if (omega_gpu_decode_attn256_cache_view(attn, 0, &av) != 0 || av.q_heads != g->qh || av.kv_heads != g->kvh)
        return OMEGA_GPU_DGRAPH_BAD_ARGS;
    g->gdn_h[head] = gdn; g->attn_h[head] = attn;
    return OMEGA_GPU_DGRAPH_OK;
}

static int shape_is(const OmegaGpuFp8Tensor *t, uint32_t n, uint32_t k) {
    uint32_t te = 0, tn = 0, tk = 0; if (t) omega_gpu_fp8_tensor_shape(t, &te, &tn, &tk);
    return t && te == 1 && tn == n && tk == k;
}

/* the norms and the layer's table row (t: the FP8 entries, or zeros for a bf16 layer) */
static int layer_common(OmegaGpuQ38Graph *g, uint32_t layer, const uint64_t t[8], const float *in_norm, const float *post_norm) {
    omega_gpu_session_lock();
    memcpy((uint8_t *)cpu_of(g, g->lo.tabs) + (size_t)layer * 64u, t, 8 * sizeof *t);
    memcpy((float *)cpu_of(g, g->lo.norms) + (size_t)layer * 2 * H, in_norm, H * 4u);
    memcpy((float *)cpu_of(g, g->lo.norms) + (size_t)layer * 2 * H + H, post_norm, H * 4u);
    int rc = omega_gpu_session_sync_to_gpu(&g->buf) == 0 ? OMEGA_GPU_DGRAPH_OK : OMEGA_GPU_DGRAPH_CHIP_FAIL;
    omega_gpu_session_unlock();
    return rc;
}

static int ab_ok(const OmegaGpuQ38Graph *g, int attn, const OmegaGpuBf16Tensor *ab) {
    if (attn) return ab == NULL;
    uint32_t n = 0, k = 0; omega_gpu_bf16_tensor_shape(ab, &n, &k);
    return ab != NULL && n == g->ab && k == H;
}

int omega_gpu_q38_graph_set_layer(OmegaGpuQ38Graph *g, uint32_t layer, const OmegaGpuFp8Tensor *mix, const OmegaGpuBf16Tensor *ab,
                                  const OmegaGpuFp8Tensor *o, const OmegaGpuFp8Tensor *gate_up, const OmegaGpuFp8Tensor *down,
                                  const float *in_norm, const float *post_norm) {
    if (!g || layer >= g->cfg.layers || !in_norm || !post_norm || g->in_token) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    const int attn = g->layer[layer].attn;
    if (!shape_is(mix, attn ? g->amix : g->gmix, H) || !shape_is(o, H, g->mout) ||
        !shape_is(gate_up, 2 * I, H) || !shape_is(down, H, I)) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    if (!ab_ok(g, attn, ab)) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    uint64_t t[8];
    if (omega_gpu_fp8_tensor_entry(mix, 0, &t[0], &t[1]) != 0 || omega_gpu_fp8_tensor_entry(o, 0, &t[2], &t[3]) != 0 ||
        omega_gpu_fp8_tensor_entry(gate_up, 0, &t[4], &t[5]) != 0 || omega_gpu_fp8_tensor_entry(down, 0, &t[6], &t[7]) != 0) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    int rc = layer_common(g, layer, t, in_norm, post_norm);
    if (rc == OMEGA_GPU_DGRAPH_OK) {
        g->layer[layer].mix = mix; g->layer[layer].ab = ab; g->layer[layer].o = o; g->layer[layer].gu = gate_up; g->layer[layer].dn = down;
        g->layer[layer].bmix = g->layer[layer].bo = g->layer[layer].bgu = g->layer[layer].bdn = g->layer[layer].bdn2 = NULL;
        g->layer[layer].bf16 = 0; g->layer[layer].set = 1;
    }
    return rc;
}

static int bf_shape_is(const OmegaGpuBf16Tensor *t, uint32_t n, uint32_t k) {
    uint32_t tn = 0, tk = 0; if (t) omega_gpu_bf16_tensor_shape(t, &tn, &tk);
    return t && tn == n && tk == k;
}

/* the bf16 GEMV stages its whole f32 x row in shared memory, which the launch descriptor caps at 32 KiB: k <= 8192 */
#define BF16_X_MAX_K (OMEGA_BW_QMD_MAX_SHARED_BYTES / 4u)

int omega_gpu_q38_graph_set_layer_bf16(OmegaGpuQ38Graph *g, uint32_t layer, const OmegaGpuBf16Tensor *mix, const OmegaGpuBf16Tensor *ab,
                                       const OmegaGpuBf16Tensor *o, const OmegaGpuBf16Tensor *gate_up, const OmegaGpuBf16Tensor *down,
                                       const OmegaGpuBf16Tensor *down2, const float *in_norm, const float *post_norm) {
    if (!g || layer >= g->cfg.layers || !in_norm || !post_norm || g->in_token) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    const int attn = g->layer[layer].attn;
    /* down: whole [H][I] when I fits one x stage, else split in two K halves (down = columns 0..I/2, down2 = I/2..I) */
    const uint32_t kd = down2 ? I / 2u : I;
    if (!bf_shape_is(mix, attn ? g->amix : g->gmix, H) || !bf_shape_is(o, H, g->mout) || !bf_shape_is(gate_up, 2 * I, H) ||
        !bf_shape_is(down, H, kd) || (down2 && !bf_shape_is(down2, H, kd)) || !ab_ok(g, attn, ab)) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    if (H > BF16_X_MAX_K || g->mout > BF16_X_MAX_K || kd > BF16_X_MAX_K || (down2 && I % 512u)) {
        omega_gpu_session_set_error("q38 graph: a bf16 projection's K exceeds the GEMV x stage (8192; split down in two halves)");
        return OMEGA_GPU_DGRAPH_BAD_ARGS;
    }
    if (omega_gpu_bf16_prepare(H) != 0 || omega_gpu_bf16_prepare(g->mout) != 0 || omega_gpu_bf16_prepare(kd) != 0) {
        omega_gpu_session_set_error("q38 graph: bf16 GEMV kernels could not be prepared");
        return OMEGA_GPU_DGRAPH_CODEGEN_FAIL;
    }
    const uint64_t t[8] = { 0 };
    int rc = layer_common(g, layer, t, in_norm, post_norm);
    if (rc == OMEGA_GPU_DGRAPH_OK) {
        g->layer[layer].mix = g->layer[layer].o = g->layer[layer].gu = g->layer[layer].dn = NULL;
        g->layer[layer].ab = ab; g->layer[layer].bmix = mix; g->layer[layer].bo = o; g->layer[layer].bgu = gate_up; g->layer[layer].bdn = down;
        g->layer[layer].bdn2 = down2;
        g->layer[layer].bf16 = 1; g->layer[layer].set = 1;
    }
    return rc;
}

int omega_gpu_q38_graph_set_final_norm(OmegaGpuQ38Graph *g, const float *final_norm) {
    if (!g || !final_norm || g->in_token) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    omega_gpu_session_lock();
    memcpy(cpu_of(g, g->lo.fnorm), final_norm, H * 4u);
    int rc = omega_gpu_session_sync_to_gpu(&g->buf) == 0 ? OMEGA_GPU_DGRAPH_OK : OMEGA_GPU_DGRAPH_CHIP_FAIL;
    omega_gpu_session_unlock();
    if (rc == OMEGA_GPU_DGRAPH_OK) g->final_set = 1;
    return rc;
}

int omega_gpu_q38_graph_set_lm_head_fp8(OmegaGpuQ38Graph *g, const OmegaGpuFp8Tensor *head) {
    if (!g || g->in_token) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    if (!head) { g->head8 = NULL; return OMEGA_GPU_DGRAPH_OK; }
    uint64_t t[2];
    if (!shape_is(head, g->cfg.vocab, H) || omega_gpu_fp8_tensor_entry(head, 0, &t[0], &t[1]) != 0) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    omega_gpu_session_lock();
    memcpy((uint8_t *)cpu_of(g, g->lo.tabs) + (size_t)g->cfg.layers * 64u, t, sizeof t);
    int rc = omega_gpu_session_sync_to_gpu(&g->buf) == 0 ? OMEGA_GPU_DGRAPH_OK : OMEGA_GPU_DGRAPH_CHIP_FAIL;
    omega_gpu_session_unlock();
    if (rc == OMEGA_GPU_DGRAPH_OK) g->head8 = head;
    return rc;
}

uint64_t omega_gpu_q38_exact_extra_bytes(void) {
    /* 27B exact-head admission reserve: FP8 screen tensor (248320 x 5120 + 128x128 bf16 scales) + device scratch + host coef */
    const uint64_t V = 248320ull, HD = OMEGA_GPU_Q38_HIDDEN;
    const uint64_t screen_w = V * HD;
    const uint64_t screen_s = ((V + 127ull) / 128ull) * ((HD + 127ull) / 128ull) * 2ull;
    const uint64_t P = ((V + OMEGA_DEC_ARGMAX_SPAN - 1ull) / OMEGA_DEC_ARGMAX_SPAN) * OMEGA_DEC_ARGMAX_SPAN;
    const uint64_t scratch = al((size_t)(HD * 4u)) + al((size_t)(V * 4u)) * 3ull + al((size_t)(P * 4u)) + al(16u) * 2ull;
    const uint64_t host_coef = V * 4ull;
    return screen_w + screen_s + scratch + host_coef;
}

int omega_gpu_q38_graph_set_exact_head(OmegaGpuQ38Graph *g, const OmegaGpuFp8Tensor *screen, const float *coef, uint32_t roundings) {
    if (!g || g->in_token) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    if (!screen) {
        omega_gpu_session_lock();
        if (g->xh.mem.cpu) omega_gpu_session_free(&g->xh.mem);
        omega_gpu_session_unlock();
        memset(&g->xh, 0, sizeof g->xh);
        return OMEGA_GPU_DGRAPH_OK;
    }
    uint64_t t[2];
    if (!coef || roundings == 0 || g->xh.screen || !shape_is(screen, g->cfg.vocab, H) ||
        omega_gpu_fp8_tensor_entry(screen, 0, &t[0], &t[1]) != 0)
        return OMEGA_GPU_DGRAPH_BAD_ARGS;
    const size_t n = g->cfg.vocab, P = (size_t)g->am_ctas * OMEGA_DEC_ARGMAX_SPAN, nh = g->heads;
    const size_t o_h8 = 0, o_s = al(o_h8 + nh * H * 4), o_c = al(o_s + nh * n * 4), o_hi = al(o_c + n * 4),
                 o_lo = al(o_hi + nh * n * 4), o_tau = al(o_lo + nh * P * 4), o_tab = al(o_tau + nh * 16), total = al(o_tab + 16);
    if (omega_gpu_bf16_prepare_mask(H) != 0) return fail(g, "q38 graph: exact head MASK kernel", OMEGA_GPU_DGRAPH_CHIP_FAIL);
    omega_gpu_session_lock();
    int rc = omega_gpu_session_alloc(total, &g->xh.mem) == 0 ? OMEGA_GPU_DGRAPH_OK : OMEGA_GPU_DGRAPH_CHIP_FAIL;
    if (rc == OMEGA_GPU_DGRAPH_OK) {
        uint8_t *B = g->xh.mem.cpu;
        memset(B, 0, total);
        memcpy(B + o_c, coef, n * 4);
        for (size_t h = 0; h < nh; h++) {
            float *lo_h = (float *)(B + o_lo + h * P * 4);
            for (size_t i = n; i < P; i++) lo_h[i] = NEG_PAD; /* XBOUND writes [0, vocab) only */
        }
        memcpy(B + o_tab, t, sizeof t);
        if (omega_gpu_session_sync_to_gpu(&g->xh.mem) != 0) rc = OMEGA_GPU_DGRAPH_CHIP_FAIL;
    }
    if (rc == OMEGA_GPU_DGRAPH_OK) {
        const uint64_t V = g->xh.mem.va;
        g->xh.h8 = V + o_h8; g->xh.s = V + o_s; g->xh.c = V + o_c; g->xh.hi = V + o_hi; g->xh.lo = V + o_lo; g->xh.tau = V + o_tau; g->xh.tab = V + o_tab;
        g->xh.screen = screen; g->xh.roundings = roundings;
        memset(g->xh.on, 1, sizeof g->xh.on);
    } else if (g->xh.mem.cpu) omega_gpu_session_free(&g->xh.mem);
    omega_gpu_session_unlock();
    return rc;
}

void omega_gpu_q38_graph_set_exact_head_on(OmegaGpuQ38Graph *g, int on) { if (g && !g->in_token) memset(g->xh.on, on ? 1 : 0, sizeof g->xh.on); }
void omega_gpu_q38_graph_set_head_exact_head_on(OmegaGpuQ38Graph *g, uint32_t head, int on) {
    if (g && !g->in_token && head < OMEGA_GPU_Q38_MAX_HEADS) g->xh.on[head] = on ? 1 : 0;
}
int omega_gpu_q38_graph_exact_head_active_head(const OmegaGpuQ38Graph *g, uint32_t head) {
    return g && head < OMEGA_GPU_Q38_MAX_HEADS && g->xh.screen && g->xh.on[head] && !g->head8;
}
int omega_gpu_q38_graph_exact_head_active(const OmegaGpuQ38Graph *g) { return omega_gpu_q38_graph_exact_head_active_head(g, 0); }

void omega_gpu_q38_graph_set_flush_each(OmegaGpuQ38Graph *g, int on) { if (g) g->flush_each = on ? 1 : 0; }
void omega_gpu_q38_graph_test_set_mutant(OmegaGpuQ38Graph *g, int mutant) {
    if (!g) return;
    g->mutant = mutant;
    omega_gpu_bf16_test_set_mask_mutant(mutant == 5 ? 4 : 0); /* process-wide, the MASK form only */
}

/* ---- the list ---- */

static OmegaGpuCmdListOpts list_opts(const OmegaGpuQ38Graph *g) {
    OmegaGpuCmdListOpts o; memset(&o, 0, sizeof o);
    o.mode = OMEGA_GPU_CMDLIST_PCAS; o.barrier = (OmegaGpuCmdListBarrier)omega_gpu_decode_graph_barrier(); o.timeout_ms = TIMEOUT_MS; o.stamps = g->stamps;
    return o;
}

static int submit_now(OmegaGpuQ38Graph *g) {
    if (omega_gpu_cmdlist_count(g->cl) == 0) return OMEGA_GPU_DGRAPH_OK;
    OmegaGpuCmdListOpts o = list_opts(g);
    OmegaGpuCmdListStats st; memset(&st, 0, sizeof st);
    int rc = omega_gpu_cmdlist_submit(g->cl, &o, &st);
    g->acc.launches += st.launches; g->acc.submits += st.submits; g->acc.chip_ns += st.elapsed_ns; g->acc.sems_done += st.sems_done;
    if (rc == 0 && g->stamps) {
        uint64_t tmp[OMEGA_GPU_CMDLIST_MAX_LAUNCHES + 1];
        int cnt = omega_gpu_cmdlist_stamps(g->cl, tmp, OMEGA_GPU_CMDLIST_MAX_LAUNCHES + 1);
        if (cnt < 0) rc = -1;
        else { const int from = g->n_stamp == 0 ? 0 : 1; for (int i = from; i < cnt && g->n_stamp <= OMEGA_GPU_CMDLIST_MAX_LAUNCHES; i++) g->stamp[g->n_stamp++] = tmp[i]; }
    }
    g->tagged_in_list = 0;
    omega_gpu_cmdlist_reset(g->cl);
    if (rc != 0) return fail(g, NULL, OMEGA_GPU_DGRAPH_CHIP_FAIL);
    if (st.sems_done != st.launches) {
        char e[128]; omega_gpu_fmt(e, sizeof e, "q38 graph: %u of %u launch semaphores DONE (first missing %d)", st.sems_done, st.launches, st.first_missing);
        return fail(g, e, OMEGA_GPU_DGRAPH_CHIP_FAIL);
    }
    return OMEGA_GPU_DGRAPH_OK;
}

static int ensure_room(OmegaGpuQ38Graph *g, uint32_t need) {
    if (omega_gpu_cmdlist_count(g->cl) + need >= OMEGA_GPU_CMDLIST_MAX_LAUNCHES) return submit_now(g);
    return OMEGA_GPU_DGRAPH_OK;
}

static void tag(OmegaGpuQ38Graph *g, uint8_t kind) {
    const uint32_t n = omega_gpu_cmdlist_count(g->cl);
    for (; g->tagged_in_list < n && g->n_kind < OMEGA_GPU_CMDLIST_MAX_LAUNCHES; g->tagged_in_list++) g->kind[g->n_kind++] = kind;
}

static int after_op(OmegaGpuQ38Graph *g, uint8_t kind, int api_rc) {
    if (api_rc != 0) return fail(g, NULL, OMEGA_GPU_DGRAPH_CHIP_FAIL);
    tag(g, kind);
    return g->flush_each ? submit_now(g) : OMEGA_GPU_DGRAPH_OK;
}

static int add_glue(OmegaGpuQ38Graph *g, uint8_t kind, int ki, uint32_t gx, uint32_t gy, size_t elems, const uint32_t *args, uint32_t n_args) {
    const Kern *k = &g->k[ki];
    OmegaGpuLaunch L; memset(&L, 0, sizeof L);
    L.code_va = k->code.va; L.gpr_count = k->gpr; L.threads_x = OMEGA_DEC_THREADS; L.threads_y = 1; L.grid_x = gx; L.grid_y = gy;
    L.num_elements = elems; L.args = args; L.n_args = n_args; L.timeout_ms = TIMEOUT_MS;
    return after_op(g, kind, omega_gpu_cmdlist_add(g->cl, &L) < 0 ? -1 : 0);
}

/* RES at the hidden width: NORM (x -> y) or ADD|NORM (x += a; y = norm(x)) */
static int rec_res(OmegaGpuQ38Graph *g, int ki, uint64_t x, uint64_t a, uint64_t nw, uint64_t y, float scale) {
    uint32_t w[OMEGA_DEC_RES_WORDS]; memset(w, 0, sizeof w);
    put64(w, OMEGA_DEC_RES_X, x); put64(w, OMEGA_DEC_RES_A, a); put64(w, OMEGA_DEC_RES_NW, nw); put64(w, OMEGA_DEC_RES_Y, y);
    putf(w, OMEGA_DEC_RES_EPS, g->cfg.eps); putf(w, OMEGA_DEC_RES_SCALE, scale);
    return add_glue(g, ki == K_NORM ? OMEGA_GPU_Q38_K_NORM : OMEGA_GPU_Q38_K_RES, ki, 1, 1, H, w, OMEGA_DEC_RES_WORDS);
}

static int rec_res_rows(OmegaGpuQ38Graph *g, int ki, uint64_t x, uint64_t a, uint64_t nw, uint64_t y, float scale, uint32_t rows) {
    uint32_t w[OMEGA_DEC_RES_WORDS]; memset(w, 0, sizeof w);
    put64(w, OMEGA_DEC_RES_X, x); put64(w, OMEGA_DEC_RES_A, a); put64(w, OMEGA_DEC_RES_NW, nw); put64(w, OMEGA_DEC_RES_Y, y);
    putf(w, OMEGA_DEC_RES_EPS, g->cfg.eps); putf(w, OMEGA_DEC_RES_SCALE, scale);
    return add_glue(g, ki == K_NORM_R ? OMEGA_GPU_Q38_K_NORM : OMEGA_GPU_Q38_K_RES, ki, 1, rows, (size_t)H * rows, w, OMEGA_DEC_RES_WORDS);
}

static int g_overlap_ab = -1;
void omega_gpu_q38_graph_set_overlap_ab(int on) { g_overlap_ab = on ? 1 : 0; }
static int q38_overlap_ab(void) {
    if (g_overlap_ab < 0) { const char *e = getenv("AIEN_OMEGA_Q38_OVERLAP_AB"); g_overlap_ab = (e && e[0] == '0' && e[1] == 0) ? 0 : 1; }
    return g_overlap_ab;
}

static int rec_fp8(OmegaGpuQ38Graph *g, uint8_t kind, const OmegaGpuFp8Tensor *t, uint64_t tab, uint64_t x, uint64_t y) {
    return after_op(g, kind, omega_gpu_fp8_gemv_grouped_record(g->cl, t, 1, tab, x, 1, y));
}
/* one projection of a layer: FP8 (table row entry tab) or, for a set_layer_bf16 layer, the bf16 GEMV (weights 2^-64 scaled) */
static int rec_proj(OmegaGpuQ38Graph *g, uint8_t kind, const OmegaGpuFp8Tensor *t8, const OmegaGpuBf16Tensor *tb, uint64_t tab, uint64_t x, uint64_t y) {
    return tb ? after_op(g, kind, omega_gpu_bf16_gemv_record(g->cl, tb, x, y)) : rec_fp8(g, kind, t8, tab, x, y);
}

/* ---- strokes (multi-head) & batch (v2) ---- */

typedef struct { uint64_t w_va, s_va; uint32_t row0, cnt, pad[2]; } Seg32;
_Static_assert(sizeof(Seg32) == OMEGA_GEMM_SEG_BYTES, "segment entry layout");

static void write_dense_segments(OmegaGpuQ38Graph *g, uint32_t heads) {
    Seg32 *s = cpu_of(g, g->lo.segd);
    for (uint32_t l = 0; l < g->cfg.layers; l++) {
        Seg32 *row = &s[l * SEGD_ROWS];
        memset(row, 0, SEGD_ROWS * sizeof *row);
        if (!g->layer[l].set || g->layer[l].bf16) continue;
        (void)omega_gpu_fp8_tensor_entry(g->layer[l].mix, 0, &row[0].w_va, &row[0].s_va);
        (void)omega_gpu_fp8_tensor_entry(g->layer[l].o, 0, &row[1].w_va, &row[1].s_va);
        (void)omega_gpu_fp8_tensor_entry(g->layer[l].gu, 0, &row[2].w_va, &row[2].s_va);
        (void)omega_gpu_fp8_tensor_entry(g->layer[l].dn, 0, &row[3].w_va, &row[3].s_va);
        for (uint32_t j = 0; j < SEGD_ROWS; j++) row[j].cnt = heads;
    }
    Seg32 *xs = cpu_of(g, g->lo.xh_seg);
    memset(xs, 0, sizeof *xs);
    if (g->xh.screen) {
        (void)omega_gpu_fp8_tensor_entry(g->xh.screen, 0, &xs->w_va, &xs->s_va);
        xs->cnt = heads;
    }
}

int omega_gpu_q38_graph_set_batch(OmegaGpuQ38Graph *g, int on) {
    if (!g || g->in_token) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    if (!on) { g->batch = 0; return OMEGA_GPU_DGRAPH_OK; }
    int rc = omega_gpu_fp8gemm_prepare_shape(H, 1, 0, 0);
    if (rc == 0) rc = omega_gpu_fp8gemm_prepare_shape(g->mout, 1, 0, 0);
    if (rc == 0) rc = omega_gpu_fp8gemm_prepare_shape(I, 1, 0, 0);
    if (rc != 0) return OMEGA_GPU_DGRAPH_CHIP_FAIL;
    if (!g->head8) {
        uint64_t max_xb = 0;
        if (omega2_q38_bf16_xbatch_max(&max_xb, H, OMEGA_BW_QMD_MAX_SHARED_BYTES) != OMEGA_OK) return OMEGA_GPU_DGRAPH_CHIP_FAIL;
        for (uint32_t xb = 2; xb <= max_xb && xb <= g->heads; xb++)
            if (omega_gpu_bf16_prepare_xbatch(H, xb, g->am_ctas * OMEGA_DEC_ARGMAX_SPAN) != OMEGA_GPU_BF16_OK)
                return OMEGA_GPU_DGRAPH_CHIP_FAIL;
    }
    g->batch = 1;
    return OMEGA_GPU_DGRAPH_OK;
}
int omega_gpu_q38_graph_batch(const OmegaGpuQ38Graph *g) { return g ? g->batch : 0; }

static int rec_gemm(OmegaGpuQ38Graph *g, uint8_t kind, const OmegaGpuFp8Tensor *t, uint32_t rows, uint64_t seg, uint64_t xp, uint64_t y) {
    return after_op(g, kind, omega_gpu_fp8gemm_record(g->cl, t, rows, 1, seg, xp, y, 0, 0, 0, 0, NULL));
}
static int rec_perm(OmegaGpuQ38Graph *g, int ki, uint64_t in, uint64_t tab, uint64_t out, uint32_t width, uint32_t rows) {
    uint32_t w[OMEGA_DEC_GA_WORDS]; memset(w, 0, sizeof w);
    put64(w, OMEGA_DEC_GA_IN, in); put64(w, OMEGA_DEC_GA_TAB, tab); put64(w, OMEGA_DEC_GA_OUT, out);
    return add_glue(g, OMEGA_GPU_Q38_K_PERM, ki, (width + OMEGA_DEC_THREADS - 1) / OMEGA_DEC_THREADS, rows, (size_t)width * rows, w, OMEGA_DEC_GA_WORDS);
}

int omega_gpu_q38_graph_begin_token(OmegaGpuQ38Graph *g, const float *x_embed) {
    return omega_gpu_q38_graph_begin_stroke(g, x_embed, 1);
}

int omega_gpu_q38_graph_begin_stroke(OmegaGpuQ38Graph *g, const float *x_embed, uint32_t heads) {
    if (!g || g->in_token || heads == 0 || heads > g->heads) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    for (uint32_t h = 1; h < heads; h++) if (!g->gdn_h[h] || !g->attn_h[h]) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    omega_gpu_session_lock();
    g->t_begin = omega_gpu_session_now_ns();
    g->in_token = 1; g->failed = 0; g->stroke_heads = heads;
    for (uint32_t h = 0; h < heads; h++) { g->xq_layer[h] = -1; g->hidden_ready[h] = 0; }
    memset(&g->acc, 0, sizeof g->acc);
    g->n_kind = 0; g->tagged_in_list = 0; g->n_stamp = 0;
    omega_gpu_cmdlist_reset(g->cl);
    if (!omega_gpu_session_open()) return fail(g, NULL, OMEGA_GPU_DGRAPH_CHIP_FAIL);
    for (uint32_t h = 0; h < heads; h++) {
        uint32_t *tok = cpu_of(g, token_of(g, h));
        tok[0] = TOKEN_POISON; tok[1] = TOKEN_POISON;
        if (x_embed) memcpy(cpu_of(g, x_of(g, h)), x_embed + (size_t)h * H, H * 4u);
    }
    if (g->batch) write_dense_segments(g, heads);
    if (omega_gpu_session_sync_to_gpu(&g->buf) != 0) return fail(g, NULL, OMEGA_GPU_DGRAPH_CHIP_FAIL);
    return OMEGA_GPU_DGRAPH_OK;
}

int omega_gpu_q38_graph_record_layer(OmegaGpuQ38Graph *g, uint32_t l, uint32_t pos) {
    return omega_gpu_q38_graph_record_head_layer(g, 0, l, pos);
}

int omega_gpu_q38_graph_record_head_layer(OmegaGpuQ38Graph *g, uint32_t h, uint32_t l, uint32_t pos) {
    if (!g || !g->in_token) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    if (g->failed) return OMEGA_GPU_DGRAPH_CHIP_FAIL;
    if (h >= g->stroke_heads) return fail(g, "q38 graph: head not in the stroke", OMEGA_GPU_DGRAPH_BAD_ARGS);
    if (l >= g->cfg.layers || !g->layer[l].set || g->hidden_ready[h] || (l + 1 == g->cfg.layers && !g->final_set))
        return fail(g, "q38 graph: layer not set, out of order, or final norm missing", OMEGA_GPU_DGRAPH_BAD_ARGS);
    int rc = ensure_room(g, 20u);
    if (rc != OMEGA_GPU_DGRAPH_OK) return rc;
    const uint64_t x = va_of(g, x_of(g, h)), xq = va_of(g, xq_of(g, h)), mix = va_of(g, g->lo.mix), agg = va_of(g, g->lo.agg);
    const uint64_t att = va_of(g, g->lo.att), o = va_of(g, g->lo.o), gu = va_of(g, g->lo.gu), act = va_of(g, g->lo.act);
    const uint64_t in_norm = va_of(g, g->lo.norms) + (uint64_t)l * 2 * H * 4u, post_norm = in_norm + H * 4u, tab = va_of(g, g->lo.tabs) + (uint64_t)l * 64u;
    const uint32_t ki = g->layer[l].kind_index;
    if (g->xq_layer[h] != (int)l) rc = rec_res(g, K_NORM, x, 0, in_norm, xq, SCALE_2P64);
    const int overlap = !g->layer[l].attn && q38_overlap_ab();
    if (overlap && rc == OMEGA_GPU_DGRAPH_OK) rc = after_op(g, OMEGA_GPU_Q38_K_AB, omega_gpu_bf16_gemv_record(g->cl, g->layer[l].ab, xq, va_of(g, g->lo.ab)));
    if (rc == OMEGA_GPU_DGRAPH_OK) {
        int mrc = g->layer[l].bf16 ? omega_gpu_bf16_gemv_record(g->cl, g->layer[l].bmix, xq, mix)
                                   : omega_gpu_fp8_gemv_grouped_record(g->cl, g->layer[l].mix, 1, tab, xq, 1, mix);
        if (mrc == 0 && overlap && !g->flush_each && omega_gpu_cmdlist_mark_independent(g->cl) != 0) mrc = -1;
        rc = after_op(g, OMEGA_GPU_Q38_K_MIX, mrc);
    }
    uint64_t mixer_out = att;
    if (!g->layer[l].attn) {
        const uint64_t ab = va_of(g, g->lo.ab);
        if (!overlap && rc == OMEGA_GPU_DGRAPH_OK) rc = after_op(g, OMEGA_GPU_Q38_K_AB, omega_gpu_bf16_gemv_record(g->cl, g->layer[l].ab, xq, ab));
        if (rc == OMEGA_GPU_DGRAPH_OK)
            rc = after_op(g, OMEGA_GPU_Q38_K_GDN, omega_gpu_gdn_record(g->cl, g->gdn_h[h], ki, mix, mix + g->gqkv * 4u, ab,
                                                                     g->cfg.eps_l2, g->cfg.eps, 1.0f, SCALE_2P64, &mixer_out));
    } else {
        uint32_t w[OMEGA_DEC_GA_WORDS]; memset(w, 0, sizeof w);
        put64(w, OMEGA_DEC_GA_IN, mix); put64(w, OMEGA_DEC_GA_TAB, va_of(g, g->lo.gtab)); put64(w, OMEGA_DEC_GA_OUT, agg);
        if (rc == OMEGA_GPU_DGRAPH_OK)
            rc = add_glue(g, OMEGA_GPU_Q38_K_GATHER, g->mutant == 2 ? K_GATHER_M1 : K_GATHER, (g->amix + OMEGA_DEC_THREADS - 1) / OMEGA_DEC_THREADS, 1,
                          g->amix, w, OMEGA_DEC_GA_WORDS);
        if (rc == OMEGA_GPU_DGRAPH_OK)
            rc = after_op(g, OMEGA_GPU_Q38_K_ATTN, omega_gpu_decode_attn256_record(g->cl, g->attn_h[h], ki, pos, agg, g->cfg.eps, SCALE_2P64, att));
        uint32_t w2[OMEGA_DEC_GT_WORDS]; memset(w2, 0, sizeof w2);
        put64(w2, OMEGA_DEC_GT_A, att); put64(w2, OMEGA_DEC_GT_G, agg + g->aqkv * 4u); put64(w2, OMEGA_DEC_GT_OUT, att);
        w2[(OMEGA_DEC_GT_N - 0x380) / 4] = g->mout;
        if (rc == OMEGA_GPU_DGRAPH_OK)
            rc = add_glue(g, OMEGA_GPU_Q38_K_GATE, g->mutant == 3 ? K_GATE_M1 : K_GATE, g->mout / OMEGA_DEC_THREADS, 1,
                          g->mout, w2, OMEGA_DEC_GT_WORDS);
    }
    if (rc == OMEGA_GPU_DGRAPH_OK) rc = rec_proj(g, OMEGA_GPU_Q38_K_O, g->layer[l].o, g->layer[l].bo, tab + 16u, mixer_out, o);
    if (rc == OMEGA_GPU_DGRAPH_OK) rc = rec_res(g, g->mutant == 4 ? K_ADDNORM_M1 : K_ADDNORM, x, o, post_norm, xq, SCALE_2P64);
    if (rc == OMEGA_GPU_DGRAPH_OK) rc = rec_proj(g, OMEGA_GPU_Q38_K_GATE_UP, g->layer[l].gu, g->layer[l].bgu, tab + 32u, xq, gu);
    uint32_t w3[OMEGA_DEC_SW_WORDS]; memset(w3, 0, sizeof w3);
    put64(w3, OMEGA_DEC_SW_GU, gu); put64(w3, OMEGA_DEC_SW_ACT, act); putf(w3, OMEGA_DEC_SW_SCALE, SCALE_2P64);
    if (rc == OMEGA_GPU_DGRAPH_OK) rc = add_glue(g, OMEGA_GPU_Q38_K_SWIGLU, g->mutant == 1 ? K_SW_M1 : K_SW, I / OMEGA_DEC_THREADS, 1, I, w3, OMEGA_DEC_SW_WORDS);
    if (rc == OMEGA_GPU_DGRAPH_OK && g->layer[l].bdn2) {
        rc = rec_proj(g, OMEGA_GPU_Q38_K_DOWN, NULL, g->layer[l].bdn, 0, act, o);
        if (rc == OMEGA_GPU_DGRAPH_OK) rc = rec_res(g, K_ADD, x, o, 0, 0, 1.0f);
        if (rc == OMEGA_GPU_DGRAPH_OK) rc = rec_proj(g, OMEGA_GPU_Q38_K_DOWN, NULL, g->layer[l].bdn2, 0, act + (uint64_t)(I / 2u) * 4u, o);
    } else if (rc == OMEGA_GPU_DGRAPH_OK) rc = rec_proj(g, OMEGA_GPU_Q38_K_DOWN, g->layer[l].dn, g->layer[l].bdn, tab + 48u, act, o);
    if (rc == OMEGA_GPU_DGRAPH_OK) {
        const int last = l + 1 == g->cfg.layers;
        const uint64_t nw = last ? va_of(g, g->lo.fnorm) : in_norm + 2 * H * 4u;
        rc = rec_res(g, K_ADDNORM, x, o, nw, last ? va_of(g, hidden_of(g, h)) : xq, last && !g->head8 ? 1.0f : SCALE_2P64);
        if (rc == OMEGA_GPU_DGRAPH_OK) { if (last) g->hidden_ready[h] = 1; else g->xq_layer[h] = (int)l + 1; }
    }
    return rc == OMEGA_GPU_DGRAPH_OK ? rc : fail(g, NULL, rc);
}

static int mark_indep_if(OmegaGpuQ38Graph *g, uint32_t ind) {
    if (!ind || g->flush_each) return OMEGA_GPU_DGRAPH_OK;
    return omega_gpu_cmdlist_mark_independent(g->cl) == 0 ? OMEGA_GPU_DGRAPH_OK : fail(g, NULL, OMEGA_GPU_DGRAPH_CHIP_FAIL);
}

int omega_gpu_q38_graph_record_layer_heads(OmegaGpuQ38Graph *g, uint32_t l, const uint32_t *pos) {
    if (!g || !g->in_token || !pos) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    if (g->failed) return OMEGA_GPU_DGRAPH_CHIP_FAIL;
    if (!g->batch) return fail(g, "q38 graph: record_layer_heads needs set_batch", OMEGA_GPU_DGRAPH_BAD_ARGS);
    if (l >= g->cfg.layers || !g->layer[l].set || (l + 1 == g->cfg.layers && !g->final_set))
        return fail(g, "q38 graph: layer not set, out of order, or final norm missing", OMEGA_GPU_DGRAPH_BAD_ARGS);
    const uint32_t N = g->stroke_heads, ki = g->layer[l].kind_index;
    if (g->layer[l].bf16) {
        int rc = OMEGA_GPU_DGRAPH_OK;
        for (uint32_t h = 0; h < N && rc == OMEGA_GPU_DGRAPH_OK; h++) rc = omega_gpu_q38_graph_record_head_layer(g, h, l, pos[h]);
        return rc;
    }
    for (uint32_t h = 0; h < N; h++)
        if (g->hidden_ready[h] || g->xq_layer[h] != g->xq_layer[0]) return fail(g, "q38 graph: heads out of step", OMEGA_GPU_DGRAPH_BAD_ARGS);
    const uint64_t pcfg[8] = { N, (uint64_t)(g->layer[l].attn ? 1u : 0u), (uint64_t)q38_overlap_ab(), (uint64_t)(g->xq_layer[0] != (int)l), 0, 0, 0, 0 };
    uint32_t plan[384]; uint64_t nops = 0;
    if (omega2_q38_plan_layer(&nops, pcfg, 8, plan, 384) != OMEGA_OK || nops == 0)
        return fail(g, "q38 graph: om/gpu/q38_plan layer failed", OMEGA_GPU_DGRAPH_CHIP_FAIL);
    int rc = ensure_room(g, (uint32_t)nops + 4u);
    if (rc != OMEGA_GPU_DGRAPH_OK) return rc;
    const Layout *L = &g->lo;
    const uint64_t x0 = va_of(g, x_of(g, 0)), xq0 = va_of(g, xq_of(g, 0)), xp = va_of(g, L->xp), mixN = va_of(g, L->mixN), abN = va_of(g, L->abN);
    const uint64_t aggN = va_of(g, L->aggN), attN = va_of(g, L->attN), op = va_of(g, L->op), oN = va_of(g, L->oN);
    const uint64_t guN = va_of(g, L->guN), actN = va_of(g, L->actN), actp = va_of(g, L->actp);
    const uint64_t ptH = va_of(g, L->ptab), ptM = ptH + (uint64_t)H * 4u, ptI = ptM + (uint64_t)g->mout * 4u;
    const uint64_t in_norm = va_of(g, L->norms) + (uint64_t)l * 2 * H * 4u, post_norm = in_norm + H * 4u;
    const uint64_t segd = va_of(g, L->segd) + (uint64_t)l * SEGD_ROWS * OMEGA_GEMM_SEG_BYTES;
    const uint64_t MOS = (uint64_t)g->mout * 4u;
    uint64_t gdn_mo[OMEGA_GPU_Q38_MAX_HEADS] = { 0 };
    for (uint64_t k = 0; k < nops && rc == OMEGA_GPU_DGRAPH_OK; k++) {
        const uint32_t op_id = plan[k * 4 + 0], ind = plan[k * 4 + 1], a0 = plan[k * 4 + 2];
        switch (op_id) {
        case 1: rc = rec_res_rows(g, K_NORM_R, x0, 0, in_norm, xq0, SCALE_2P64, N); break;
        case 2: rc = rec_perm(g, K_PERM_XQ, xq0, ptH, xp, H, N); break;
        case 3: rc = after_op(g, OMEGA_GPU_Q38_K_AB, omega_gpu_bf16_gemv_rows_record(g->cl, g->layer[l].ab, N, xq0, abN)); break;
        case 4: rc = rec_gemm(g, OMEGA_GPU_Q38_K_MIX, g->layer[l].mix, N, segd, xp, mixN); break;
        case 5: {
            const uint64_t mix_h = mixN + (uint64_t)a0 * g->gmix * 4u;
            rc = after_op(g, OMEGA_GPU_Q38_K_GDN, omega_gpu_gdn_record(g->cl, g->gdn_h[a0], ki, mix_h, mix_h + g->gqkv * 4u,
                                                                     abN + (uint64_t)a0 * g->ab * 4u, g->cfg.eps_l2, g->cfg.eps, 1.0f, SCALE_2P64, &gdn_mo[a0]));
            break;
        }
        case 6: rc = rec_perm(g, K_PERM_O, gdn_mo[a0], ptM, op + (uint64_t)a0 * MOS, g->mout, 1); break;
        case 7: {
            uint32_t w[OMEGA_DEC_GA_WORDS]; memset(w, 0, sizeof w);
            put64(w, OMEGA_DEC_GA_IN, mixN); put64(w, OMEGA_DEC_GA_TAB, va_of(g, L->gtab)); put64(w, OMEGA_DEC_GA_OUT, aggN);
            rc = add_glue(g, OMEGA_GPU_Q38_K_GATHER, g->mutant == 2 ? K_GATHER_M1 : K_GATHER, (g->amix + OMEGA_DEC_THREADS - 1) / OMEGA_DEC_THREADS, N,
                          (size_t)g->amix * N, w, OMEGA_DEC_GA_WORDS);
            break;
        }
        case 8: {
            const uint64_t agg_h = aggN + (uint64_t)a0 * g->amix * 4u, att_h = attN + (uint64_t)a0 * MOS;
            rc = after_op(g, OMEGA_GPU_Q38_K_ATTN, omega_gpu_decode_attn256_record(g->cl, g->attn_h[a0], ki, pos[a0], agg_h, g->cfg.eps, SCALE_2P64, att_h));
            break;
        }
        case 9: {
            const uint64_t agg_h = aggN + (uint64_t)a0 * g->amix * 4u, att_h = attN + (uint64_t)a0 * MOS;
            uint32_t w2[OMEGA_DEC_GT_WORDS]; memset(w2, 0, sizeof w2);
            put64(w2, OMEGA_DEC_GT_A, att_h); put64(w2, OMEGA_DEC_GT_G, agg_h + g->aqkv * 4u); put64(w2, OMEGA_DEC_GT_OUT, att_h);
            w2[(OMEGA_DEC_GT_N - 0x380) / 4] = g->mout;
            rc = add_glue(g, OMEGA_GPU_Q38_K_GATE, g->mutant == 3 ? K_GATE_M1 : K_GATE, g->mout / OMEGA_DEC_THREADS, 1, g->mout, w2, OMEGA_DEC_GT_WORDS);
            break;
        }
        case 10: rc = rec_perm(g, K_PERM_O, attN, ptM, op, g->mout, N); break;
        case 11: rc = rec_gemm(g, OMEGA_GPU_Q38_K_O, g->layer[l].o, N, segd + OMEGA_GEMM_SEG_BYTES, op, oN); break;
        case 12: rc = rec_res_rows(g, g->mutant == 4 ? K_ADDNORM_R_M1 : K_ADDNORM_R, x0, oN, post_norm, xq0, SCALE_2P64, N); break;
        case 13: rc = rec_gemm(g, OMEGA_GPU_Q38_K_GATE_UP, g->layer[l].gu, N, segd + 2u * OMEGA_GEMM_SEG_BYTES, xp, guN); break;
        case 14: {
            uint32_t w3[OMEGA_DEC_SW_WORDS]; memset(w3, 0, sizeof w3);
            put64(w3, OMEGA_DEC_SW_GU, guN); put64(w3, OMEGA_DEC_SW_ACT, actN); putf(w3, OMEGA_DEC_SW_SCALE, SCALE_2P64);
            rc = add_glue(g, OMEGA_GPU_Q38_K_SWIGLU, g->mutant == 1 ? K_SW_M1 : K_SW, I / OMEGA_DEC_THREADS, N, (size_t)N * I, w3, OMEGA_DEC_SW_WORDS);
            break;
        }
        case 15: rc = rec_perm(g, K_PERM_ACT, actN, ptI, actp, I, N); break;
        case 16: rc = rec_gemm(g, OMEGA_GPU_Q38_K_DOWN, g->layer[l].dn, N, segd + 3u * OMEGA_GEMM_SEG_BYTES, actp, oN); break;
        case 17: {
            const int last = l + 1 == g->cfg.layers;
            const uint64_t nw = last ? va_of(g, L->fnorm) : in_norm + 2 * H * 4u;
            rc = rec_res_rows(g, K_ADDNORM_R, x0, oN, nw, last ? va_of(g, hidden_of(g, 0)) : xq0, last && !g->head8 ? 1.0f : SCALE_2P64, N);
            for (uint32_t h = 0; h < N && rc == OMEGA_GPU_DGRAPH_OK; h++) { if (last) g->hidden_ready[h] = 1; else g->xq_layer[h] = (int)l + 1; }
            break;
        }
        default: rc = fail(g, "q38 graph: unknown om plan op", OMEGA_GPU_DGRAPH_CHIP_FAIL); break;
        }
        if (rc == OMEGA_GPU_DGRAPH_OK) rc = mark_indep_if(g, ind);
    }
    return rc == OMEGA_GPU_DGRAPH_OK ? rc : fail(g, NULL, rc);
}

static int rec_argmax(OmegaGpuQ38Graph *g, uint64_t logits, uint64_t token) {
    uint32_t a0[OMEGA_DEC_AM_WORDS], a1[OMEGA_DEC_AM_WORDS]; memset(a0, 0, sizeof a0); memset(a1, 0, sizeof a1);
    const uint64_t amv = va_of(g, g->lo.am_v), ami = va_of(g, g->lo.am_i);
    put64(a0, OMEGA_DEC_AM_V, logits); put64(a0, OMEGA_DEC_AM_I, 0); put64(a0, OMEGA_DEC_AM_OV, amv); put64(a0, OMEGA_DEC_AM_OI, ami);
    put64(a1, OMEGA_DEC_AM_V, amv); put64(a1, OMEGA_DEC_AM_I, ami); put64(a1, OMEGA_DEC_AM_OV, token + 4u); put64(a1, OMEGA_DEC_AM_OI, token);
    int rc = add_glue(g, OMEGA_GPU_Q38_K_ARGMAX, K_AM0, g->am_ctas, 1, (size_t)g->am_ctas * OMEGA_DEC_ARGMAX_SPAN, a0, OMEGA_DEC_AM_WORDS);
    if (rc == OMEGA_GPU_DGRAPH_OK) rc = add_glue(g, OMEGA_GPU_Q38_K_ARGMAX, K_AM1, 1, 1, OMEGA_DEC_ARGMAX_SPAN, a1, OMEGA_DEC_AM_WORDS);
    return rc;
}

int omega_gpu_q38_graph_record_final(OmegaGpuQ38Graph *g) {
    return omega_gpu_q38_graph_record_head_final(g, 0);
}

int omega_gpu_q38_graph_record_head_final(OmegaGpuQ38Graph *g, uint32_t h) {
    if (!g || !g->in_token) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    if (g->failed) return OMEGA_GPU_DGRAPH_CHIP_FAIL;
    if (h >= g->stroke_heads) return fail(g, "q38 graph: head not in the stroke", OMEGA_GPU_DGRAPH_BAD_ARGS);
    if (!g->final_set) return fail(g, "q38 graph: final norm not set", OMEGA_GPU_DGRAPH_BAD_ARGS);
    int rc = ensure_room(g, 12u);
    if (rc != OMEGA_GPU_DGRAPH_OK) return rc;
    const uint64_t x = va_of(g, x_of(g, h)), hidden = va_of(g, hidden_of(g, h)), logits = va_of(g, logits_of(g, h)), token = va_of(g, token_of(g, h));
    if (!g->hidden_ready[h]) rc = rec_res(g, K_NORM, x, 0, va_of(g, g->lo.fnorm), hidden, g->head8 ? SCALE_2P64 : 1.0f);
    const uint64_t amv = va_of(g, g->lo.am_v), ami = va_of(g, g->lo.am_i);
    if (rc == OMEGA_GPU_DGRAPH_OK && omega_gpu_q38_graph_exact_head_active_head(g, h)) {
        /* HUM L314 two-pass head at hidden width H: h8 = hidden * 2^64; s = screen . h8; lo/hi = s -/+ c|hidden|;
         * tau = max lo; logits = lm_head . hidden where hi >= tau, -inf elsewhere. */
        uint32_t xs[OMEGA_DEC_XB_WORDS], xb[OMEGA_DEC_XB_WORDS], t0[OMEGA_DEC_AM_WORDS], t1[OMEGA_DEC_AM_WORDS];
        memset(xs, 0, sizeof xs); memset(xb, 0, sizeof xb); memset(t0, 0, sizeof t0); memset(t1, 0, sizeof t1);
        put64(xs, OMEGA_DEC_XB_S, hidden); put64(xs, OMEGA_DEC_XB_LO, g->xh.h8); xs[(OMEGA_DEC_XB_N - 0x380) / 4] = H;
        put64(xb, OMEGA_DEC_XB_S, g->xh.s); put64(xb, OMEGA_DEC_XB_C, g->xh.c); put64(xb, OMEGA_DEC_XB_H, hidden);
        put64(xb, OMEGA_DEC_XB_LO, g->xh.lo); put64(xb, OMEGA_DEC_XB_HI, g->xh.hi); xb[(OMEGA_DEC_XB_N - 0x380) / 4] = g->cfg.vocab;
        put64(t0, OMEGA_DEC_AM_V, g->xh.lo); put64(t0, OMEGA_DEC_AM_I, 0); put64(t0, OMEGA_DEC_AM_OV, amv); put64(t0, OMEGA_DEC_AM_OI, ami);
        put64(t1, OMEGA_DEC_AM_V, amv); put64(t1, OMEGA_DEC_AM_I, ami); put64(t1, OMEGA_DEC_AM_OV, g->xh.tau); put64(t1, OMEGA_DEC_AM_OI, g->xh.tau + 4u);
        rc = add_glue(g, OMEGA_GPU_Q38_K_LM_HEAD, K_XS, H / OMEGA_DEC_THREADS, 1, H, xs, OMEGA_DEC_XB_WORDS);
        if (rc == OMEGA_GPU_DGRAPH_OK) rc = rec_fp8(g, OMEGA_GPU_Q38_K_LM_HEAD, g->xh.screen, g->xh.tab, g->xh.h8, g->xh.s);
        if (rc == OMEGA_GPU_DGRAPH_OK)
            rc = add_glue(g, OMEGA_GPU_Q38_K_LM_HEAD, g->mutant == 6 ? K_XB_M1 : K_XB, (g->cfg.vocab + OMEGA_DEC_THREADS - 1) / OMEGA_DEC_THREADS, 1,
                          g->cfg.vocab, xb, OMEGA_DEC_XB_WORDS);
        if (rc == OMEGA_GPU_DGRAPH_OK) rc = add_glue(g, OMEGA_GPU_Q38_K_ARGMAX, K_AM0, g->am_ctas, 1, (size_t)g->am_ctas * OMEGA_DEC_ARGMAX_SPAN, t0, OMEGA_DEC_AM_WORDS);
        if (rc == OMEGA_GPU_DGRAPH_OK) rc = add_glue(g, OMEGA_GPU_Q38_K_ARGMAX, K_AM1, 1, 1, OMEGA_DEC_ARGMAX_SPAN, t1, OMEGA_DEC_AM_WORDS);
        if (rc == OMEGA_GPU_DGRAPH_OK)
            rc = after_op(g, OMEGA_GPU_Q38_K_LM_HEAD, omega_gpu_bf16_gemv_mask_record(g->cl, g->cfg.lm_head, hidden, logits, g->xh.hi, g->xh.tau));
    } else if (rc == OMEGA_GPU_DGRAPH_OK)
        rc = g->head8 ? rec_fp8(g, OMEGA_GPU_Q38_K_LM_HEAD, g->head8, va_of(g, g->lo.tabs) + (uint64_t)g->cfg.layers * 64u, hidden, logits)
                      : after_op(g, OMEGA_GPU_Q38_K_LM_HEAD, omega_gpu_bf16_gemv_record(g->cl, g->cfg.lm_head, hidden, logits));
    if (rc == OMEGA_GPU_DGRAPH_OK) rc = rec_argmax(g, logits, token);
    return rc == OMEGA_GPU_DGRAPH_OK ? rc : fail(g, NULL, rc);
}

static int record_final_heads(OmegaGpuQ38Graph *g) {
    const uint32_t N = g->stroke_heads;
    if (!g->final_set) return fail(g, "q38 graph: final norm not set", OMEGA_GPU_DGRAPH_BAD_ARGS);
    for (uint32_t h = 0; h < N; h++)
        if (!g->hidden_ready[h]) return fail(g, "q38 graph: batch final before the last layer", OMEGA_GPU_DGRAPH_BAD_ARGS);
    int all_exact = 1, any_exact = 0;
    for (uint32_t h = 0; h < N; h++) {
        const int ex = omega_gpu_q38_graph_exact_head_active_head(g, h);
        all_exact &= ex; any_exact |= ex;
    }
    const uint64_t pcfg[8] = { N, H, OMEGA_BW_QMD_MAX_SHARED_BYTES, (uint64_t)all_exact, (uint64_t)any_exact, (uint64_t)(g->head8 != NULL), 0, 0 };
    uint32_t plan[384]; uint64_t nops = 0;
    if (omega2_q38_plan_final(&nops, pcfg, 8, plan, 384) != OMEGA_OK || nops == 0)
        return fail(g, "q38 graph: om/gpu/q38_plan final failed", OMEGA_GPU_DGRAPH_CHIP_FAIL);
    int rc = ensure_room(g, (uint32_t)nops + 4u);
    const size_t n = g->cfg.vocab, P = (size_t)g->am_ctas * OMEGA_DEC_ARGMAX_SPAN;
    const uint64_t ptH = va_of(g, g->lo.ptab), xp = va_of(g, g->lo.xp);
    for (uint64_t k = 0; k < nops && rc == OMEGA_GPU_DGRAPH_OK; k++) {
        const uint32_t op_id = plan[k * 4 + 0], ind = plan[k * 4 + 1], a0 = plan[k * 4 + 2], a1 = plan[k * 4 + 3];
        switch (op_id) {
        case 101: { /* FOP_XS_ALL: scale hidden[0..N-1] * 2^64 -> xh.h8[0..N-1] */
            uint32_t xs[OMEGA_DEC_XB_WORDS]; memset(xs, 0, sizeof xs);
            put64(xs, OMEGA_DEC_XB_S, va_of(g, hidden_of(g, 0))); put64(xs, OMEGA_DEC_XB_LO, g->xh.h8);
            xs[(OMEGA_DEC_XB_N - 0x380) / 4] = N * H;
            rc = add_glue(g, OMEGA_GPU_Q38_K_LM_HEAD, K_XS, (N * H) / OMEGA_DEC_THREADS, 1, (size_t)N * H, xs, OMEGA_DEC_XB_WORDS);
            break;
        }
        case 102: /* FOP_PERM_XH: permute xh.h8[0..N-1] -> xp */
            rc = rec_perm(g, K_PERM_XQ, g->xh.h8, ptH, xp, H, N);
            break;
        case 103: /* FOP_GEMM_SCREEN: single batched FP8 GEMM over xh.screen for all N heads */
            rc = rec_gemm(g, OMEGA_GPU_Q38_K_LM_HEAD, g->xh.screen, N, va_of(g, g->lo.xh_seg), xp, g->xh.s);
            break;
        case 104: { /* FOP_XB: bounds lo/hi for head a0 */
            uint32_t xb[OMEGA_DEC_XB_WORDS]; memset(xb, 0, sizeof xb);
            put64(xb, OMEGA_DEC_XB_S, g->xh.s + (uint64_t)a0 * n * 4u);
            put64(xb, OMEGA_DEC_XB_C, g->xh.c);
            put64(xb, OMEGA_DEC_XB_H, va_of(g, hidden_of(g, a0)));
            put64(xb, OMEGA_DEC_XB_LO, g->xh.lo + (uint64_t)a0 * P * 4u);
            put64(xb, OMEGA_DEC_XB_HI, g->xh.hi + (uint64_t)a0 * n * 4u);
            xb[(OMEGA_DEC_XB_N - 0x380) / 4] = g->cfg.vocab;
            rc = add_glue(g, OMEGA_GPU_Q38_K_LM_HEAD, g->mutant == 6 ? K_XB_M1 : K_XB, (g->cfg.vocab + OMEGA_DEC_THREADS - 1) / OMEGA_DEC_THREADS, 1,
                          g->cfg.vocab, xb, OMEGA_DEC_XB_WORDS);
            break;
        }
        case 105: { /* FOP_TAU_AM0: stage-1 argmax on xh.lo[a0] -> amv[a0]/ami[a0] */
            uint32_t t0[OMEGA_DEC_AM_WORDS]; memset(t0, 0, sizeof t0);
            put64(t0, OMEGA_DEC_AM_V, g->xh.lo + (uint64_t)a0 * P * 4u); put64(t0, OMEGA_DEC_AM_I, 0);
            put64(t0, OMEGA_DEC_AM_OV, va_of(g, amv_of(g, a0))); put64(t0, OMEGA_DEC_AM_OI, va_of(g, ami_of(g, a0)));
            rc = add_glue(g, OMEGA_GPU_Q38_K_ARGMAX, K_AM0, g->am_ctas, 1, P, t0, OMEGA_DEC_AM_WORDS);
            break;
        }
        case 106: { /* FOP_TAU_AM1: stage-2 argmax -> xh.tau[a0] */
            uint32_t t1[OMEGA_DEC_AM_WORDS]; memset(t1, 0, sizeof t1);
            const uint64_t tau_h = g->xh.tau + (uint64_t)a0 * 16u;
            put64(t1, OMEGA_DEC_AM_V, va_of(g, amv_of(g, a0))); put64(t1, OMEGA_DEC_AM_I, va_of(g, ami_of(g, a0)));
            put64(t1, OMEGA_DEC_AM_OV, tau_h); put64(t1, OMEGA_DEC_AM_OI, tau_h + 4u);
            rc = add_glue(g, OMEGA_GPU_Q38_K_ARGMAX, K_AM1, 1, 1, OMEGA_DEC_ARGMAX_SPAN, t1, OMEGA_DEC_AM_WORDS);
            break;
        }
        case 107: /* FOP_BF16_MASK: masked bf16 lm_head for head a0 */
            rc = after_op(g, OMEGA_GPU_Q38_K_LM_HEAD,
                          omega_gpu_bf16_gemv_mask_record(g->cl, g->cfg.lm_head, va_of(g, hidden_of(g, a0)), va_of(g, logits_of(g, a0)),
                                                          g->xh.hi + (uint64_t)a0 * n * 4u, g->xh.tau + (uint64_t)a0 * 16u));
            break;
        case 108: /* FOP_BF16_XBATCH: xbatch bf16 lm_head for heads [a0, a0 + a1) */
            rc = after_op(g, OMEGA_GPU_Q38_K_LM_HEAD,
                          omega_gpu_bf16_gemv_xbatch_record(g->cl, g->cfg.lm_head, a1, va_of(g, hidden_of(g, a0)),
                                                            va_of(g, logits_of(g, a0)), g->am_ctas * OMEGA_DEC_ARGMAX_SPAN));
            break;
        case 109: { /* FOP_LOG_AM0: stage-1 argmax on logits[a0] -> amv[a0]/ami[a0] */
            uint32_t l0[OMEGA_DEC_AM_WORDS]; memset(l0, 0, sizeof l0);
            put64(l0, OMEGA_DEC_AM_V, va_of(g, logits_of(g, a0))); put64(l0, OMEGA_DEC_AM_I, 0);
            put64(l0, OMEGA_DEC_AM_OV, va_of(g, amv_of(g, a0))); put64(l0, OMEGA_DEC_AM_OI, va_of(g, ami_of(g, a0)));
            rc = add_glue(g, OMEGA_GPU_Q38_K_ARGMAX, K_AM0, g->am_ctas, 1, P, l0, OMEGA_DEC_AM_WORDS);
            break;
        }
        case 110: { /* FOP_LOG_AM1: stage-2 argmax -> token[a0] */
            uint32_t l1[OMEGA_DEC_AM_WORDS]; memset(l1, 0, sizeof l1);
            const uint64_t tok_h = va_of(g, token_of(g, a0));
            put64(l1, OMEGA_DEC_AM_V, va_of(g, amv_of(g, a0))); put64(l1, OMEGA_DEC_AM_I, va_of(g, ami_of(g, a0)));
            put64(l1, OMEGA_DEC_AM_OV, tok_h + 4u); put64(l1, OMEGA_DEC_AM_OI, tok_h);
            rc = add_glue(g, OMEGA_GPU_Q38_K_ARGMAX, K_AM1, 1, 1, OMEGA_DEC_ARGMAX_SPAN, l1, OMEGA_DEC_AM_WORDS);
            break;
        }
        case 111: rc = omega_gpu_q38_graph_record_head_final(g, a0); break;
        default: rc = fail(g, "q38 graph: unknown om final op", OMEGA_GPU_DGRAPH_CHIP_FAIL); break;
        }
        if (rc == OMEGA_GPU_DGRAPH_OK) rc = mark_indep_if(g, ind);
    }
    return rc == OMEGA_GPU_DGRAPH_OK ? rc : fail(g, NULL, rc);
}

int omega_gpu_q38_graph_end_token(OmegaGpuQ38Graph *g, uint32_t *token, OmegaGpuDecodeGraphStats *st) {
    return omega_gpu_q38_graph_end_stroke(g, token, st);
}

int omega_gpu_q38_graph_end_stroke(OmegaGpuQ38Graph *g, uint32_t *tokens, OmegaGpuDecodeGraphStats *st) {
    if (!g || !g->in_token) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    int rc = g->failed ? OMEGA_GPU_DGRAPH_CHIP_FAIL : OMEGA_GPU_DGRAPH_OK;
    const uint64_t t_rec = omega_gpu_session_now_ns();
    if (rc == OMEGA_GPU_DGRAPH_OK) rc = submit_now(g);
    for (uint32_t h = 0; h < g->stroke_heads && rc == OMEGA_GPU_DGRAPH_OK; h++)
        if (omega_gpu_decode_attn256_counters_check(g->attn_h[h]) != 0) rc = fail(g, NULL, OMEGA_GPU_DGRAPH_CHIP_FAIL);
    if (rc == OMEGA_GPU_DGRAPH_OK && omega_gpu_session_sync_to_cpu(&g->buf) != 0) rc = fail(g, NULL, OMEGA_GPU_DGRAPH_CHIP_FAIL);
    for (uint32_t h = 0; h < g->stroke_heads && rc == OMEGA_GPU_DGRAPH_OK; h++) {
        const uint32_t t = ((const uint32_t *)cpu_of(g, token_of(g, h)))[0];
        if (t == TOKEN_POISON || t >= g->cfg.vocab) {
            char e[96]; omega_gpu_fmt(e, sizeof e, "q38 graph: head %u token output %u not written or out of range", h, t);
            rc = fail(g, e, OMEGA_GPU_DGRAPH_CHIP_FAIL);
        } else if (tokens) tokens[h] = t;
    }
    omega_gpu_cmdlist_reset(g->cl);
    g->in_token = 0;
    const uint64_t t_end = omega_gpu_session_now_ns();
    if (st) { *st = g->acc; st->record_ns = (g->flush_each ? t_end : t_rec) - g->t_begin; st->total_ns = t_end - g->t_begin; }
    omega_gpu_session_unlock();
    return rc;
}

int omega_gpu_q38_graph_token(OmegaGpuQ38Graph *g, const float *x_embed, uint32_t pos, uint32_t *token, OmegaGpuDecodeGraphStats *st) {
    if (!g) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    if (omega_gpu_q38_graph_begin_token(g, x_embed) == OMEGA_GPU_DGRAPH_BAD_ARGS) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    for (uint32_t l = 0; l < g->cfg.layers && !g->failed; l++) (void)omega_gpu_q38_graph_record_layer(g, l, pos);
    if (!g->failed) (void)omega_gpu_q38_graph_record_final(g);
    return omega_gpu_q38_graph_end_token(g, token, st);
}

int omega_gpu_q38_graph_stroke(OmegaGpuQ38Graph *g, const float *x_embed, const uint32_t *pos, uint32_t heads, uint32_t *tokens,
                               OmegaGpuDecodeGraphStats *st) {
    if (!g || !pos) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    if (omega_gpu_q38_graph_begin_stroke(g, x_embed, heads) == OMEGA_GPU_DGRAPH_BAD_ARGS) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    for (uint32_t l = 0; l < g->cfg.layers && !g->failed; l++) {
        if (g->batch) (void)omega_gpu_q38_graph_record_layer_heads(g, l, pos);
        else for (uint32_t h = 0; h < heads && !g->failed; h++) (void)omega_gpu_q38_graph_record_head_layer(g, h, l, pos[h]);
    }
    if (g->batch && !g->head8) { if (!g->failed) (void)record_final_heads(g); }
    else for (uint32_t h = 0; h < heads && !g->failed; h++) (void)omega_gpu_q38_graph_record_head_final(g, h);
    return omega_gpu_q38_graph_end_stroke(g, tokens, st);
}

int omega_gpu_q38_graph_read(OmegaGpuQ38Graph *g, float *x, float *hidden, float *logits) {
    return omega_gpu_q38_graph_read_head(g, 0, x, hidden, logits);
}

int omega_gpu_q38_graph_read_head(OmegaGpuQ38Graph *g, uint32_t h, float *x, float *hidden, float *logits) {
    if (!g || g->in_token || h >= g->heads) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    omega_gpu_session_lock();
    int rc = omega_gpu_session_sync_to_cpu(&g->buf) == 0 ? OMEGA_GPU_DGRAPH_OK : OMEGA_GPU_DGRAPH_CHIP_FAIL;
    if (rc == OMEGA_GPU_DGRAPH_OK) {
        if (x) memcpy(x, cpu_of(g, x_of(g, h)), H * 4u);
        if (hidden) memcpy(hidden, cpu_of(g, hidden_of(g, h)), H * 4u);
        if (hidden && g->head8) for (unsigned i = 0; i < H; i++) hidden[i] *= 0x1p-64f; /* exact: a power of two */
        if (logits) memcpy(logits, cpu_of(g, logits_of(g, h)), (size_t)g->cfg.vocab * 4u);
    }
    omega_gpu_session_unlock();
    return rc;
}

int omega_gpu_q38_graph_read_buf(OmegaGpuQ38Graph *g, int which, float *out, uint32_t n) {
    if (!g || g->in_token || !out || which < 0 || which >= OMEGA_GPU_Q38_BUF_COUNT) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    const struct { size_t off; uint32_t cap; } b[OMEGA_GPU_Q38_BUF_COUNT] = {
        [OMEGA_GPU_Q38_BUF_X] = { g->lo.x, H }, [OMEGA_GPU_Q38_BUF_XQ] = { g->lo.xq, H }, [OMEGA_GPU_Q38_BUF_MIX] = { g->lo.mix, g->gmix },
        [OMEGA_GPU_Q38_BUF_AB] = { g->lo.ab, g->ab }, [OMEGA_GPU_Q38_BUF_AGG] = { g->lo.agg, g->amix },
        [OMEGA_GPU_Q38_BUF_ATT] = { g->lo.att, g->mout }, [OMEGA_GPU_Q38_BUF_O] = { g->lo.o, H },
        [OMEGA_GPU_Q38_BUF_GU] = { g->lo.gu, 2 * I }, [OMEGA_GPU_Q38_BUF_ACT] = { g->lo.act, I }, [OMEGA_GPU_Q38_BUF_HIDDEN] = { g->lo.hidden, H },
    };
    if (n > b[which].cap) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    omega_gpu_session_lock();
    int rc = OMEGA_GPU_DGRAPH_OK;
    size_t from = b[which].off;
    if (from >= g->lo.split && n) {
        /* a chip-only region: K_COPY moves ceil(n / 256) rows of 256 floats into stage (every cap is a multiple of 256) */
        uint32_t w[OMEGA_DEC_GA_WORDS]; memset(w, 0, sizeof w);
        put64(w, OMEGA_DEC_GA_IN, va_of(g, from)); put64(w, OMEGA_DEC_GA_TAB, va_of(g, g->lo.idtab)); put64(w, OMEGA_DEC_GA_OUT, va_of(g, g->lo.stage));
        const Kern *k = &g->k[K_COPY];
        OmegaGpuLaunch L; memset(&L, 0, sizeof L);
        L.code_va = k->code.va; L.gpr_count = k->gpr; L.threads_x = OMEGA_DEC_THREADS; L.threads_y = 1; L.grid_x = 1; L.grid_y = (n + COPY_ROW - 1) / COPY_ROW;
        L.num_elements = (size_t)L.grid_y * COPY_ROW; L.args = w; L.n_args = OMEGA_DEC_GA_WORDS; L.timeout_ms = TIMEOUT_MS;
        if (!omega_gpu_session_open() || omega_gpu_session_launch(&L, NULL, NULL) != 0) rc = OMEGA_GPU_DGRAPH_CHIP_FAIL;
        from = g->lo.stage;
    }
    if (rc == OMEGA_GPU_DGRAPH_OK && omega_gpu_session_sync_to_cpu(&g->buf) != 0) rc = OMEGA_GPU_DGRAPH_CHIP_FAIL;
    if (rc == OMEGA_GPU_DGRAPH_OK) memcpy(out, cpu_of(g, from), (size_t)n * 4u);
    omega_gpu_session_unlock();
    return rc;
}

/* ---- timeline ---- */
void omega_gpu_q38_graph_set_stamps(OmegaGpuQ38Graph *g, int on) { if (g && !g->in_token) g->stamps = on ? 1 : 0; }

int omega_gpu_q38_graph_stamps(const OmegaGpuQ38Graph *g, uint64_t *stamps, uint8_t *kinds, uint32_t cap) {
    if (!g || g->in_token || !stamps || !kinds) return OMEGA_GPU_DGRAPH_BAD_ARGS;
    if (!g->stamps || g->n_stamp != g->n_kind + 1u) { omega_gpu_session_set_error("q38 graph: no timeline for the last token (stamps off or it failed)"); return OMEGA_GPU_DGRAPH_BAD_ARGS; }
    if (cap < g->n_stamp) { omega_gpu_session_set_error("q38 graph: timeline buffers too small"); return OMEGA_GPU_DGRAPH_BAD_ARGS; }
    memcpy(stamps, g->stamp, (size_t)g->n_stamp * sizeof stamps[0]);
    memcpy(kinds, g->kind, (size_t)g->n_kind);
    return (int)g->n_kind;
}

const char *omega_gpu_q38_graph_kind_name(uint8_t kind) {
    static const char *const names[OMEGA_GPU_Q38_K_COUNT] = { "norm", "mix", "ab", "gdn", "gather", "attn", "gate", "o_proj", "res",
                                                              "gate_up", "swiglu", "down", "lm_head", "argmax", "perm" };
    return kind < OMEGA_GPU_Q38_K_COUNT ? names[kind] : "?";
}
