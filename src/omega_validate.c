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

/* Semantic object and graph validator backed by pure seeded OM-2 (om/visor/validate_om2.om). */
#include "omega_validate.h"
#include "omega_core.h"
#include "omega_canonical.h"
#include "omega_native.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

static const OmegaObject* find_object_by_id(const OmegaGraph *graph, const SemanticId *id) {
    if (!graph || !id) return NULL;
    for (uint16_t i = 0; i < graph->object_count; ++i) {
        if (graph->objects[i].has_id && omega_compare_semantic_id(&graph->objects[i].id, id) == 0) {
            return &graph->objects[i];
        }
    }
    return NULL;
}

int omega_validate_object(const OmegaGraph *graph, const OmegaObject *obj, char *err_msg, size_t err_msg_len) {
    uint64_t r = 0;
    if (!obj) {
        snprintf(err_msg, err_msg_len, "Null object pointer");
        return -1;
    }
    if (omega2_om_val_kind(&r, (uint64_t)obj->kind) != OMEGA_OK) abort();
    if ((int64_t)r != 0) {
        snprintf(err_msg, err_msg_len, "Invalid semantic kind tag 0x%02x", obj->kind);
        return -1;
    }

    for (uint16_t i = 0; i < obj->attr_count; ++i) {
        if (strlen(obj->attributes[i].key) == 0) {
            snprintf(err_msg, err_msg_len, "Empty attribute key at index %u", i);
            return -1;
        }
    }

    for (uint16_t i = 0; i < obj->rel_count; ++i) {
        if (omega2_om_val_rel_kind(&r, (uint64_t)obj->relations[i].kind) != OMEGA_OK) abort();
        if ((int64_t)r != 0) {
            snprintf(err_msg, err_msg_len, "Invalid relation kind 0x%04x at index %u", obj->relations[i].kind, i);
            return -1;
        }
        if (graph) {
            const OmegaObject *target = find_object_by_id(graph, &obj->relations[i].target_id);
            if (!target) {
                char hex[65];
                omega_hex_semantic_id(&obj->relations[i].target_id, hex);
                snprintf(err_msg, err_msg_len, "Dangling relation target reference %s", hex);
                return -1;
            }
        }
    }

    for (uint16_t i = 0; i < obj->const_count; ++i) {
        if (omega2_om_val_const_kind(&r, (uint64_t)obj->constraints[i].kind) != OMEGA_OK) abort();
        if ((int64_t)r != 0) {
            snprintf(err_msg, err_msg_len, "Invalid constraint kind 0x%04x at index %u", obj->constraints[i].kind, i);
            return -1;
        }
    }

    switch (obj->kind) {
        case KIND_TYPE: {
            if (obj->payload_len < sizeof(TypePayload)) {
                snprintf(err_msg, err_msg_len, "Type payload length too short (%u bytes)", obj->payload_len);
                return -1;
            }
            const TypePayload *tp = (const TypePayload*)obj->payload;
            if (omega2_om_val_type_fields(&r, (uint64_t)tp->tag, (uint64_t)tp->width, (uint64_t)tp->length) != OMEGA_OK) abort();
            switch ((int64_t)r) {
                case 0: break;
                case 1: snprintf(err_msg, err_msg_len, "Invalid type tag 0x%02x", tp->tag); return -1;
                case 2: snprintf(err_msg, err_msg_len, "Unsigned integer width %u out of bounds [1..256]", tp->width); return -1;
                case 3: snprintf(err_msg, err_msg_len, "Signed integer width %u out of bounds [2..256]", tp->width); return -1;
                case 4: snprintf(err_msg, err_msg_len, "FP32 width %u is not 32", tp->width); return -1;
                case 5: snprintf(err_msg, err_msg_len, "Bitvector width %u out of bounds [1..256]", tp->width); return -1;
                case 6: snprintf(err_msg, err_msg_len, "Sequence length %u exceeds 65535", tp->length); return -1;
                default: return -1;
            }
            if (tp->tag == TYPE_SEQUENCE && graph) {
                const OmegaObject *elem_tp = find_object_by_id(graph, &tp->elem_type);
                if (!elem_tp || elem_tp->kind != KIND_TYPE) {
                    snprintf(err_msg, err_msg_len, "Sequence element type unresolved or not KIND_TYPE");
                    return -1;
                }
            }
            break;
        }
        case KIND_VALUE: {
            if (obj->payload_len < sizeof(ValuePayload)) {
                snprintf(err_msg, err_msg_len, "Value payload length too short (%u bytes)", obj->payload_len);
                return -1;
            }
            const ValuePayload *vp = (const ValuePayload*)obj->payload;
            if (graph) {
                const OmegaObject *tp_obj = find_object_by_id(graph, &vp->type_id);
                if (!tp_obj || tp_obj->kind != KIND_TYPE) {
                    snprintf(err_msg, err_msg_len, "Value type_id unresolved or not KIND_TYPE");
                    return -1;
                }
                const TypePayload *tp = (const TypePayload*)tp_obj->payload;
                if (omega2_om_val_val_bytes(&r, (uint64_t)tp->tag, (uint64_t)tp->width, (uint64_t)vp->byte_len) != OMEGA_OK) abort();
                if ((int64_t)r > 0) {
                    snprintf(err_msg, err_msg_len, "Value byte length %u does not match declared type width %u (expected %u bytes)",
                             vp->byte_len, tp->width, (unsigned)r);
                    return -1;
                }
            }
            break;
        }
        case KIND_OPERATION: {
            if (obj->payload_len >= sizeof(OperationPayload)) {
                const OperationPayload *op = (const OperationPayload*)obj->payload;
                if (omega2_om_val_op_fields(&r, (uint64_t)op->opcode, (uint64_t)op->overflow) != OMEGA_OK) abort();
                if ((int64_t)r == 1) {
                    snprintf(err_msg, err_msg_len, "Invalid opcode 0x%02x", op->opcode);
                    return -1;
                }
                if ((int64_t)r == 2) {
                    snprintf(err_msg, err_msg_len, "Operation overflow policy not explicitly declared");
                    return -1;
                }
            } else if (obj->payload_len >= sizeof(ApplyPayload)) {
                const ApplyPayload *app = (const ApplyPayload*)obj->payload;
                if (graph) {
                    const OmegaObject *op_obj = find_object_by_id(graph, &app->op_id);
                    if (!op_obj || op_obj->kind != KIND_OPERATION) {
                        snprintf(err_msg, err_msg_len, "Apply op_id unresolved or not KIND_OPERATION");
                        return -1;
                    }
                    for (uint8_t i = 0; i < app->operand_count; ++i) {
                        const OmegaObject *arg = find_object_by_id(graph, &app->operands[i]);
                        if (!arg || (arg->kind != KIND_VALUE && arg->kind != KIND_OPERATION)) {
                            snprintf(err_msg, err_msg_len, "Apply operand %u unresolved or invalid kind", i);
                            return -1;
                        }
                    }
                }
            }
            break;
        }
        case KIND_EFFECT: {
            EffectPayload eff;
            int erc = omega_effect_read(obj, &eff);
            if (erc != OMEGA_EFFECT_OK) {
                snprintf(err_msg, err_msg_len, "Effect payload refused: %s (%u bytes)",
                         omega_effect_strerror(erc), obj->payload_len);
                return -1;
            }
            break;
        }
        default:
            break;
    }

    return 0;
}

