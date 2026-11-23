/* SPDX-License-Identifier: Apache-2.0
 * Copyright 2026 Drake Stapleton (AIEN / aien-dev)
 *
 * Pure seeded OM-2 backed implementation of aienos_cap.h (seed/authority/cap_table_om2.om).
 * Severs the external libaienos_capability.a / aienos.lock C dependency.
 */
#include "aienos_cap.h"
#include "omega_native.h"
#include "rx_caproot.h"

#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <sys/random.h>
#include <time.h>

struct AienosCapView {
    pthread_mutex_t mu;
    uint64_t hdr[4];
    uint64_t slots[RX_CAP_MAX * 13];
    uint8_t delivered[RX_CAP_MAX];
    uint8_t token[RX_CAP_TOKEN_LEN];
    AienosCapObserver obs;
    void *obs_ctx;
    int alive;
};

struct AienosCapAdmin {
    struct AienosCapView *view;
};

static _Atomic uint64_t g_om2_boot_gen = 0;

static uint64_t om2_boot_seed(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_BOOTTIME, &ts) != 0) return 0;
    uint64_t ns = (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
    if (ns > (UINT64_MAX >> 9)) return 0;
    return ns << 8;
}

static int om2_take_boot_gen(uint64_t *out) {
    uint64_t seed = om2_boot_seed();
    uint64_t cur = atomic_load_explicit(&g_om2_boot_gen, memory_order_relaxed);
    for (;;) {
        if (cur == UINT64_MAX) return RX_CAP_ERR_EXHAUSTED;
        uint64_t next = cur + 1u;
        if (seed > next) next = seed;
        if (next == UINT64_MAX) return RX_CAP_ERR_EXHAUSTED;
        if (atomic_compare_exchange_weak_explicit(&g_om2_boot_gen, &cur, next,
                                                  memory_order_acq_rel, memory_order_relaxed)) {
            *out = next;
            return RX_CAP_OK;
        }
    }
}

static void unpack_entry(const uint64_t s[13], AienosCapEntry *e) {
    e->cap_id = (uint32_t)s[0];
    e->generation = s[1];
    e->state = (uint32_t)s[2];
    e->issuer = (uint32_t)s[3];
    e->subject = (uint32_t)s[4];
    e->rights = (uint32_t)s[5];
    e->resource = s[6];
    e->epoch = s[7];
    e->lease_expiry = s[8];
    e->parent_id = (uint32_t)s[9];
    e->parent_generation = s[10];
    e->minted_by_id = (uint32_t)s[11];
    e->minted_by_generation = s[12];
}

static int fill_rand(uint8_t *buf, size_t len) {
    size_t n = 0;
    while (n < len) {
        ssize_t r = getrandom(buf + n, len - n, 0);
        if (r < 0 && errno == EINTR) continue;
        if (r <= 0) return -1;
        n += (size_t)r;
    }
    return 0;
}

int aienos_cap_start(AienosCapAdmin **admin, AienosCapView **view) {
    if (!admin || !view) return RX_CAP_ERR_STATE;
    uint64_t boot = 0;
    int brc = om2_take_boot_gen(&boot);
    if (brc != RX_CAP_OK) return brc;
    AienosCapView *v = calloc(1, sizeof *v);
    AienosCapAdmin *a = calloc(1, sizeof *a);
    if (!v || !a) { free(v); free(a); return RX_CAP_ERR_IO; }
    pthread_mutex_init(&v->mu, NULL);
    uint64_t rc = (uint64_t)(int64_t)RX_CAP_ERR_IO;
    if (omega2_cap_table_init(&rc, v->hdr, 4, v->slots, RX_CAP_MAX * 13,
                              v->delivered, RX_CAP_MAX, boot) != OMEGA_OK) {
        pthread_mutex_destroy(&v->mu);
        free(v);
        free(a);
        return RX_CAP_ERR_IO;
    }
    if ((int64_t)rc != RX_CAP_OK) {
        pthread_mutex_destroy(&v->mu);
        free(v);
        free(a);
        return (int)(int64_t)rc;
    }
    if (fill_rand(v->token, sizeof v->token) != 0) {
        memset(v->token, 0, sizeof v->token);
        pthread_mutex_destroy(&v->mu);
        free(v);
        free(a);
        return RX_CAP_ERR_IO;
    }
    v->alive = 1;
    a->view = v;
    *admin = a;
    *view = v;
    return RX_CAP_OK;
}

