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

/*
 * rx_capq.c -- Omega capability query IR. See rx_capq.h.
 *
 * The catalog is indexed by (operation, source). A query compiles to the
 * buckets of its operation and specializations, in the sources that may
 * realize it; it never walks the rest of the catalog and never reads a
 * description. What it returns is a bounded array of fixed-size records.
 */
#include "rx_capq.h"

#include "omega_native.h"
#include "sha256.h"

#include <stdlib.h>
#include <string.h>

/* ---- small open-addressing maps (key 0 = empty) ---- */

static uint32_t pow2_at_least(uint32_t n) {
    uint32_t p = 16;
    while (p < n) p <<= 1;
    return p;
}

static uint32_t hslot(uint32_t key, uint32_t mask) { return (key * 0x9E3779B1u) & mask; }

static int map_put(uint32_t *keys, uint32_t mask, uint32_t *count, uint32_t key, uint32_t *slot) {
    if (key == 0) return CQ_E_ARG;
    uint32_t i = hslot(key, mask);
    for (uint32_t probe = 0; probe <= mask; probe++, i = (i + 1) & mask) {
        if (keys[i] == key) { *slot = i; return CQ_OK; }
        if (keys[i] == 0) {
            if ((*count + 1) * 2 > mask + 1) return CQ_E_NOMEM;   /* keep load <= 1/2 */
            keys[i] = key;
            (*count)++;
            *slot = i;
            return CQ_OK;
        }
    }
    return CQ_E_NOMEM;
}

static int map_get(const uint32_t *keys, uint32_t mask, uint32_t key, uint32_t *slot) {
    if (key == 0 || !keys) return 0;
    uint32_t i = hslot(key, mask);
    for (uint32_t probe = 0; probe <= mask; probe++, i = (i + 1) & mask) {
        if (keys[i] == key) { *slot = i; return 1; }
        if (keys[i] == 0) return 0;
    }
    return 0;
}

/* ---- catalog ---- */

int cq_catalog_init(CqCatalog *c, uint32_t self_machine, uint32_t alias_capacity,
                    uint32_t machine_capacity) {
    if (!c || self_machine == 0) return CQ_E_ARG;
    memset(c, 0, sizeof *c);
    c->self_machine = self_machine;
    uint32_t an = pow2_at_least(alias_capacity * 2 + 2), mn = pow2_at_least(machine_capacity * 2 + 2);
    c->alias_mask = an - 1;
    c->mach_mask = mn - 1;
    c->alias_key = calloc(an, sizeof *c->alias_key);
    c->alias_op = calloc(an, sizeof *c->alias_op);
    c->mach_key = calloc(mn, sizeof *c->mach_key);
    c->mach_lease = calloc(mn, sizeof *c->mach_lease);
    c->cap_ops = 64;
    c->ops = calloc(c->cap_ops + 1, sizeof *c->ops);
    c->key_mask = 255;
    c->key_slot = calloc(c->key_mask + 1, sizeof *c->key_slot);
    if (!c->alias_key || !c->alias_op || !c->mach_key || !c->mach_lease || !c->ops || !c->key_slot) {
        cq_catalog_free(c);
        return CQ_E_NOMEM;
    }
    return CQ_OK;
}

int cq_catalog_init_canonical(CqCatalog *c, AienMachineIndex *machines, const AienMachineId *self,
                              uint32_t alias_capacity, uint32_t machine_capacity) {
    if (!c || !machines || !self) return CQ_E_ARG;
    uint32_t idx = aien_mid_index_bind(machines, self);
    if (idx == 0) return CQ_E_NO_IDENTITY;
    int rc = cq_catalog_init(c, idx, alias_capacity, machine_capacity);
    if (rc == CQ_OK) c->machines = machines;
    return rc;
}

int cq_machine_identity(const CqCatalog *c, uint32_t machine, AienMachineId *out) {
    if (!c || !out) return CQ_E_ARG;
    if (!c->machines || aien_mid_index_get(c->machines, machine, out) != AIEN_MID_OK)
        return CQ_E_NO_IDENTITY;
    return CQ_OK;
}

uint32_t cq_machine_index(const CqCatalog *c, const AienMachineId *m) {
    return c && c->machines && m ? aien_mid_index_find(c->machines, m) : 0;
}

void cq_catalog_free(CqCatalog *c) {
    if (!c) return;
    free(c->key_slot);
    free(c->alias_key);
    free(c->alias_op);
    free(c->mach_key);
    free(c->mach_lease);
    free(c->ops);
    free(c->e);
    free(c->desc);
    free(c->bucket_start);
    free(c->bucket);
    memset(c, 0, sizeof *c);
}

