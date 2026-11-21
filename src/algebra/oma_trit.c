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

/* Omega mixed algebra: trit, block, dot, integer conversion. */
#include "algebra/oma_trit.h"
#include "omega_native.h"

const char *oma_strerror(int rc) {
    switch (rc) {
    case OMA_OK: return "ok";
    case OMA_E_INVALID_TRIT: return "invalid trit value";
    case OMA_E_INVALID_CODE: return "invalid trit code (pos=1,neg=1)";
    case OMA_E_INVALID_PLANES: return "invalid block (pos & neg != 0)";
    case OMA_E_OVERFLOW: return "overflow";
    case OMA_E_INVALID_BYTE: return "invalid dense byte";
    case OMA_E_INVALID_Z3: return "invalid Z3 value";
    case OMA_E_ARG: return "invalid argument";
    case OMA_E_UNDERFLOW: return "quantization scale underflow";
    default: return "unknown error";
    }
}

static int ctz64(uint64_t x) { /* x != 0 */
#if defined(__GNUC__) || defined(__clang__)
    return __builtin_ctzll(x);
#else
    int n = 0;
    while (!(x & 1u)) { x >>= 1; n++; }
    return n;
#endif
}

int oma_trit_make(int v, oma_trit *out) {
    if (!out) return OMA_E_ARG;
    if (v < -1 || v > 1) return OMA_E_INVALID_TRIT;
    *out = (oma_trit)v;
    return OMA_OK;
}

int oma_trit_to_code(int t, uint8_t *code) {
    if (!code) return OMA_E_ARG;
    switch (t) {
    case 0: *code = OMA_CODE_ZERO; return OMA_OK;
    case 1: *code = OMA_CODE_POS; return OMA_OK;
    case -1: *code = OMA_CODE_NEG; return OMA_OK;
    default: return OMA_E_INVALID_TRIT;
    }
}

int oma_code_to_trit(int code, oma_trit *out) {
    if (!out) return OMA_E_ARG;
    if (code < 0 || code > 2) return OMA_E_INVALID_CODE; /* 0b11 and anything wider */
    *out = (oma_trit)((code & 1) - ((code >> 1) & 1));
    return OMA_OK;
}

/* Per-trit ops use the same plane formulas as the block ops, on 1-bit planes. */
int oma_code_neg(int a, uint8_t *out) {
    if (!out) return OMA_E_ARG;
    if (a < 0 || a > 2) return OMA_E_INVALID_CODE;
    *out = (uint8_t)(((a & 1) << 1) | ((a >> 1) & 1));
    return OMA_OK;
}

int oma_code_add(int a, int b, uint8_t *sum, uint8_t *carry) {
    if (!sum || !carry) return OMA_E_ARG;
    if (a < 0 || a > 2 || b < 0 || b > 2) return OMA_E_INVALID_CODE;
    oma_block A = {(uint64_t)(a & 1), (uint64_t)((a >> 1) & 1)}, B = {(uint64_t)(b & 1), (uint64_t)((b >> 1) & 1)}, S = {0, 0}, C = {0, 0};
    int rc = oma_block_add(&A, &B, &S, &C);
    if (rc) return rc;
    *sum = (uint8_t)((S.pos & 1u) | ((S.neg & 1u) << 1));
    *carry = (uint8_t)((C.pos & 1u) | ((C.neg & 1u) << 1));
    return OMA_OK;
}

int oma_code_mul(int a, int b, uint8_t *out) {
    if (!out) return OMA_E_ARG;
    if (a < 0 || a > 2 || b < 0 || b > 2) return OMA_E_INVALID_CODE;
    oma_block A = {(uint64_t)(a & 1), (uint64_t)((a >> 1) & 1)}, B = {(uint64_t)(b & 1), (uint64_t)((b >> 1) & 1)}, P = {0, 0};
    int rc = oma_block_mul(&A, &B, &P);
    if (rc) return rc;
    *out = (uint8_t)((P.pos & 1u) | ((P.neg & 1u) << 1));
    return OMA_OK;
}

int oma_trit_neg(int a, oma_trit *out) {
    uint8_t ca, r;
    int rc;
    if (!out) return OMA_E_ARG;
    if ((rc = oma_trit_to_code(a, &ca))) return rc;
    if ((rc = oma_code_neg(ca, &r))) return rc;
    return oma_code_to_trit(r, out);
}

int oma_trit_add(int a, int b, oma_trit *sum, oma_trit *carry) {
    uint8_t ca, cb, s, c;
    int rc;
    if (!sum || !carry) return OMA_E_ARG;
    if ((rc = oma_trit_to_code(a, &ca)) || (rc = oma_trit_to_code(b, &cb))) return rc;
    if ((rc = oma_code_add(ca, cb, &s, &c))) return rc;
    if ((rc = oma_code_to_trit(s, sum))) return rc;
    return oma_code_to_trit(c, carry);
}

int oma_trit_mul(int a, int b, oma_trit *out) {
    uint8_t ca, cb, r;
    int rc;
    if (!out) return OMA_E_ARG;
    if ((rc = oma_trit_to_code(a, &ca)) || (rc = oma_trit_to_code(b, &cb))) return rc;
    if ((rc = oma_code_mul(ca, cb, &r))) return rc;
    return oma_code_to_trit(r, out);
}

/* ---- blocks ---- */
int oma_block_validate(const oma_block *b) {
    if (!b) return OMA_E_ARG;
    return (b->pos & b->neg) ? OMA_E_INVALID_PLANES : OMA_OK;
}

