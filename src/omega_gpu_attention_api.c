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

/* omega_gpu_attention_api.c: FB-1 cut 5 (2026-10-04). See the header.
 *
 * Layout: (1) kernel codegen on the BlackwellIR with the serialising scheduler
 * of cut 4 (every instruction waits on everything still pending; slow and safe),
 * extended with forward branches and more loops; (2) the launcher, cloned from
 * cut 4's run_abc with a fourth buffer (block tables and context lengths), 16
 * argument words, and cut 1b's shader-cache invalidate; (3) the public entry
 * points, which stage the referenced KV blocks per launch and apply the oracle's
 * argument rules (dropped tokens past the table, negative table entries, zero
 * context) on the host.
 *
 * One CTA per (query head, sequence), head_dim threads (64 or 128; the text below says 64, the
 * constants scale with KSpec.hd). The context is walked in chunks of head_dim tokens:
 *   phase A  thread t owns token base+t: block lookup, K dot q (f32 FFMA), s = dot * scale
 *            (scale folds 1/sqrt(d) and log2 e), s and the token's byte offset go to shared;
 *   reduce   chunk max (SHFL.DOWN tree per warp, lane partials to shared, BAR.SYNC, 2 LDS),
 *            m_new = max(m, chunk max), alpha = EX2(m - m_new), p = EX2(s - m_new) to shared,
 *            chunk sum the same way, l = l * alpha + chunk sum;
 *   phase B  thread d owns dimension d: acc = acc * alpha + sum over the chunk of p_t * V[t][d].
 * Then out[d] = acc * RCP(l). The first chunk sees m = -inf, so alpha = EX2(-inf) = 0 and
 * the initial l and acc drop out (PTX ISA ex2.approx: ex2(-Inf) = +0).
 *
 * Shared memory (16 * head_dim bytes; hd 64: 1024 bytes, the QMD default): [0,4hd) q, [4hd,8hd) s then p,
 * [8hd,12hd) token byte offsets, [12hd,16hd) warp partials for the reductions (hd 64: 0, 256, 512,
 * 768; hd 128: 0, 512, 1024, 1536; the partials of warp w are read at 12hd + 128w).
 */
#include "omega_gpu_attention_api.h"
#include "omega_blackwell_codegen.h"
#include "omega_bw_om_ir.h"
#include "omega_native.h"
#include "omega_blackwell_qmd.h"
#include "omega_blackwell_submit.h"
#include "omega_gpu_session.h"
#include "omega_gpu_fmt.h"
#include "sha256.h"
#ifdef OMEGA_ATTN_DEBUG
#include <stdio.h> /* the debug trace only; never in the freestanding build */
#endif
#include <string.h>

/* ------------------------------------------------------------------ codegen */

/* A value first defined inside a loop may not be read after it before being redefined. */
static int check_loop_invariant(const BlackwellIRProgram *prog, const uint64_t *meta) {
    const OmegaRegAlloc *ra = &prog->regalloc;
    for (size_t L = 0; L < meta[3]; L++)
        for (int v = 0; v < ra->num_vregs; v++) {
            int fd = ra->intervals[v].first_def;
            if (fd < (int)meta[320 + 2 * L] || fd > (int)meta[321 + 2 * L]) continue;
            for (size_t i = (size_t)(int)meta[321 + 2 * L] + 1; i < prog->count; i++) {
                const BlackwellIRInsn *in = &prog->insns[i];
                if (in->src1_vreg == v || in->src2_vreg == v || in->src3_vreg == v) return -1;
                if (in->dst_vreg == v && !in->is_uniform) break;
            }
        }
    return 0;
}

#define ARG_WORDS 16u

/* divergent (omega #308 regression R2): 0 = production branch-free chunk loop; 1 = the
 * lane-dependent "j >= ctx" branch restored inside a reconvergence region (BSSY/BSYNC) so
 * the SHFL reductions run on a joined warp; 2 = the same with the BSYNC dropped (the
 * 2026-10-04 bug shape, a negative control the host simulator must catch). */
typedef struct { bool f32; uint32_t log2bs, log2gqa; int mutant; int divergent; uint32_t hd; int split; } KSpec;
/* split (cut F, 2026-10-12): -1 = direct output (the gqa f32 and rows callers; byte for byte the kernel before).
 * 0..MAX_LOG2SPLIT = the paged path: 2^split CTAs share one (sequence, head). Each sequence derives its own split
 * count from its own context (so its result never depends on the other sequences in the launch), every CTA writes
 * an unnormalised partial (acc[hd], running max, running sum; an empty slice writes acc 0, max -inf) and the host
 * combines them, also when split == 0. */

/* cut K (2026-10-12, GQA group): at head_dim 128 one CTA serves the GC query heads of one kv head, GC =
 * min(2^log2gqa, 4), so every K and V byte of a launch is read once instead of once per query head. The KV
 * pool is GPU-uncached (host-written), so the four CTAs of a GQA group were four DRAM reads of the same
 * bytes: 21 MB per call at 1268 tokens, the memory ceiling (sc leg smoke-ctx-chunk: 152 us per call).
 * Grid x is the head group (num_q_heads / GC CTAs per sequence and split). Shared memory: q, scores and
 * warp partials per head, token offsets once. GC = 1 (every hd 64 kernel, hd 128 with gqa 1) emits exactly
 * the program before this cut (digest fixtures). */
static uint32_t heads_per_cta(uint32_t hd, uint32_t log2gqa) { return hd == 128u ? (1u << (log2gqa < 2u ? log2gqa : 2u)) : 1u; }
static uint32_t shared_bytes_for(uint32_t hd, uint32_t log2gqa) { return (3u * heads_per_cta(hd, log2gqa) + 1u) * hd * 4u; }
uint32_t omega_gpu_attention_heads_per_cta(uint32_t head_dim, uint32_t log2_gqa) { return heads_per_cta(head_dim, log2_gqa); }

#define AT_GPR_BUDGET 96u /* cut K: the GQA-group hd 128 kernel carries four heads of running state (the matmul blocked kernels launch at 108) */

static int build_kernel(const KSpec *k, OmegaBlackwellKernel *kernel, BlackwellIRProgram **keep) {
    BlackwellIRProgram *prog = omega_gpu_host_calloc(1, sizeof *prog);
    if (!prog) return OMEGA_GPU_ATTN_CODEGEN_FAIL;
    uint64_t spec[8] = {k->f32, k->log2bs, k->log2gqa, k->mutant, k->divergent,
                        k->hd, k->split >= 0, k->split >= 0 ? (uint64_t)k->split : 0};
    uint64_t *ins = omega_gpu_host_calloc(8192, sizeof *ins);
    uint64_t meta[512] = {0}, emit_status = 1;
    int rc = OMEGA_GPU_ATTN_CODEGEN_FAIL;
    int valid = ins && omega2_cg_gpu_attn_emit(&emit_status, spec, 8, ins, 8192, meta, 512) == OMEGA_OK &&
                emit_status == 0 && meta[15] == 0 && omega_bw_ir_from_om(ins, meta, prog) == 0 &&
                check_loop_invariant(prog, meta) == 0;
    omega_gpu_host_free(ins);
    if (valid && prog->regalloc.peak_gpr_usage <= AT_GPR_BUDGET) {
        size_t max_bytes = (size_t)BW_MAX_IR_INSNS * 16;
        memset(kernel, 0, sizeof *kernel);
        kernel->code = omega_gpu_host_alloc(max_bytes);
        size_t emitted = 0;
        if (kernel->code && omega_bw_encode_program(prog, kernel->code, max_bytes, &emitted) == 0) {
            kernel->code_size = emitted;
            kernel->insn_count = emitted / 16;
            kernel->gpr_count = prog->regalloc.peak_gpr_usage;
            kernel->uniform_gpr_count = prog->regalloc.peak_ugpr_usage;
            sha256_hash(kernel->code, kernel->code_size, kernel->code_digest);
            rc = OMEGA_GPU_ATTN_OK;
        } else {
            omega_gpu_host_free(kernel->code); kernel->code = NULL;
        }
    }
    if (keep && rc == OMEGA_GPU_ATTN_OK) *keep = prog; else omega_gpu_host_free(prog);
    return rc;
}