int cq_op_define(CqCatalog *c, uint32_t op, uint32_t parent, uint32_t domains) {
    if (!c || op != c->n_ops + 1 || parent >= op || (domains & ~CQ_SRC_ALL)) return CQ_E_ARG;
    if (op > c->cap_ops) {
        uint32_t nc = c->cap_ops * 2;
        CqOp *n = realloc(c->ops, (size_t)(nc + 1) * sizeof *n);
        if (!n) return CQ_E_NOMEM;
        memset(n + c->cap_ops + 1, 0, (size_t)(nc - c->cap_ops) * sizeof *n);
        c->ops = n;
        c->cap_ops = nc;
    }
    c->ops[op] = (CqOp){ parent, domains, 0, 0 };
    if (parent) {
        c->ops[op].next_sibling = c->ops[parent].first_child;
        c->ops[parent].first_child = op;
    }
    c->n_ops = op;
    c->built = 0;
    return CQ_OK;
}

int cq_alias(CqCatalog *c, uint32_t alias, uint32_t op) {
    if (!c || op == 0 || op > c->n_ops || alias == op) return CQ_E_ARG;
    uint32_t s;
    int rc = map_put(c->alias_key, c->alias_mask, &c->n_alias, alias, &s);
    if (rc != CQ_OK) return rc;
    c->alias_op[s] = op;
    return CQ_OK;
}

int cq_machine_advertise(CqCatalog *c, uint32_t machine, uint64_t lease_until_us) {
    if (!c || machine == 0 || machine == c->self_machine) return CQ_E_ARG;
    uint32_t s;
    int rc = map_put(c->mach_key, c->mach_mask, &c->n_mach, machine, &s);
    if (rc != CQ_OK) return rc;
    c->mach_lease[s] = lease_until_us;
    return CQ_OK;
}

int cq_machine_advertise_id(CqCatalog *c, const AienMachineId *m, uint64_t lease_until_us,
                            uint32_t *index_out) {
    if (!c || !m) return CQ_E_ARG;
    if (!c->machines) return CQ_E_NO_IDENTITY;
    uint32_t idx = aien_mid_index_bind(c->machines, m);
    if (idx == 0) return CQ_E_NO_IDENTITY;
    int rc = cq_machine_advertise(c, idx, lease_until_us);
    if (rc == CQ_OK && index_out) *index_out = idx;
    return rc;
}

/* ---- entry keys ---- */

CqKey cq_key_of(const CqEntry *e) {
    return (CqKey){ e->capability_id, e->realization_id, e->machine_id, e->skill_id };
}

CqKey cq_key_of_candidate(const CqCandidate *x) {
    return (CqKey){ x->capability_id, x->realization_id, x->machine_id, x->skill_id };
}

static uint32_t key_hash(const CqKey *k) {
    uint64_t res = 0;
    (void)omega2_rx_cq_key_hash(&res, (uint64_t)k->capability_id, (uint64_t)k->realization_id,
                                (uint64_t)k->machine_id, (uint64_t)k->skill_id);
    return (uint32_t)res;
}

static int key_eq(const CqEntry *e, const CqKey *k) {
    return e->capability_id == k->capability_id && e->realization_id == k->realization_id &&
           e->machine_id == k->machine_id && e->skill_id == k->skill_id;
}

/* Slot holding k, or the empty slot where it would go. */
static uint32_t key_find(const CqCatalog *c, const CqKey *k) {
    uint32_t i = key_hash(k) & c->key_mask;
    while (c->key_slot[i] && !key_eq(&c->e[c->key_slot[i] - 1], k)) i = (i + 1) & c->key_mask;
    return i;
}

static int key_grow(CqCatalog *c) {
    uint32_t nm = (c->key_mask + 1) * 2 - 1;
    uint32_t *ns = calloc((size_t)nm + 1, sizeof *ns);
    if (!ns) return CQ_E_NOMEM;
    free(c->key_slot);
    c->key_slot = ns;
    c->key_mask = nm;
    for (uint32_t i = 0; i < c->n; i++) {
        CqKey k = cq_key_of(&c->e[i]);
        c->key_slot[key_find(c, &k)] = i + 1;
    }
    return CQ_OK;
}

const CqEntry *cq_lookup(const CqCatalog *c, const CqKey *k) {
    if (!c || !k || !c->key_slot) return NULL;
    uint32_t s = c->key_slot[key_find(c, k)];
    return s ? &c->e[s - 1] : NULL;
}

int cq_set_availability(CqCatalog *c, const CqKey *k, uint32_t live) {
    if (!c || !k || (live != CQ_LIVE_AVAILABLE && live != CQ_LIVE_UNAVAILABLE)) return CQ_E_ARG;
    uint32_t s = c->key_slot[key_find(c, k)];
    if (!s) return CQ_E_NOT_FOUND;
    if (c->e[s - 1].live == CQ_LIVE_WITHDRAWN) return CQ_E_WITHDRAWN;
    c->e[s - 1].live = live;   /* same (op, source) bucket: the index stays valid */
    return CQ_OK;
}

int cq_withdraw(CqCatalog *c, const CqKey *k) {
    if (!c || !k) return CQ_E_ARG;
    uint32_t s = c->key_slot[key_find(c, k)];
    if (!s) return CQ_E_NOT_FOUND;
    c->e[s - 1].live = CQ_LIVE_WITHDRAWN;
    return CQ_OK;
}

