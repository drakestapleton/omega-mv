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

/* tg_sgd.c -- seeded float32 SGD over a tg_store shadow. See tg_sgd.h. */
#include "train/tg_sgd.h"

#include "omega_api_decl.h"
#include <string.h>

static uint32_t fbits(float f) { uint32_t u; memcpy(&u, &f, 4); return u; }

/* The public API permits a gradient backed by the shadow. Overlapping
 * spans must observe the previous element's writes in source order. */
static int spans_overlap(const void *a, const void *b, size_t bytes)
{
    uintptr_t x = (uintptr_t)a, y = (uintptr_t)b;
    return (x <= y ? y - x : x - y) < bytes;
}

int tg_sgd_step(tg_store *st, tg_shadow *sh, const float *grad, size_t n,
                float lr, float momentum, uint64_t grad_ref)
{
    if (!st || !sh || !grad || n == 0 || n > (SIZE_MAX / 4)) return TG_E_ARG;
    uint32_t learning_bits = fbits(lr), momentum_bits = fbits(momentum);
    uint64_t mode;
    if (omega2_tg_sgd_mode(&mode, learning_bits, momentum_bits) != OMEGA_OK)
        return TG_E_NOMEM;
    int use_v = (int)(int64_t)mode;
    if (use_v < 0 || sh->param_bytes != n * 4) return TG_E_ARG;
    if (use_v && sh->opt_bytes != n * 4) return TG_E_ARG;

    tg_ref refs[TG_MAX_REFS];
    uint32_t nr = 0;
    refs[nr++] = (tg_ref){TG_BUF_PARAMS, 0, (uint64_t)n * 4};
    if (use_v) refs[nr++] = (tg_ref){TG_BUF_OPT, 0, (uint64_t)n * 4};
    refs[nr++] = (tg_ref){TG_BUF_EXTERNAL, grad_ref, (uint64_t)n * 4};
    uint64_t arg0 = (uint64_t)learning_bits | ((uint64_t)momentum_bits << 32);
    int r = tg_dispatch(st, sh, TG_OP_SGD, arg0, grad_ref, refs, nr);
    if (r) return r;

    uint32_t *params = (uint32_t *)(void *)sh->params;
    uint32_t *velocity = (uint32_t *)(void *)sh->opt;
    const uint32_t *gradient = (const uint32_t *)(const void *)grad;
    size_t bytes = n * sizeof *gradient;
    if (spans_overlap(params, gradient, bytes) ||
        (use_v && (spans_overlap(velocity, gradient, bytes) || spans_overlap(params, velocity, bytes)))) {
        for (size_t i = 0; i < n; i++) {
            uint32_t direction;
            memcpy(&direction, grad + i, sizeof direction);
            if (use_v) {
                tg_update_velocity(velocity + i, 1, &direction, 1, momentum_bits);
                memcpy(&direction, velocity + i, sizeof direction);
            }
            tg_update_params(params + i, 1, &direction, 1, learning_bits);
        }
    } else {
        /* Bound each native loop and reuse the updated velocity while it is in cache. */
        for (size_t first = 0; first < n;) {
            size_t count = n - first;
            if (count > 2048) count = 2048;
            const uint32_t *direction = gradient + first;
            if (use_v) {
                tg_update_velocity(velocity + first, count, direction, count, momentum_bits);
                direction = velocity + first;
            }
            tg_update_params(params + first, count, direction, count, learning_bits);
            first += count;
        }
    }
    return TG_OK;
}