/* --------------------------------------------------------- kernel cache */

/* One kernel per KSpec; the device copy is uploaded once and stays resident for
 * the process (cut 4b). The IR program is kept for the host simulator. */
static int g_mutant;
static int g_divergent; /* omega #308 R2 test hook: see KSpec.divergent */
static bool g_dedupe = true; /* shared-prefix staging dedupe; false = legacy per-sequence staging (test hook) */
typedef struct { int used; KSpec k; OmegaBlackwellKernel kernel; BlackwellIRProgram *prog; OmegaGpuMem code; } Slot;
static OmegaGpuAttnSim g_sim;
static Slot g_cache[16]; /* split variants (cut F) multiply the shapes in flight */
static int g_split = -1; /* test hook: forced log2split (0..OMEGA_GPU_ATTN_MAX_LOG2SPLIT), -1 = chosen per launch from the context */
static OmegaGpuScratch g_q, g_pool, g_tab, g_out; /* staging, grown to the high-water mark, reused per call */
static OmegaGpuMem g_resident; /* the resident KV pool (omega_gpu_attention_pool_alloc); cpu NULL = none */
static bool g_hooked;
#define LOCK() omega_gpu_session_lock()
#define UNLOCK() omega_gpu_session_unlock()

void omega_gpu_attention_test_set_simulator(OmegaGpuAttnSim sim) { LOCK(); g_sim = sim; UNLOCK(); }
static uint32_t g_sim_shared_bytes; /* shared bytes the launcher would declare for the kernel the simulator is running */
uint32_t omega_gpu_attention_test_shared_bytes(void) { return g_sim_shared_bytes; }
void omega_gpu_attention_test_set_dedupe(bool on) { LOCK(); g_dedupe = on; UNLOCK(); }
void omega_gpu_attention_test_set_split(int log2split) { LOCK(); g_split = (log2split >= 0 && log2split <= (int)OMEGA_GPU_ATTN_MAX_LOG2SPLIT) ? log2split : -1; UNLOCK(); }

/* ---- resident KV pool (see the header) ---- */

static int dev_open_locked(void);

/* The kernel computes block_id * block_stride + slot * token_stride + head offset in 32 bits before
 * widening onto the 64-bit layer base: one layer slice (both planes, every token and head of the
 * block) past the block's start must stay inside 32 bits. */
static bool resident_fits(const OmegaGpuKvLayout *ly, uint32_t block_id) {
    return ly->block_stride_bytes <= 0xffffffffull &&
           (uint64_t)block_id * ly->block_stride_bytes + ly->layer_stride_bytes <= 0xffffffffull;
}
bool omega_gpu_attention_test_resident_fits(const OmegaGpuKvLayout *layout, uint32_t block_id) {
    return layout && resident_fits(layout, block_id);
}

int omega_gpu_attention_pool_alloc(size_t bytes, void **cpu) {
    if (!cpu || bytes == 0) return OMEGA_GPU_ATTN_BAD_ARGS;
    *cpu = NULL;
    LOCK();
    if (g_resident.cpu) { omega_gpu_session_set_error("attention pool: already allocated"); UNLOCK(); return OMEGA_GPU_ATTN_BAD_ARGS; }
    if (g_sim) {
        g_resident.cpu = omega_gpu_host_calloc(1, bytes);
        if (!g_resident.cpu) { UNLOCK(); return OMEGA_GPU_ATTN_CHIP_FAIL; }
        g_resident.va = (uintptr_t)g_resident.cpu; g_resident.size = bytes;
    } else {
        int rc = dev_open_locked();
        if (rc != OMEGA_GPU_ATTN_OK) { UNLOCK(); return rc; }
        if (omega_gpu_session_alloc(bytes, &g_resident) != 0) { memset(&g_resident, 0, sizeof g_resident); UNLOCK(); return OMEGA_GPU_ATTN_CHIP_FAIL; }
    }
    *cpu = g_resident.cpu;
    UNLOCK();
    return OMEGA_GPU_ATTN_OK;
}

void omega_gpu_attention_pool_free(void) {
    LOCK();
    if (g_resident.cpu) { if (g_sim) omega_gpu_host_free(g_resident.cpu); else omega_gpu_session_free(&g_resident); }
    memset(&g_resident, 0, sizeof g_resident);
    UNLOCK();
}

static void cache_clear_locked(void) {
    for (size_t i = 0; i < sizeof g_cache / sizeof g_cache[0]; i++)
        if (g_cache[i].used) { omega_gpu_host_free(g_cache[i].kernel.code); omega_gpu_host_free(g_cache[i].prog); omega_gpu_session_free(&g_cache[i].code); memset(&g_cache[i], 0, sizeof g_cache[i]); }
}

void omega_gpu_attention_cache_clear(void) {
    LOCK();
    cache_clear_locked();
    UNLOCK();
}

/* Called by the session (lock held, device still open) right before it closes. */
static void on_session_close(void) {
    cache_clear_locked();
    memset(&g_resident, 0, sizeof g_resident); /* the session's memory goes with it; the caller's mapping is dead */
    omega_gpu_session_scratch_free(&g_q); omega_gpu_session_scratch_free(&g_pool);
    omega_gpu_session_scratch_free(&g_tab); omega_gpu_session_scratch_free(&g_out);
}

void omega_gpu_attention_test_set_mutant(OmegaGpuAttnMutant m) {
    LOCK();
    g_mutant = (int)m;
    cache_clear_locked();
    UNLOCK();
}

/* Caller holds the lock. Builds the kernel if needed; uploads the device copy when
 * `upload` (the chip path; the simulator never needs one). */
static int kernel_for(bool f32, uint32_t log2bs, uint32_t log2gqa, uint32_t hd, int split, bool upload, Slot **out, bool *hit) {
    KSpec k = { .f32 = f32, .log2bs = log2bs, .log2gqa = log2gqa, .mutant = g_mutant, .divergent = g_divergent, .hd = hd, .split = split };
    Slot *s = NULL;
    for (size_t i = 0; i < sizeof g_cache / sizeof g_cache[0]; i++)
        if (g_cache[i].used && g_cache[i].k.f32 == k.f32 && g_cache[i].k.log2bs == k.log2bs && g_cache[i].k.log2gqa == k.log2gqa && g_cache[i].k.mutant == k.mutant && g_cache[i].k.divergent == k.divergent && g_cache[i].k.hd == k.hd && g_cache[i].k.split == k.split) { /* field compare: memcmp would read struct padding */
            s = &g_cache[i]; *hit = true; break;
        }
    if (!s) {
        OmegaBlackwellKernel kern; BlackwellIRProgram *kp = NULL;
        int rc = build_kernel(&k, &kern, &kp);
        if (rc != OMEGA_GPU_ATTN_OK) return rc;
        size_t slot = 0;
        for (size_t i = 0; i < sizeof g_cache / sizeof g_cache[0]; i++) if (!g_cache[i].used) { slot = i; break; }
        s = &g_cache[slot];
        if (s->used) { omega_gpu_host_free(s->kernel.code); omega_gpu_host_free(s->prog); omega_gpu_session_free(&s->code); } /* full: evict slot 0 */
        memset(s, 0, sizeof *s);
        s->used = 1; s->k = k; s->kernel = kern; s->prog = kp;
        *hit = false;
    }
    if (upload && !s->code.cpu) {
        if (omega_gpu_session_alloc_code(s->kernel.code_size, &s->code) != 0) return OMEGA_GPU_ATTN_CHIP_FAIL;
        memcpy(s->code.cpu, s->kernel.code, s->kernel.code_size);
        if (omega_gpu_session_sync_to_gpu(&s->code) != 0) { omega_gpu_session_free(&s->code); return OMEGA_GPU_ATTN_CHIP_FAIL; }
    }
    *out = s;
    return OMEGA_GPU_ATTN_OK;
}