int cq_register(CqCatalog *c, const CqEntry *e, const char *desc, uint32_t desc_len) {
    if (!c || !e || e->op == 0 || e->op > c->n_ops || e->source >= CQ_SOURCES ||
        e->machine_id == 0 || (desc_len && !desc) || e->live > CQ_LIVE_UNAVAILABLE)
        return CQ_E_ARG;
    if (!(c->ops[e->op].domains & CQ_SRC(e->source))) return CQ_E_ARG;
    /* Only the Fabric speaks for another machine; the Fabric only for another machine. */
    if ((e->source == CQ_SRC_FABRIC) != (e->machine_id != c->self_machine)) return CQ_E_ARG;
    CqKey k = cq_key_of(e);
    uint32_t ks = key_find(c, &k);
    if (c->key_slot[ks]) {
        /* Update in place. */
        CqEntry *old = &c->e[c->key_slot[ks] - 1];
        uint64_t off = old->desc_off;
        uint32_t len = old->desc_len;
        int moved = old->op != e->op || old->source != e->source;
        if (desc_len) {
            if (c->desc_bytes + desc_len > c->desc_cap) {
                uint64_t nc = c->desc_cap ? c->desc_cap : 65536;
                while (nc < c->desc_bytes + desc_len) nc *= 2;
                char *n = realloc(c->desc, nc);
                if (!n) return CQ_E_NOMEM;
                c->desc = n;
                c->desc_cap = nc;
            }
            memcpy(c->desc + c->desc_bytes, desc, desc_len);
            off = c->desc_bytes;
            len = desc_len;
            c->desc_bytes += desc_len;   /* the old text stays as dead bytes */
        }
        *old = *e;
        old->desc_off = off;
        old->desc_len = len;
        if (moved) c->built = 0;
        return CQ_OK;
    }
    if ((c->n + 1) * 2 > c->key_mask + 1) {
        if (key_grow(c) != CQ_OK) return CQ_E_NOMEM;
        ks = key_find(c, &k);
    }
    if (c->n == c->cap) {
        uint32_t nc = c->cap ? c->cap * 2 : 256;
        CqEntry *n = realloc(c->e, (size_t)nc * sizeof *n);
        if (!n) return CQ_E_NOMEM;
        c->e = n;
        c->cap = nc;
    }
    if (c->desc_bytes + desc_len > c->desc_cap) {
        uint64_t nc = c->desc_cap ? c->desc_cap : 65536;
        while (nc < c->desc_bytes + desc_len) nc *= 2;
        char *n = realloc(c->desc, nc);
        if (!n) return CQ_E_NOMEM;
        c->desc = n;
        c->desc_cap = nc;
    }
    CqEntry x = *e;
    x.desc_off = c->desc_bytes;
    x.desc_len = desc_len;
    if (desc_len) memcpy(c->desc + c->desc_bytes, desc, desc_len);
    c->desc_bytes += desc_len;
    c->e[c->n++] = x;
    c->key_slot[ks] = c->n;
    c->built = 0;
    return CQ_OK;
}

static uint32_t bucket_key(uint32_t op, uint32_t source) { return op * CQ_SOURCES + source; }

int cq_catalog_build(CqCatalog *c) {
    if (!c) return CQ_E_ARG;
    free(c->bucket_start);
    free(c->bucket);
    uint32_t nb = (c->n_ops + 1) * CQ_SOURCES;
    c->bucket_start = calloc((size_t)nb + 1, sizeof *c->bucket_start);
    c->bucket = malloc((size_t)(c->n ? c->n : 1) * sizeof *c->bucket);
    if (!c->bucket_start || !c->bucket) return CQ_E_NOMEM;
    for (uint32_t i = 0; i < c->n; i++) c->bucket_start[bucket_key(c->e[i].op, c->e[i].source) + 1]++;
    for (uint32_t b = 0; b < nb; b++) c->bucket_start[b + 1] += c->bucket_start[b];
    uint32_t *fill = malloc((size_t)nb * sizeof *fill);
    if (!fill) return CQ_E_NOMEM;
    memcpy(fill, c->bucket_start, (size_t)nb * sizeof *fill);
    for (uint32_t i = 0; i < c->n; i++) c->bucket[fill[bucket_key(c->e[i].op, c->e[i].source)]++] = i;
    free(fill);
    c->built = 1;
    return CQ_OK;
}

uint32_t cq_resolve(const CqCatalog *c, uint32_t name) {
    if (!c || name == 0) return 0;
    uint32_t s;
    if (map_get(c->alias_key, c->alias_mask, name, &s)) return c->alias_op[s];
    return name <= c->n_ops ? name : 0;
}

uint64_t cq_catalog_bytes(const CqCatalog *c) {
    uint64_t b = (uint64_t)c->cap * sizeof(CqEntry) + (uint64_t)(c->cap_ops + 1) * sizeof(CqOp) +
                 (uint64_t)(c->alias_mask + 1) * 8u + (uint64_t)(c->mach_mask + 1) * 12u +
                 (uint64_t)(c->key_mask + 1) * 4u + c->desc_cap;
    if (c->built) b += (uint64_t)((c->n_ops + 1) * CQ_SOURCES + 1) * 4u + (uint64_t)c->n * 4u;
    return b;
}

