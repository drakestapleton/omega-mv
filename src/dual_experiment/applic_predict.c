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

/* Aggregate (macroscopic) predictor and its error against the exact discrete
 * outcome. The predictor sees one ap_window record only: densities, last
 * window's arrival count, the counts in system, and running means over
 * completed items. It never sees the item list. Flow balance (v2):
 *     resident_cap = min(slots / mean_slots, memory / mean_mem)      items
 *     cap_W        = resident_cap * W / mean_demand                   max completions in a window
 *     frac         = min(1, W / mean_demand)                           share of a resident item finished within W
 *     completions  = min(cap_W, running*frac + queue*frac + A*max(0, W - mean_demand)/W)
 *     in_next      = in_system + A - completions
 *     queue        = max(0, in_next - resident_cap) / queue_max
 *     occupancy    = in_next / resident_cap
 *     blocked      = clamp((occupancy - RAMP_START) / (1 - RAMP_START), 0, 1)
 * A is the arrival forecast: the last window's count (real predictor), the
 * next window's true count (known-arrivals variant, isolates aggregation
 * error from forecast error) or a shuffled window's record (negative control).
 * These formulas are pre-registered. A first draft (v1) counted running items
 * as newly offered work and always predicted full capacity; it was replaced
 * before any result was recorded, and no v1 number is reported anywhere. */
#include "applic.h"
#include "omega_native.h"

#include <math.h>
#include <string.h>

static ap_prediction predict_with_arrivals(const ap_window *w, double A)
{
    ap_prediction p;
    uint64_t inp[8], out_p[3] = { 0, 0, 0 }, u = 0;
    inp[0] = w->slots_capacity;
    inp[1] = w->running;
    inp[2] = w->queue_len;
    inp[3] = w->in_system;
    memcpy(&inp[4], &w->mean_demand, 8);
    memcpy(&inp[5], &w->mean_slots, 8);
    memcpy(&inp[6], &w->mean_mem, 8);
    memcpy(&inp[7], &A, 8);
    (void)omega2_applic_om_predict_with_arrivals(&u, inp, 8, out_p, 3);
    memcpy(&p.completions, &out_p[0], 8);
    memcpy(&p.queue_density, &out_p[1], 8);
    memcpy(&p.blocked, &out_p[2], 8);
    return p;
}

ap_prediction ap_predict(const ap_window *w) { return predict_with_arrivals(w, (double)w->arrivals); }

/* mode 0: real (A = last window's arrivals); 1: known arrivals (A = next
 * window's true count); 2: shuffled (record and A from window src). */
static ap_error score(const ap_sim *s, int mode, uint32_t offset)
{
    ap_error e;
    uint32_t first = AP_WARMUP_WINDOWS, last = s->n_windows ? s->n_windows - 1u : 0u;
    uint32_t scored = last > first ? last - first : 0u;    /* predictions for windows first+1..last */
    double se_c = 0.0, se_q = 0.0, se_b = 0.0, sum_actual_c = 0.0;
    uint32_t t;
    e.completions_nrmse = e.queue_rmse = e.blocked_rmse = e.composite = 0.0;
    e.windows = scored;
    if (scored == 0) return e;
    for (t = first; t < last; t++) {
        const ap_window *a = &s->windows[t + 1];
        uint32_t src = mode == 2 ? first + ((t - first + offset) % scored) : t;
        ap_prediction p = mode == 1 ? predict_with_arrivals(&s->windows[t], (double)a->arrivals)
                                    : ap_predict(&s->windows[src]);
        double ac = (double)a->completions;
        double ab = (double)a->blocked_steps / (double)AP_WINDOW;
        se_c += (p.completions - ac) * (p.completions - ac);
        se_q += (p.queue_density - a->queue_density) * (p.queue_density - a->queue_density);
        se_b += (p.blocked - ab) * (p.blocked - ab);
        sum_actual_c += ac;
    }
    {
        uint64_t se[4], out_e[4] = { 0, 0, 0, 0 }, u = 0;
        memcpy(&se[0], &se_c, 8);
        memcpy(&se[1], &se_q, 8);
        memcpy(&se[2], &se_b, 8);
        memcpy(&se[3], &sum_actual_c, 8);
        (void)omega2_applic_om_error_finalize(&u, se, 4, scored, out_e, 4);
        memcpy(&e.completions_nrmse, &out_e[0], 8);
        memcpy(&e.queue_rmse, &out_e[1], 8);
        memcpy(&e.blocked_rmse, &out_e[2], 8);
        memcpy(&e.composite, &out_e[3], 8);
    }
    return e;
}

ap_error ap_error_real(const ap_sim *s) { return score(s, 0, 0); }
ap_error ap_error_known_arrivals(const ap_sim *s) { return score(s, 1, 0); }
ap_error ap_error_shuffled(const ap_sim *s, uint32_t offset)
{
    uint32_t first = AP_WARMUP_WINDOWS, last = s->n_windows ? s->n_windows - 1u : 0u;
    uint32_t scored = last > first ? last - first : 0u;
    if (scored < 2) return score(s, 0, 0);
    offset = 1u + (offset % (scored - 1u));     /* never the true window */
    return score(s, 2, offset);
}
