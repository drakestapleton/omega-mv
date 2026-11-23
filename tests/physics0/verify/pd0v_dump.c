/* SPDX-License-Identifier: Apache-2.0
 * pd0v_dump.c -- REFERENCE-ONLY C dumper for tests/physics0/verify/pd0v_parity.sh. Reads the corpus of
 * commands on stdin, drives the live C PD-0 verifier library (src/physics0/ladder/pd0_fmt.c, pd0_codes.c,
 * src/physics0/controls/pd0_controls.c, pd0_receipt.c, as at main commit 3f2c70dc5) and prints what
 * tests/physics0/verify/pd0v_dump.om must print. It generated the goldens in
 * tests/physics0/verify/parity_golden once and is then removed from the tree (the MANIFEST records its
 * blob and sha256). Commands: see pd0v_parity.sh. argv[1]: the receipt directory. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "pd0_fmt.h"
#include "pd0_codes.h"
#include "pd0_controls.h"
#include "pd0_receipt.h"

static long long a[48];
static int na;
static char word[2048];
static uint8_t buf[8192];
static size_t blen;
static uint8_t led[16384];
static size_t llen;
static uint8_t lhash[PD0_HASH];
static pd0_rel rel;
static int last_eq = -1, last_term = -1;
static pd0_law law;
static pd0_rec recs[4096];
static uint32_t nrec;
static uint64_t rs;
static const char *rdir;

static uint64_t rnd(void) { rs = rs * 6364136223846793005ull + 1442695040888963407ull; return rs >> 11; }
static void hex(const uint8_t *p, size_t n) { for (size_t i = 0; i < n; i++) printf("%02x", p[i]); }
static void hexbuf(long ln, char c, size_t n) { printf("L%ld %c n=%zu ", ln, c, n); hex(buf, n); printf("\n"); }

static void rel_show(long ln, const pd0_rel *r) {
    static uint8_t o[8192];
    size_t n = pd0_rel_write(r, o, sizeof o);
    printf("L%ld rel nv=%u nl=%u nc=%u ne=%u bits=%u nref=%u size=%u cbits=%u deg=%d n=%zu ", ln, r->n_vars, r->n_latent, r->n_channels,
           r->n_equations, r->description_bits, r->n_refutations, pd0_rel_size(r), pd0_rel_bits(r), pd0_rel_max_degree(r), n);
    hex(o, n);
    printf("\n");
}

static void rec_show(long ln, const pd0_rec *r) {
    printf("L%ld rec no=%u st=%u k=%u ch=%u seq=%llu ep=%u s=%u t=%lld rq=%lld ap=%lld b=", ln, r->n_obs, r->status, r->kind, r->channel,
           (unsigned long long)r->seq, r->episode, r->step_in_episode, (long long)r->time_micro, (long long)r->requested, (long long)r->applied);
    for (int i = 0; i < r->n_obs && i < PD0_MAX_OBS; i++) printf("%s%lld", i ? "," : "", (long long)r->before[i]);
    printf(" a=");
    for (int i = 0; i < r->n_obs && i < PD0_MAX_OBS; i++) printf("%s%lld", i ? "," : "", (long long)r->after[i]);
    printf(" p=");
    hex(r->prev_hash, PD0_HASH);
    printf(" h=");
    hex(r->record_hash, PD0_HASH);
    printf("\n");
}

static void exp_show(long ln, const pd0_exp *e) {
    printf("L%ld exp no=%u nh=%u ns=%u div=%lld r=", ln, e->n_obs, e->n_hyp, e->n_steps, (long long)e->divergence_micro);
    for (int i = 0; i < e->n_obs; i++) printf("%s%lld", i ? "," : "", (long long)e->reset[i]);
    printf(" s=");
    for (int s = 0; s < e->n_steps; s++) printf("%s%u:%lld", s ? "," : "", e->steps[s].channel, (long long)e->steps[s].value);
    printf(" x=");
    int first = 1;
    for (int k = 0; k < e->n_hyp; k++) for (int s = 0; s < e->n_steps; s++) for (int i = 0; i < e->n_obs; i++) {
        printf("%s%lld", first ? "" : ",", (long long)e->expected[k][s][i]); first = 0; }
    printf(" h=");
    hex(e->schedule_hash, PD0_HASH);
    printf("\n");
}

static void law_show(long ln, const pd0_law *l) {
    printf("L%ld law st=%u conf=%u ne=%u nx=%u cl=%u id=", ln, l->state, l->confidence_ppm, l->n_exceptions, l->n_experiments, l->claim_len);
    hex(l->law_id, PD0_HASH);
    const pd0_domain *d = &l->dom;
    printf(" dom=%u,%u", d->n_obs, d->n_channels);
    for (int i = 0; i < d->n_obs; i++) printf(",%lld:%lld", (long long)d->var_min[i], (long long)d->var_max[i]);
    for (int i = 0; i < d->n_channels; i++) printf(",%lld:%lld", (long long)d->chan_min[i], (long long)d->chan_max[i]);
    printf(",%lld,%llu,%u,%lld,%lld,%u,%lld", (long long)d->dt_micro, (unsigned long long)d->n_observations, d->n_episodes,
           (long long)d->reset_min, (long long)d->reset_max, d->episode_len, (long long)d->latent_reset);
    printf(" exc=");
    for (uint32_t k = 0; k < l->n_exceptions; k++) { printf("%s%llu:", k ? "," : "", (unsigned long long)l->exc[k].record_seq); hex(l->exc[k].record_hash, 4);
        printf(":%lld:%lld:%lld", (long long)l->exc[k].predicted, (long long)l->exc[k].observed, (long long)l->exc[k].error_micro); }
    printf(" xp=");
    for (uint32_t k = 0; k < l->n_experiments; k++) { const pd0_experiment *x = &l->exp[k]; printf("%s", k ? "," : ""); hex(x->experiment_id, 4);
        printf(":%u:", x->kind); hex(x->prereg_hash, 4); printf(":"); hex(x->outcome_hash, 4);
        printf(":%u:%llu:%llu", x->result, (unsigned long long)x->first_seq, (unsigned long long)x->last_seq); }
    printf(" root=");
    hex(l->chain_root, PD0_HASH);
    printf(" claim=");
    hex(l->claim, l->claim_len);
    printf("\n");
    rel_show(ln, &l->rel);
}

/* the law fields from the generator stream (rel = the current relation) */
static void law_fill(void) {
    memset(&law, 0, sizeof law);
    law.state = (uint8_t)a[1]; law.confidence_ppm = (uint32_t)a[2];
    law.n_exceptions = (uint32_t)a[3]; law.n_experiments = (uint32_t)a[4]; law.claim_len = (uint32_t)a[5];
    rs = (uint64_t)a[0];
    memcpy(&law.rel, &rel, sizeof rel);
    pd0_domain *d = &law.dom;
    d->n_obs = (uint8_t)a[6]; d->n_channels = (uint8_t)a[7];
    for (int i = 0; i < PD0_MAX_OBS; i++) { d->var_min[i] = -(int64_t)(rnd() % 5000000); d->var_max[i] = (int64_t)(rnd() % 5000000); }
    for (int i = 0; i < PD0_MAX_CHAN; i++) { d->chan_min[i] = -(int64_t)(rnd() % 3000000); d->chan_max[i] = (int64_t)(rnd() % 3000000); }
    d->dt_micro = (int64_t)(rnd() % 100000); d->n_observations = rnd(); d->n_episodes = (uint32_t)rnd();
    d->reset_min = -(int64_t)(rnd() % 2000000); d->reset_max = (int64_t)(rnd() % 2000000); d->episode_len = (uint32_t)rnd(); d->latent_reset = (int64_t)rnd() - (int64_t)(1ull << 52);
    for (uint32_t k = 0; k < PD0_MAX_EXC; k++) { pd0_exception *x = &law.exc[k]; x->record_seq = rnd();
        for (int j = 0; j < PD0_HASH; j++) x->record_hash[j] = (uint8_t)rnd();
        x->predicted = (int64_t)rnd() - (int64_t)(1ull << 52); x->observed = (int64_t)rnd(); x->error_micro = (int64_t)(rnd() % 1000000); }
    for (uint32_t k = 0; k < PD0_MAX_EXP; k++) { pd0_experiment *x = &law.exp[k];
        for (int j = 0; j < PD0_HASH; j++) { x->experiment_id[j] = (uint8_t)rnd(); x->prereg_hash[j] = (uint8_t)rnd(); x->outcome_hash[j] = (uint8_t)rnd(); }
        x->kind = (uint8_t)(rnd() & 1); x->result = (uint8_t)(rnd() & 1); x->first_seq = rnd(); x->last_seq = rnd(); }
    for (int j = 0; j < PD0_HASH; j++) law.chain_root[j] = (uint8_t)rnd();
    for (uint32_t j = 0; j < PD0_MAX_CLAIM; j++) law.claim[j] = (uint8_t)(32 + rnd() % 95);
}

