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

#include "physics0/pd0_wire.h"
#include "omega_native.h"

#include <string.h>

#include "sha256.h"

void pd0_put_u16(uint8_t *p, uint16_t v) { uint64_t u = 0; (void)omega2_pd0_om_put_u16(&u, p, 2, 0, v); }
void pd0_put_u32(uint8_t *p, uint32_t v) { uint64_t u = 0; (void)omega2_pd0_om_put_u32(&u, p, 4, 0, v); }
void pd0_put_u64(uint8_t *p, uint64_t v) { uint64_t u = 0; (void)omega2_pd0_om_put_u64(&u, p, 8, 0, v); }
uint16_t pd0_get_u16(const uint8_t *p) { uint64_t v = 0; (void)omega2_pd0_om_get_u16(&v, p, 2, 0); return (uint16_t)v; }
uint32_t pd0_get_u32(const uint8_t *p) { uint64_t v = 0; (void)omega2_pd0_om_get_u32(&v, p, 4, 0); return (uint32_t)v; }
uint64_t pd0_get_u64(const uint8_t *p) { uint64_t v = 0; (void)omega2_pd0_om_get_u64(&v, p, 8, 0); return v; }

static const uint8_t DESC_MAGIC[8] = {'P', 'D', '0', 'D', 'E', 'S', 'C', '2'};
static const uint8_t REC_MAGIC[8] = {'P', 'D', '0', 'R', 'E', 'C', '1', 0};

size_t pd0_desc_encode(const pd0_desc *d, uint8_t *out, size_t cap) {
    if (!d || d->n_obs < 1 || d->n_obs > PD0_MAX_OBS || d->n_channels < 1 || d->n_channels > PD0_MAX_CH) return 0;
    size_t need = 8 + 2 + 8 + 16u * d->n_channels + 16u * d->n_obs + 12;
    if (cap < need) return 0;
    uint8_t *p = out;
    memcpy(p, DESC_MAGIC, 8); p += 8;
    *p++ = d->n_obs; *p++ = d->n_channels;
    pd0_put_u64(p, (uint64_t)d->dt_micro); p += 8;
    for (unsigned i = 0; i < d->n_channels; i++) { pd0_put_u64(p, (uint64_t)d->chan_min[i]); p += 8; }
    for (unsigned i = 0; i < d->n_channels; i++) { pd0_put_u64(p, (uint64_t)d->chan_max[i]); p += 8; }
    for (unsigned i = 0; i < d->n_obs; i++) { pd0_put_u64(p, (uint64_t)d->reset_min[i]); p += 8; }
    for (unsigned i = 0; i < d->n_obs; i++) { pd0_put_u64(p, (uint64_t)d->reset_max[i]); p += 8; }
    pd0_put_u32(p, d->episode_max_steps); p += 4;
    pd0_put_u32(p, d->budget_steps); p += 4;
    pd0_put_u32(p, d->budget_episodes); p += 4;
    return (size_t)(p - out);
}

int pd0_desc_decode(const uint8_t *in, size_t len, pd0_desc *d) {
    uint64_t mrc = 2;
    if (len > 0) (void)omega2_pd0_om_check_desc_magic(&mrc, in, len, len);
    if (mrc == 1) return PD0_DESC_REFUSED_V1;
    if (mrc != 0) return -1;
    memset(d, 0, sizeof *d);
    d->n_obs = in[8]; d->n_channels = in[9];
    if (d->n_obs < 1 || d->n_obs > PD0_MAX_OBS || d->n_channels < 1 || d->n_channels > PD0_MAX_CH) return -1;
    size_t need = 8 + 2 + 8 + 16u * d->n_channels + 16u * d->n_obs + 12;
    if (len != need) return -1;
    const uint8_t *p = in + 10;
    d->dt_micro = (int64_t)pd0_get_u64(p); p += 8;
    for (unsigned i = 0; i < d->n_channels; i++) { d->chan_min[i] = (int64_t)pd0_get_u64(p); p += 8; }
    for (unsigned i = 0; i < d->n_channels; i++) { d->chan_max[i] = (int64_t)pd0_get_u64(p); p += 8; }
    for (unsigned i = 0; i < d->n_obs; i++) { d->reset_min[i] = (int64_t)pd0_get_u64(p); p += 8; }
    for (unsigned i = 0; i < d->n_obs; i++) { d->reset_max[i] = (int64_t)pd0_get_u64(p); p += 8; }
    d->episode_max_steps = pd0_get_u32(p); p += 4;
    d->budget_steps = pd0_get_u32(p); p += 4;
    d->budget_episodes = pd0_get_u32(p);
    return 0;
}

