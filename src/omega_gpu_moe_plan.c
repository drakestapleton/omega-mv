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

#include "omega_gpu_moe_plan.h"
#include "omega_gpu_pfhost.h"
#include "omega_gpu_fp8gemm_api.h"
#include "omega_native.h"
#include <string.h>

int omega_moe_queue_init(OmegaMoeQueue *q, uint32_t cap) {
    if (!q) return -1;
    uint64_t rc = 1;
    if (omega2_moe_queue_init(&rc, q->words, OMEGA_MOE_QUEUE_WORDS, cap) != OMEGA_OK || rc != 0) return -1;
    return 0;
}

int omega_moe_queue_enqueue(OmegaMoeQueue *q, uint32_t req_id, uint32_t tokens, uint32_t layer, uint32_t flags, uint32_t *slot_out) {
    if (!q) return -1;
    uint64_t slot = 0xffffffffu;
    if (omega2_moe_queue_enqueue(&slot, q->words, OMEGA_MOE_QUEUE_WORDS, req_id, tokens, layer, flags) != OMEGA_OK || slot == 0xffffffffu)
        return -1;
    if (slot_out) *slot_out = (uint32_t)slot;
    return 0;
}

int omega_moe_queue_claim_batch(OmegaMoeQueue *q, uint32_t max_tokens, uint32_t out_slots[64], uint32_t *claimed_out) {
    if (!q || !out_slots || !claimed_out) return -1;
    uint64_t n = 0;
    if (omega2_moe_queue_claim_batch(&n, q->words, OMEGA_MOE_QUEUE_WORDS, max_tokens, out_slots, 64u) != OMEGA_OK)
        return -1;
    *claimed_out = (uint32_t)n;
    return 0;
}

int omega_moe_queue_complete_batch(OmegaMoeQueue *q, uint32_t n, const uint32_t slots[64], uint32_t status) {
    if (!q || !slots) return -1;
    uint64_t rc = 1;
    if (omega2_moe_queue_complete_batch(&rc, q->words, OMEGA_MOE_QUEUE_WORDS, n, slots, 64u, status) != OMEGA_OK || rc != 0)
        return -1;
    return 0;
}

static void pack_cfg(const OmegaMoePlanConfig *c, uint64_t out[8]) {
    out[0] = c->tokens;
    out[1] = c->hidden;
    out[2] = c->inter;
    out[3] = c->experts;
    out[4] = c->top_k;
    out[5] = c->flags;
    out[6] = 0;
    out[7] = 0;
}

int omega_moe_plan_layer(const OmegaMoePlanConfig *cfg, OmegaMoePlanOp out_ops[OMEGA_MOE_PLAN_MAX_OPS], uint32_t *n_ops) {
    if (!cfg || !out_ops || !n_ops) return -1;
    uint64_t cv[8];
    uint32_t raw[128];
    memset(raw, 0, sizeof raw);
    pack_cfg(cfg, cv);
    uint64_t k = 0;
    if (omega2_moe_plan_layer(&k, cv, 8u, raw, 128u) != OMEGA_OK || k == 0 || k > OMEGA_MOE_PLAN_MAX_OPS)
        return -1;
    for (uint64_t i = 0; i < k; i++) {
        out_ops[i].op = raw[4u * i + 0u];
        out_ops[i].mark_independent = raw[4u * i + 1u];
        out_ops[i].arg0 = raw[4u * i + 2u];
        out_ops[i].arg1 = raw[4u * i + 3u];
    }
    *n_ops = (uint32_t)k;
    return 0;
}

int omega_moe_plan_traffic(const OmegaMoePlanConfig *cfg, uint32_t distinct_experts, OmegaMoeTraffic *out) {
    if (!cfg || !out) return -1;
    uint64_t cv[8], bytes[8], rc = 1;
    memset(bytes, 0, sizeof bytes);
    pack_cfg(cfg, cv);
    if (omega2_moe_plan_traffic(&rc, cv, 8u, distinct_experts, bytes, 8u) != OMEGA_OK || rc != 0)
        return -1;
    out->router_bytes = bytes[0];
    out->gateup_bytes = bytes[1];
    out->down_bytes = bytes[2];
    out->combine_bytes = bytes[3];
    out->total_bytes = bytes[4];
    return 0;
}

