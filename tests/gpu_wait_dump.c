/* SPDX-License-Identifier: Apache-2.0
 * gpu_wait_dump.c -- REFERENCE-ONLY C dumper for tests/gpu_wait_parity.sh: runs the scripted
 * scenarios of a corpus (stdin) through omega_gpu_wait_fixed and omega_gpu_wait_sequence of
 * src/omega_gpu_wait.c, built with OMEGA_GPU_NO_POSIX
 * (so a wait without a clock is expressible), and prints the report, the return value and the
 * trace of hook calls. tests/gpu_wait_dump.om prints the same from src/omega_gpu_wait.om.
 * Committed once with the goldens it generated (tests/gpu_wait_golden), removed in the next commit.
 *
 * Corpus (one command per line, decimal numbers, '#' and blank lines skipped):
 *   R                     reset the scenario
 *   K kind expected total_ms progress_ms flags marker2_want
 *        flags: 1 word, 2 marker2, 4 snapshot, 8 valid, 16 abort, 32 clock, 64 no cfg, 128 no report
 *   W v ...  watched word values, M v ... marker2 values, P a b ... snapshot pairs: the first
 *            value holds until the first relax, each relax moves to the next, the last one stays
 *   V b ...  valid answers, A b ... abort answers: one per call, then the last repeats (default
 *            valid 1, abort 0)
 *   T t ...  clock values, one per call; after the last, each call adds the step (S step,
 *            default 1000000)
 *   G        run and print
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include "omega_gpu_wait.h"

#define NV 64
static uint64_t lw[NV], lm[NV], lp[2 * NV], lv[NV], la[NV], lt[NV];
static int nw, nm, np, nvv, na, nt;
static uint64_t step = 1000000, tnow;
static int ep, vi, ai, ti;
static unsigned kind, flags;
static uint64_t expected, total_ms, progress_ms, m2want;
static volatile uint32_t word, marker2;
static char trace[200];
static uint64_t ntr, cnt[6];
static const char letters[] = "absnvr";

static void tr(int k)
{
    if (ntr < 160) trace[ntr] = letters[k];
    ntr++;
    cnt[k]++;
}

static void load(void)
{
    word = (uint32_t)(nw ? lw[ep < nw ? ep : nw - 1] : 0);
    marker2 = (uint32_t)(nm ? lm[ep < nm ? ep : nm - 1] : 0);
}

static void h_snapshot(void *ctx, uint32_t out[2])
{
    (void)ctx;
    tr(2);
    int n = np / 2, k = ep < n ? ep : n - 1;
    out[0] = n ? (uint32_t)lp[2 * k] : 0;
    out[1] = n ? (uint32_t)lp[2 * k + 1] : 0;
}
static bool h_valid(void *ctx, uint32_t v)
{
    (void)ctx; (void)v;
    tr(4);
    uint64_t b = nvv ? lv[vi < nvv ? vi : nvv - 1] : 1;
    vi++;
    return b != 0;
}
static bool h_abort(void *ctx)
{
    (void)ctx;
    tr(0);
    uint64_t b = na ? la[ai < na ? ai : na - 1] : 0;
    ai++;
    return b != 0;
}
static uint64_t h_now(void *ctx)
{
    (void)ctx;
    tr(3);
    if (ti < nt) tnow = lt[ti];
    else tnow += step;
    ti++;
    return tnow;
}
static void h_barrier(void *ctx) { (void)ctx; tr(1); }
static void h_relax(void *ctx)
{
    (void)ctx;
    tr(5);
    ep++;
    load();
}

static void reset(void)
{
    nw = nm = np = nvv = na = nt = 0;
    step = 1000000; tnow = 0;
    kind = 1; flags = 33; expected = total_ms = progress_ms = m2want = 0;
}

static void run(void)
{
    omega_gpu_wait_report_t rpt;
    omega_gpu_wait_cfg_t cfg;
    memset(&rpt, 0xa5, sizeof rpt);
    memset(&cfg, 0, sizeof cfg);
    ep = vi = ai = ti = 0; ntr = 0; memset(cnt, 0, sizeof cnt); tnow = 0;
    load();
    cfg.total_timeout_ms = (uint32_t)total_ms;
    cfg.progress_timeout_ms = (uint32_t)progress_ms;
    cfg.marker2 = (flags & 2) ? &marker2 : NULL;
    cfg.marker2_want = (uint32_t)m2want;
    cfg.snapshot = (flags & 4) ? h_snapshot : NULL;
    cfg.valid = (flags & 8) ? h_valid : NULL;
    cfg.abort = (flags & 16) ? h_abort : NULL;
    cfg.now_ns = (flags & 32) ? h_now : NULL;
    cfg.barrier = h_barrier;
    cfg.relax = h_relax;
    volatile uint32_t *w = (flags & 1) ? &word : NULL;
    omega_gpu_wait_report_t *rp = (flags & 128) ? NULL : &rpt;
    const omega_gpu_wait_cfg_t *cp = (flags & 64) ? NULL : &cfg;
    bool ok = kind == 2 ? omega_gpu_wait_sequence(w, (uint32_t)expected, rp, cp)
                        : omega_gpu_wait_fixed(w, (uint32_t)expected, rp, cp);
    printf("G ret=%d", ok ? 1 : 0);
    if (rp)
        printf(" kind=%d result=%d expected=%" PRIu32 " last=%" PRIu32 " m2=%" PRIu32
               " snap=%" PRIu32 ",%" PRIu32 " start=%" PRIu64 " elapsed=%" PRIu64 " lastprog=%" PRIu64
               " progress=%" PRIu64 " polls=%" PRIu64,
               (int)rpt.wait_kind, (int)rpt.result, rpt.expected, rpt.last_observed,
               rpt.last_marker2, rpt.snap[0], rpt.snap[1], rpt.start_ns, rpt.elapsed_ns,
               rpt.last_progress_ns, rpt.progress_count, rpt.polls);
    printf(" calls=%" PRIu64 " a=%" PRIu64 " b=%" PRIu64 " s=%" PRIu64 " n=%" PRIu64 " v=%" PRIu64
           " r=%" PRIu64 " trace=%.*s\n", ntr, cnt[0], cnt[1], cnt[2], cnt[3], cnt[4], cnt[5],
           (int)(ntr < 160 ? ntr : 160), trace);
}

static int list(const char *p, uint64_t *dst, int max)
{
    int n = 0;
    char *e;
    for (;;) {
        while (*p == ' ') p++;
        if (*p < '0' || *p > '9' || n >= max) break;
        dst[n++] = strtoull(p, &e, 10);
        p = e;
    }
    return n;
}

int main(void)
{
    char line[8192];
    uint64_t a[6];
    reset();
    while (fgets(line, sizeof line, stdin)) {
        char c = line[0];
        if (c == '#' || c == '\n' || c == 0) continue;
        const char *p = line + 1;
        switch (c) {
        case 'R': reset(); break;
        case 'K':
            memset(a, 0, sizeof a);
            list(p, a, 6);
            kind = (unsigned)a[0]; expected = a[1]; total_ms = a[2]; progress_ms = a[3];
            flags = (unsigned)a[4]; m2want = a[5];
            break;
        case 'W': nw = list(p, lw, NV); break;
        case 'M': nm = list(p, lm, NV); break;
        case 'P': np = list(p, lp, 2 * NV); break;
        case 'V': nvv = list(p, lv, NV); break;
        case 'A': na = list(p, la, NV); break;
        case 'T': nt = list(p, lt, NV); break;
        case 'S': list(p, &step, 1); break;
        case 'G': run(); break;
        default: printf("? %c\n", c); break;
        }
    }
    return 0;
}
