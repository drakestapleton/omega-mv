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

#ifndef OMEGA_GPU_MOE_PLAN_H
#define OMEGA_GPU_MOE_PLAN_H
/*
 * omega_gpu_moe_plan: Pure-OM-2 persistent MoE request queue + unified single-submit
 * MoE layer execution planner & PTIMER/traffic instrumentation (om/gpu/moe_plan.om).
 */
#include <stdint.h>
#include <stddef.h>
#include "omega_gpu_fp8_api.h"
#include "omega_gpu_cmdlist.h"

#ifdef __cplusplus
extern "C" {
#endif

#define OMEGA_MOE_QUEUE_WORDS 512u
#define OMEGA_MOE_QUEUE_MAX_CAP 64u
#define OMEGA_MOE_PLAN_MAX_OPS 32u

enum {
    OMEGA_MOE_ST_EMPTY = 0,
    OMEGA_MOE_ST_QUEUED = 1,
    OMEGA_MOE_ST_RUNNING = 2,
    OMEGA_MOE_ST_DONE = 3,
    OMEGA_MOE_ST_ERROR = 4
};

enum {
    OMEGA_MOP_ROUTER_LOGITS = 1,
    OMEGA_MOP_ACT_QUANT = 2,
    OMEGA_MOP_EXPERT_GATEUP_GEMM = 3,
    OMEGA_MOP_EXPERT_GATEUP_GEMV = 4,
    OMEGA_MOP_EXPERT_DOWN_GEMM = 5,
    OMEGA_MOP_EXPERT_DOWN_GEMV = 6,
    OMEGA_MOP_MOE_COMBINE = 7
};

enum {
    OMEGA_MOE_FLAG_ROUTER = 1u << 0,
    OMEGA_MOE_FLAG_GATEUP = 1u << 1,
    OMEGA_MOE_FLAG_DOWN = 1u << 2,
    OMEGA_MOE_FLAG_COMBINE = 1u << 3,
    OMEGA_MOE_FLAG_USE_QMMA = 1u << 4,
    OMEGA_MOE_FLAG_OVERLAP_RQ = 1u << 5
};

typedef struct {
    uint32_t words[OMEGA_MOE_QUEUE_WORDS];
} OmegaMoeQueue;

typedef struct {
    uint32_t op;
    uint32_t mark_independent;
    uint32_t arg0;
    uint32_t arg1;
} OmegaMoePlanOp;

typedef struct {
    uint32_t tokens;
    uint32_t hidden;
    uint32_t inter;
    uint32_t experts;
    uint32_t top_k;
    uint32_t flags;
} OmegaMoePlanConfig;

typedef struct {
    uint64_t router_bytes;
    uint64_t gateup_bytes;
    uint64_t down_bytes;
    uint64_t combine_bytes;
    uint64_t total_bytes;
} OmegaMoeTraffic;

typedef struct {
    OmegaMoePlanConfig cfg;
    uint32_t distinct_experts;
    /* Router logits (rl) device buffers */
    uint64_t x_va;
    uint64_t router_wq_va;
    uint64_t logits_va;
    /* Grouped FP8 gate_up expert GEMM buffers */
    const OmegaGpuFp8Tensor *gateup_t;
    uint32_t gateup_segs;
    uint64_t gateup_seg_va;
    uint64_t gateup_xp_va;
    uint64_t gateup_y_va;
    /* Grouped FP8 down expert GEMM buffers */
    const OmegaGpuFp8Tensor *down_t;
    uint32_t down_segs;
    uint64_t down_seg_va;
    uint64_t down_xp_va;
    uint64_t down_y_va;
    /* Weighted combine (mc) buffers */
    uint64_t inv_va;
    uint64_t wt_va;
    uint64_t out_va;
    /* Optional cmdlist barrier (default WFI_DATA) */
    OmegaGpuCmdListBarrier barrier;
} OmegaGpuMoeExecArgs;

typedef struct {
    uint32_t planned_ops;
    uint32_t launches;
    uint32_t submits;
    uint64_t chip_ns;
    uint64_t host_build_ns;
    uint64_t stage_ns[OMEGA_MOE_PLAN_MAX_OPS];
    uint32_t stage_op[OMEGA_MOE_PLAN_MAX_OPS];
    OmegaMoeTraffic traffic;
    double effective_gbps;
} OmegaGpuMoeExecStats;

/* Pure OM-2 queue state machine wrappers (never abort) */
int omega_moe_queue_init(OmegaMoeQueue *q, uint32_t cap);
int omega_moe_queue_enqueue(OmegaMoeQueue *q, uint32_t req_id, uint32_t tokens, uint32_t layer, uint32_t flags, uint32_t *slot_out);
int omega_moe_queue_claim_batch(OmegaMoeQueue *q, uint32_t max_tokens, uint32_t out_slots[64], uint32_t *claimed_out);
int omega_moe_queue_complete_batch(OmegaMoeQueue *q, uint32_t n, const uint32_t slots[64], uint32_t status);

/* Pure OM-2 MoE planner & traffic estimator wrappers (never abort) */
int omega_moe_plan_layer(const OmegaMoePlanConfig *cfg, OmegaMoePlanOp out_ops[OMEGA_MOE_PLAN_MAX_OPS], uint32_t *n_ops);
int omega_moe_plan_traffic(const OmegaMoePlanConfig *cfg, uint32_t distinct_experts, OmegaMoeTraffic *out);

/* Execute a unified .om-planned MoE layer in ONE OmegaGpuCmdList PCAS submission with PTIMER stamps. */
int omega_gpu_moe_plan_exec(OmegaGpuCmdList *cl, const OmegaGpuMoeExecArgs *args, OmegaGpuMoeExecStats *stats);

#ifdef __cplusplus
}
#endif
#endif