void aienos_cap_stop(AienosCapAdmin *admin, AienosCapView *view) {
    AienosCapView *v = view ? view : (admin ? admin->view : NULL);
    if (admin) free(admin);
    if (v) {
        memset(v->token, 0, sizeof v->token);
        pthread_mutex_destroy(&v->mu);
        free(v);
    }
}

int aienos_cap_office(const AienosCapAdmin *admin, AienosCapRef *out) {
    if (!admin || !admin->view || !out) return RX_CAP_ERR_STATE;
    AienosCapView *v = admin->view;
    pthread_mutex_lock(&v->mu);
    if (v->hdr[3] != 0) {
        pthread_mutex_unlock(&v->mu);
        return RX_CAP_ERR_IO;
    }
    out->cap_id = (uint32_t)v->slots[0];
    out->generation = v->slots[1];
    pthread_mutex_unlock(&v->mu);
    return RX_CAP_OK;
}

int aienos_cap_mint(AienosCapAdmin *admin, const AienosCapMint *request, AienosCapRef *out) {
    if (!admin || !admin->view || !request) return RX_CAP_ERR_STATE;
    AienosCapView *v = admin->view;
    uint64_t req[9] = {
        request->issuer, request->subject, request->resource, request->rights,
        request->lease_ticks, request->parent.cap_id, request->parent.generation,
        request->authority.cap_id, request->authority.generation
    };
    uint64_t ref[2] = { 0, 0 }, rc = (uint64_t)(int64_t)RX_CAP_ERR_IO;
    AienosCapEntry ent;
    int have_ent = 0;
    AienosCapObserver obs = NULL;
    void *obs_ctx = NULL;

    pthread_mutex_lock(&v->mu);
    uint32_t om_rc = omega2_cap_table_mint(&rc, v->hdr, 4, v->slots, RX_CAP_MAX * 13,
                                           v->delivered, RX_CAP_MAX, req, 9, ref, 2);
    int res = (om_rc == OMEGA_OK) ? (int)(int64_t)rc : RX_CAP_ERR_IO;
    obs = v->obs;
    obs_ctx = v->obs_ctx;
    if (res == RX_CAP_OK) {
        if (ref[0] >= RX_CAP_MAX) {
            res = RX_CAP_ERR_BOUNDS;
        } else {
            if (out) { out->cap_id = (uint32_t)ref[0]; out->generation = ref[1]; }
            unpack_entry(&v->slots[(size_t)ref[0] * 13], &ent);
            have_ent = 1;
        }
    }
    pthread_mutex_unlock(&v->mu);

    if (obs) obs(obs_ctx, AIENOS_CAP_OBS_MINT, have_ent ? &ent : NULL, res);
    return res;
}