int omega_gpu_attention_codegen_hd(bool kv_f32, uint32_t log2_block_size, uint32_t log2_gqa, uint32_t head_dim, OmegaBlackwellKernel *kernel) {
    if (!kernel || log2_block_size > 16 || log2_gqa > 6) return OMEGA_GPU_ATTN_BAD_ARGS;
    if (head_dim != 64u && head_dim != 128u) return OMEGA_GPU_ATTN_TOO_LARGE;
    LOCK();
    KSpec k = { .f32 = kv_f32, .log2bs = log2_block_size, .log2gqa = log2_gqa, .mutant = g_mutant, .divergent = g_divergent, .hd = head_dim, .split = -1 };
    UNLOCK();
    return build_kernel(&k, kernel, NULL);
}

int omega_gpu_attention_codegen(bool kv_f32, uint32_t log2_block_size, uint32_t log2_gqa, OmegaBlackwellKernel *kernel) {
    return omega_gpu_attention_codegen_hd(kv_f32, log2_block_size, log2_gqa, OMEGA_GPU_ATTN_HEAD_DIM, kernel);
}

const char *omega_gpu_attention_last_error(void) { return omega_gpu_session_last_error(); }

/* ------------------------------------------------------------ launcher */

#define AT_POISON 0xffbadbadu
#define AT_WAIT_MS 600000ull

static uint64_t now_ns(void) { return omega_gpu_session_now_ns(); } /* the platform clock (CLOCK_NS) */

typedef OmegaGpuAttnLaunch Launch;

/* Caller holds the lock. Chip path: open the shared device on first use. */
static int dev_open_locked(void) {
    if (!g_hooked) { (void)omega_gpu_session_on_close(on_session_close); g_hooked = true; }
    return omega_gpu_session_open() ? OMEGA_GPU_ATTN_OK : OMEGA_GPU_ATTN_CHIP_FAIL;
}

/* Where a call stages the KV slice it is about to hand the kernel: straight into the
 * device staging buffer on the chip path (one copy), a host buffer under the simulator.
 * Caller holds the lock; the result is valid until the next staging call. */
static void *stage_target(size_t bytes, void **host_tmp, int *fail_rc) {
    *host_tmp = NULL;
    *fail_rc = OMEGA_GPU_ATTN_CHIP_FAIL;
    if (g_sim) { *host_tmp = omega_gpu_host_alloc(bytes ? bytes : 1); return *host_tmp; }
    int r = omega_gpu_session_scratch(&g_pool, bytes);
    if (r != 0) { if (r == OMEGA_GPU_SESSION_SCRATCH_RESERVED) *fail_rc = OMEGA_GPU_ATTN_TOO_LARGE; return NULL; } /* reserved bound exceeded: loud, no allocation */
    return g_pool.mem.cpu;
}

/* One launch through the shared session (omega_gpu_session_launch: shader-cache
 * invalidate, constant bank, QMD0/QMD1, first marker, L2_FLUSH_DIRTY, second marker),
 * then readback and the poison scan. L->pool may already be the pool staging buffer. */
static int run_launch(const Slot *ks, const Launch *L, OmegaGpuAttnInfo *info) {
    int sr = omega_gpu_session_scratch(&g_q, L->q_bytes);
    if (!sr) sr = omega_gpu_session_scratch(&g_tab, L->tab_bytes);
    if (!sr) sr = omega_gpu_session_scratch(&g_out, L->out_bytes);
    if (!sr && !L->pool_va && L->pool != g_pool.mem.cpu) sr = omega_gpu_session_scratch(&g_pool, L->pool_bytes);
    if (sr) return sr == OMEGA_GPU_SESSION_SCRATCH_RESERVED ? OMEGA_GPU_ATTN_TOO_LARGE : OMEGA_GPU_ATTN_CHIP_FAIL;
    memcpy(g_q.mem.cpu, L->q, L->q_bytes);
    if (!L->pool_va && L->pool != g_pool.mem.cpu) memcpy(g_pool.mem.cpu, L->pool, L->pool_bytes);
    const uint64_t pool_va = L->pool_va ? L->pool_va : g_pool.mem.va; /* resident: the caller's KV, read in place */
    memcpy(g_tab.mem.cpu, L->tab, L->tab_bytes);
    size_t out_words = L->out_bytes / 4;
    uint32_t *out_dev = (uint32_t *)g_out.mem.cpu;
    for (size_t i = 0; i < out_words; i++) out_dev[i] = AT_POISON;
    /* the KV this launch reads: the staged pool, or the resident pool the caller wrote in place */
    if (omega_gpu_session_sync_to_gpu(&g_q.mem) != 0 || omega_gpu_session_sync_to_gpu(&g_tab.mem) != 0 ||
        omega_gpu_session_sync_to_gpu(&g_out.mem) != 0 || omega_gpu_session_sync_to_gpu(L->pool_va ? &g_resident : &g_pool.mem) != 0)
        return OMEGA_GPU_ATTN_CHIP_FAIL;

    uint32_t args[ARG_WORDS];
    args[0] = (uint32_t)g_q.mem.va; args[1] = (uint32_t)(g_q.mem.va >> 32);
    args[2] = (uint32_t)pool_va; args[3] = (uint32_t)(pool_va >> 32);
    args[4] = (uint32_t)g_out.mem.va; args[5] = (uint32_t)(g_out.mem.va >> 32);
    args[6] = (uint32_t)g_tab.mem.va; args[7] = (uint32_t)(g_tab.mem.va >> 32);
    memcpy(&args[8], L->params, sizeof L->params);
    OmegaGpuLaunch GL = {
        .code_va = ks->code.va, .gpr_count = AT_GPR_BUDGET, .threads_x = ks->k.hd, .threads_y = 1, .shared_bytes = shared_bytes_for(ks->k.hd, ks->k.log2gqa), /* (3 GC + 1) arrays of hd words: 1024 B for hd 64, 2048 B for hd 128 gqa 1, 6656 B for hd 128 gqa 4 */
        .grid_x = L->grid_x, .grid_y = L->grid_y, .num_elements = out_words,
        .args = args, .n_args = ARG_WORDS, .timeout_ms = AT_WAIT_MS,
    };
    uint64_t elapsed = 0; uint32_t marker = 0;
    if (omega_gpu_session_launch(&GL, &elapsed, &marker) != 0) return OMEGA_GPU_ATTN_CHIP_FAIL;
    if (omega_gpu_session_sync_to_cpu(&g_out.mem) != 0) return OMEGA_GPU_ATTN_CHIP_FAIL;

    memcpy(L->out, g_out.mem.cpu, L->out_bytes);
    uint32_t unwritten = 0;
    for (size_t i = 0; i < out_words; i++) if (((uint32_t *)L->out)[i] == AT_POISON) unwritten++;
    if (info) {
        info->chip_calls++;
        info->elapsed_ns += elapsed;
        info->completion_marker = marker;
        info->unwritten_words += unwritten;
        info->threads_per_cta = ks->k.hd;
        info->ctas_last_launch = L->grid_x * L->grid_y;
    }
    return unwritten ? OMEGA_GPU_ATTN_UNWRITTEN : OMEGA_GPU_ATTN_OK;
}

