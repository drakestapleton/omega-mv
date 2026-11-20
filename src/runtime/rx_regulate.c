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

/* ADAPTIVE-M4: bounded resource regulation. Contract in rx_regulate.h.
 * Core decision, envelope validation, policy derivation, bounds check,
 * and step transition execute in pure OM-2 (om/runtime/rx_regulate.om). */
#include "runtime/rx_regulate.h"
#include "omega_native.h"

#include <string.h>

static void pack_env(const RxRegulateEnvelope *e, uint64_t out[16]) {
    memset(out, 0, sizeof(uint64_t) * 16);
    out[0] = e->slots_min;
    out[1] = e->slots_max;
    out[2] = e->memory_min;
    out[3] = e->memory_max;
    out[4] = e->energy_min;
    out[5] = e->energy_max;
    out[6] = e->base.slots;
    out[7] = e->base.memory_bytes;
    out[8] = e->base.energy_budget;
    out[9] = e->contention_hi;
    out[10] = e->contention_lo;
    out[11] = e->pressure_hi;
    out[12] = e->pressure_lo;
    out[13] = e->min_dwell;
}

static const RxSnapshotDep *in_of(const RxCtx *c, RxObjRef r) {
    for (uint32_t i = 0; i < c->n_in; i++)
        if (c->in[i].obj.id == r.id) return &c->in[i];
    return NULL;
}

static void put(RxCtx *c, RxObjRef o, uint32_t field, uint64_t v) {
    c->out[c->n_out++] = (RxMutation){ o, field, v };
}

int rx_regulate_envelope_ok(const RxRegulateEnvelope *e) {
    if (!e) return RX_ERR_ARG;
    uint64_t env[16], res = 0;
    pack_env(e, env);
    if (omega2_rx_reg_envelope_ok(&res, env, 16) != OMEGA_OK) return RX_ERR_ARG;
    return (int)(int64_t)res;
}

void rx_regulate_policy_for(const RxRegulateEnvelope *e, uint32_t regime, RxResourceBudget *out) {
    *out = e->base;
    uint64_t env[16], dst[4] = { 0 }, res = 0;
    pack_env(e, env);
    if (omega2_rx_reg_policy_for(&res, env, 16, (uint64_t)regime, dst, 4) == OMEGA_OK) {
        out->slots = (uint32_t)dst[0];
        out->memory_bytes = dst[1];
        out->energy_budget = dst[2];
    }
}

uint32_t rx_regulate_decide(const RxRegulateEnvelope *e, uint32_t regime, uint64_t dwell,
                            uint64_t contention, uint64_t pressure) {
    uint64_t env[16], res = RX_REG_NOMINAL;
    pack_env(e, env);
    if (omega2_rx_reg_decide(&res, env, 16, (uint64_t)regime, dwell, contention, pressure) != OMEGA_OK)
        return RX_REG_PROTECT;
    return (uint32_t)res;
}

/* Policy written only here. A condition sample already decided on (same seq)
 * publishes nothing, so a re-run of the same activation is a no-op. */
static int fn_regulate(RxCtx *c) {
    RxRegulator *r = c->user;
    const RxSnapshotDep *cond = in_of(c, r->condition);
    const RxSnapshotDep *pol = in_of(c, r->policy);
    if (!cond || !pol) return RX_ERR_ARG;
    uint64_t env[16], dst[8] = { 0 }, act = 0;
    pack_env(&r->env, env);
    if (omega2_rx_reg_step(&act, env, 16, cond->field, 8, pol->field, 8, dst, 8) != OMEGA_OK)
        return RX_ERR_ARG;
    if (act == 0) return 0;
    put(c, r->policy, 5, dst[5]);
    if (act == 1) {
        put(c, r->policy, 6, dst[6]);
        return 0;
    }
    put(c, r->policy, 0, dst[0]);
    put(c, r->policy, 1, dst[1]);
    put(c, r->policy, 2, dst[2]);
    put(c, r->policy, 3, dst[3]);
    put(c, r->policy, 4, dst[4]);
    put(c, r->policy, 6, dst[6]);
    put(c, r->policy, 7, dst[7]);
    return 0;
}

