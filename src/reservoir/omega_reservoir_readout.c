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

/* Ridge readout and NRMSE; contract in omega_reservoir_readout.h. */
#include "omega_reservoir_readout.h"
#include "omega_api_decl.h"

#include <stddef.h>
#include <string.h>

_Static_assert(sizeof(OmegaResReadoutWorkspace) == 67334u * sizeof(uint64_t),
               "workspace layout matches reservoir_readout.om");
_Static_assert(offsetof(OmegaResReadoutWorkspace, g) == 0u &&
               offsetof(OmegaResReadoutWorkspace, d) == 66049u * sizeof(uint64_t) &&
               offsetof(OmegaResReadoutWorkspace, rhs) == 66306u * sizeof(uint64_t),
               "workspace field offsets match reservoir_readout.om");

static uint64_t f64_bits(double d) { uint64_t u; memcpy(&u, &d, 8); return u; }

OmegaResStatus omega_res_readout_fit(const double *x, const double *y, uint32_t n_samples, uint32_t n_features,
                                     uint32_t n_outputs, double lambda, OmegaResReadoutWorkspace *ws,
                                     OmegaResReadout *out)
{
    if (!x || !y || !ws || !out) return OMEGA_RES_ERR_NULL;
    if (n_features < 1u || n_features > OMEGA_RES_READOUT_MAX_FEATURES) return OMEGA_RES_ERR_PARAM;
    if (n_outputs < 1u || n_outputs > OMEGA_RES_READOUT_MAX_OUTPUTS) return OMEGA_RES_ERR_PARAM;
    if (n_samples < 1u) return OMEGA_RES_ERR_PARAM;
    const uint64_t meta[4] = { n_samples, n_features, n_outputs, f64_bits(lambda) };
    uint64_t *wsp = (uint64_t *)(void *)ws;
    int64_t rc = res_om_fit_normal((const uint64_t *)(const void *)x, (size_t)n_samples * n_features,
                                   (const uint64_t *)(const void *)y, (size_t)n_samples * n_outputs,
                                   wsp, meta);
    if (rc != 0) return (OmegaResStatus)rc;
    rc = res_om_fit_solve(wsp, n_features, n_outputs);
    if (rc != 0) return (OmegaResStatus)rc;
    OmegaResReadout r;
    memset(&r, 0, sizeof r);
    r.n_features = n_features;
    r.n_outputs = n_outputs;
    r.lambda = lambda;
    const uint32_t p = n_features + 1u;
    const uint32_t O = OMEGA_RES_READOUT_MAX_OUTPUTS;
    for (uint32_t i = 0; i < p; i++)
        for (uint32_t o = 0; o < n_outputs; o++)
            r.w[i * O + o] = ws->rhs[i * O + o];
    *out = r;
    return OMEGA_RES_OK;
}

OmegaResStatus omega_res_readout_apply(const OmegaResReadout *r, const double *x, double *y_out)
{
    if (!r || !x || !y_out) return OMEGA_RES_ERR_NULL;
    if (r->n_features < 1u || r->n_features > OMEGA_RES_READOUT_MAX_FEATURES || r->n_outputs < 1u ||
        r->n_outputs > OMEGA_RES_READOUT_MAX_OUTPUTS)
        return OMEGA_RES_ERR_PARAM;
    const uint64_t meta[2] = { r->n_features, r->n_outputs };
    return (OmegaResStatus)res_om_readout_apply((const uint64_t *)(const void *)r->w,
                                                (const uint64_t *)(const void *)x, r->n_features,
                                                (uint64_t *)(void *)y_out, r->n_outputs, meta);
}

OmegaResStatus omega_res_nrmse(const double *ref, const double *pred, uint32_t n, double *out)
{
    if (!ref || !pred || !out) return OMEGA_RES_ERR_NULL;
    if (n < 2u) return OMEGA_RES_ERR_PARAM;
    uint64_t bits = 0;
    int64_t rc = res_om_nrmse((const uint64_t *)(const void *)ref, n,
                              (const uint64_t *)(const void *)pred, n, &bits);
    if (rc != 0) return (OmegaResStatus)rc;
    memcpy(out, &bits, 8);
    return OMEGA_RES_OK;
}