int aienos_cap_revoke(AienosCapAdmin *admin, AienosCapRef authority, AienosCapRef target) {
    if (!admin || !admin->view) return RX_CAP_ERR_STATE;
    AienosCapView *v = admin->view;
    uint64_t args[4] = { authority.cap_id, authority.generation, target.cap_id, target.generation };
    uint64_t rev_list[257] = { 0 }, rc = (uint64_t)(int64_t)RX_CAP_ERR_IO;
    AienosCapEntry ents[RX_CAP_MAX];
    uint64_t n_rev = 0;
    AienosCapObserver obs = NULL;
    void *obs_ctx = NULL;

    pthread_mutex_lock(&v->mu);
    uint32_t om_rc = omega2_cap_table_revoke(&rc, v->hdr, 4, v->slots, RX_CAP_MAX * 13,
                                             v->delivered, RX_CAP_MAX, args, 4, rev_list, 257);
    int res = (om_rc == OMEGA_OK) ? (int)(int64_t)rc : RX_CAP_ERR_IO;
    obs = v->obs;
    obs_ctx = v->obs_ctx;
    if (res == RX_CAP_OK && obs) {
        uint64_t raw_n = rev_list[0] <= RX_CAP_MAX ? rev_list[0] : RX_CAP_MAX;
        for (uint64_t i = 0; i < raw_n; i++) {
            if (rev_list[i + 1] >= RX_CAP_MAX) {
                res = RX_CAP_ERR_BOUNDS;
                n_rev = 0;
                break;
            }
            unpack_entry(&v->slots[(size_t)rev_list[i + 1] * 13], &ents[n_rev++]);
        }
    }
    pthread_mutex_unlock(&v->mu);

    if (obs) {
        if (res == RX_CAP_OK) {
            for (uint64_t i = 0; i < n_rev; i++) obs(obs_ctx, AIENOS_CAP_OBS_REVOKE, &ents[i], res);
        } else {
            obs(obs_ctx, AIENOS_CAP_OBS_REVOKE, NULL, res);
        }
    }
    return res;
}

int aienos_cap_reclaim(AienosCapAdmin *admin, AienosCapRef authority, uint32_t cap_id) {
    if (!admin || !admin->view) return RX_CAP_ERR_STATE;
    AienosCapView *v = admin->view;
    uint64_t args[3] = { authority.cap_id, authority.generation, cap_id };
    uint64_t rc = (uint64_t)(int64_t)RX_CAP_ERR_IO;
    AienosCapEntry ent;
    int have_ent = 0;
    AienosCapObserver obs = NULL;
    void *obs_ctx = NULL;

    pthread_mutex_lock(&v->mu);
    uint32_t om_rc = omega2_cap_table_reclaim(&rc, v->hdr, 4, v->slots, RX_CAP_MAX * 13,
                                              v->delivered, RX_CAP_MAX, args, 3);
    int res = (om_rc == OMEGA_OK) ? (int)(int64_t)rc : RX_CAP_ERR_IO;
    obs = v->obs;
    obs_ctx = v->obs_ctx;
    if (res == RX_CAP_OK && cap_id < RX_CAP_MAX) {
        unpack_entry(&v->slots[(size_t)cap_id * 13], &ent);
        have_ent = 1;
    }
    pthread_mutex_unlock(&v->mu);

    if (obs) obs(obs_ctx, AIENOS_CAP_OBS_RECLAIM, have_ent ? &ent : NULL, res);
    return res;
}

int aienos_cap_advance_clock(AienosCapAdmin *admin, AienosCapRef authority, uint64_t ticks) {
    if (!admin || !admin->view) return RX_CAP_ERR_STATE;
    AienosCapView *v = admin->view;
    uint64_t args[3] = { authority.cap_id, authority.generation, ticks };
    uint64_t rc = (uint64_t)(int64_t)RX_CAP_ERR_IO;
    AienosCapEntry ent;
    int have_ent = 0;
    AienosCapObserver obs = NULL;
    void *obs_ctx = NULL;

    pthread_mutex_lock(&v->mu);
    uint32_t om_rc = omega2_cap_table_clock(&rc, v->hdr, 4, v->slots, RX_CAP_MAX * 13,
                                            v->delivered, RX_CAP_MAX, args, 3);
    int res = (om_rc == OMEGA_OK) ? (int)(int64_t)rc : RX_CAP_ERR_IO;
    obs = v->obs;
    obs_ctx = v->obs_ctx;
    if (res == RX_CAP_OK && authority.cap_id < RX_CAP_MAX) {
        unpack_entry(&v->slots[(size_t)authority.cap_id * 13], &ent);
        have_ent = 1;
    }
    pthread_mutex_unlock(&v->mu);

    if (obs) obs(obs_ctx, AIENOS_CAP_OBS_CLOCK, have_ent ? &ent : NULL, res);
    return res;
}