/* Caller holds the lock. Accounts the launch's q / table / output traffic (the KV
 * staging bytes are accounted where the slices are copied). */
static int launch(const Slot *ks, const Launch *L, OmegaGpuAttnInfo *info) {
    if (info) {
        info->q_bytes += L->q_bytes; info->tab_bytes += L->tab_bytes; info->out_bytes += L->out_bytes;
        info->kv_source = L->pool_va ? OMEGA_GPU_ATTN_KV_RESIDENT : OMEGA_GPU_ATTN_KV_STAGED;
    }
    if (g_sim) { g_sim_shared_bytes = shared_bytes_for(ks->k.hd, ks->k.log2gqa); return g_sim(ks->prog, L, info); }
    return run_launch(ks, L, info);
}

/* ---- opt-in serving reservation (see the header) ---- */

static int check_heads(uint32_t num_q_heads, uint32_t num_kv_heads, uint32_t head_dim, uint32_t *log2gqa);
static int log2_exact(uint32_t v, uint32_t *out);

int omega_gpu_attention_reserve(uint32_t max_context, uint32_t max_seqs, uint32_t num_q_heads, uint32_t num_kv_heads, uint32_t head_dim, uint32_t kv_block_size) {
    uint32_t log2gqa, log2bs;
    if (max_context == 0 || max_seqs == 0) { omega_gpu_session_set_error("attention reserve: zero bound"); return OMEGA_GPU_ATTN_BAD_ARGS; }
    if (kv_block_size && log2_exact(kv_block_size, &log2bs) != 0) { omega_gpu_session_set_error("attention reserve: block size not a power of two"); return OMEGA_GPU_ATTN_BAD_ARGS; }
    int rc = check_heads(num_q_heads, num_kv_heads, head_dim, &log2gqa);
    if (rc != OMEGA_GPU_ATTN_OK) { omega_gpu_session_set_error("attention reserve: bad head shape"); return rc; }
    /* KV staging, worst case over the two paths, per sequence: contiguous f32 holds both planes for max_context tokens
     * (2 * ctx * kvh * hd * 4); paged bf16 stages whole blocks of both planes (round_up(ctx, block) * kvh * hd * 4), which
     * is the larger one when max_context is under half a block. */
    size_t per_seq = 2u * max_context * (size_t)num_kv_heads * head_dim * 4u;
    if (kv_block_size) {
        size_t paged = ((size_t)max_context + kv_block_size - 1) / kv_block_size * kv_block_size * num_kv_heads * head_dim * 4u;
        if (paged > per_seq) per_seq = paged;
    }
    const size_t pool = per_seq * max_seqs;
    /* q rows for every sequence, and the output buffer sized for the paged path's partials of one launch
     * (cut J: up to 2^MAX_LOG2SPLIT partials of head_dim + 2 words per (sequence, head), at most
     * MAX_CTAS / num_q_heads sequences per launch; the rows reserve usually asks for more). */
    const size_t q_bytes = (size_t)max_seqs * num_q_heads * head_dim * 4u;
    size_t launch_seqs = OMEGA_GPU_ATTN_MAX_CTAS / num_q_heads;
    if (launch_seqs == 0) launch_seqs = 1;
    if (launch_seqs > max_seqs) launch_seqs = max_seqs;
    const size_t partials = launch_seqs * num_q_heads * ((size_t)1u << OMEGA_GPU_ATTN_MAX_LOG2SPLIT) * ((size_t)head_dim + 2u) * 4u;
    const size_t qo = q_bytes > partials ? q_bytes : partials;
    const size_t tab = ((size_t)max_seqs * max_context + max_seqs) * 4u;
    LOCK();
    rc = OMEGA_GPU_ATTN_OK;
    if (g_sim) rc = OMEGA_GPU_ATTN_OK; /* the simulator stages in host memory: nothing to reserve */
    else if (dev_open_locked() != OMEGA_GPU_ATTN_OK) rc = OMEGA_GPU_ATTN_CHIP_FAIL;
    else if (omega_gpu_session_scratch_reserve(&g_pool, pool) || omega_gpu_session_scratch_reserve(&g_q, q_bytes) ||
             omega_gpu_session_scratch_reserve(&g_out, qo) || omega_gpu_session_scratch_reserve(&g_tab, tab < 8 ? 8 : tab)) {
        /* roll back this API's own buffers: a failed reserve leaves nothing flagged (growth allowed as before) */
        omega_gpu_session_scratch_unreserve(&g_pool); omega_gpu_session_scratch_unreserve(&g_q);
        omega_gpu_session_scratch_unreserve(&g_out); omega_gpu_session_scratch_unreserve(&g_tab);
        rc = OMEGA_GPU_ATTN_CHIP_FAIL;
    }
    UNLOCK();
    return rc;
}

int omega_gpu_attention_reserve_rows(uint32_t max_rows, uint32_t num_q_heads, uint32_t head_dim) {
    if (max_rows == 0 || num_q_heads == 0 || num_q_heads > OMEGA_GPU_ATTN_MAX_Q_HEADS || (head_dim != 64u && head_dim != 128u)) {
        omega_gpu_session_set_error("attention reserve rows: bad bound");
        return OMEGA_GPU_ATTN_BAD_ARGS;
    }
    uint32_t per = OMEGA_GPU_ATTN_ROWS_MAX_CTAS / num_q_heads;
    if (per == 0) per = 1;
    if (per > max_rows) per = max_rows;
    const size_t qo = (size_t)per * num_q_heads * head_dim * 4u, tab = (size_t)per * 8u;
    LOCK();
    int rc = OMEGA_GPU_ATTN_OK;
    if (g_sim) rc = OMEGA_GPU_ATTN_OK;
    else if (dev_open_locked() != OMEGA_GPU_ATTN_OK) rc = OMEGA_GPU_ATTN_CHIP_FAIL;
    else if ((qo > g_q.cap && omega_gpu_session_scratch_reserve(&g_q, qo)) ||
             (qo > g_out.cap && omega_gpu_session_scratch_reserve(&g_out, qo)) ||
             (tab > g_tab.cap && omega_gpu_session_scratch_reserve(&g_tab, tab)))
        rc = OMEGA_GPU_ATTN_CHIP_FAIL; /* growth failed; whatever grew stays reserved at its larger size */
    UNLOCK();
    return rc;
}
void omega_gpu_attention_unreserve(void) {
    LOCK();
    omega_gpu_session_scratch_unreserve(&g_pool); omega_gpu_session_scratch_unreserve(&g_q);
    omega_gpu_session_scratch_unreserve(&g_out); omega_gpu_session_scratch_unreserve(&g_tab);
    UNLOCK();
}

/* ------------------------------------------------------- public entries */