/* ---- compile ---- */

static int cmp_u32(const void *a, const void *b) {
    uint32_t x = *(const uint32_t *)a, y = *(const uint32_t *)b;
    return x < y ? -1 : x > y;
}

static void put_u32(sha256_ctx *h, uint32_t v) {
    uint8_t b[4] = { (uint8_t)v, (uint8_t)(v >> 8), (uint8_t)(v >> 16), (uint8_t)(v >> 24) };
    sha256_update(h, b, 4);
}

static void put_u64(sha256_ctx *h, uint64_t v) {
    put_u32(h, (uint32_t)v);
    put_u32(h, (uint32_t)(v >> 32));
}

static int cmp_u64_(const void *a, const void *b) {
    uint64_t x = *(const uint64_t *)a, y = *(const uint64_t *)b;
    return x < y ? -1 : x > y;
}

void cq_ontology_digest(const CqCatalog *c, uint8_t out[32]) {
    sha256_ctx h;
    sha256_init(&h);
    sha256_update(&h, (const uint8_t *)"OMEGA-CAPQ-ONTOLOGY-1", 21);
    put_u32(&h, c->n_ops);
    for (uint32_t op = 1; op <= c->n_ops; op++) {
        put_u32(&h, c->ops[op].parent);
        put_u32(&h, c->ops[op].domains);
    }
    /* Aliases in key order, not table order. */
    uint64_t *pairs = malloc((size_t)(c->n_alias ? c->n_alias : 1) * sizeof *pairs);
    uint32_t np = 0;
    for (uint32_t i = 0; pairs && i <= c->alias_mask; i++)
        if (c->alias_key[i]) pairs[np++] = (uint64_t)c->alias_key[i] << 32 | c->alias_op[i];
    if (pairs) {
        qsort(pairs, np, sizeof *pairs, cmp_u64_);
        put_u32(&h, np);
        for (uint32_t i = 0; i < np; i++) put_u64(&h, pairs[i]);
    } else {
        put_u32(&h, UINT32_MAX);   /* no memory: a digest no peer can match */
    }
    free(pairs);
    sha256_final(&h, out);
}

int cq_compile(const CqCatalog *c, const CqNeed *need, CqPlan *plan) {
    if (!plan) return CQ_E_ARG;
    memset(plan, 0, sizeof *plan);
    if (!c || !need) return plan->verdict = CQ_E_ARG;
    uint32_t op = cq_resolve(c, need->semantic_operation);
    if (op == 0) return plan->verdict = CQ_E_NO_OP;
    plan->op = op;

    /* The operation and every specialization of it (breadth first). */
    plan->ops[plan->n_ops++] = op;
    uint32_t domains = 0;
    for (uint32_t i = 0; i < plan->n_ops; i++) {
        domains |= c->ops[plan->ops[i]].domains;
        for (uint32_t ch = c->ops[plan->ops[i]].first_child; ch; ch = c->ops[ch].next_sibling) {
            if (plan->n_ops == CQ_MAX_PLAN_OPS) return plan->verdict = CQ_E_PLAN_FULL;
            plan->ops[plan->n_ops++] = ch;
        }
    }
    qsort(plan->ops, plan->n_ops, sizeof plan->ops[0], cmp_u32);

    /* Sources: computed in pure OM-2 (om/runtime/rx_capq_core.om). */
    uint32_t loc = need->locality_constraints.allowed ? need->locality_constraints.allowed
                                                       : (CQ_LOC_LOCAL | CQ_LOC_FABRIC);
    uint32_t pin = need->locality_constraints.machine;
    uint64_t s64 = 0;
    (void)omega2_rx_cq_plan_sources(&s64, (uint64_t)domains, (uint64_t)need->sources,
                                    (uint64_t)loc, (uint64_t)pin, (uint64_t)c->self_machine);
    uint32_t s = (uint32_t)s64;
    plan->sources = s;
    plan->n_probes = plan->n_ops * (uint32_t)__builtin_popcount(s);

    /* Identity: the resolved operation, not the name it was asked by. */
    sha256_ctx h;
    sha256_init(&h);
    sha256_update(&h, (const uint8_t *)"OMEGA-CAPQ-PLAN-1", 17);
    put_u32(&h, plan->op);
    put_u32(&h, plan->n_ops);
    for (uint32_t i = 0; i < plan->n_ops; i++) put_u32(&h, plan->ops[i]);
    put_u32(&h, plan->sources);
    put_u64(&h, need->accepted_input_types);
    put_u64(&h, need->required_output_types);
    put_u32(&h, need->effect_class);
    put_u64(&h, need->authority_ceiling.resource_lo);
    put_u64(&h, need->authority_ceiling.resource_hi);
    put_u32(&h, need->authority_ceiling.rights);
    put_u32(&h, loc);
    put_u32(&h, pin);
    put_u64(&h, need->latency_budget);
    put_u64(&h, need->energy_budget);
    put_u32(&h, need->reliability_requirement);
    put_u32(&h, need->evidence_requirement);
    sha256_final(&h, plan->digest);
    return plan->verdict = s ? CQ_OK : CQ_E_NO_SOURCE;
}

