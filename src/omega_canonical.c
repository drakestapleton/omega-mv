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

/* Canonical object encoding and SemanticId operations backed by pure seeded OM-2
 * (om/visor/canonical_om2.om and om/sha256/sha256-om2.om). */
#include "omega_canonical.h"
#include "omega_native.h"
#include "sha256.h"
#include <string.h>
#include <stdlib.h>

int omega_compare_semantic_id(const SemanticId *a, const SemanticId *b) {
    uint64_t r = 0;
    if (omega2_om_canon_cmp_id(&r, a->bytes, OMEGA_ID_BYTES, b->bytes, OMEGA_ID_BYTES) != OMEGA_OK) abort();
    return (int)(int64_t)r;
}

void omega_hex_semantic_id(const SemanticId *id, char out_hex[65]) {
    uint64_t unused = 0;
    if (omega2_om_canon_hex_id(&unused, id->bytes, OMEGA_ID_BYTES, (uint8_t *)out_hex, 65) != OMEGA_OK) abort();
}

int omega_parse_hex_semantic_id(const char *hex, SemanticId *out_id) {
    if (!hex || !out_id) return -1;
    size_t n = strlen(hex);
    if (n != 64) return -1;
    uint64_t r = 0;
    if (omega2_om_canon_parse_hex(&r, (const uint8_t *)hex, n, n, out_id->bytes, OMEGA_ID_BYTES) != OMEGA_OK) abort();
    return (int)(int64_t)r;
}

uint8_t omega_canonical_object_version(uint8_t kind) {
    uint64_t r = 0;
    if (omega2_om_canon_obj_ver(&r, (uint64_t)kind) != OMEGA_OK) abort();
    return (uint8_t)r;
}

int omega_canonical_check_header(uint8_t version, uint8_t kind) {
    uint64_t r = 0;
    if (omega2_om_canon_chk_hdr(&r, (uint64_t)version, (uint64_t)kind) != OMEGA_OK) abort();
    return (int)(int64_t)r;
}

static int put_u16_be(uint8_t *buf, size_t *pos, size_t max_len, uint16_t v) {
    uint64_t r = 0;
    if (omega2_om_canon_write_u16be(&r, (uint64_t)v, buf, max_len, *pos, max_len) != OMEGA_OK) abort();
    int64_t np = (int64_t)r;
    if (np < 0) return -1;
    *pos = (size_t)np;
    return 0;
}

static int put_u32_be(uint8_t *buf, size_t *pos, size_t max_len, uint32_t v) {
    uint64_t r = 0;
    if (omega2_om_canon_write_u32be(&r, (uint64_t)v, buf, max_len, *pos, max_len) != OMEGA_OK) abort();
    int64_t np = (int64_t)r;
    if (np < 0) return -1;
    *pos = (size_t)np;
    return 0;
}