int aienos_cap_bump_epoch(AienosCapAdmin *admin, AienosCapRef authority) {
    if (!admin || !admin->view) return RX_CAP_ERR_STATE;
    AienosCapView *v = admin->view;
    uint64_t rc = (uint64_t)(int64_t)RX_CAP_ERR_IO;
    AienosCapEntry ent;
    int have_ent = 0;
    AienosCapObserver obs = NULL;
    void *obs_ctx = NULL;

    pthread_mutex_lock(&v->mu);
    uint32_t om_rc = omega2_cap_table_epoch(&rc, v->hdr, 4, v->slots, RX_CAP_MAX * 13,
                                            v->delivered, RX_CAP_MAX, authority.cap_id, authority.generation);
    int res = (om_rc == OMEGA_OK) ? (int)(int64_t)rc : RX_CAP_ERR_IO;
    obs = v->obs;
    obs_ctx = v->obs_ctx;
    if (res == RX_CAP_OK && authority.cap_id < RX_CAP_MAX) {
        unpack_entry(&v->slots[(size_t)authority.cap_id * 13], &ent);
        have_ent = 1;
    }
    pthread_mutex_unlock(&v->mu);

    if (obs) obs(obs_ctx, AIENOS_CAP_OBS_EPOCH, have_ent ? &ent : NULL, res);
    return res;
}

int aienos_cap_kill(AienosCapAdmin *admin) {
    if (!admin || !admin->view) return RX_CAP_ERR_STATE;
    AienosCapView *v = admin->view;
    pthread_mutex_lock(&v->mu);
    v->hdr[3] = 1;
    AienosCapObserver obs = v->obs;
    void *obs_ctx = v->obs_ctx;
    pthread_mutex_unlock(&v->mu);
    if (obs) obs(obs_ctx, AIENOS_CAP_OBS_KILL, NULL, RX_CAP_OK);
    return RX_CAP_OK;
}

int aienos_cap_restart(AienosCapAdmin *admin) {
    if (!admin || !admin->view) return RX_CAP_ERR_STATE;
    uint64_t boot = 0;
    int brc = om2_take_boot_gen(&boot);
    if (brc != RX_CAP_OK) return brc;
    AienosCapView *v = admin->view;
    uint64_t rc = (uint64_t)(int64_t)RX_CAP_ERR_IO;
    AienosCapEntry ent;
    AienosCapObserver obs = NULL;
    void *obs_ctx = NULL;

    pthread_mutex_lock(&v->mu);
    uint32_t om_rc = omega2_cap_table_init(&rc, v->hdr, 4, v->slots, RX_CAP_MAX * 13,
                                           v->delivered, RX_CAP_MAX, boot);
    int res = (om_rc == OMEGA_OK) ? (int)(int64_t)rc : RX_CAP_ERR_IO;
    if (res == RX_CAP_OK && fill_rand(v->token, sizeof v->token) != 0) {
        memset(v->token, 0, sizeof v->token);
        v->hdr[3] = 1;
        res = RX_CAP_ERR_IO;
    }
    obs = v->obs;
    obs_ctx = v->obs_ctx;
    if (res == RX_CAP_OK) unpack_entry(&v->slots[0], &ent);
    pthread_mutex_unlock(&v->mu);

    if (obs) obs(obs_ctx, AIENOS_CAP_OBS_RESTART, res == RX_CAP_OK ? &ent : NULL, res);
    return res;
}

int aienos_cap_validate(const AienosCapView *view, AienosCapRef cap, uint32_t subject,
                        uint64_t resource, uint32_t rights, AienosCapEntry *out) {
    if (!view) return RX_CAP_ERR_STATE;
    AienosCapView *v = (AienosCapView *)view;
    uint64_t args[5] = { cap.cap_id, cap.generation, subject, resource, rights };
    uint64_t slot[13] = { 0 }, rc = (uint64_t)(int64_t)RX_CAP_ERR_IO;
    pthread_mutex_lock(&v->mu);
    uint32_t om_rc = omega2_cap_table_validate(&rc, v->hdr, 4, v->slots, RX_CAP_MAX * 13, args, 5, slot, 13);
    pthread_mutex_unlock(&v->mu);
    int res = (om_rc == OMEGA_OK) ? (int)(int64_t)rc : RX_CAP_ERR_IO;
    if (res == RX_CAP_OK && out) unpack_entry(slot, out);
    return res;
}

