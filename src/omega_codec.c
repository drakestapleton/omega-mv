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

/* Binary graph codec backed by pure seeded OM-2 (om/visor/codec_om2.om & canonical_om2.om). */
#include "omega_codec.h"
#include "omega_canonical.h"
#include "omega_core.h"
#include "omega_validate.h"
#include "omega_native.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>

static uint16_t rd_u16_be(const uint8_t *buf, size_t buf_len, size_t pos) {
    uint64_t r = 0;
    if (omega2_om_codec_u16_rd(&r, buf, buf_len, pos) != OMEGA_OK) abort();
    return (uint16_t)r;
}

static uint32_t rd_u32_be(const uint8_t *buf, size_t buf_len, size_t pos) {
    uint64_t r = 0;
    if (omega2_om_codec_u32_rd(&r, buf, buf_len, pos) != OMEGA_OK) abort();
    return (uint32_t)r;
}

int omega_graph_serialize_binary(const OmegaGraph *graph, uint8_t *out_buf, size_t max_len, size_t *out_len) {
    if (!graph || !out_buf || !out_len || max_len == 0) return -1;
    uint64_t r = 0;
    if (omega2_om_codec_hdr_enc(&r, graph->object_count, out_buf, max_len, max_len) != OMEGA_OK) abort();
    if ((int64_t)r < 0) return -1;
    size_t pos = (size_t)r;

    for (uint16_t i = 0; i < graph->object_count; ++i) {
        uint8_t cbuf[4096];
        size_t clen = 0;
        if (omega_canonical_encode(&graph->objects[i], cbuf, sizeof(cbuf), &clen) != 0) {
            return -1;
        }
        if (pos + 4 + clen > max_len) return -1;
        if (omega2_om_canon_write_u32be(&r, (uint64_t)clen, out_buf, max_len, pos, max_len) != OMEGA_OK) abort();
        if ((int64_t)r < 0) return -1;
        pos = (size_t)r;
        memcpy(&out_buf[pos], cbuf, clen);
        pos += clen;
    }

    *out_len = pos;
    return 0;
}