/* ---- ranking ---- */

static void pack_cand_7(const CqCandidate *c, uint64_t out[7]) {
    out[0] = c->expected_cost;
    out[1] = c->expected_latency;
    out[2] = c->expected_energy;
    out[3] = c->confidence;
    out[4] = c->reliability;
    out[5] = c->required_authority.held ? 1ull : 0ull;
    out[6] = c->local ? 1ull : 0ull;
}

static void pack_cand_11(const CqCandidate *c, uint64_t out[11]) {
    pack_cand_7(c, out);
    out[7] = c->capability_id;
    out[8] = c->realization_id;
    out[9] = c->machine_id;
    out[10] = c->skill_id;
}

uint64_t cq_dim_value(const CqCandidate *c, uint32_t dim) {
    uint64_t vals[7], res = 0;
    pack_cand_7(c, vals);
    (void)omega2_rx_cq_dim_value(&res, vals, 7, (uint64_t)dim);
    return res;
}

typedef struct {
    const CqCandidate *c;
    const uint8_t *dims;
    uint32_t n_dims;
} RankCtx;

/* Strict order: the named dimensions, then the ids. */
static int cmp_full(const CqCandidate *a, const CqCandidate *b, const uint8_t *dims, uint32_t nd) {
    uint64_t pa[11], pb[11], res = 0;
    uint8_t d7[7] = { 0 };
    pack_cand_11(a, pa);
    pack_cand_11(b, pb);
    for (uint32_t i = 0; i < nd && i < 7; i++) d7[i] = dims[i];
    (void)omega2_rx_cq_cmp_full(&res, pa, 11, pb, 11, d7, 7, (uint64_t)nd);
    return (int)(int64_t)res;
}

static __thread RankCtx t_sort;   /* qsort has no context argument */

static int cmp_idx(const void *a, const void *b) {
    const RankCtx *r = &t_sort;
    return cmp_full(&r->c[*(const uint32_t *)a], &r->c[*(const uint32_t *)b], r->dims, r->n_dims);
}

static int dominates(const CqCandidate *a, const CqCandidate *b, const uint8_t *dims, uint32_t nd) {
    uint64_t pa[7], pb[7], res = 0;
    uint8_t d7[7] = { 0 };
    pack_cand_7(a, pa);
    pack_cand_7(b, pb);
    for (uint32_t i = 0; i < nd && i < 7; i++) d7[i] = dims[i];
    (void)omega2_rx_cq_dominates(&res, pa, 7, pb, 7, d7, 7, (uint64_t)nd);
    return res != 0;
}

static int within(uint64_t v, uint64_t best, uint32_t tol_ppm) {
    uint64_t res = 0;
    (void)omega2_rx_cq_within(&res, v, best, (uint64_t)tol_ppm);
    return res != 0;
}

int cq_rank(const CqCandidate *in, uint32_t n, const CqTradeoffs *t, CqCandidate *out, uint32_t k,
            uint32_t *front) {
    static const uint8_t all_dims[CQ_DIMS] = { 0, 1, 2, 3, 4, 5, 6 };
    const uint8_t *dims = t && t->n_order ? t->order : all_dims;
    uint32_t nd = t && t->n_order ? t->n_order : CQ_DIMS;
    if (nd > CQ_DIMS) return CQ_E_ARG;
    for (uint32_t i = 0; i < nd; i++)
        if (dims[i] >= CQ_DIMS) return CQ_E_ARG;
    if (front) *front = 0;
    if (n == 0 || k == 0) return 0;

    uint32_t *idx = malloc((size_t)n * sizeof *idx);
    uint8_t *mark = calloc(n, 1);   /* 1 in pool, 2 taken */
    if (!idx || !mark) { free(idx); free(mark); return CQ_E_NOMEM; }
    for (uint32_t i = 0; i < n; i++) idx[i] = i;
    t_sort = (RankCtx){ in, dims, nd };
    qsort(idx, n, sizeof *idx, cmp_idx);

    /* Pareto front: a dominator sorts earlier, and dominance is transitive,
     * so checking against the front found so far is enough. */
    uint32_t nf = 0;
    uint32_t *fr = malloc((size_t)n * sizeof *fr);
    if (!fr) { free(idx); free(mark); return CQ_E_NOMEM; }
    for (uint32_t i = 0; i < n; i++) {
        const CqCandidate *x = &in[idx[i]];
        int dom = 0;
        for (uint32_t j = 0; j < nf && !dom; j++) dom = dominates(&in[fr[j]], x, dims, nd);
        if (!dom) fr[nf++] = idx[i];
    }
    if (front) *front = nf;
    int all = t && t->include_dominated;
    if (all) for (uint32_t i = 0; i < n; i++) mark[i] = 1;
    else for (uint32_t j = 0; j < nf; j++) mark[fr[j]] = 1;
    uint32_t pool = all ? n : nf;
    if (k > pool) k = pool;

    /* Caller's priorities: keep what is within the band of the best on the
     * first dimension, let the next decide among those, and so on; the strict
     * order (dimensions, then ids) breaks what remains. Pool members are
     * visited in the strict order, so the first survivor wins. */
    uint8_t *live = malloc(n);
    if (!live) { free(idx); free(mark); free(fr); return CQ_E_NOMEM; }
    uint32_t got = 0;
    while (got < k) {
        for (uint32_t i = 0; i < n; i++) live[i] = mark[i] == 1;
        for (uint32_t d = 0; d < nd; d++) {
            uint64_t best = UINT64_MAX;
            for (uint32_t i = 0; i < n; i++)
                if (live[i]) {
                    uint64_t v = cq_dim_value(&in[i], dims[d]);
                    if (v < best) best = v;
                }
            uint32_t tol = t ? t->tolerance_ppm[dims[d]] : 0;
            for (uint32_t i = 0; i < n; i++)
                if (live[i] && !within(cq_dim_value(&in[i], dims[d]), best, tol)) live[i] = 0;
        }
        uint32_t pick = UINT32_MAX;
        for (uint32_t i = 0; i < n && pick == UINT32_MAX; i++)
            if (live[idx[i]]) pick = idx[i];
        if (pick == UINT32_MAX) break;
        out[got++] = in[pick];
        mark[pick] = 2;
    }
    free(live);
    free(fr);
    free(mark);
    free(idx);
    return (int)got;
}