static void info_begin(OmegaGpuAttnInfo *info, const OmegaBlackwellKernel *k, bool hit) {
    if (!info) return;
    memset(info, 0, sizeof *info);
    info->kernel_cache_hit = hit;
    info->gpr_count = k->gpr_count;
    info->insn_count = (uint32_t)k->insn_count;
    omega_gpu_fmt(info->target_chip, sizeof info->target_chip, "NVIDIA DGX Spark (Grace Blackwell GB10)");
    info->sm_architecture = 121;
}
static uint32_t f2u(float f) { uint32_t u; memcpy(&u, &f, 4); return u; }
static int log2_exact(uint32_t v, uint32_t *out) {
    if (v == 0 || (v & (v - 1))) return -1;
    uint32_t l = 0; while ((1u << l) != v) l++;
    *out = l; return 0;
}
/* log2(e) / sqrt(head_dim) with the square roots as literals (8 and 11.313708498984761 = sqrt(128), both exactly what sqrt() returns):
 * the library must not need libm (omegatool links without -lm; a constant head_dim folded sqrt away, a runtime one does not). */
static float score_scale(uint32_t hd) { return (float)(1.4426950408889634 / (hd == 128u ? 11.313708498984761 : 8.0)); }

/* Common head-shape checks; returns log2 of the gqa ratio. */
static int check_heads(uint32_t num_q_heads, uint32_t num_kv_heads, uint32_t head_dim, uint32_t *log2gqa) {
    if (num_q_heads == 0 || num_kv_heads == 0 || head_dim == 0) return OMEGA_GPU_ATTN_BAD_ARGS;
    if ((head_dim != 64u && head_dim != 128u) || num_q_heads > OMEGA_GPU_ATTN_MAX_Q_HEADS) return OMEGA_GPU_ATTN_TOO_LARGE;
    if (num_q_heads % num_kv_heads != 0 || log2_exact(num_q_heads / num_kv_heads, log2gqa) != 0) return OMEGA_GPU_ATTN_BAD_ARGS;
    return OMEGA_GPU_ATTN_OK;
}

/* Common prologue of every chip entry (lock held on success): device, kernel, info. */
static int begin(bool f32, uint32_t log2bs, uint32_t log2gqa, uint32_t hd, int split, Slot **ks, OmegaGpuAttnInfo *info) {
    LOCK();
    int rc = g_sim ? OMEGA_GPU_ATTN_OK : dev_open_locked();
    bool hit = false;
    if (rc == OMEGA_GPU_ATTN_OK) rc = kernel_for(f32, log2bs, log2gqa, hd, split, !g_sim, ks, &hit);
    if (rc != OMEGA_GPU_ATTN_OK) { UNLOCK(); return rc; }
    info_begin(info, &(*ks)->kernel, hit);
    return OMEGA_GPU_ATTN_OK;
}

int omega_gpu_gqa_attention_f32(const float *q, const float *k_cache, const float *v_cache,
                                uint32_t seq_len, uint32_t num_q_heads, uint32_t num_kv_heads,
                                uint32_t head_dim, float *out, OmegaGpuAttnInfo *info) {
    uint64_t t0 = now_ns();
    if (!q || !k_cache || !v_cache || !out) return OMEGA_GPU_ATTN_BAD_ARGS;
    uint32_t log2gqa;
    int rc = check_heads(num_q_heads, num_kv_heads, head_dim, &log2gqa);
    if (rc != OMEGA_GPU_ATTN_OK) return rc;
    if (seq_len > OMEGA_GPU_ATTN_MAX_GQA_CTX) return OMEGA_GPU_ATTN_TOO_LARGE;
    const uint32_t HD = head_dim;
    size_t n_out = (size_t)num_q_heads * HD;
    if (seq_len == 0) { memset(out, 0, n_out * 4); if (info) { memset(info, 0, sizeof *info); info->call_ns = now_ns() - t0; } return OMEGA_GPU_ATTN_OK; }
    Slot *ks = NULL;
    const uint32_t log2bs = 12; /* one block of 4096 slots */
    rc = begin(true, log2bs, log2gqa, HD, -1, &ks, info);
    if (rc != OMEGA_GPU_ATTN_OK) return rc;
    size_t plane = (size_t)seq_len * num_kv_heads * HD * 4;
    void *host_tmp = NULL;
    int stage_rc;
    uint8_t *pool = stage_target(2 * plane, &host_tmp, &stage_rc);
    if (!pool) { UNLOCK(); return stage_rc; }
    memcpy(pool, k_cache, plane);
    memcpy(pool + plane, v_cache, plane);
    if (info) { info->kv_bytes_staged += 2 * plane; info->kv_bytes_naive += 2 * plane; info->kv_blocks_logical += 1; info->kv_blocks_unique += 1; } /* one contiguous pseudo-block */
    uint32_t tab[2] = { 0, seq_len }; /* table row {0}, then the context length at byte 4 */
    Launch L = {
        .q = q, .q_bytes = n_out * 4, .pool = pool, .pool_bytes = 2 * plane, .tab = tab, .tab_bytes = sizeof tab,
        .out = out, .out_bytes = n_out * 4, .grid_x = num_q_heads / heads_per_cta(HD, log2gqa), .grid_y = 1,
        .params = { 1, f2u(score_scale(HD)), (uint32_t)(2 * plane), num_kv_heads * HD * 4, (uint32_t)plane, HD * 4, num_q_heads, 4 }
    };
    rc = launch(ks, &L, info);
    omega_gpu_host_free(host_tmp);
    UNLOCK();
    if (info) info->call_ns = now_ns() - t0;
    return rc;
}

/* Rows per launch of the rows path: the CTA bound, then (under a reservation) what the q buffer holds. Caller holds the lock. */
static uint32_t rows_per_launch(uint32_t num_rows, uint32_t num_q_heads, size_t row_bytes) {
    uint32_t per = OMEGA_GPU_ATTN_ROWS_MAX_CTAS / num_q_heads;
    if (per == 0) per = 1;
    if (per > num_rows) per = num_rows;
    if (!g_sim && g_q.reserved && g_q.cap >= row_bytes) {
        size_t fit = g_q.cap / row_bytes;
        if (fit < per) per = (uint32_t)fit;
    }
    return per;
}

