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

#include "algebra/oma_pack.h"
#include "omega_native.h"

/* Every function here validates its whole input before writing any output,
 * so on error the output buffers are left untouched (spec: return codes). */

size_t oma_bitplane_blocks(size_t n) { return n / 64 + (n % 64 != 0); }
size_t oma_dense_bytes(size_t n) { return n / 5 + (n % 5 != 0); }

int oma_pack_bitplane(const int8_t *t, size_t n, oma_block *out, size_t out_blocks) {
    size_t nb = oma_bitplane_blocks(n);
    if ((n && !t) || (nb && !out)) return OMA_E_ARG;
    if (out_blocks < nb) return OMA_E_OVERFLOW;
    for (size_t i = 0; i < n; i++)
        if (t[i] < -1 || t[i] > 1) return OMA_E_INVALID_TRIT;
    for (size_t k = 0; k < nb; k++) {
        int8_t lane[OMA_BLOCK_TRITS] = {0};
        size_t m = n - k * 64 < 64 ? n - k * 64 : 64;
        for (size_t i = 0; i < m; i++) lane[i] = t[k * 64 + i];
        int rc = oma_block_encode(lane, &out[k]); /* cannot fail: trits checked */
        if (rc) return rc;
    }
    return OMA_OK;
}

int oma_unpack_bitplane(const oma_block *in, size_t in_blocks, size_t n, int8_t *out) {
    size_t nb = oma_bitplane_blocks(n);
    if ((n && !out) || (nb && !in)) return OMA_E_ARG;
    if (in_blocks < nb) return OMA_E_ARG;
    /* pass 1: validate every block and every unused lane */
    for (size_t k = 0; k < nb; k++) {
        int rc = oma_block_validate(&in[k]);
        if (rc) return rc;
        size_t m = n - k * 64 < 64 ? n - k * 64 : 64;
        uint64_t live = m == 64 ? ~0ull : ((1ull << m) - 1u);
        if ((in[k].pos | in[k].neg) & ~live) return OMA_E_ARG;
    }
    /* pass 2: decode */
    for (size_t k = 0; k < nb; k++) {
        int8_t lane[OMA_BLOCK_TRITS];
        int rc = oma_block_decode(&in[k], lane);
        if (rc) return rc;
        size_t m = n - k * 64 < 64 ? n - k * 64 : 64;
        for (size_t i = 0; i < m; i++) out[k * 64 + i] = lane[i];
    }
    return OMA_OK;
}

int oma_block_serialize(const oma_block *b, uint8_t out[OMA_BLOCK_BYTES]) {
    uint64_t rc = 0;
    if (!b || !out) return OMA_E_ARG;
    (void)omega2_oma_om_block_serialize(&rc, b->pos, b->neg, out, OMA_BLOCK_BYTES);
    return rc ? -(int)rc : OMA_OK;
}

int oma_block_deserialize(const uint8_t in[OMA_BLOCK_BYTES], oma_block *out) {
    uint64_t dst[2] = { 0, 0 }, rc = 0;
    if (!in || !out) return OMA_E_ARG;
    (void)omega2_oma_om_block_deserialize(&rc, in, OMA_BLOCK_BYTES, dst, 2);
    if (rc) return -(int)rc;
    out->pos = dst[0];
    out->neg = dst[1];
    return OMA_OK;
}

int oma_pack_dense(const int8_t *t, size_t n, uint8_t *out, size_t out_cap, size_t *out_len) {
    size_t nbytes = oma_dense_bytes(n);
    if (!out_len || (n && !t) || (nbytes && !out)) return OMA_E_ARG;
    if (out_cap < nbytes) return OMA_E_OVERFLOW;
    for (size_t i = 0; i < n; i++)
        if (t[i] < -1 || t[i] > 1) return OMA_E_INVALID_TRIT;
    for (size_t k = 0; k < nbytes; k++) {
        uint64_t v = 0;
        (void)omega2_oma_om_pack_dense_byte(&v, (const uint8_t *)t, n, k * 5, n);
        out[k] = (uint8_t)v;
    }
    *out_len = nbytes;
    return OMA_OK;
}

int oma_dense_byte_decode(int byte, int8_t out[OMA_DENSE_TRITS_PER_BYTE]) {
    uint64_t rc = 0;
    if (!out) return OMA_E_ARG;
    if (byte < 0 || byte >= OMA_DENSE_BYTE_LIMIT) return OMA_E_INVALID_BYTE;
    (void)omega2_oma_om_dense_byte_decode(&rc, (uint64_t)byte, (uint8_t *)out, OMA_DENSE_TRITS_PER_BYTE);
    return rc ? -(int)rc : OMA_OK;
}

int oma_unpack_dense(const uint8_t *in, size_t in_len, size_t n, int8_t *out) {
    size_t nbytes = oma_dense_bytes(n);
    if ((n && !out) || (nbytes && !in)) return OMA_E_ARG;
    if (in_len < nbytes) return OMA_E_ARG;
    /* pass 1: every byte < 243, padding trits of the last byte zero */
    for (size_t k = 0; k < nbytes; k++) {
        int8_t d[OMA_DENSE_TRITS_PER_BYTE];
        int rc = oma_dense_byte_decode(in[k], d);
        if (rc) return rc;
        for (size_t j = 0; j < OMA_DENSE_TRITS_PER_BYTE; j++)
            if (k * 5 + j >= n && d[j] != 0) return OMA_E_INVALID_BYTE; /* non-canonical padding */
    }
    /* pass 2: decode */
    for (size_t k = 0; k < nbytes; k++) {
        int8_t d[OMA_DENSE_TRITS_PER_BYTE];
        int rc = oma_dense_byte_decode(in[k], d);
        if (rc) return rc;
        for (size_t j = 0; j < OMA_DENSE_TRITS_PER_BYTE && k * 5 + j < n; j++) out[k * 5 + j] = d[j];
    }
    return OMA_OK;
}