int omega_validate_graph(const OmegaGraph *graph, char *err_msg, size_t err_msg_len) {
    uint64_t r = 0;
    if (!graph) {
        snprintf(err_msg, err_msg_len, "Null graph pointer");
        return -1;
    }
    if (omega2_om_val_graph_count(&r, (uint64_t)graph->object_count, OMEGA_MAX_GRAPH_OBJECTS) != OMEGA_OK) abort();
    if ((int64_t)r == 1) {
        snprintf(err_msg, err_msg_len, "Empty graph (0 objects)");
        return -1;
    }
    if ((int64_t)r == 2) {
        snprintf(err_msg, err_msg_len, "Graph object count %u exceeds maximum %d",
                 graph->object_count, OMEGA_MAX_GRAPH_OBJECTS);
        return -1;
    }

    for (uint16_t i = 0; i < graph->object_count; ++i) {
        if (omega_validate_object(graph, &graph->objects[i], err_msg, err_msg_len) != 0) {
            return -1;
        }
    }

    /* Build adjacency list and run iterative 3-color DFS cycle detection in OM-2 */
    static uint16_t edges[OMEGA_MAX_GRAPH_OBJECTS * 128];
    uint16_t deg[OMEGA_MAX_GRAPH_OBJECTS];
    memset(deg, 0, sizeof(deg));
    for (uint16_t i = 0; i < graph->object_count; ++i) {
        const OmegaObject *obj = &graph->objects[i];
        uint16_t d = 0;
        for (uint16_t ri = 0; ri < obj->rel_count && d < 128; ++ri) {
            for (uint16_t j = 0; j < graph->object_count && d < 128; ++j) {
                if (graph->objects[j].has_id && omega_compare_semantic_id(&graph->objects[j].id, &obj->relations[ri].target_id) == 0) {
                    edges[i * 128 + d++] = j;
                }
            }
        }
        if (obj->kind == KIND_OPERATION && obj->payload_len >= sizeof(ApplyPayload)) {
            const ApplyPayload *app = (const ApplyPayload*)obj->payload;
            for (uint8_t oi = 0; oi < app->operand_count && d < 128; ++oi) {
                for (uint16_t j = 0; j < graph->object_count && d < 128; ++j) {
                    if (graph->objects[j].has_id && omega_compare_semantic_id(&graph->objects[j].id, &app->operands[oi]) == 0) {
                        edges[i * 128 + d++] = (uint16_t)((1U << 9) | j);
                    }
                }
            }
        }
        deg[i] = d;
    }

    uint64_t info[2] = {0, 0};
    if (omega2_om_val_find_cycle(&r, edges, OMEGA_MAX_GRAPH_OBJECTS * 128, deg, OMEGA_MAX_GRAPH_OBJECTS, graph->object_count, info, 2) != OMEGA_OK) abort();
    if ((int64_t)r != 0) {
        if (info[1] == 0) {
            snprintf(err_msg, err_msg_len, "Structural cycle detected involving relation target at object index %u", (unsigned)info[0]);
        } else {
            snprintf(err_msg, err_msg_len, "Structural cycle detected involving operand target at object index %u", (unsigned)info[0]);
        }
        return -1;
    }

    return 0;
}