/* ---- run ---- */

size_t cq_result_bytes(const CqResult *r) {
    return offsetof(CqResult, cand) + (size_t)r->n * sizeof(CqCandidate);
}

static int machine_live(const CqCatalog *c, uint32_t machine, uint64_t now_us) {
    if (machine == c->self_machine) return 1;
    uint32_t s;
    return map_get(c->mach_key, c->mach_mask, machine, &s) && c->mach_lease[s] > now_us;
}

/* Weak runtime hooks so Fabric/standalone capq links never require rx_world.o or rx_graph.o. */
extern int rx_world_validate_cap(const RxWorld *w, RxCapRef ref, uint32_t subject,
                                 uint64_t resource, uint32_t rights, RxCapEntry *out)
    __attribute__((weak));
extern int rx_graph_need_authority(AgGraph *g, uint32_t node, uint64_t resource, uint32_t rights)
    __attribute__((weak));

static uint32_t held_now(const CqHeld *h, uint64_t resource, uint32_t rights) {
    if (rights == 0) return 1;
    if (!h || !h->w || !h->caps || !rx_world_validate_cap) return 0;
    for (uint32_t i = 0; i < h->caps->n; i++) {
        if (h->caps->cap[i].resource != resource || (rights & ~h->caps->cap[i].rights)) continue;
        RxCapEntry ent;
        if (rx_world_validate_cap(h->w, h->caps->cap[i].ref, h->caps->subject, resource, rights,
                                  &ent) == RX_OK)
            return 1;
    }
    return 0;
}

int cq_query(const CqCatalog *c, const CqPlan *plan, const CqNeed *need, const CqTradeoffs *t,
             const CqHeld *held, uint64_t now_us, CqResult *out, CqStats *stats) {
    return cq_query_admit(c, plan, need, t, held, now_us, NULL, NULL, out, stats);
}