static void parse_args(char *p) {
    na = 0; memset(a, 0, sizeof a); word[0] = 0;
    while (*p && na < 48) {
        while (*p == ' ') p++;
        if (!*p) break;
        if (*p == '"') { p++; size_t k = 0; while (*p && *p != '"' && k + 1 < sizeof word) word[k++] = *p++; word[k] = 0; if (*p) p++; continue; }
        int neg = 0;
        if (*p == '-') { neg = 1; p++; }
        unsigned long long v = 0;
        while (*p >= '0' && *p <= '9') { v = v * 10 + (unsigned)(*p - '0'); p++; }
        a[na++] = neg ? (long long)(0ull - v) : (long long)v;
        while (*p && *p != ' ') p++;
    }
}

static int hexval(int c) { return c >= 'a' ? c - 'a' + 10 : c - '0'; }

static void line(long ln, char *s) {
    char c = s[0], c2 = s[1];
    if (c == 'H') {   /* H <hex>: the buffer */
        char *p = s + 1; while (*p == ' ') p++;
        blen = 0; while (p[0] && p[1] && blen < sizeof buf) { buf[blen++] = (uint8_t)(hexval(p[0]) * 16 + hexval(p[1])); p += 2; }
        return;
    }
    parse_args(s + 2);
    switch (c) {
    case 'Y': if ((size_t)a[0] < sizeof buf) buf[a[0]] = (uint8_t)a[1]; break;
    case 'Z': if ((size_t)a[0] <= sizeof buf) { if ((size_t)a[0] > blen) memset(buf + blen, 0, (size_t)a[0] - blen); blen = (size_t)a[0]; } break;
    case 'B': hexbuf(ln, 'B', blen); break;
    case 'R': memset(&rel, 0, sizeof rel); rel.n_vars = (uint8_t)a[0]; rel.n_latent = (uint8_t)a[1]; rel.n_channels = (uint8_t)a[2];
              rel.description_bits = (uint32_t)a[3]; rel.n_refutations = (uint16_t)a[4]; last_eq = -1; break;
    case 'Q': { int e = rel.n_equations++; rel.eq[e].target = (uint8_t)a[0]; rel.eq[e].n_terms = 0; last_eq = e; break; }
    case 'T': { pd0_eq *q = &rel.eq[last_eq]; int t = q->n_terms++; q->coef[t] = a[0];
                memset(q->expo[t], 0, sizeof q->expo[t]); q->expo[t][a[1]] = (uint8_t)a[2]; last_term = t; break; }
    case 'X': rel.eq[last_eq].expo[last_term][a[0]] = (uint8_t)a[1]; break;
    case 'G': { /* G n tiny: n terms of coefficient tiny on the last equation, exponent 1 at input (t mod ne) */
                pd0_eq *q = &rel.eq[last_eq]; unsigned ne = rel.n_vars + rel.n_channels;
                for (long long k = 0; k < a[0]; k++) { int t = q->n_terms++; q->coef[t] = a[1] + k; memset(q->expo[t], 0, sizeof q->expo[t]); q->expo[t][(unsigned)k % ne] = 1; last_term = t; }
                break; }
    case 'r': if (c2 == 'w') { blen = pd0_rel_write(&rel, buf, (size_t)a[0]); hexbuf(ln, 'w', blen); }
              else if (c2 == 's') rel_show(ln, &rel);
              else if (c2 == 't') { int64_t st[PD0_MAX_VARS] = { 0 }, nx[PD0_MAX_VARS];
                  for (int i = 0; i < rel.n_vars && i + 2 < na; i++) st[i] = a[i + 2];
                  pd0_rel_step(&rel, st, (uint8_t)a[0], a[1], nx);
                  printf("L%ld step", ln); for (int i = 0; i < rel.n_vars; i++) printf(" %lld", (long long)nx[i]); printf("\n"); }
              else if (c2 == 'p') { pd0_rel r; size_t used = 0; int rc = pd0_rel_parse(buf, blen, &r, &used);
                  printf("L%ld relp rc=%d used=%zu\n", ln, rc, rc == 0 ? used : 0); if (rc == 0) rel_show(ln, &r); }
              break;
    case 'm': printf("L%ld mul %lld\n", ln, (long long)pd0_mul(a[0], a[1])); break;
    case 'u': { uint8_t o[8]; pd0_put_u16(o, (uint16_t)a[0]); printf("L%ld u16 ", ln); hex(o, 2); printf(" %u", pd0_get_u16(o));
                pd0_put_u32(o, (uint32_t)a[0]); printf(" u32 "); hex(o, 4); printf(" %u", pd0_get_u32(o));
                pd0_put_u64(o, (uint64_t)a[0]); printf(" u64 "); hex(o, 8); printf(" %llu\n", (unsigned long long)pd0_get_u64(o)); break; }
    case 'w': { /* record write: w cap nobs st kind ch seq ep step t rq ap prevbyte b.. a.. */
                pd0_rec r; memset(&r, 0, sizeof r); r.n_obs = (uint8_t)a[1]; r.status = (uint8_t)a[2]; r.kind = (uint8_t)a[3]; r.channel = (uint8_t)a[4];
                r.seq = (uint64_t)a[5]; r.episode = (uint32_t)a[6]; r.step_in_episode = (uint32_t)a[7]; r.time_micro = a[8]; r.requested = a[9]; r.applied = a[10];
                memset(r.prev_hash, (int)(a[11] & 255), PD0_HASH);
                for (int i = 0; i < PD0_MAX_OBS && 12 + i < na; i++) r.before[i] = a[12 + i];
                for (int i = 0; i < PD0_MAX_OBS && 12 + r.n_obs + i < na; i++) r.after[i] = a[12 + r.n_obs + i];
                printf("L%ld recsize %zu\n", ln, pd0_rec_size(r.n_obs));
                blen = pd0_rec_write(&r, buf, (size_t)a[0]); hexbuf(ln, 'w', blen); break; }
    case 'p': { size_t used = 0; int rc;
        if (c2 == 'r') { pd0_rec r; rc = pd0_rec_parse(buf, blen, &r, &used); printf("L%ld recp rc=%d used=%zu\n", ln, rc, rc == 0 ? used : 0); if (rc == 0) rec_show(ln, &r); }
        else if (c2 == 'e') { pd0_exp e; rc = pd0_exp_parse(buf, blen, &e, &used); printf("L%ld expp rc=%d used=%zu\n", ln, rc, rc == 0 ? used : 0); if (rc == 0) exp_show(ln, &e); }
        else if (c2 == 'w') { static pd0_law l; rc = pd0_law_parse(buf, blen, &l); printf("L%ld lawp rc=%d\n", ln, rc); if (rc == 0) law_show(ln, &l); }
        else if (c2 == 't') { pd0_tag t; rc = pd0_tag_parse(buf, blen, &t); printf("L%ld tagp rc=%d", ln, rc); if (rc == 0) printf(" %u %u %u %u", t.episode, t.tag, t.batch_id, t.origin); printf("\n"); }
        else if (c2 == 'c') { pd0_corr k; rc = pd0_corr_parse(buf, blen, &k); printf("L%ld corrp rc=%d", ln, rc);
            if (rc == 0) printf(" %u %u %u %lld %lld %u %u %llu", k.var_a, k.var_b, k.n, (long long)k.r_micro, (long long)k.p_micro, k.n_pairs, k.n_shuffles, (unsigned long long)k.shuffle_seed); printf("\n"); }
        else if (c2 == 'f') { pd0_falsifier f; rc = pd0_fals_parse(buf, blen, &f); printf("L%ld falsp rc=%d", ln, rc);
            if (rc == 0) { printf(" "); hex(f.candidate, PD0_HASH); printf(" %u", f.n_rivals); for (int k = 0; k < f.n_rivals; k++) { printf(" "); hex(f.rival[k], PD0_HASH); }
                printf(" %lld %u", (long long)f.eps_micro, f.min_trials); } printf("\n"); }
        else if (c2 == 'b') { pd0_batch b; rc = pd0_batch_parse(buf, blen, &b); printf("L%ld batchp rc=%d", ln, rc); if (rc == 0) printf(" %u %llu %u", b.batch_id, (unsigned long long)b.stream_seed, b.n_episodes); printf("\n"); }
        else if (c2 == 'g') { /* walk the buffer as a ledger from offset a[0] with expected prev byte a[1] */
            size_t off = (size_t)a[0]; uint8_t prev[PD0_HASH]; memset(prev, (int)(a[1] & 255), PD0_HASH);
            for (int k = 0; k < 64; k++) { pd0_entry e; rc = pd0_ledg_next(buf, blen, &off, prev, &e);
                printf("L%ld ledgn rc=%d", ln, rc);
                if (rc == 0) { printf(" k=%u pl=%u off=%zu h=", e.kind, e.payload_len, off); hex(e.entry_hash, PD0_HASH); memcpy(prev, e.entry_hash, PD0_HASH); }
                printf("\n");
                if (rc != 0 || off >= blen) break; } }
        break; }
    case 'e': { /* exp write: e cap nobs nhyp nsteps seed */
        static pd0_exp e; memset(&e, 0, sizeof e); e.n_obs = (uint8_t)a[1]; e.n_hyp = (uint8_t)a[2]; e.n_steps = (uint8_t)a[3]; rs = (uint64_t)a[4];
        for (int i = 0; i < PD0_MAX_OBS; i++) e.reset[i] = (int64_t)(rnd() % 4000000) - 2000000;
        for (int s = 0; s < PD0_MAX_STEPS; s++) { e.steps[s].channel = (uint8_t)(rnd() % 5); e.steps[s].value = (int64_t)rnd() - (int64_t)(1ull << 52); }
        for (int k = 0; k < PD0_MAX_HYP; k++) for (int s = 0; s < PD0_MAX_STEPS; s++) for (int i = 0; i < PD0_MAX_OBS; i++) e.expected[k][s][i] = (int64_t)rnd() - (int64_t)(1ull << 52);
        e.divergence_micro = (int64_t)rnd();
        blen = pd0_exp_write(&e, buf, (size_t)a[0]); hexbuf(ln, 'e', blen); printf("L%ld exph ", ln); hex(e.schedule_hash, PD0_HASH); printf("\n");
        if (e.n_obs <= PD0_MAX_OBS && e.n_steps <= PD0_MAX_STEPS) { uint8_t h[PD0_HASH]; pd0_schedule_hash(e.n_obs, e.reset, e.n_steps, e.steps, h); printf("L%ld schh ", ln); hex(h, PD0_HASH); printf("\n"); }
        break; }
    case 'l': { /* law write: l seed state conf nexc nexp claimlen dom_nobs dom_nch cap */
        law_fill(); size_t n = pd0_law_write(&law, buf, (size_t)a[8]); blen = n; hexbuf(ln, 'l', n);
        printf("L%ld lawid ", ln); hex(law.law_id, PD0_HASH); printf("\n");
        uint8_t d[512]; size_t dn = pd0_dom_write(&law.dom, d); printf("L%ld dom n=%zu ", ln, dn); hex(d, dn); printf("\n");
        break; }
    case 't': { pd0_tag t = { (uint32_t)a[0], (uint8_t)a[1], (uint32_t)a[2], (uint8_t)a[3] }; blen = pd0_tag_write(&t, buf); hexbuf(ln, 't', blen); break; }
    case 'c': { pd0_corr k = { (uint8_t)a[0], (uint8_t)a[1], (uint32_t)a[2], a[3], a[4], (uint32_t)a[5], (uint32_t)a[6], (uint64_t)a[7] }; blen = pd0_corr_write(&k, buf); hexbuf(ln, 'c', blen); break; }
    case 'f': { pd0_falsifier f; memset(&f, 0, sizeof f); rs = (uint64_t)a[0]; f.n_rivals = (uint8_t)a[1]; f.eps_micro = a[2]; f.min_trials = (uint32_t)a[3];
                for (int j = 0; j < PD0_HASH; j++) f.candidate[j] = (uint8_t)rnd();
                for (int k = 0; k < PD0_MAX_HYP; k++) for (int j = 0; j < PD0_HASH; j++) f.rival[k][j] = (uint8_t)rnd();
                blen = pd0_fals_write(&f, buf); hexbuf(ln, 'f', blen); break; }
    case 'b': { pd0_batch b = { (uint32_t)a[0], (uint64_t)a[1], (uint32_t)a[2] }; blen = pd0_batch_write(&b, buf); hexbuf(ln, 'b', blen); break; }
    case 'g': if (c2 == 'r') { llen = 0; memset(lhash, (int)(a[0] & 255), PD0_HASH); }
              else if (c2 == 'a') { size_t n = pd0_ledg_append(led, llen, (size_t)a[1], (uint8_t)a[0], buf, (uint32_t)blen, lhash);
                  printf("L%ld ledga n=%zu h=", ln, n); hex(lhash, PD0_HASH); printf("\n"); if (n) llen = n; }
              else if (c2 == 'b') { blen = llen < sizeof buf ? llen : sizeof buf; memcpy(buf, led, blen); }
              break;
    case 'n': printf("L%ld name %lld %s\n", ln, a[0], pd0v_name((int)a[0])); break;
    case 'k': { /* receipt: k code hashseed "extra" (the kind is the dumper's fixed word list) */
        uint8_t h[32]; rs = (uint64_t)a[1]; for (int j = 0; j < 32; j++) h[j] = (uint8_t)rnd();
        static const char *kinds[] = { "ladder", "score", "fmt" };
        char path[1024]; path[0] = 0;
        int rc = pd0_receipt_write(c2 == 'x' ? "/nonexistent/pd0v" : rdir, kinds[a[2] % 3], h, (int)a[0], na > 3 && a[3] ? word : NULL, path, sizeof path);
        printf("L%ld receipt rc=%d", ln, rc);
        if (rc == 0) { const char *b = strrchr(path, '/'); printf(" %s\n", b ? b + 1 : path);
            FILE *f = fopen(path, "rb"); char body[8192]; size_t n = f ? fread(body, 1, sizeof body, f) : 0; if (f) fclose(f);
            for (size_t i = 0; i < n; i++) { if (body[i] == '\n') printf("|"); else putchar(body[i]); } }
        printf("\n");
        break; }
    case 'N': /* null world: N seed nobs neps steps rmin rmax cmin cmax cap */
        nrec = pd0_null_world((uint64_t)a[0], (uint8_t)a[1], (uint32_t)a[2], (uint32_t)a[3], a[4], a[5], a[6], a[7], recs, (uint32_t)a[8]);
        printf("L%ld null n=%u\n", ln, nrec); break;
    case 'S': pd0_shuffle_outcomes(recs, nrec, (uint64_t)a[0]); break;
    case 'C': pd0_rechain(recs, nrec); break;
    case 'E': { pd0_rec *r = &recs[a[0]]; /* E i field v: 0 kind 1 status 2 episode 3 after[j=a3] */
                if (a[1] == 0) r->kind = (uint8_t)a[2]; else if (a[1] == 1) r->status = (uint8_t)a[2]; else if (a[1] == 2) r->episode = (uint32_t)a[2]; else r->after[a[3]] = a[2]; break; }
    case 'P': for (uint32_t i = 0; i < nrec; i++) rec_show(ln, &recs[i]); break;
    case 'M': { uint8_t ex[PD0_MAX_VARS + PD0_MAX_CHAN]; memset(ex, 0, sizeof ex); /* M tgt num den e0 e1 ... */
                for (int i = 0; i < PD0_MAX_VARS + PD0_MAX_CHAN && i + 3 < na; i++) ex[i] = (uint8_t)a[i + 3];
                pd0_mut_scale_coef(&rel, (uint8_t)a[0], ex, a[1], a[2]); break; }
    case 'D': pd0_mut_pad(&rel, (uint32_t)a[0], a[1]); break;
    case 'K': { pd0_memoriser m = { NULL, (uint32_t)a[0], (uint8_t)a[1] }; printf("L%ld stored %u\n", ln, pd0_memoriser_stored_numbers(&m)); break; }
    default: printf("L%ld ? %c\n", ln, c);
    }
}

int main(int argc, char **argv) {
    static char lb[20000];
    long ln = 0;
    rdir = argc > 1 ? argv[1] : "receipts";
    while (fgets(lb, sizeof lb, stdin)) {
        ln++;
        size_t n = strlen(lb);
        while (n && (lb[n - 1] == '\n' || lb[n - 1] == '\r')) lb[--n] = 0;
        if (!n || lb[0] == '#') continue;
        if (n < 2) { lb[1] = ' '; lb[2] = 0; }
        line(ln, lb);
    }
    return 0;
}