static size_t rec_body(const pd0_rec *r, uint8_t *out) {
    uint8_t *p = out;
    memcpy(p, REC_MAGIC, 8); p += 8;
    pd0_put_u16(p, 1); p += 2;
    *p++ = r->n_obs; *p++ = r->status; *p++ = r->kind; *p++ = r->channel;
    *p++ = 0; *p++ = 0;
    pd0_put_u64(p, r->seq); p += 8;
    pd0_put_u32(p, r->episode); p += 4;
    pd0_put_u32(p, r->step_in_episode); p += 4;
    pd0_put_u64(p, (uint64_t)r->time_micro); p += 8;
    pd0_put_u64(p, (uint64_t)r->requested); p += 8;
    pd0_put_u64(p, (uint64_t)r->applied); p += 8;
    for (unsigned i = 0; i < r->n_obs; i++) { pd0_put_u64(p, (uint64_t)r->before[i]); p += 8; }
    for (unsigned i = 0; i < r->n_obs; i++) { pd0_put_u64(p, (uint64_t)r->after[i]); p += 8; }
    memcpy(p, r->prev_hash, PD0_HASH); p += PD0_HASH;
    return (size_t)(p - out);
}

size_t pd0_rec_encode(pd0_rec *r, uint8_t *out, size_t cap) {
    if (!r || r->n_obs < 1 || r->n_obs > PD0_MAX_OBS) return 0;
    size_t need = PD0_REC_SIZE(r->n_obs);
    if (cap < need) return 0;
    size_t n = rec_body(r, out);
    sha256_hash(out, n, r->hash);
    memcpy(out + n, r->hash, PD0_HASH);
    return n + PD0_HASH;
}

int pd0_rec_decode(const uint8_t *in, size_t len, pd0_rec *r) {
    uint64_t mrc = 1;
    if (len > 0) (void)omega2_pd0_om_check_rec_magic(&mrc, in, len, len);
    if (mrc != 0) return -1;
    memset(r, 0, sizeof *r);
    r->n_obs = in[10];
    if (r->n_obs < 1 || r->n_obs > PD0_MAX_OBS || len != PD0_REC_SIZE(r->n_obs)) return -1;
    r->status = in[11]; r->kind = in[12]; r->channel = in[13];
    if (in[14] || in[15]) return -1;
    const uint8_t *p = in + 16;
    r->seq = pd0_get_u64(p); p += 8;
    r->episode = pd0_get_u32(p); p += 4;
    r->step_in_episode = pd0_get_u32(p); p += 4;
    r->time_micro = (int64_t)pd0_get_u64(p); p += 8;
    r->requested = (int64_t)pd0_get_u64(p); p += 8;
    r->applied = (int64_t)pd0_get_u64(p); p += 8;
    for (unsigned i = 0; i < r->n_obs; i++) { r->before[i] = (int64_t)pd0_get_u64(p); p += 8; }
    for (unsigned i = 0; i < r->n_obs; i++) { r->after[i] = (int64_t)pd0_get_u64(p); p += 8; }
    memcpy(r->prev_hash, p, PD0_HASH); p += PD0_HASH;
    uint8_t h[PD0_HASH];
    sha256_hash(in, (size_t)(p - in), h);
    if (memcmp(h, p, PD0_HASH) != 0) return -1;
    memcpy(r->hash, h, PD0_HASH);
    return 0;
}

int pd0_rec_chained(const pd0_rec *r, const pd0_rec *prev) {
    static const uint8_t zero[PD0_HASH] = {0};
    if (!prev) return r->seq == 0 && memcmp(r->prev_hash, zero, PD0_HASH) == 0;
    return r->seq == prev->seq + 1 && memcmp(r->prev_hash, prev->hash, PD0_HASH) == 0;
}

size_t pd0_req_describe(uint8_t *out) { out[0] = PD0_OP_DESCRIBE; return 1; }
size_t pd0_req_reset(uint8_t n_obs, const int64_t *vals, uint8_t *out, size_t cap) {
    if (n_obs < 1 || n_obs > PD0_MAX_OBS || !vals || !out) return 0;
    size_t need = 2 + 8u * n_obs;
    if (cap < need) return 0;
    out[0] = PD0_OP_RESET; out[1] = n_obs;
    for (unsigned i = 0; i < n_obs; i++) pd0_put_u64(out + 2 + 8 * i, (uint64_t)vals[i]);
    return need;
}
size_t pd0_req_step(uint8_t channel, int64_t value, uint8_t *out) {
    out[0] = PD0_OP_STEP; out[1] = channel;
    pd0_put_u64(out + 2, (uint64_t)value);
    return 10;
}