int cq_query_admit(const CqCatalog *c, const CqPlan *plan, const CqNeed *need,
                   const CqTradeoffs *t, const CqHeld *held, uint64_t now_us,
                   CqAdmitFn admit, void *admit_ctx, CqResult *out, CqStats *stats) {
    if (!out) return CQ_E_ARG;
    memset(out, 0, offsetof(CqResult, cand));
    CqStats st;
    memset(&st, 0, sizeof st);
    if (!c || !plan || !need || !t) return out->verdict = CQ_E_ARG;
    if (!c->built) return out->verdict = CQ_E_UNBUILT;
    if (plan->verdict != CQ_OK) {
        if (stats) *stats = st;
        return out->verdict = plan->verdict;
    }

    uint64_t upper = 0;
    for (uint32_t i = 0; i < plan->n_ops; i++)
        for (uint32_t s = 0; s < CQ_SOURCES; s++)
            if (plan->sources & CQ_SRC(s)) {
                uint32_t b = bucket_key(plan->ops[i], s);
                upper += c->bucket_start[b + 1] - c->bucket_start[b];
            }
    CqCandidate *feas = malloc((size_t)(upper ? upper : 1) * sizeof *feas);
    if (!feas) return out->verdict = CQ_E_NOMEM;

    const uint32_t loc = need->locality_constraints.allowed ? need->locality_constraints.allowed
                                                             : (CQ_LOC_LOCAL | CQ_LOC_FABRIC);
    const uint32_t pin = need->locality_constraints.machine;
    uint64_t need_vec[14] = {
        loc, pin, need->accepted_input_types, need->required_output_types, need->effect_class,
        need->authority_ceiling.resource_lo, need->authority_ceiling.resource_hi,
        need->authority_ceiling.rights, need->latency_budget, need->energy_budget,
        need->reliability_requirement, need->evidence_requirement, t->max_cost, t->min_confidence
    };
    uint32_t nf = 0;
    for (uint32_t i = 0; i < plan->n_ops; i++)
        for (uint32_t s = 0; s < CQ_SOURCES; s++) {
            if (!(plan->sources & CQ_SRC(s))) continue;
            uint32_t b = bucket_key(plan->ops[i], s);
            for (uint32_t j = c->bucket_start[b]; j < c->bucket_start[b + 1]; j++) {
                const CqEntry *e = &c->e[c->bucket[j]];
                st.probed++;
                if (e->live == CQ_LIVE_WITHDRAWN || !machine_live(c, e->machine_id, now_us)) {
                    st.rejected_dead++;
                    continue;
                }
                if (e->live != CQ_LIVE_AVAILABLE) { st.rejected_unavailable++; continue; }
                int local = e->machine_id == c->self_machine;
                uint64_t ent_vec[14] = {
                    e->machine_id, e->in_types, e->out_types, e->effects, e->auth_resource,
                    e->auth_rights, e->latency_us, e->energy_uj, e->reliability_ppm,
                    e->evidence_level, e->cost, e->confidence_ppm, (uint64_t)(local ? 1 : 0),
                    e->live
                };
                uint64_t ok = 0;
                (void)omega2_rx_cq_filter_entry(&ok, ent_vec, 14, need_vec, 14);
                if (!ok) continue;
                CqCandidate *x = &feas[nf++];
                memset(x, 0, sizeof *x);
                x->capability_id = e->capability_id;
                x->skill_id = e->skill_id;
                x->machine_id = e->machine_id;
                x->realization_id = e->realization_id;
                x->required_authority.resource = e->auth_resource;
                x->required_authority.rights = e->auth_rights;
                x->required_authority.held = held_now(held, e->auth_resource, e->auth_rights);
                x->expected_cost = e->cost;
                x->expected_latency = e->latency_us;
                x->expected_energy = e->energy_uj;
                x->confidence = e->confidence_ppm;
                x->reliability = e->reliability_ppm;
                x->evidence.ref = e->evidence_ref;
                x->evidence.level = e->evidence_level;
                x->source = e->source;
                x->local = (uint8_t)local;
                x->effects = e->effects;
                if (t->require_held && !x->required_authority.held) {
                    st.rejected_authority++;
                    nf--;
                    continue;
                }
                if (admit && !admit(admit_ctx, e, x)) {
                    st.rejected_admission++;
                    nf--;
                    continue;
                }
            }
        }
    st.feasible = nf;
    uint32_t k = t->k ? t->k : CQ_MAX_K;
    if (k > CQ_MAX_K) k = CQ_MAX_K;
    uint32_t front = 0;
    int n = cq_rank(feas, nf, t, out->cand, k, &front);
    free(feas);
    if (n < 0) return out->verdict = n;
    out->n = (uint32_t)n;
    out->n_feasible = nf;
    out->n_front = front;
    if (stats) *stats = st;
    return out->verdict = CQ_OK;
}

/* ---- consumption ---- */

int cq_bind_skill_node(AgGraph *g, uint32_t node, const CqCandidate *c) {
    if (!g || !c || node >= g->n_nodes || c->skill_id == 0) return CQ_E_ARG;
    if (g->nodes[node].kind != AG_SKILL && g->nodes[node].kind != AG_RETRY) return CQ_E_ARG;
    g->nodes[node].op = c->skill_id;
    if (c->required_authority.rights) {
        if (!rx_graph_need_authority ||
            rx_graph_need_authority(g, node, c->required_authority.resource,
                                    c->required_authority.rights) < 0)
            return CQ_E_ARG;
    }
    return CQ_OK;
}

const char *cq_source_name(uint32_t s) {
    static const char *n[CQ_SOURCES] = { "capability_graph", "skill_network", "mcp_registry",
                                         "local_physical", "fabric" };
    return s < CQ_SOURCES ? n[s] : "?";
}

/* ---- wire form (pure OM-2 codec in om/runtime/rx_capq_core.om) ---- */

static void wire_check(const uint8_t *rec, uint8_t out[4]) {
    uint8_t d[SHA256_DIGEST_SIZE];
    sha256_hash(rec, CQ_WIRE_BYTES - 4, d);
    memcpy(out, d, 4);
}

