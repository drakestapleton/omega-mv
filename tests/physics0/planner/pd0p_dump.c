/* SPDX-License-Identifier: Apache-2.0
 * pd0p_dump.c -- REFERENCE-ONLY C dumper for tests/physics0/planner/pd0p_parity.sh. Reads the corpus of
 * one-letter commands on stdin, drives the retired C planner (src/physics0/planner/pd0_planner.c at main
 * commit 3f2c70dc5, with src/physics0/ladder/pd0_fmt.c) and prints what tests/physics0/planner/pd0p_dump.om
 * must print. It generated the goldens in tests/physics0/planner/parity_golden once and is then removed
 * from the tree (the MANIFEST records its blob and sha256). Commands: see pd0p_parity.sh. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "pd0_planner.h"

static pd0_rel rel[9];
static int last_eq[9], last_term[9];
static pd0p_bounds bnd;
static pd0p_domain dom;
static int have_dom;
static pd0p_prior prior;
static int use_prior;
static pd0p_hyps hyps;
static pd0p_proposal prop;
static long long a[40];
static int na;

static void hex(const uint8_t *p, size_t n) { for (size_t i = 0; i < n; i++) printf("%02x", p[i]); }

static void exp_dump(long ln, const pd0_exp *e) {
    printf("L%ld E no=%u nh=%u ns=%u div=%lld r=", ln, e->n_obs, e->n_hyp, e->n_steps, (long long)e->divergence_micro);
    for (int i = 0; i < PD0_MAX_OBS; i++) printf("%s%lld", i ? "," : "", (long long)e->reset[i]);
    printf(" s=");
    for (int s = 0; s < PD0_MAX_STEPS; s++) printf("%s%u:%lld", s ? "," : "", e->steps[s].channel, (long long)e->steps[s].value);
    printf(" h=");
    hex(e->schedule_hash, PD0_HASH);
    printf(" x=");
    int first = 1;
    for (int k = 0; k < e->n_hyp && k < PD0_MAX_HYP; k++)
        for (int s = 0; s < e->n_steps && s < PD0_MAX_STEPS; s++)
            for (int i = 0; i < e->n_obs && i < PD0_MAX_OBS; i++) { printf("%s%lld", first ? "" : ",", (long long)e->expected[k][s][i]); first = 0; }
    printf("\n");
}

static void prop_dump(long ln, char c, const pd0p_proposal *p) {
    printf("L%ld %c st=%d d=%lld info=%lld cost=%lld nc=%u nr=%u nsk=%u om=%u seed=%llu h=", ln, c, p->status,
           (long long)p->divergence_micro, (long long)p->info_proxy_micro, (long long)p->cost_micro,
           p->n_candidates, p->n_refined, p->n_skipped_duplicate, p->outside_middle, (unsigned long long)p->seed);
    hex(p->exp.schedule_hash, PD0_HASH);
    printf("\n");
}

static void line(long ln, char *s) {
    char c = s[0];
    na = 0;
    memset(a, 0, sizeof a);
    char *p = s + 1;
    while (*p && na < 40) {
        while (*p == ' ') p++;
        if (!*p) break;
        int neg = 0;
        if (*p == '-') { neg = 1; p++; }
        unsigned long long v = 0;
        while (*p >= '0' && *p <= '9') { v = v * 10 + (unsigned)(*p - '0'); p++; }
        a[na++] = neg ? (long long)(0ull - v) : (long long)v;
        while (*p && *p != ' ') p++;
    }
    switch (c) {
    case 'R': { int k = (int)a[0]; memset(&rel[k], 0, sizeof rel[k]); rel[k].n_vars = (uint8_t)a[1]; rel[k].n_latent = (uint8_t)a[2];
                rel[k].n_channels = (uint8_t)a[3]; last_eq[k] = -1; break; }
    case 'Q': { int k = (int)a[0]; int e = rel[k].n_equations++; rel[k].eq[e].target = (uint8_t)a[1]; rel[k].eq[e].n_terms = 0; last_eq[k] = e; break; }
    case 'T': { int k = (int)a[0]; pd0_eq *q = &rel[k].eq[last_eq[k]]; int t = q->n_terms++; q->coef[t] = a[1];
                memset(q->expo[t], 0, sizeof q->expo[t]); q->expo[t][a[2]] = (uint8_t)a[3]; last_term[k] = t; break; }
    case 'X': { int k = (int)a[0]; rel[k].eq[last_eq[k]].expo[last_term[k]][a[1]] = (uint8_t)a[2]; break; }
    case 'B': memset(&bnd, 0, sizeof bnd); bnd.n_obs = (uint8_t)a[0]; bnd.n_channels = (uint8_t)a[1]; bnd.episode_max_steps = (uint32_t)a[2]; break;
    case 'C': bnd.chan_min[a[0]] = a[1]; bnd.chan_max[a[0]] = a[2]; break;
    case 'Z': bnd.reset_min[a[0]] = a[1]; bnd.reset_max[a[0]] = a[2]; break;
    case 'D': if (!have_dom) memset(&dom, 0, sizeof dom); have_dom = 1; dom.var_min[a[0]] = a[1]; dom.var_max[a[0]] = a[2]; break;
    case 'N': have_dom = 0; break;
    case 'Y': use_prior = 1; break;
    case 'U': use_prior = 0; break;
    case 'K': prior.n = 0; break;
    case 'A': pd0p_prior_add(&prior, prop.exp.schedule_hash); break;
    case 'H': { memset(&hyps, 0, sizeof hyps); hyps.n_hyp = (uint8_t)a[0]; hyps.residual_sd_micro = a[1];
                for (int k = 0; k < PD0_MAX_HYP && k + 2 < na; k++) hyps.hyp[k] = &rel[a[k + 2]]; break; }
    case 'P': pd0p_propose(&bnd, have_dom ? &dom : NULL, &hyps, (uint32_t)a[0], use_prior ? &prior : NULL, (uint64_t)a[1], &prop);
              prop_dump(ln, 'P', &prop); exp_dump(ln, &prop.exp); break;
    case 'G': { static uint8_t b[16384]; size_t n = pd0p_prereg_bytes(&prop, b, sizeof b); printf("L%ld G n=%zu ", ln, n); hex(b, n); printf("\n"); break; }
    case 'W': { uint8_t b[PD0P_PLAN_SIZE]; size_t n = pd0p_plan_write(&prop, b); printf("L%ld W n=%zu ", ln, n); hex(b, n); printf("\n"); break; }
    case 'L': { uint8_t b[128]; memset(b, 0, sizeof b); pd0p_plan_write(&prop, b);
                if (a[1] < 128) b[a[1]] = (uint8_t)a[2];
                pd0p_proposal q; memset(&q, 0x5a, sizeof q);
                int rc = pd0p_plan_parse(b, (size_t)a[0], &q);
                printf("L%ld L rc=%d\n", ln, rc);
                if (rc == 0) prop_dump(ln, 'l', &q);
                break; }
    case 'V': printf("L%ld V rc=%d\n", ln, pd0p_validate(&bnd, use_prior ? &prior : NULL, &prop.exp)); break;
    case 'M': { pd0_exp *e = &prop.exp;
                if (a[0] == 0) e->reset[a[1]] = a[2];
                else if (a[0] == 1) { e->steps[a[1]].channel = (uint8_t)a[2]; e->steps[a[1]].value = a[3]; }
                else if (a[0] == 2) e->n_steps = (uint8_t)a[1];
                else if (a[0] == 3) e->n_obs = (uint8_t)a[1];
                else pd0_schedule_hash(e->n_obs, e->reset, e->n_steps, e->steps, e->schedule_hash);
                break; }
    case 'S': { int rc = pd0p_passive(&bnd, (uint32_t)a[0], (uint64_t)a[1], (uint32_t)a[2], &prop.exp);
                printf("L%ld S rc=%d\n", ln, rc); if (rc == 0) exp_dump(ln, &prop.exp); break; }
    case 'F': { uint8_t f[64]; int n = (int)a[0]; for (int i = 0; i < n && i < 64; i++) f[i] = (uint8_t)a[i + 1];
                printf("L%ld F ppm=%u\n", ln, pd0p_outside_fraction_ppm(f, (uint32_t)n)); break; }
    default: printf("L%ld ? %c\n", ln, c);
    }
}

int main(void) {
    static char buf[4096];
    long ln = 0;
    while (fgets(buf, sizeof buf, stdin)) {
        ln++;
        size_t n = strlen(buf);
        while (n && (buf[n - 1] == '\n' || buf[n - 1] == '\r')) buf[--n] = 0;
        if (!n || buf[0] == '#') continue;
        line(ln, buf);
    }
    return 0;
}