int omega_graph_deserialize_binary(const uint8_t *in_buf, size_t in_len, OmegaGraph *out_graph) {
    if (!in_buf || !out_graph || in_len < 6) return -1;
    uint64_t r = 0;
    if (omega2_om_codec_hdr_dec(&r, in_buf, in_len, in_len, OMEGA_MAX_GRAPH_OBJECTS) != OMEGA_OK) abort();
    if ((int64_t)r < 0) return -1;
    uint16_t count = (uint16_t)r;
    size_t pos = 6;

    memset(out_graph, 0, sizeof(OmegaGraph));

    for (uint16_t i = 0; i < count; ++i) {
        if (pos + 4 > in_len) return -1;
        uint32_t clen = rd_u32_be(in_buf, in_len, pos);
        pos += 4;
        if (pos + clen > in_len || clen < 6) return -1;

        if (omega2_om_codec_obj_hdr_chk(&r, in_buf, in_len, pos, clen) != OMEGA_OK) abort();
        if ((int64_t)r < 0) return -1;

        const uint8_t *cbuf = &in_buf[pos];
        OmegaObject *obj = &out_graph->objects[out_graph->object_count++];
        obj->kind = (SemanticKind)r;
        size_t cpos = 6;

        if (cpos + 2 > clen) return -1;
        obj->attr_count = rd_u16_be(cbuf, clen, cpos);
        cpos += 2;
        if (obj->attr_count > OMEGA_MAX_ATTRIBUTES) return -1;
        for (uint16_t a = 0; a < obj->attr_count; ++a) {
            if (cpos + 1 > clen) return -1;
            uint8_t klen = cbuf[cpos++];
            if (klen >= OMEGA_MAX_KEY_LEN) return -1;
            if (cpos + klen + 2 > clen) return -1;
            memcpy(obj->attributes[a].key, &cbuf[cpos], klen);
            obj->attributes[a].key[klen] = '\0';
            cpos += klen;
            obj->attributes[a].val_len = rd_u16_be(cbuf, clen, cpos);
            cpos += 2;
            if (obj->attributes[a].val_len > OMEGA_MAX_VAL_LEN) return -1;
            if (cpos + obj->attributes[a].val_len > clen) return -1;
            memcpy(obj->attributes[a].value, &cbuf[cpos], obj->attributes[a].val_len);
            cpos += obj->attributes[a].val_len;
        }

        if (cpos + 2 > clen) return -1;
        obj->rel_count = rd_u16_be(cbuf, clen, cpos);
        cpos += 2;
        if (obj->rel_count > OMEGA_MAX_RELATIONS) return -1;
        for (uint16_t ri = 0; ri < obj->rel_count; ++ri) {
            if (cpos + 2 + OMEGA_ID_BYTES > clen) return -1;
            obj->relations[ri].kind = rd_u16_be(cbuf, clen, cpos);
            cpos += 2;
            memcpy(obj->relations[ri].target_id.bytes, &cbuf[cpos], OMEGA_ID_BYTES);
            cpos += OMEGA_ID_BYTES;
        }

        if (cpos + 2 > clen) return -1;
        obj->const_count = rd_u16_be(cbuf, clen, cpos);
        cpos += 2;
        if (obj->const_count > OMEGA_MAX_CONSTRAINTS) return -1;
        for (uint16_t c = 0; c < obj->const_count; ++c) {
            if (cpos + 4 > clen) return -1;
            obj->constraints[c].kind = rd_u16_be(cbuf, clen, cpos);
            cpos += 2;
            obj->constraints[c].payload_len = rd_u16_be(cbuf, clen, cpos);
            cpos += 2;
            if (obj->constraints[c].payload_len > sizeof obj->constraints[c].payload) return -1;
            if (cpos + obj->constraints[c].payload_len > clen) return -1;
            memcpy(obj->constraints[c].payload, &cbuf[cpos], obj->constraints[c].payload_len);
            cpos += obj->constraints[c].payload_len;
        }

        if (cpos + 4 > clen) return -1;
        obj->payload_len = rd_u32_be(cbuf, clen, cpos);
        cpos += 4;
        if (obj->payload_len > OMEGA_MAX_PAYLOAD_LEN) return -1;
        if (cpos + obj->payload_len > clen) return -1;
        memcpy(obj->payload, &cbuf[cpos], obj->payload_len);
        cpos += obj->payload_len;
        if (obj->kind == KIND_EFFECT) {
            EffectPayload eff;
            if (omega_effect_read(obj, &eff) != OMEGA_EFFECT_OK) return -1;
        }

        omega_compute_semantic_id(obj);
        pos += clen;
    }

    return 0;
}