int omega_gpu_gqa_attention_rows_f32(const float *q, const float *k_cache, const float *v_cache,
                                     uint32_t base_len, uint32_t num_rows, uint32_t num_q_heads,
                                     uint32_t num_kv_heads, uint32_t head_dim, float *out, OmegaGpuAttnInfo *info) {
    uint64_t t0 = now_ns();
    if (!q || !k_cache || !v_cache || !out || num_rows == 0) return OMEGA_GPU_ATTN_BAD_ARGS;
    uint32_t log2gqa;
    int rc = check_heads(num_q_heads, num_kv_heads, head_dim, &log2gqa);
    if (rc != OMEGA_GPU_ATTN_OK) return rc;
    if ((uint64_t)base_len + num_rows > OMEGA_GPU_ATTN_MAX_GQA_CTX) return OMEGA_GPU_ATTN_TOO_LARGE;
    const uint32_t HD = head_dim, total = base_len + num_rows;
    const size_t row = (size_t)num_q_heads * HD;
    Slot *ks = NULL;
    const uint32_t log2bs = 12; /* one block of 4096 slots, as the single-row call */
    rc = begin(true, log2bs, log2gqa, HD, -1, &ks, info);
    if (rc != OMEGA_GPU_ATTN_OK) return rc;
    /* the whole context (every row's keys are a prefix of it) staged once */
    size_t plane = (size_t)total * num_kv_heads * HD * 4;
    void *host_tmp = NULL;
    int stage_rc;
    uint8_t *pool = stage_target(2 * plane, &host_tmp, &stage_rc);
    if (!pool) { UNLOCK(); return stage_rc; }
    memcpy(pool, k_cache, plane);
    memcpy(pool + plane, v_cache, plane);
    if (info) { info->kv_bytes_staged += 2 * plane; info->kv_bytes_naive += (uint64_t)num_rows * 2 * plane; info->kv_blocks_logical += num_rows; info->kv_blocks_unique += 1; }
    const uint32_t per = rows_per_launch(num_rows, num_q_heads, row * 4);
    /* table of one launch: per block ids (all 0: the one staged block), then per context lengths */
    uint32_t *tab = omega_gpu_host_calloc(2 * (size_t)per, sizeof *tab);
    if (!tab) { omega_gpu_host_free(host_tmp); UNLOCK(); return OMEGA_GPU_ATTN_CHIP_FAIL; }
    for (uint32_t r0 = 0; r0 < num_rows && rc == OMEGA_GPU_ATTN_OK; r0 += per) {
        const uint32_t nr = num_rows - r0 < per ? num_rows - r0 : per;
        for (uint32_t i = 0; i < nr; i++) { tab[i] = 0; tab[nr + i] = base_len + r0 + i + 1; }
        Launch L = {
            .q = q + (size_t)r0 * row, .q_bytes = (size_t)nr * row * 4, .pool = pool, .pool_bytes = 2 * plane,
            .tab = tab, .tab_bytes = (size_t)2 * nr * 4, .out = out + (size_t)r0 * row, .out_bytes = (size_t)nr * row * 4,
            .grid_x = num_q_heads / heads_per_cta(HD, log2gqa), .grid_y = nr,
            .params = { 1, f2u(score_scale(HD)), (uint32_t)(2 * plane), num_kv_heads * HD * 4, (uint32_t)plane, HD * 4, num_q_heads, nr * 4 }
        };
        rc = launch(ks, &L, info);
    }
    omega_gpu_host_free(tab);
    omega_gpu_host_free(host_tmp);
    UNLOCK();
    if (info) info->call_ns = now_ns() - t0;
    return rc;
}

/* Paged path shared by the single and batched entries. tables[s] has n_blocks[s] entries
 * (already filtered of negatives), ctx[s] the context length. */
/* cut F: a sequence's own split count from its context alone (the kernel computes the same): log2 of the largest
 * power of two <= min(2^MAX_LOG2SPLIT, chunks), chunks = ceil(ctx / HD) (cut J: one whole chunk per split; cut F took two). */
static uint32_t own_log2split(uint32_t ctx, uint32_t HD) {
    uint32_t x = (ctx + HD - 1) / HD, l = 0;
    while (l < OMEGA_GPU_ATTN_MAX_LOG2SPLIT && (2u << l) <= x) l++;
    return l;
}

/* 2^x in float without the math library (the engine archive also links where there is none): round x to the
 * nearest integer n, 2^f on f in [-0.5, 0.5] by the Cephes exp2f polynomial, scale by 2^n through the exponent
 * bits. x <= -127 (so also -inf, an empty split) is 0. The combine only passes x <= 0. */
static float host_exp2(float x) {
    if (x <= -127.0f) return 0.0f;
    if (x > 127.0f) x = 127.0f;
    int n = (int)(x + (x < 0.0f ? -0.5f : 0.5f));
    const float f = x - (float)n;
    float px = 1.535336188319500e-4f;
    px = px * f + 1.339887440266574e-3f;
    px = px * f + 9.618437357674640e-3f;
    px = px * f + 5.550332471162809e-2f;
    px = px * f + 2.402264791363012e-1f;
    px = px * f + 6.931472028550421e-1f;
    px = 1.0f + f * px;
    if (n < -126) { px *= 0.5f; n = -126; }
    union { uint32_t u; float f; } sc;
    sc.u = (uint32_t)(n + 127) << 23;
    return px * sc.f;
}

/* cut F: fold the per-split partials of each (sequence, head) row into out. w_s = 2^(M_s - max M): the kernel's
 * running max and sum live in the log2 domain (scale carries log2 e, MUFU.EX2). A row whose every split is empty
 * (context 0) is 0. */
static void combine_splits(const float *part, float *out, size_t rows, uint32_t S, uint32_t HD) {
    const size_t pw = (size_t)HD + 2;
    for (size_t r = 0; r < rows; r++) {
        const float *p = part + r * S * pw;
        float *o = out + r * HD;
        float mx = -__builtin_inff();
        for (uint32_t s = 0; s < S; s++) if (p[s * pw + HD] > mx) mx = p[s * pw + HD];
        if (!(mx > -__builtin_inff())) { memset(o, 0, (size_t)HD * 4); continue; }
        float w[1u << OMEGA_GPU_ATTN_MAX_LOG2SPLIT], lsum = 0.0f;
        for (uint32_t s = 0; s < S; s++) { w[s] = host_exp2(p[s * pw + HD] - mx); lsum += w[s] * p[s * pw + HD + 1]; }
        const float inv = 1.0f / lsum;
        for (uint32_t d = 0; d < HD; d++) {
            float a = 0.0f;
            for (uint32_t s = 0; s < S; s++) a += w[s] * p[s * pw + d];
            o[d] = a * inv;
        }
    }
}