int rx_regulate_create_objects(RxRegulator *r, RxWorld *w, const RxRegulateEnvelope *e) {
    if (!r || !w) return RX_ERR_ARG;
    int rc = rx_regulate_envelope_ok(e);
    if (rc != RX_OK) return rc;
    memset(r, 0, sizeof(*r));
    r->w = w;
    r->env = *e;
    uint64_t z[RX_MAX_FIELDS] = { 0 };
    rc = rx_world_create(w, RX_OT_REG_CONDITION, RX_PERSIST_RESIDENT,
                         RX_REG_RES_BASE + RX_REG_RES_CONDITION, z, &r->condition);
    if (rc != RX_OK) return rc;
    uint64_t p[RX_MAX_FIELDS] = { 1, e->base.slots, e->base.memory_bytes, e->base.energy_budget,
                                  RX_REG_NOMINAL, 0, 0, 0 };
    return rx_world_create(w, RX_OT_REG_POLICY, RX_PERSIST_RESIDENT,
                           RX_REG_RES_BASE + RX_REG_RES_POLICY, p, &r->policy);
}

int rx_regulate_register(RxRegulator *r, const RxRegulateCaps *caps, const RxCallerCred *cred) {
    if (!r || !r->w || !caps) return RX_ERR_ARG;
    RxReactionDesc d;
    memset(&d, 0, sizeof d);
    d.name = "regulate.budget";
    d.faculty = RX_FACULTY_AIEN;
    d.subject = RX_REG_SUBJ;
    d.priority = RX_PRIO_CRITICAL;
    d.fn = fn_regulate;
    d.user = r;
    if (cred) d.caller = *cred;
    d.n_triggers = 1;
    d.triggers[0] = (RxDep){ r->condition, RX_FIELD(0) };
    d.n_reads = 2;
    d.reads[0] = (RxDep){ r->condition, RX_ALL_FIELDS };
    d.reads[1] = (RxDep){ r->policy, RX_ALL_FIELDS };
    d.n_writes = 1;
    d.writes[0] = (RxDep){ r->policy, RX_ALL_FIELDS };
    d.n_caps = 2;
    d.caps[0] = (RxCapNeed){ caps->condition_read, RX_REG_RES_BASE + RX_REG_RES_CONDITION,
                             RX_RIGHT_READ };
    d.caps[1] = (RxCapNeed){ caps->policy_rw, RX_REG_RES_BASE + RX_REG_RES_POLICY,
                             RX_RIGHT_READ | RX_RIGHT_WRITE };
    return rx_world_add_reaction(r->w, &d, &r->rid);
}

int rx_regulate_apply(RxRegulator *r) {
    if (!r || !r->w) return RX_ERR_ARG;
    RxHaltStatus h;
    rx_world_halt_status(r->w, &h);
    if (h.halted) { r->refused++; return RX_ERR_HALTED; }
    RxObject p;
    int rc = rx_world_read(r->w, r->policy, &p);
    if (rc != RX_OK) return rc;
    if (p.field[0] == r->applied_version) return 1;
    const RxRegulateEnvelope *e = &r->env;
    uint64_t env[16], chk = 0;
    pack_env(e, env);
    if (omega2_rx_reg_apply_check(&chk, env, 16, p.field, 8) != OMEGA_OK ||
        (int64_t)chk != RX_OK) {
        r->refused++;
        return RX_ERR_BOUNDS;
    }
    RxResourceBudget b = e->base;           /* fairness and offers: never regulated */
    b.slots = (uint32_t)p.field[1];
    b.memory_bytes = p.field[2];
    b.energy_budget = p.field[3];
    rx_world_set_resources(r->w, &b);
    r->applied = b;
    r->applied_version = p.field[0];
    return RX_OK;
}