int omega_canonical_encode(const OmegaObject *obj, uint8_t *out_buf, size_t max_len, size_t *out_len) {
    if (!obj || !out_buf || !out_len || max_len == 0) return -1;

    uint64_t r = 0;
    if (omega2_om_canon_write_hdr(&r, (uint64_t)obj->kind, out_buf, max_len, max_len) != OMEGA_OK) abort();
    if ((int64_t)r < 0) return -1;
    size_t pos = (size_t)r;

    /* 2. Attributes (canonical sort in OM-2) */
    uint16_t n_attrs = obj->attr_count;
    if (n_attrs > OMEGA_MAX_ATTRIBUTES) return -1;
    uint16_t attr_indices[OMEGA_MAX_ATTRIBUTES] = {0};
    if (n_attrs > 0) {
        uint8_t keys[OMEGA_MAX_ATTRIBUTES * OMEGA_MAX_KEY_LEN];
        memset(keys, 0, sizeof(keys));
        for (uint16_t i = 0; i < n_attrs; ++i) {
            memcpy(&keys[i * OMEGA_MAX_KEY_LEN], obj->attributes[i].key, OMEGA_MAX_KEY_LEN);
        }
        if (omega2_om_canon_sort_attr(&r, keys, sizeof(keys), n_attrs, attr_indices, OMEGA_MAX_ATTRIBUTES) != OMEGA_OK) abort();
        if ((int64_t)r != 0) return -1;
    }
    if (put_u16_be(out_buf, &pos, max_len, n_attrs) != 0) return -1;
    for (uint16_t i = 0; i < n_attrs; ++i) {
        const OmegaAttribute *attr = &obj->attributes[attr_indices[i]];
        size_t klen = strlen(attr->key);
        if (klen > 255) return -1;
        if (pos + 1 + klen + 2 + attr->val_len > max_len) return -1;
        out_buf[pos++] = (uint8_t)klen;
        memcpy(&out_buf[pos], attr->key, klen);
        pos += klen;
        if (put_u16_be(out_buf, &pos, max_len, attr->val_len) != 0) return -1;
        if (attr->val_len > 0) {
            memcpy(&out_buf[pos], attr->value, attr->val_len);
            pos += attr->val_len;
        }
    }

    /* 3. Relations (canonical sort in OM-2) */
    uint16_t n_rels = obj->rel_count;
    if (n_rels > OMEGA_MAX_RELATIONS) return -1;
    uint16_t rel_indices[OMEGA_MAX_RELATIONS] = {0};
    if (n_rels > 0) {
        uint16_t rkinds[OMEGA_MAX_RELATIONS] = {0};
        uint8_t rtgts[OMEGA_MAX_RELATIONS * OMEGA_ID_BYTES];
        memset(rtgts, 0, sizeof(rtgts));
        for (uint16_t i = 0; i < n_rels; ++i) {
            rkinds[i] = obj->relations[i].kind;
            memcpy(&rtgts[i * OMEGA_ID_BYTES], obj->relations[i].target_id.bytes, OMEGA_ID_BYTES);
        }
        if (omega2_om_canon_sort_rel(&r, rkinds, OMEGA_MAX_RELATIONS, rtgts, sizeof(rtgts), n_rels, rel_indices, OMEGA_MAX_RELATIONS) != OMEGA_OK) abort();
        if ((int64_t)r != 0) return -1;
    }
    if (put_u16_be(out_buf, &pos, max_len, n_rels) != 0) return -1;
    for (uint16_t i = 0; i < n_rels; ++i) {
        const OmegaRelation *rel = &obj->relations[rel_indices[i]];
        if (pos + 2 + OMEGA_ID_BYTES > max_len) return -1;
        if (put_u16_be(out_buf, &pos, max_len, rel->kind) != 0) return -1;
        memcpy(&out_buf[pos], rel->target_id.bytes, OMEGA_ID_BYTES);
        pos += OMEGA_ID_BYTES;
    }

    /* 4. Constraints (canonical sort in OM-2) */
    uint16_t n_consts = obj->const_count;
    if (n_consts > OMEGA_MAX_CONSTRAINTS) return -1;
    uint16_t const_indices[OMEGA_MAX_CONSTRAINTS] = {0};
    if (n_consts > 0) {
        uint16_t cmeta[OMEGA_MAX_CONSTRAINTS * 2] = {0};
        uint8_t cpays[OMEGA_MAX_CONSTRAINTS * 128];
        memset(cpays, 0, sizeof(cpays));
        for (uint16_t i = 0; i < n_consts; ++i) {
            cmeta[i * 2] = obj->constraints[i].kind;
            cmeta[i * 2 + 1] = obj->constraints[i].payload_len;
            uint16_t cl = obj->constraints[i].payload_len <= 128 ? obj->constraints[i].payload_len : 128;
            if (cl > 0) memcpy(&cpays[i * 128], obj->constraints[i].payload, cl);
        }
        if (omega2_om_canon_sort_const(&r, cmeta, OMEGA_MAX_CONSTRAINTS * 2, cpays, sizeof(cpays), n_consts, const_indices, OMEGA_MAX_CONSTRAINTS) != OMEGA_OK) abort();
        if ((int64_t)r != 0) return -1;
    }
    if (put_u16_be(out_buf, &pos, max_len, n_consts) != 0) return -1;
    for (uint16_t i = 0; i < n_consts; ++i) {
        const OmegaConstraint *c = &obj->constraints[const_indices[i]];
        if (pos + 4 + c->payload_len > max_len) return -1;
        if (put_u16_be(out_buf, &pos, max_len, c->kind) != 0) return -1;
        if (put_u16_be(out_buf, &pos, max_len, c->payload_len) != 0) return -1;
        if (c->payload_len > 0) {
            memcpy(&out_buf[pos], c->payload, c->payload_len);
            pos += c->payload_len;
        }
    }

    /* 5. Payload */
    if (pos + 4 + obj->payload_len > max_len) return -1;
    if (put_u32_be(out_buf, &pos, max_len, obj->payload_len) != 0) return -1;
    if (obj->payload_len > 0) {
        memcpy(&out_buf[pos], obj->payload, obj->payload_len);
        pos += obj->payload_len;
    }

    *out_len = pos;
    return 0;
}

int omega_compute_semantic_id(OmegaObject *obj) {
    if (!obj) return -1;
    uint8_t canon_buf[4096];
    size_t canon_len = 0;
    if (omega_canonical_encode(obj, canon_buf, sizeof(canon_buf), &canon_len) != 0) {
        return -1;
    }
    sha256_hash(canon_buf, canon_len, obj->id.bytes);
    obj->has_id = true;
    return 0;
}