int aienos_cap_inspect(const AienosCapView *view, AienosCapRef cap, AienosCapEntry *out) {
    if (!view) return RX_CAP_ERR_STATE;
    AienosCapView *v = (AienosCapView *)view;
    uint64_t slot[13] = { 0 }, rc = (uint64_t)(int64_t)RX_CAP_ERR_IO;
    pthread_mutex_lock(&v->mu);
    uint32_t om_rc = omega2_cap_table_inspect(&rc, v->hdr, 4, v->slots, RX_CAP_MAX * 13,
                                              cap.cap_id, cap.generation, slot, 13);
    pthread_mutex_unlock(&v->mu);
    int res = (om_rc == OMEGA_OK) ? (int)(int64_t)rc : RX_CAP_ERR_IO;
    if (res == RX_CAP_OK && out) unpack_entry(slot, out);
    return res;
}

uint64_t aienos_cap_clock(const AienosCapView *view) {
    if (!view) return 0;
    AienosCapView *v = (AienosCapView *)view;
    pthread_mutex_lock(&v->mu);
    uint64_t clk = v->hdr[2];
    pthread_mutex_unlock(&v->mu);
    return clk;
}

int aienos_cap_cognition_mint(const AienosCapView *view, const AienosCapMint *request,
                              const uint8_t *token) {
    (void)view; (void)request; (void)token;
    return RX_CAP_ERR_UNAUTHORIZED;
}

int aienos_cap_cognition_admin(const AienosCapView *view, uint32_t op, AienosCapRef authority,
                               AienosCapRef target) {
    (void)view; (void)op; (void)authority; (void)target;
    return RX_CAP_ERR_UNAUTHORIZED;
}

int aienos_cap_force_generation(AienosCapAdmin *admin, uint32_t cap_id, uint64_t generation) {
    if (!admin || !admin->view || cap_id >= RX_CAP_MAX) return RX_CAP_ERR_BOUNDS;
    AienosCapView *v = admin->view;
    pthread_mutex_lock(&v->mu);
    v->slots[(size_t)cap_id * 13 + 1] = generation;
    pthread_mutex_unlock(&v->mu);
    return RX_CAP_OK;
}

int aienos_cap_generation_advance(uint64_t generation, uint64_t *out) {
    uint64_t next = 0, rc = (uint64_t)(int64_t)RX_CAP_ERR_IO;
    if (omega2_cap_gen_advance(&rc, generation, &next, 1) != OMEGA_OK)
        return RX_CAP_ERR_IO;
    if ((int64_t)rc == RX_CAP_OK && out) *out = next;
    return (int)(int64_t)rc;
}

int aienos_cap_set_observer(AienosCapAdmin *admin, AienosCapObserver fn, void *ctx) {
    if (!admin || !admin->view) return RX_CAP_ERR_STATE;
    AienosCapView *v = admin->view;
    pthread_mutex_lock(&v->mu);
    v->obs = fn;
    v->obs_ctx = ctx;
    pthread_mutex_unlock(&v->mu);
    return RX_CAP_OK;
}

int aienos_cap_authorize(const AienosCapAdmin *admin, const uint8_t *presented) {
    if (!admin || !admin->view || !presented) return RX_CAP_ERR_UNAUTHORIZED;
    AienosCapView *v = admin->view;
    uint64_t eq = 0;
    pthread_mutex_lock(&v->mu);
    uint32_t om_rc = omega2_cap_token_eq(&eq, v->token, RX_CAP_TOKEN_LEN, presented, RX_CAP_TOKEN_LEN);
    pthread_mutex_unlock(&v->mu);
    return (om_rc == OMEGA_OK && eq) ? RX_CAP_OK : RX_CAP_ERR_UNAUTHORIZED;
}