int omega_gpu_moe_plan_exec(OmegaGpuCmdList *cl, const OmegaGpuMoeExecArgs *args, OmegaGpuMoeExecStats *stats) {
    if (!cl || !args) return -1;
    OmegaMoePlanOp ops[OMEGA_MOE_PLAN_MAX_OPS];
    uint32_t n_ops = 0;
    if (omega_moe_plan_layer(&args->cfg, ops, &n_ops) != 0) return -1;

    OmegaMoeTraffic traffic;
    memset(&traffic, 0, sizeof traffic);
    (void)omega_moe_plan_traffic(&args->cfg, args->distinct_experts, &traffic);

    if (stats) memset(stats, 0, sizeof *stats);

    const uint32_t rows = args->cfg.tokens * args->cfg.top_k;
    omega_gpu_session_lock();
    omega_gpu_cmdlist_reset(cl);

    int rc = 0;
    uint32_t recorded = 0;
    for (uint32_t i = 0; i < n_ops && rc == 0; i++) {
        const OmegaMoePlanOp *op = &ops[i];
        switch (op->op) {
        case OMEGA_MOP_ROUTER_LOGITS:
            rc = omega_gpu_pf_router_logits_record(cl, args->cfg.hidden, args->cfg.experts, args->cfg.tokens,
                                                   args->x_va, args->router_wq_va, args->logits_va);
            break;
        case OMEGA_MOP_EXPERT_GATEUP_GEMM:
            if (!args->gateup_t) { rc = -1; break; }
            rc = omega_gpu_fp8gemm_record(cl, args->gateup_t, rows, args->gateup_segs, args->gateup_seg_va,
                                          args->gateup_xp_va, args->gateup_y_va, 0, 0, 0, 0, NULL);
            break;
        case OMEGA_MOP_EXPERT_DOWN_GEMM:
            if (!args->down_t) { rc = -1; break; }
            rc = omega_gpu_fp8gemm_record(cl, args->down_t, rows, args->down_segs, args->down_seg_va,
                                          args->down_xp_va, args->down_y_va, 0, 0, 0, 0, NULL);
            break;
        case OMEGA_MOP_MOE_COMBINE:
            rc = omega_gpu_pf_moe_combine_record(cl, args->cfg.hidden, args->cfg.top_k, args->cfg.tokens,
                                                 args->down_y_va, args->inv_va, args->wt_va, args->out_va);
            break;
        default:
            rc = -1;
            break;
        }
        if (rc == 0) {
            if (op->mark_independent) omega_gpu_cmdlist_mark_independent(cl);
            if (stats && recorded < OMEGA_MOE_PLAN_MAX_OPS) stats->stage_op[recorded] = op->op;
            recorded++;
        }
    }

    OmegaGpuCmdListStats cst;
    memset(&cst, 0, sizeof cst);
    uint64_t stamps[OMEGA_MOE_PLAN_MAX_OPS + 1];
    memset(stamps, 0, sizeof stamps);
    int n_stamps = 0;
    if (rc == 0) {
        OmegaGpuCmdListOpts opts;
        memset(&opts, 0, sizeof opts);
        opts.mode = OMEGA_GPU_CMDLIST_PCAS;
        opts.barrier = args->barrier;
        opts.stamps = 1;
        rc = omega_gpu_cmdlist_submit(cl, &opts, &cst);
        if (rc == 0) n_stamps = omega_gpu_cmdlist_stamps(cl, stamps, OMEGA_MOE_PLAN_MAX_OPS + 1u);
    }
    omega_gpu_session_unlock();

    if (rc != 0) return -1;
    if (stats) {
        stats->planned_ops = n_ops;
        stats->launches = cst.launches;
        stats->submits = cst.submits;
        stats->chip_ns = cst.elapsed_ns;
        stats->host_build_ns = cst.host_ns;
        stats->traffic = traffic;
        if (n_stamps == (int)(recorded + 1u)) {
            for (uint32_t i = 0; i < recorded; i++)
                stats->stage_ns[i] = stamps[i + 1u] >= stamps[i] ? (stamps[i + 1u] - stamps[i]) : 0u;
        }
        if (cst.elapsed_ns > 0)
            stats->effective_gbps = (double)traffic.total_bytes / (double)cst.elapsed_ns;
    }
    return 0;
}
