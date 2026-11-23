/* SPDX-License-Identifier: Apache-2.0
 * pd0l_dump.c -- REFERENCE-ONLY C dumper for tests/physics0/verify/pd0l_parity.sh. Reads the corpus of
 * commands on stdin, drives the live C PD-0 ladder checker and scorer (src/physics0/ladder/pd0_ladder.c,
 * src/physics0/score/pd0_score.c and the memoriser of src/physics0/controls/pd0_controls.c, as at main
 * commit 3f2c70dc5) over evidence ledgers and scoring sets built by the test bundle builders
 * (tests/physics0/verify/bundle.h, truth.h), and prints what tests/physics0/verify/pd0l_dump.om must
 * print. It generated the goldens in tests/physics0/verify/ladder_golden once and is then removed from the
 * tree (the MANIFEST records its blob and sha256). Commands: see pd0l_parity.sh. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "bundle.h"
#include "pd0_score.h"
#include "pd0_controls.h"
#include "sha256.h"

static long long a[64];
static int na;
static uint8_t hbuf[8192];
static size_t hlen;
static bundle B;
static int have_b;
static pd0_ladder_report R;
static uint8_t law[8192], saved[8192];
static size_t law_n, saved_n;
static uint64_t rs;
static pd0_score_params SP;
static pd0_score_episode eps[32];
static uint32_t n_eps;
static pd0_transition fit[65536];
static uint32_t n_fit;
static truth_world W;
static pd0_rel rel;
static double xs[65536], ys[65536];
static uint8_t hs[8][PD0_HASH];
static pd0_rel cand, nullr;
static int64_t sreset[2]; static pd0_step ssteps[100];

static uint64_t rnd(void) { rs = rs * 6364136223846793005ull + 1442695040888963407ull; return rs >> 11; }
static long long rnds(long long m) { return (long long)(rnd() % (uint64_t)(2 * m + 1)) - m; }
static void hex(const uint8_t *p, size_t n) { for (size_t i = 0; i < n; i++) printf("%02x", p[i]); }
static unsigned long long dbits(double d) { unsigned long long u; memcpy(&u, &d, 8); return u; }

static void report(long ln, int rc)
{
    printf("L%ld rep rc=%d st=%d code=%d tr=%d dem=%d stall=%d nref=%u p=%u f=%u conf=%u hc=%d ch=", ln, rc, R.state, R.code, R.transition,
           R.demoted, R.stall_code, R.n_refutations, R.p, R.f, R.confidence_ppm, R.have_candidate);
    hex(R.candidate_hash, PD0_HASH);
    printf(" eps=%lld root=", (long long)R.eps_micro);
    hex(R.chain_root, PD0_HASH);
    printf(" ne=%llu nr=%llu nrm=%lld vep=%u vbat=%u r=%016llx pp=%016llx\n", (unsigned long long)R.n_entries, (unsigned long long)R.n_records,
           (long long)R.last_nrmse_micro, R.n_void_episodes, R.n_void_batches, dbits(R.last_r), dbits(R.last_p));
    law_n = pd0_ladder_emit_law(&R, &B.P, law, sizeof law);
    printf("L%ld law n=%zu ", ln, law_n); hex(law, law_n); printf("\n");
    static char cl[1024]; uint32_t n = pd0_claim_text(&R, &B.P, cl, sizeof cl);
    printf("L%ld claim n=%u %.*s\n", ln, n, (int)(n < sizeof cl ? n : sizeof cl), cl);
}
static void ledger_line(long ln, int rc)
{
    uint8_t h[32]; sha256_hash(B.buf, B.len, h);
    printf("L%ld ledger rc=%d len=%zu sha=", ln, rc, B.len); hex(h, 32); printf("\n");
}
static void ensure(void) { if (!have_b) { b_init(&B, 1, 1); have_b = 1; } }

static void cmd_build(long ln)
{
    if (have_b) b_free(&B);
    b_init(&B, (int)a[0], (uint64_t)a[1]); have_b = 1;
    bundle_opts o; memset(&o, 0, sizeof o);
    for (int i = 2; i + 1 < na; i += 2) {
        long long v = a[i + 1];
        switch (a[i]) {
        case 0: o.skip_corr = (int)v; break; case 1: o.fake_corr = (int)v; break; case 2: o.no_rival = (int)v; break;
        case 3: o.reuse_schedule = (int)v; break; case 4: o.trial_without_prereg = (int)v; break; case 5: o.wrong_k = (int)v; break;
        case 6: o.rep_before_candidate = (int)v; break; case 7: o.batch_seed_reuse = (int)v; break; case 8: o.all_planner = (int)v; break;
        case 9: o.eps_above_bound = (int)v; break; case 10: o.stop_after_prereg = (int)v; break; case 11: o.stop_after_trials = (int)v; break;
        case 12: o.demote_after_law = (int)v; break; case 13: o.null_world = (int)v; break; case 14: o.null_seed = (uint64_t)v; break;
        case 15: o.end_last = (int)v; break; case 16: o.quiet_trials = (int)v; break; case 17: o.obs_noise = v; break;
        case 18: o.void_rep = (int)v; break; case 19: o.void_rep_four = (int)v; break; case 20: o.void_trial = (int)v; break;
        default: break; }
    }
    int rc = b_build(&B, &o, &R);
    ledger_line(ln, rc);
    report(ln, rc);
}
static void cmd_param(long ln)
{
    pd0_ladder_params *P = &B.P; long long v = a[1];
    switch (a[0]) {
    case 0: P->n_obs = (uint8_t)v; break; case 1: P->n_channels = (uint8_t)v; break; case 2: P->noisy = (uint8_t)v; break;
    case 3: P->chan_min[0] = v; break; case 4: P->chan_max[0] = v; break; case 5: P->reset_min = v; break; case 6: P->reset_max = v; break;
    case 7: P->episode_len = (uint32_t)v; break; case 8: P->dt_micro = v; break; case 9: P->size_bound = (uint32_t)v; break;
    case 10: P->eps_bound_micro = v; break; case 11: P->min_t1_records = (uint32_t)v; break; case 12: P->min_t1_episodes = (uint32_t)v; break;
    case 13: P->min_prereg = (uint32_t)v; break; case 14: P->min_batches = (uint32_t)v; break; case 15: P->min_batch_episodes = (uint32_t)v; break;
    case 16: P->rollout_steps = (uint32_t)v; break; default: break; }
    (void)ln;
}
static void cmd_params(long ln)
{
    pd0_ladder_params *P = &B.P; pd0_ladder_params_default(P, (uint8_t)a[0], (uint8_t)a[1]);
    printf("L%ld params no=%u nc=%u noisy=%u c=", ln, P->n_obs, P->n_channels, P->noisy);
    for (int c = 0; c < PD0_MAX_CHAN; c++) printf("%s%lld:%lld", c ? "," : "", (long long)P->chan_min[c], (long long)P->chan_max[c]);
    printf(" r=%lld:%lld el=%u dt=%lld sb=%u eb=%lld t1=%u,%u pre=%u bat=%u,%u roll=%u\n", (long long)P->reset_min, (long long)P->reset_max,
           P->episode_len, (long long)P->dt_micro, P->size_bound, (long long)P->eps_bound_micro, P->min_t1_records, P->min_t1_episodes,
           P->min_prereg, P->min_batches, P->min_batch_episodes, P->rollout_steps);
}
static void cmd_tamper(long ln)
{
    int k = (int)a[0]; static uint8_t l2[8192]; size_t n = 0; int prc = 0;
    if (k == 10 || k == 11) {
        memcpy(l2, law, law_n); n = law_n;
        if (k == 10 && n) l2[n - 1] ^= 1;
        if (k == 11 && n) n--;
    } else {
        pd0_law *l = calloc(1, sizeof *l); prc = pd0_law_parse(law, law_n, l);
        switch (k) {
        case 0: l->confidence_ppm += 1; break;
        case 1: memcpy(l->claim, "This is always true. ", 21); break;
        case 2: l->claim[0] = 'B'; break;
        case 3: l->n_experiments--; break;
        case 4: l->chain_root[0] ^= 1; break;
        case 5: l->rel.eq[1].coef[0] += 1; break;
        case 6: l->dom.n_observations += 1; break;
        case 7: l->n_exceptions = 1; break;
        case 8: l->state = PDLAW_PROVISIONAL_LAW; break;
        case 12: l->state = PDLAW_HYPOTHESIS; break;
        case 13: l->state = PDLAW_REFUTED; break;
        case 14: l->state = PDLAW_REJECTED; break;
        case 15: l->rel.n_refutations += 1; break;
        default: break; }
        n = prc ? 0 : pd0_law_write(l, l2, sizeof l2); free(l);
    }
    printf("L%ld tamper %d prc=%d n=%zu v=%d\n", ln, k, prc, n, pd0_ladder_verify_law(&R, &B.P, l2, n));
}
static void cmd_fab(long ln)
{
    pd0_law *l = calloc(1, sizeof *l); l->state = PDLAW_PROVISIONAL_LAW; l->rel.n_vars = 2; l->rel.n_channels = 1; l->dom.n_obs = 2; l->dom.n_channels = 1;
    static uint8_t l2[8192]; size_t n = pd0_law_write(l, l2, sizeof l2); free(l);
    printf("L%ld fab n=%zu v=%d\n", ln, n, pd0_ladder_verify_law(&R, &B.P, l2, n));
}
static void cmd_stats(long ln)
{
    uint32_t n = (uint32_t)a[0]; rs = (uint64_t)a[1]; int mode = (int)a[2];
    for (uint32_t i = 0; i < n; i++) {
        long long x = rnds(2000000), y = rnds(2000000);
        if (mode == 1) y = 3 * x + rnds(1000);
        if (mode == 2) x = 5;
        if (mode == 3) y = -7;
        if (mode == 4) y = -x;
        xs[i] = (double)x; ys[i] = (double)y; }
    double r = pd0_pearson(xs, ys, n), p = n ? pd0_perm_p(xs, ys, n, (uint32_t)a[3], (uint64_t)a[4]) : 0;
    printf("L%ld stats r=%016llx p=%016llx\n", ln, dbits(r), dbits(p));
}
static void cmd_nrmse(long ln)
{
    uint32_t n = (uint32_t)a[0]; uint8_t no = (uint8_t)a[1]; rs = (uint64_t)a[2]; int sdm = (int)a[3];
    int64_t pred[160], obs[160], sd[8];
    for (uint32_t i = 0; i < n * no; i++) { obs[i] = a[5] ? 7 : rnds(3000000); pred[i] = obs[i] + rnds(a[4]); }
    for (int j = 0; j < 8; j++) sd[j] = sdm == 0 ? 0 : sdm == 1 ? 1 + (int64_t)(rnd() % 2000000) : sdm == 3 ? 1 : (j & 1) ? 0 : 500000;
    printf("L%ld nrmse a=%lld b=%lld\n", ln, (long long)pd0_nrmse_micro(pred, obs, n, no), (long long)pd0_nrmse_pooled_micro(pred, obs, n, no, sd));
}
static void cmd_episode(long ln)
{
    ensure(); int64_t reset[2]; pd0_step steps[100]; uint32_t n = (uint32_t)a[0];
    b_random_schedule(&B, reset, steps, n); uint32_t ep = b_episode(&B, reset, steps, n, &B.w);
    printf("L%ld ep %u len=%zu\n", ln, ep, B.len);
}
static void cmd_append(long ln)
{
    ensure(); B.len = pd0_ledg_append(B.buf, B.len, LCAP, (uint8_t)a[0], hbuf, (uint32_t)hlen, B.last);
    printf("L%ld app len=%zu\n", ln, B.len);
}
static void score_show(long ln, int rc, const pd0_score_result *o)
{
    printf("L%ld score rc=%d code=%d mask=%x in=%lld ex=%lld one=%lld ref=%lld size=%u bits=%u\n", ln, rc, o->code, o->fail_mask,
           (long long)o->inbox_nrmse, (long long)o->extrap_nrmse, (long long)o->onestep_nrmse, (long long)o->ref_nrmse, o->size, o->bits);
}
static void cmd_score_set(long ln)
{
    truth_init(&W, (int)a[0], (uint64_t)a[1]); truth_score_params(&W, &SP);
    n_eps = (uint32_t)(a[3] + a[4]); truth_score_episodes(&W, (uint64_t)a[2], (uint32_t)a[3], (uint32_t)a[4], eps);
    n_fit = truth_fit_transitions(&W, (uint64_t)a[5], (uint32_t)a[6], (uint32_t)a[7], fit, (uint32_t)a[8]);
    printf("L%ld set neps=%u nfit=%u sb=%u nt=%u\n", ln, n_eps, n_fit, SP.size_bound, SP.n_true_terms);
}
static void cmd_score(long ln)
{
    pd0_score_result o; int rc; int k = (int)a[0];
    truth_oracle_rel(&W, &rel);
    if (k == 1) { uint8_t ex[16] = { 1, 0, 0 }; pd0_mut_scale_coef(&rel, 1, ex, a[1], a[2]); }
    if (k == 2) pd0_mut_pad(&rel, (uint32_t)a[1], a[2]);
    if (k == 3) { pd0_memoriser m = { fit, n_fit, SP.n_obs }; pd0_rel e; memset(&e, 0, sizeof e); e.n_vars = 2; e.n_channels = 1;
        rc = pd0_score(&SP, &e, pd0_memoriser_stored_numbers(&m), pd0_memoriser_rollout, pd0_memoriser_predict, &m, eps, n_eps, fit, n_fit, &o);
        score_show(ln, rc, &o); return; }
    if (k == 4) { pd0_eq *q = &rel.eq[1]; q->coef[q->n_terms] = 1; memset(q->expo[q->n_terms], 0, sizeof q->expo[0]); q->expo[q->n_terms][0] = 4; q->n_terms++; rel.description_bits = pd0_rel_bits(&rel); }
    if (k == 5) rel.description_bits += 1;
    if (k == 12) rel.eq[1].coef[0] = 0;
    if (k == 6) { int frc = pd0_reference_fit(SP.n_obs, SP.n_channels, (uint32_t)a[1], fit, n_fit, &rel); printf("L%ld fit rc=%d\n", ln, frc); if (frc) return; }
    if (k == 7) { truth_world w1 = W; w1.level = 1; w1.n_hidden = 0; truth_oracle_rel(&w1, &rel); }
    if (k == 8) { memset(&rel, 0, sizeof rel); rel.n_vars = 3; rel.n_channels = 1; }
    if (k == 9) { rel.n_channels = 2; }
    if (k == 10) { rel.n_vars = (uint8_t)(rel.n_vars + 1); rel.n_latent = (uint8_t)(rel.n_latent + 1); }
    rc = pd0_score(&SP, &rel, (uint32_t)(k == 11 ? a[1] : 0), pd0_rel_rollout_fn, pd0_rel_predict_fn, &rel, eps, n_eps, fit, n_fit, &o);
    score_show(ln, rc, &o);
}
static void cmd_sparam(long ln)
{
    long long v = a[1];
    switch (a[0]) {
    case 0: SP.inbox_bound = v; break; case 1: SP.extrap_bound = v; break; case 2: SP.onestep_bound = v; break; case 3: SP.score_constants = (int)v; break;
    case 4: SP.const_tol_ppm = v; break; case 5: SP.require_latent = (int)v; break; case 6: SP.latent_ref_factor = v; break; case 7: SP.size_bound = (uint32_t)v; break;
    case 8: SP.n_true_terms = (uint32_t)v; break; case 9: SP.true_terms[a[2]].coef = v; break; case 10: SP.true_terms[a[2]].expo[0] = (uint8_t)v; break;
    case 11: n_fit = (uint32_t)v; break; case 12: eps[a[2]].in_box = (uint8_t)v; break; case 13: n_eps = (uint32_t)v; break;
    default: break; }
    (void)ln;
}
static void cmd_reffit(long ln)
{
    pd0_rel r; int rc = pd0_reference_fit((uint8_t)a[1], (uint8_t)a[2], (uint32_t)a[0], fit, n_fit, &r);
    static uint8_t o[8192]; size_t n = rc ? 0 : pd0_rel_write(&r, o, sizeof o);
    printf("L%ld reffit rc=%d n=%zu ", ln, rc, n); hex(o, n); printf("\n");
}

static void cmd_corr(long ln)
{
    ensure(); int va = (int)a[0], vb = (int)a[1]; uint32_t nsh = (uint32_t)a[2]; uint64_t seed = (uint64_t)a[3]; uint32_t npairs = (uint32_t)a[4]; int fake = (int)a[5]; uint32_t epmax = (uint32_t)a[6]; uint32_t n = 0;
    for (uint32_t i = 0; fake != 3 && i < B.nrec; i++) { const pd0_rec *r = &B.recs[i]; if (r->kind != PD0_KIND_STEP || (r->status != PD0_ST_OK && r->status != PD0_ST_EPISODE_END) || r->episode >= epmax) continue;
        xs[n] = (double)r->before[va]; ys[n] = (double)(r->after[vb] - r->before[vb]); n++; }
    pd0_corr c; memset(&c, 0, sizeof c); c.var_a = (uint8_t)va; c.var_b = (uint8_t)vb; c.n = n; c.n_pairs = npairs; c.n_shuffles = nsh; c.shuffle_seed = seed;
    if (fake != 3) { double r = pd0_pearson(xs, ys, n), p = pd0_perm_p(xs, ys, n, nsh, seed) * (double)npairs; c.r_micro = (int64_t)(r * 1e6); c.p_micro = (int64_t)(p * 1e6); }
    if (fake == 1) { c.r_micro = 900000; c.p_micro = 100; }
    if (fake == 2) c.n = n + 1;
    if (fake == 4) c.r_micro += 1500;
    if (fake == 5) c.p_micro = 15000;
    uint8_t pl[64]; B.len = pd0_ledg_append(B.buf, B.len, LCAP, LEDG_CORR, pl, (uint32_t)pd0_corr_write(&c, pl), B.last);
    printf("L%ld corr n=%u r=%lld p=%lld len=%zu\n", ln, n, (long long)c.r_micro, (long long)c.p_micro, B.len);
}
static void cmd_rel(long ln)
{
    ensure(); int mode = (int)a[1]; pd0_rel *r = mode == 2 ? &nullr : &cand;
    if (mode == 2) { memset(r, 0, sizeof *r); r->n_vars = 2; r->n_channels = 1; }
    else { truth_oracle_rel(&B.w, r); if (mode == 3) { uint8_t ex[16] = { 1, 0, 0 }; pd0_mut_scale_coef(r, 1, ex, a[2], a[3]); } if (mode == 1) { pd0_eq *q = &r->eq[1]; q->coef[q->n_terms] = 1; memset(q->expo[q->n_terms], 0, sizeof q->expo[0]); q->expo[q->n_terms][0] = 4; q->n_terms++; r->description_bits = pd0_rel_bits(r); } }
    static uint8_t pl[8192]; pl[0] = (uint8_t)a[0]; size_t n = pd0_rel_write(r, pl + 1, sizeof pl - 1); B.len = pd0_ledg_append(B.buf, B.len, LCAP, LEDG_RELATION, pl, (uint32_t)n + 1, B.last);
    printf("L%ld rel len=%zu\n", ln, B.len);
}
static void cmd_fals(long ln)
{
    ensure(); pd0_falsifier f; memset(&f, 0, sizeof f); f.n_rivals = (uint8_t)a[0]; f.eps_micro = a[1]; f.min_trials = (uint32_t)a[2];
    if (a[3] < 8) memcpy(f.candidate, hs[a[3]], PD0_HASH);
    for (int i = 0; i < f.n_rivals && i < 8; i++) if (a[4 + i] < 8) memcpy(f.rival[i], hs[a[4 + i]], PD0_HASH);
    uint8_t pl[512]; B.len = pd0_ledg_append(B.buf, B.len, LCAP, LEDG_FALSIFIER, pl, (uint32_t)pd0_fals_write(&f, pl), B.last);
    printf("L%ld fals len=%zu\n", ln, B.len);
}
static void cmd_prereg(long ln)
{
    ensure(); pd0_exp *x = calloc(1, sizeof *x); static uint8_t xb[16384];
    x->n_obs = 2; x->n_hyp = (uint8_t)a[0]; x->n_steps = 20; b_random_schedule(&B, sreset, ssteps, 20);
    memcpy(x->reset, sreset, sizeof sreset); for (int s = 0; s < 20; s++) x->steps[s] = ssteps[s];
    int64_t tmp[40]; pd0_rel_rollout_fn(&cand, x->reset, x->steps, 20, tmp); for (int s = 0; s < 20; s++) for (int j = 0; j < 2; j++) x->expected[0][s][j] = tmp[s * 2 + j];
    pd0_rel_rollout_fn(&nullr, x->reset, x->steps, 20, tmp); for (int s = 0; s < 20; s++) for (int j = 0; j < 2; j++) x->expected[1][s][j] = tmp[s * 2 + j];
    x->divergence_micro = 5000000;
    size_t xn = pd0_exp_write(x, xb, sizeof xb); free(x);
    B.len = pd0_ledg_append(B.buf, B.len, LCAP, LEDG_PREREG, xb, (uint32_t)xn, B.last);
    printf("L%ld prereg n=%zu len=%zu\n", ln, xn, B.len);
}

static void parse(const char *s)
{
    na = 0; const char *p = s + 1;
    while (*p && na < 64) { while (*p == ' ') p++; if (!*p) break; a[na++] = strtoll(p, (char **)&p, 10); while (*p && *p != ' ') p++; }
}
static int hv(int c) { return c >= 'a' ? c - 'a' + 10 : c - '0'; }

int main(void)
{
    static char line[65536]; long ln = 0; ensure();
    while (fgets(line, sizeof line, stdin)) {
        ln++; size_t L = strlen(line); while (L && (line[L - 1] == '\n' || line[L - 1] == '\r')) line[--L] = 0;
        if (!L || line[0] == '#') continue;
        char c = line[0];
        if (c == 'H') { const char *p = line + 1; while (*p == ' ') p++; hlen = 0; while (p[0] && p[1] && hlen < sizeof hbuf) { hbuf[hlen++] = (uint8_t)(hv(p[0]) * 16 + hv(p[1])); p += 2; } continue; }
        parse(line);
        switch (c) {
        case 'b': cmd_build(ln); break;
        case 'i': if (have_b) b_free(&B); b_init(&B, (int)a[0], (uint64_t)a[1]); have_b = 1; break;
        case 'c': ensure(); { int rc = pd0_ladder_check(B.buf, B.len, &B.P, &R); report(ln, rc); } break;
        case 'x': ensure(); if ((size_t)a[0] < B.len) B.buf[a[0]] = (uint8_t)a[1]; break;
        case 'C': cmd_corr(ln); break;
        case 'R': cmd_rel(ln); break;
        case 'K': ensure(); memcpy(hs[a[0] & 7], B.last, PD0_HASH); break;
        case 'A': cmd_fals(ln); break;
        case 'P': cmd_prereg(ln); break;
        case 'T': ensure(); { uint32_t ep = b_episode(&B, sreset, ssteps, 20, &B.w); printf("L%ld trial %u len=%zu\n", ln, ep, B.len); } break;
        case 'W': ensure(); B.w.k = B.w.k * a[0] / a[1]; break;
        case 'X': ensure(); if ((size_t)a[0] < B.len) B.buf[a[0]] ^= 1; break;
        case 'G': ensure(); b_tag(&B, B.episode, (uint8_t)a[0], (uint32_t)a[1], (uint8_t)a[2]); break;
        case 'z': ensure(); if ((size_t)a[0] <= B.len) B.len = (size_t)a[0]; break;
        case 'Q': ensure(); cmd_param(ln); break;
        case 'd': ensure(); cmd_params(ln); break;
        case 'L': memcpy(saved, law, law_n); saved_n = law_n; break;
        case 'v': ensure(); printf("L%ld verify v=%d\n", ln, pd0_ladder_verify_law(&R, &B.P, saved, saved_n)); break;
        case 't': ensure(); cmd_tamper(ln); break;
        case 'f': ensure(); cmd_fab(ln); break;
        case 's': printf("L%ld name %s\n", ln, pd0_ladder_state_name((int)a[0])); break;
        case 'k': printf("L%ld conf %u\n", ln, pd0_confidence_ppm((uint32_t)a[0], (uint32_t)a[1])); break;
        case 'r': cmd_stats(ln); break;
        case 'q': cmd_nrmse(ln); break;
        case 'e': cmd_episode(ln); break;
        case 'g': ensure(); b_tag(&B, (uint32_t)a[0], (uint8_t)a[1], (uint32_t)a[2], (uint8_t)a[3]); break;
        case 'B': ensure(); { pd0_batch bb = { (uint32_t)a[0], (uint64_t)a[1], (uint32_t)a[2] }; uint8_t pl[64]; B.len = pd0_ledg_append(B.buf, B.len, LCAP, LEDG_BATCH, pl, (uint32_t)pd0_batch_write(&bb, pl), B.last); } break;
        case 'O': ensure(); B.oob_at = (uint32_t)a[0]; break;
        case 'a': cmd_append(ln); break;
        case 'S': cmd_score_set(ln); break;
        case 'o': cmd_score(ln); break;
        case 'u': cmd_sparam(ln); break;
        case 'F': cmd_reffit(ln); break;
        default: printf("L%ld ?\n", ln); break; }
    }
    return 0;
}