int omega_graph_format_text(const OmegaGraph *graph, char *out_str, size_t max_len) {
    if (!graph || !out_str || max_len == 0) return -1;
    size_t pos = 0;

    int w = snprintf(out_str + pos, max_len - pos, "// OMEGA NON-CANONICAL TEXTUAL FORM\n// Objects: %u\n\n", graph->object_count);
    if (w < 0 || (size_t)w >= max_len - pos) return -1;
    pos += (size_t)w;

    for (uint16_t i = 0; i < graph->object_count; ++i) {
        const OmegaObject *obj = &graph->objects[i];
        char hex[65];
        omega_hex_semantic_id(&obj->id, hex);

        switch (obj->kind) {
            case KIND_TYPE: {
                const TypePayload *tp = (const TypePayload*)obj->payload;
                if (tp->tag == TYPE_UNSIGNED_INT) {
                    w = snprintf(out_str + pos, max_len - pos, "type U%u = UNSIGNED_INTEGER(%u); // id=%s\n", tp->width, tp->width, hex);
                } else if (tp->tag == TYPE_BOOL) {
                    w = snprintf(out_str + pos, max_len - pos, "type Bool = BOOL; // id=%s\n", hex);
                } else {
                    w = snprintf(out_str + pos, max_len - pos, "type Tag%u; // id=%s\n", tp->tag, hex);
                }
                break;
            }
            case KIND_VALUE: {
                const ValuePayload *vp = (const ValuePayload*)obj->payload;
                uint64_t v = 0;
                for (int b = 0; b < vp->byte_len; ++b) {
                    v = (v << 8) | vp->bytes[b];
                }
                w = snprintf(out_str + pos, max_len - pos, "val v_%u = %lu; // id=%s\n", i, (unsigned long)v, hex);
                break;
            }
            case KIND_OPERATION: {
                if (obj->payload_len >= sizeof(OperationPayload)) {
                    const OperationPayload *op = (const OperationPayload*)obj->payload;
                    const char *opname = (op->opcode == OP_ADD) ? "ADD" : (op->opcode == OP_SUB ? "SUB" : "OP");
                    w = snprintf(out_str + pos, max_len - pos, "op %s = %s[WRAP]; // id=%s\n", opname, opname, hex);
                } else if (obj->payload_len >= sizeof(ApplyPayload)) {
                    w = snprintf(out_str + pos, max_len - pos, "apply app_%u; // id=%s\n", i, hex);
                }
                break;
            }
            default:
                w = snprintf(out_str + pos, max_len - pos, "object kind=%u; // id=%s\n", obj->kind, hex);
                break;
        }
        if (w < 0 || (size_t)w >= max_len - pos) return -1;
        pos += (size_t)w;
    }

    return 0;
}

int omega_graph_parse_text(const char *in_str, OmegaGraph *out_graph, char *err_msg, size_t err_msg_len) {
    if (!in_str || !out_graph) {
        snprintf(err_msg, err_msg_len, "Null arguments to parse_text");
        return -1;
    }
    memset(out_graph, 0, sizeof(OmegaGraph));

    const char *p = in_str;
    OmegaObject *u32_type = NULL;
    OmegaObject *val_a = NULL;
    OmegaObject *val_b = NULL;
    OmegaObject *op_add = NULL;
    OmegaObject *op_sub = NULL;

    while (*p) {
        while (*p && isspace((unsigned char)*p)) p++;
        if (!*p) break;
        if (*p == '/' && *(p + 1) == '/') {
            while (*p && *p != '\n') p++;
            continue;
        }

        if (strncmp(p, "type", 4) == 0) {
            if (strstr(p, "UNSIGNED_INTEGER(32)") != NULL) {
                u32_type = omega_build_type_uint(out_graph, 32);
            }
            while (*p && *p != '\n') p++;
        } else if (strncmp(p, "val", 3) == 0) {
            const char *eq = strchr(p, '=');
            if (eq && u32_type) {
                unsigned long v = strtoul(eq + 1, NULL, 0);
                if (val_a == NULL) {
                    val_a = omega_build_val_uint(out_graph, &u32_type->id, 32, (uint64_t)v);
                } else if (val_b == NULL) {
                    val_b = omega_build_val_uint(out_graph, &u32_type->id, 32, (uint64_t)v);
                }
            }
            while (*p && *p != '\n') p++;
        } else if (strncmp(p, "op", 2) == 0) {
            if (strstr(p, "ADD") != NULL && u32_type) {
                op_add = omega_build_op_binary(out_graph, OP_ADD, OVERFLOW_WRAP, &u32_type->id);
            } else if (strstr(p, "SUB") != NULL && u32_type) {
                op_sub = omega_build_op_binary(out_graph, OP_SUB, OVERFLOW_WRAP, &u32_type->id);
            }
            while (*p && *p != '\n') p++;
        } else if (strncmp(p, "apply", 5) == 0) {
            if (op_add && val_a && val_b) {
                omega_build_apply(out_graph, &op_add->id, &val_a->id, &val_b->id);
            } else if (op_sub && val_a && val_b) {
                omega_build_apply(out_graph, &op_sub->id, &val_a->id, &val_b->id);
            }
            while (*p && *p != '\n') p++;
        } else {
            while (*p && *p != '\n') p++;
        }
    }

    return 0;
}