int cq_wire_encode(const CqCatalog *c, const CqEntry *e, uint32_t kind, uint8_t out[CQ_WIRE_BYTES]) {
    if (!c || !e || !out || kind < CQ_WIRE_ADVERTISE || kind > CQ_WIRE_WITHDRAW) return CQ_E_ARG;
    if (e->machine_id != c->self_machine || e->source == CQ_SRC_FABRIC || e->source >= CQ_SOURCES ||
        e->live > CQ_LIVE_UNAVAILABLE)
        return CQ_E_WIRE;
    AienMachineId m;
    if (cq_machine_identity(c, e->machine_id, &m) != CQ_OK) return CQ_E_NO_IDENTITY;
    uint8_t mid_buf[AIEN_MID_RECORD_BYTES];
    if (aien_mid_encode(&m, mid_buf) != AIEN_MID_OK) return CQ_E_NO_IDENTITY;
    uint64_t hdr[4] = { kind, e->source, e->evidence_level, e->live };
    uint64_t fields[17] = {
        e->capability_id, e->realization_id, e->skill_id, e->skill_version,
        e->op, e->effects, e->in_types, e->out_types, e->auth_resource,
        e->auth_rights, e->confidence_ppm, e->reliability_ppm, e->cost,
        e->latency_us, e->energy_uj, e->evidence_ref, e->generation
    };
    uint64_t ok = 0;
    (void)omega2_rx_cq_wire_encode_body(&ok, hdr, 4, fields, 17, mid_buf, AIEN_MID_RECORD_BYTES,
                                        e->skill_digest, 32, out, CQ_WIRE_BYTES);
    if (!ok) return CQ_E_WIRE;
    wire_check(out, out + 184);
    return CQ_OK;
}

int cq_wire_decode(const uint8_t *in, size_t len, uint32_t *kind, AienMachineId *machine,
                   CqEntry *out) {
    if (!in || !kind || !machine || !out) return CQ_E_ARG;
    if (len != CQ_WIRE_BYTES) return CQ_E_WIRE;
    uint8_t chk[4];
    wire_check(in, chk);
    if (memcmp(chk, in + 184, 4) != 0) return CQ_E_WIRE;
    uint64_t hdr[4] = { 0 }, fields[17] = { 0 }, ok = 0;
    uint8_t sdig[32] = { 0 };
    if (omega2_rx_cq_wire_decode_body(&ok, in, CQ_WIRE_BYTES, hdr, 4, fields, 17, sdig, 32) != OMEGA_OK || !ok)
        return CQ_E_WIRE;
    if (aien_mid_decode(in + 8, AIEN_MID_RECORD_BYTES, machine) != AIEN_MID_OK) return CQ_E_WIRE;
    memset(out, 0, sizeof *out);
    out->source = (uint8_t)hdr[1];
    out->evidence_level = (uint8_t)hdr[2];
    out->live = (uint32_t)hdr[3];
    out->capability_id = (uint32_t)fields[0];
    out->realization_id = (uint32_t)fields[1];
    out->skill_id = (uint32_t)fields[2];
    out->skill_version = (uint32_t)fields[3];
    memcpy(out->skill_digest, sdig, 32);
    out->op = (uint32_t)fields[4];
    out->effects = (uint16_t)fields[5];
    out->in_types = fields[6];
    out->out_types = fields[7];
    out->auth_resource = fields[8];
    out->auth_rights = (uint32_t)fields[9];
    out->confidence_ppm = (uint32_t)fields[10];
    out->reliability_ppm = (uint32_t)fields[11];
    out->cost = fields[12];
    out->latency_us = fields[13];
    out->energy_uj = fields[14];
    out->evidence_ref = fields[15];
    out->generation = fields[16];
    *kind = (uint32_t)hdr[0];
    return CQ_OK;
}

int cq_wire_apply(CqCatalog *c, const uint8_t *in, size_t len, CqKey *key_out) {
    if (!c) return CQ_E_ARG;
    if (!c->machines) return CQ_E_NO_IDENTITY;
    uint32_t kind;
    AienMachineId m;
    CqEntry e;
    int rc = cq_wire_decode(in, len, &kind, &m, &e);
    if (rc != CQ_OK) return rc;
    uint32_t idx = aien_mid_index_find(c->machines, &m);
    if (idx == c->self_machine) return CQ_E_WIRE;           /* nobody speaks for us */
    if (idx == 0) {
        idx = aien_mid_index_bind(c->machines, &m);
        if (idx == 0) return CQ_E_NO_IDENTITY;
    }
    uint32_t op = cq_resolve(c, e.op);
    if (op == 0) return CQ_E_NO_OP;
    e.op = op;
    e.machine_id = idx;
    e.source = CQ_SRC_FABRIC;                               /* local source was provenance only */
    CqKey k = cq_key_of(&e);
    const CqEntry *old = cq_lookup(c, &k);
    uint64_t chk = (uint64_t)(int64_t)CQ_E_WIRE;
    if (omega2_rx_cq_wire_apply_check(&chk, old ? 1ull : 0ull, old ? old->generation : 0ull,
                                      old ? (uint64_t)old->live : 0ull, e.generation,
                                      (uint64_t)kind) != OMEGA_OK)
        return CQ_E_WIRE;
    if ((int64_t)chk != 0) return (int)(int64_t)chk;
    if (kind != CQ_WIRE_ADVERTISE && !old) return CQ_E_WIRE;
    if (kind == CQ_WIRE_ADVERTISE) {
        rc = cq_register(c, &e, NULL, 0);
    } else {
        /* Availability and withdrawal change only `live` (and the revision):
         * the rest of the held entry stays as advertised. */
        CqEntry x = *old;
        x.live = e.live;
        x.generation = e.generation;
        rc = cq_register(c, &x, NULL, 0);
    }
    if (rc == CQ_OK && key_out) *key_out = k;
    return rc;
}