static int paged_core(const float *q, const uint8_t *pool, const OmegaGpuKvLayout *ly,
                      const uint32_t *const *tables, const uint32_t *n_blocks, const uint32_t *ctx,
                      uint32_t num_seqs, uint32_t layer_idx, uint32_t num_q_heads, uint32_t num_kv_heads,
                      uint32_t head_dim, float *out, OmegaGpuAttnInfo *info) {
    uint64_t t0 = now_ns();
    uint32_t log2gqa, log2bs;
    int rc = check_heads(num_q_heads, num_kv_heads, head_dim, &log2gqa);
    if (rc != OMEGA_GPU_ATTN_OK) return rc;
    const uint32_t HD = head_dim;
    if (!ly || layer_idx >= ly->num_layers || log2_exact(ly->block_size, &log2bs) != 0) return OMEGA_GPU_ATTN_BAD_ARGS;
    /* the oracle addresses heads as kv_head * head_dim * 2 inside a token: the layout must agree */
    if (ly->head_stride_bytes != HD * 2 || ly->token_stride_bytes != (uint64_t)num_kv_heads * HD * 2 ||
        ly->kv_plane_stride_bytes != (uint64_t)ly->block_size * ly->token_stride_bytes ||
        ly->layer_stride_bytes != 2 * ly->kv_plane_stride_bytes || ly->block_stride_bytes < (uint64_t)ly->num_layers * ly->layer_stride_bytes)
        return OMEGA_GPU_ATTN_BAD_ARGS;
    size_t row = (size_t)num_q_heads * HD;
    /* effective context per sequence and block id range check */
    uint32_t *eff = omega_gpu_host_calloc(num_seqs ? num_seqs : 1, sizeof *eff);
    if (!eff) return OMEGA_GPU_ATTN_CHIP_FAIL;
    for (uint32_t s = 0; s < num_seqs; s++) {
        uint64_t cap = (uint64_t)n_blocks[s] * ly->block_size;
        eff[s] = (uint32_t)(ctx[s] < cap ? ctx[s] : cap);
        for (uint32_t b = 0; b < n_blocks[s]; b++) {
            uint64_t id = tables[s][b];
            if (id >= ly->num_blocks || id * ly->block_stride_bytes + (uint64_t)(layer_idx + 1) * ly->layer_stride_bytes > ly->pool_bytes) { omega_gpu_host_free(eff); return OMEGA_GPU_ATTN_BAD_ARGS; }
        }
    }
    uint32_t seqs_per_launch = OMEGA_GPU_ATTN_MAX_CTAS / num_q_heads;
    if (seqs_per_launch == 0) seqs_per_launch = 1;
    /* cut F: split each (sequence, head) over 2^log2split CTAs along the context: at least one whole chunk per
     * split, from the longest context in the call, within the split launch bound (the test hook forces it). */
    uint32_t log2split = 0;
    if (g_split >= 0) log2split = (uint32_t)g_split;
    else for (uint32_t s = 0; s < num_seqs; s++) { uint32_t l = own_log2split(eff[s], HD); if (l > log2split) log2split = l; }
    while (log2split && ((uint64_t)num_q_heads * seqs_per_launch << log2split) > OMEGA_GPU_ATTN_SPLIT_MAX_CTAS) log2split--;
    const uint32_t S = 1u << log2split;
    float *part = omega_gpu_host_alloc((size_t)seqs_per_launch * num_q_heads * S * (HD + 2) * 4); /* the partials of one launch */
    if (!part) { omega_gpu_host_free(eff); return OMEGA_GPU_ATTN_CHIP_FAIL; }
    Slot *ks = NULL;
    rc = begin(false, log2bs, log2gqa, HD, (int)log2split, &ks, info);
    if (rc != OMEGA_GPU_ATTN_OK) { omega_gpu_host_free(eff); omega_gpu_host_free(part); return rc; }
    uint32_t maxb = 1;
    for (uint32_t s = 0; s < num_seqs; s++) if (n_blocks[s] > maxb) maxb = n_blocks[s];
    /* Resident pool (2026-10-12): the caller's pool IS omega's allocation. Read it in place when the
     * layout fits the allocation and every referenced block passes the 32-bit fit rule; else stage. */
    bool resident = g_resident.cpu && (const void *)pool == g_resident.cpu && ly->pool_bytes <= g_resident.size;
    for (uint32_t s = 0; resident && s < num_seqs; s++) {
        uint32_t need = eff[s] ? (eff[s] + ly->block_size - 1) / ly->block_size : 0;
        for (uint32_t b = 0; b < need; b++) if (!resident_fits(ly, tables[s][b])) { resident = false; break; }
    }
    /* Dedupe map: physical block id -> staged slot of the current launch (-1 = not staged yet),
     * plus the list of ids touched by the launch (in slot order) so the reset is O(unique). */
    int32_t *slot_of = NULL; uint32_t *touched = NULL;
    if (g_dedupe && !resident) {
        size_t nb = ly->num_blocks ? ly->num_blocks : 1;
        slot_of = omega_gpu_host_alloc(nb * sizeof *slot_of);
        touched = omega_gpu_host_alloc(nb * sizeof *touched);
        if (!slot_of || !touched) { omega_gpu_host_free(slot_of); omega_gpu_host_free(touched); omega_gpu_host_free(eff); UNLOCK(); return OMEGA_GPU_ATTN_CHIP_FAIL; }
        memset(slot_of, 0xff, nb * sizeof *slot_of); /* every entry -1 */
    }
    for (uint32_t s0 = 0; s0 < num_seqs && rc == OMEGA_GPU_ATTN_OK; s0 += seqs_per_launch) {
        uint32_t ns = num_seqs - s0 < seqs_per_launch ? num_seqs - s0 : seqs_per_launch;
        /* logical references: every sequence's blocks up to its (truncated) context */
        uint32_t total = 0;
        for (uint32_t s = 0; s < ns; s++) total += eff[s0 + s] ? (eff[s0 + s] + ly->block_size - 1) / ly->block_size : 0;
        uint32_t *tab = omega_gpu_host_calloc((size_t)ns * maxb + ns, sizeof *tab);
        if (!tab) { rc = OMEGA_GPU_ATTN_CHIP_FAIL; break; }
        if (resident) {
            /* the table carries the physical ids; the kernel's block stride is the pool's; the layer
             * base is the chip address of this layer's slice of block 0 */
            for (uint32_t s = 0; s < ns; s++) {
                uint32_t need = eff[s0 + s] ? (eff[s0 + s] + ly->block_size - 1) / ly->block_size : 0;
                for (uint32_t b = 0; b < need; b++) tab[(size_t)s * maxb + b] = tables[s0 + s][b];
                tab[(size_t)ns * maxb + s] = eff[s0 + s];
            }
            if (info) { info->kv_blocks_logical += total; info->kv_bytes_naive += (uint64_t)total * ly->layer_stride_bytes; }
            Launch L = {
                .q = q + (size_t)s0 * row, .q_bytes = (size_t)ns * row * 4,
                .pool = (const uint8_t *)pool + (size_t)layer_idx * ly->layer_stride_bytes, .pool_bytes = 0,
                .tab = tab, .tab_bytes = ((size_t)ns * maxb + ns) * 4,
                .out = part, .out_bytes = (size_t)ns * num_q_heads * S * (HD + 2) * 4,
                .grid_x = num_q_heads / heads_per_cta(HD, log2gqa), .grid_y = ns * S,
                .params = { maxb, f2u(score_scale(HD)), (uint32_t)ly->block_stride_bytes, (uint32_t)ly->token_stride_bytes,
                            (uint32_t)ly->kv_plane_stride_bytes, (uint32_t)ly->head_stride_bytes, num_q_heads, ns * maxb * 4 },
                .pool_va = g_resident.va + (uint64_t)layer_idx * ly->layer_stride_bytes,
            };
            rc = launch(ks, &L, info);
            if (rc == OMEGA_GPU_ATTN_OK) combine_splits(part, out + (size_t)s0 * row, (size_t)ns * num_q_heads, S, HD);
            omega_gpu_host_free(tab);
            continue;
        }
        /* pass 1: assign staged slots. Dedupe keys on the PHYSICAL block id (not the table
         * position): a CoW prefix block shared by several branches gets one slot. Each
         * sequence's compact table keeps its own block order and truncated context. */
        uint32_t g = 0;
        for (uint32_t s = 0; s < ns; s++) {
            uint32_t need = eff[s0 + s] ? (eff[s0 + s] + ly->block_size - 1) / ly->block_size : 0;
            for (uint32_t b = 0; b < need; b++) {
                uint32_t id = tables[s0 + s][b];
                if (g_dedupe) {
                    if (slot_of[id] < 0) { slot_of[id] = (int32_t)g; touched[g] = id; g++; }
                    tab[(size_t)s * maxb + b] = (uint32_t)slot_of[id];
                } else {
                    tab[(size_t)s * maxb + b] = g++; /* legacy: one slot per reference */
                }
            }
            tab[(size_t)ns * maxb + s] = eff[s0 + s];
        }
        uint64_t staged_bytes = (uint64_t)(g ? g : 1) * ly->layer_stride_bytes;
        if (staged_bytes > 0xffffffffull) { omega_gpu_host_free(tab); rc = OMEGA_GPU_ATTN_TOO_LARGE; break; }
        void *host_tmp = NULL;
        int stage_rc;
        uint8_t *staged = stage_target((size_t)staged_bytes, &host_tmp, &stage_rc);
        if (!staged) { omega_gpu_host_free(tab); rc = stage_rc; break; }
        /* pass 2: copy each staged slot's (physical block, layer) slice exactly once */
        if (g_dedupe) {
            for (uint32_t u = 0; u < g; u++) {
                const uint8_t *src = pool + (size_t)touched[u] * ly->block_stride_bytes + (size_t)layer_idx * ly->layer_stride_bytes;
                memcpy(staged + (size_t)u * ly->layer_stride_bytes, src, (size_t)ly->layer_stride_bytes);
                slot_of[touched[u]] = -1; /* reset for the next launch */
            }
        } else {
            uint32_t w = 0;
            for (uint32_t s = 0; s < ns; s++) {
                uint32_t need = eff[s0 + s] ? (eff[s0 + s] + ly->block_size - 1) / ly->block_size : 0;
                for (uint32_t b = 0; b < need; b++, w++) {
                    const uint8_t *src = pool + (size_t)tables[s0 + s][b] * ly->block_stride_bytes + (size_t)layer_idx * ly->layer_stride_bytes;
                    memcpy(staged + (size_t)w * ly->layer_stride_bytes, src, (size_t)ly->layer_stride_bytes);
                }
            }
        }
        if (info) {
            info->kv_blocks_logical += total; info->kv_blocks_unique += g;
            info->kv_bytes_staged += (uint64_t)g * ly->layer_stride_bytes;
            info->kv_bytes_naive += (uint64_t)total * ly->layer_stride_bytes;
        }
        Launch L = {
            .q = q + (size_t)s0 * row, .q_bytes = (size_t)ns * row * 4, .pool = staged, .pool_bytes = (size_t)staged_bytes,
            .tab = tab, .tab_bytes = ((size_t)ns * maxb + ns) * 4,
            .out = part, .out_bytes = (size_t)ns * num_q_heads * S * (HD + 2) * 4,
            .grid_x = num_q_heads / heads_per_cta(HD, log2gqa), .grid_y = ns * S,
            .params = { maxb, f2u(score_scale(HD)), (uint32_t)ly->layer_stride_bytes, (uint32_t)ly->token_stride_bytes,
                        (uint32_t)ly->kv_plane_stride_bytes, (uint32_t)ly->head_stride_bytes, num_q_heads, ns * maxb * 4 }
        };
        rc = launch(ks, &L, info);
        if (rc == OMEGA_GPU_ATTN_OK) combine_splits(part, out + (size_t)s0 * row, (size_t)ns * num_q_heads, S, HD);
        omega_gpu_host_free(host_tmp); omega_gpu_host_free(tab);
    }
    UNLOCK();
    omega_gpu_host_free(eff); omega_gpu_host_free(slot_of); omega_gpu_host_free(touched); omega_gpu_host_free(part);
    if (info) info->call_ns = now_ns() - t0;
    return rc;
}