int oma_block_encode(const int8_t in[OMA_BLOCK_TRITS], oma_block *out) {
    uint64_t dst[2] = { 0, 0 }, rc = 0;
    if (!in || !out) return OMA_E_ARG;
    (void)omega2_oma_om_block_encode(&rc, (const uint8_t *)in, OMA_BLOCK_TRITS, dst, 2);
    if (rc) return -(int)rc;
    out->pos = dst[0];
    out->neg = dst[1];
    return OMA_OK;
}

int oma_block_decode(const oma_block *b, int8_t out[OMA_BLOCK_TRITS]) {
    uint64_t rc = 0;
    if (!b || !out) return OMA_E_ARG;
    (void)omega2_oma_om_block_decode(&rc, b->pos, b->neg, (uint8_t *)out, OMA_BLOCK_TRITS);
    return rc ? -(int)rc : OMA_OK;
}

int oma_block_neg(const oma_block *a, oma_block *out) {
    int rc;
    if (!out) return OMA_E_ARG;
    if ((rc = oma_block_validate(a))) return rc;
    oma_block r = {a->neg, a->pos};
    *out = r;
    return OMA_OK;
}

int oma_block_add(const oma_block *a, const oma_block *b, oma_block *sum, oma_block *carry) {
    uint64_t av[2], bv[2], dst[4] = { 0, 0, 0, 0 }, rc = 0;
    if (!a || !b || !sum || !carry) return OMA_E_ARG;
    av[0] = a->pos; av[1] = a->neg;
    bv[0] = b->pos; bv[1] = b->neg;
    (void)omega2_oma_om_block_add(&rc, av, 2, bv, 2, dst, 4);
    if (rc) return -(int)rc;
    sum->pos = dst[0]; sum->neg = dst[1];
    carry->pos = dst[2]; carry->neg = dst[3];
    return OMA_OK;
}

int oma_block_mul(const oma_block *a, const oma_block *b, oma_block *out) {
    uint64_t av[2], bv[2], dst[2] = { 0, 0 }, rc = 0;
    if (!a || !b || !out) return OMA_E_ARG;
    av[0] = a->pos; av[1] = a->neg;
    bv[0] = b->pos; bv[1] = b->neg;
    (void)omega2_oma_om_block_mul(&rc, av, 2, bv, 2, dst, 2);
    if (rc) return -(int)rc;
    out->pos = dst[0]; out->neg = dst[1];
    return OMA_OK;
}

int oma_block_dot(const oma_block *a, const oma_block *b, int32_t *out) {
    uint64_t av[2], bv[2], dst[1] = { 0 }, rc = 0;
    if (!a || !b || !out) return OMA_E_ARG;
    av[0] = a->pos; av[1] = a->neg;
    bv[0] = b->pos; bv[1] = b->neg;
    (void)omega2_oma_om_block_dot(&rc, av, 2, bv, 2, dst, 1);
    if (rc) return -(int)rc;
    *out = (int32_t)(int64_t)dst[0];
    return OMA_OK;
}

int oma_dot_tw_i8(const oma_block *w, const int8_t *x, size_t n, int32_t *out) {
    if (!out || (n && (!w || !x))) return OMA_E_ARG;
    if (n > OMA_DOT_I8_MAX_N) return OMA_E_OVERFLOW;
    size_t nb = (n + 63) / 64;
    int32_t acc = 0; /* |acc| <= 128*n < 2^31 by the n bound */
    for (size_t k = 0; k < nb; k++) {
        int rc = oma_block_validate(&w[k]);
        if (rc) return rc;
        size_t lanes = (n - k * 64) < 64 ? (n - k * 64) : 64;
        uint64_t live = lanes == 64 ? ~0ull : ((1ull << lanes) - 1u);
        if ((w[k].pos | w[k].neg) & ~live) return OMA_E_ARG;
        const int8_t *xs = x + k * 64;
        for (uint64_t m = w[k].pos; m; m &= m - 1) acc += xs[ctz64(m)];
        for (uint64_t m = w[k].neg; m; m &= m - 1) acc -= xs[ctz64(m)];
    }
    *out = acc;
    return OMA_OK;
}

/* ---- integer <-> balanced ternary ---- */
int oma_int_to_bt(int64_t v, int8_t *digits, size_t cap, size_t *ndigits) {
    uint8_t tmp[41] = { 0 };
    uint64_t n_out[1] = { 0 }, u = 0;
    if (!ndigits || (cap && !digits)) return OMA_E_ARG;
    (void)omega2_oma_om_int_to_bt(&u, (uint64_t)v, tmp, 41, n_out, 1);
    if ((size_t)n_out[0] > cap) return OMA_E_OVERFLOW;
    for (size_t i = 0; i < (size_t)n_out[0]; i++) digits[i] = (int8_t)tmp[i];
    *ndigits = (size_t)n_out[0];
    return OMA_OK;
}

int oma_int_to_bt_fixed(int64_t v, int8_t *digits, size_t n) {
    size_t used;
    int rc = oma_int_to_bt(v, digits, n, &used);
    if (rc) return rc;
    for (size_t i = used; i < n; i++) digits[i] = 0;
    return OMA_OK;
}

int oma_bt_to_int(const int8_t *digits, size_t n, int64_t *out) {
    uint64_t dst[1] = { 0 }, rc = 0;
    if (!out || (n && !digits)) return OMA_E_ARG;
    if (n == 0) { *out = 0; return OMA_OK; }
    (void)omega2_oma_om_bt_to_int(&rc, (const uint8_t *)digits, n, n, dst, 1);
    if (rc) return -(int)rc;
    *out = (int64_t)dst[0];
    return OMA_OK;
}