int omega_gpu_paged_attention_bf16(const float *q, const void *pool, const OmegaGpuKvLayout *layout,
                                   const uint32_t *block_ids, uint32_t num_block_ids,
                                   uint32_t context_len, uint32_t layer_idx,
                                   uint32_t num_q_heads, uint32_t num_kv_heads, uint32_t head_dim,
                                   float *out, OmegaGpuAttnInfo *info) {
    if (!q || !pool || !layout || !out || (num_block_ids && !block_ids)) return OMEGA_GPU_ATTN_BAD_ARGS;
    const uint32_t *tables[1] = { block_ids };
    uint32_t nb[1] = { num_block_ids }, cx[1] = { context_len };
    return paged_core(q, pool, layout, tables, nb, cx, 1, layer_idx, num_q_heads, num_kv_heads, head_dim, out, info);
}

int omega_gpu_paged_attention_batch_bf16(const float *q, const void *pool, const OmegaGpuKvLayout *layout,
                                         const int32_t *block_tables, const int32_t *context_lens,
                                         uint32_t max_blocks_per_seq, uint32_t num_seqs, uint32_t layer_idx,
                                         uint32_t num_q_heads, uint32_t num_kv_heads, uint32_t head_dim,
                                         float *out, OmegaGpuAttnInfo *info) {
    if (!q || !pool || !layout || !out || !block_tables || !context_lens || num_seqs == 0) return OMEGA_GPU_ATTN_BAD_ARGS;
    /* the oracle's rules: ctx <= 0 -> 0; a table row past the array -> empty; negatives removed */
    uint32_t **tables = omega_gpu_host_calloc(num_seqs, sizeof *tables);
    uint32_t *nb = omega_gpu_host_calloc(num_seqs, sizeof *nb), *cx = omega_gpu_host_calloc(num_seqs, sizeof *cx);
    if (!tables || !nb || !cx) { omega_gpu_host_free(tables); omega_gpu_host_free(nb); omega_gpu_host_free(cx); return OMEGA_GPU_ATTN_CHIP_FAIL; }
    int rc = OMEGA_GPU_ATTN_OK;
    for (uint32_t s = 0; s < num_seqs; s++) {
        cx[s] = context_lens[s] > 0 ? (uint32_t)context_lens[s] : 0;
        tables[s] = omega_gpu_host_calloc(max_blocks_per_seq ? max_blocks_per_seq : 1, sizeof **tables);
        if (!tables[s]) { rc = OMEGA_GPU_ATTN_CHIP_FAIL; break; }
        for (uint32_t b = 0; b < max_blocks_per_seq; b++) {
            int32_t v = block_tables[(size_t)s * max_blocks_per_seq + b];
            if (v >= 0) tables[s][nb[s]++] = (uint32_t)v;
        }
    }
    if (rc == OMEGA_GPU_ATTN_OK)
        rc = paged_core(q, pool, layout, (const uint32_t *const *)tables, nb, cx, num_seqs, layer_idx, num_q_heads, num_kv_heads, head_dim, out, info);
    for (uint32_t s = 0; s < num_seqs; s++) omega_gpu_host_free(tables[s]);
    omega_gpu_host_free(tables); omega_gpu_host_free(nb); omega_gpu_host_free(cx);
    return rc;
}

static const char *const k_mutant_names[OMEGA_GPU_ATTN_MUTANT_COUNT] = {
    "none", "NO_MAX", "KV_HEAD", "SLOT", "NO_RESCALE", "Q_ROW", "OUT_ROW"
};
_Static_assert(sizeof k_mutant_names / sizeof k_mutant_names[0] == OMEGA_GPU_ATTN_MUTANT_COUNT, "mutant name table");

const char *omega_gpu_attention_mutant_name(OmegaGpuAttnMutant m) {
    return (m >= 0 && m < OMEGA_GPU_ATTN_MUTANT_COUNT && k_mutant_names[m]) ? k_mutant_names[m] : "?";
}

const char *omega_gpu_attention_rc_name(int rc) {
    switch (rc) {
    case OMEGA_GPU_ATTN_OK: return "OK";
    case OMEGA_GPU_ATTN_BAD_ARGS: return "BAD_ARGS";
    case OMEGA_GPU_ATTN_TOO_LARGE: return "TOO_LARGE";
    case OMEGA_GPU_ATTN_CODEGEN_FAIL: return "CODEGEN_FAIL";
    case OMEGA_GPU_ATTN_CHIP_FAIL: return "CHIP_FAIL";
    case OMEGA_GPU_ATTN_UNWRITTEN: return "UNWRITTEN";
    default: return "UNKNOWN";
    }
}

/* omega #308 R2 test hook: 0 production, 1 lane-dependent branch inside a reconvergence
 * region, 2 the same with the BSYNC dropped (negative control). Clears the kernel cache. */
void omega_gpu_attention_test_set_divergent(int mode) {
    LOCK();
    g_divergent = (mode < 0 || mode > 2) ? 0 : mode;
    cache_clear_locked();
    UNLOCK();
}
