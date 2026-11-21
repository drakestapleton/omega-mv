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

/* Structural, differential, and algebraic property verification backed by pure seeded OM-2
 * (om/visor/verify_om2.om, om/visor/validate_om2.om, om/aarch64/aarch64_om2.om). */
#include "omega_verify.h"
#include "omega_validate.h"
#include "omega_canonical.h"
#include "omega_core.h"
#include "aarch64_decoder.h"
#include "omega_exec.h"
#include "omega_native.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

int omega_verify_v0_structural(const OmegaGraph *graph, const RealizationObject *real, VerifyReport *report) {
    if (!report) return -1;
    memset(report, 0, sizeof(VerifyReport));
    report->tier = VERIFY_TIER_V0;
    report->passed = true;

    if (graph) {
        char err[256];
        report->check_count++;
        if (omega_validate_graph(graph, err, sizeof(err)) != 0) {
            report->passed = false;
            report->fail_count++;
            snprintf(report->error_detail, sizeof(report->error_detail), "V0 Graph Validation Failed: %.200s", err);
            return -1;
        }
        report->check_count++;
        if (graph->object_count == 0) {
            report->passed = false;
            report->fail_count++;
            snprintf(report->error_detail, sizeof(report->error_detail), "V0 Graph Validation Failed: Empty graph");
            return -1;
        }
    }

    if (real) {
        uint64_t r = 0;
        if (omega2_om_ver_v0_real(&r, (uint64_t)real->target_profile, (uint64_t)real->code_len,
                                  AARCH64_MAX_CODE_BYTES, real->has_id ? 1ULL : 0ULL) != OMEGA_OK) abort();
        report->check_count++;
        if ((int64_t)r == 1) {
            report->passed = false;
            report->fail_count++;
            snprintf(report->error_detail, sizeof(report->error_detail),
                     "V0 Realization Profile Failed: Unknown profile 0x%02x", real->target_profile);
            return -1;
        }
        report->check_count++;
        if ((int64_t)r == 2) {
            report->passed = false;
            report->fail_count++;
            snprintf(report->error_detail, sizeof(report->error_detail),
                     "V0 Realization Code Bounds Failed: Invalid length %zu bytes", real->code_len);
            return -1;
        }

        report->check_count++;
        char dec_err[256];
        if (aarch64_validate_code_buffer(real->code_bytes, real->code_len, dec_err, sizeof(dec_err)) != 0) {
            report->passed = false;
            report->fail_count++;
            snprintf(report->error_detail, sizeof(report->error_detail),
                     "V0 Instruction Stream Failed: %.200s", dec_err);
            return -1;
        }

        report->check_count++;
        if ((int64_t)r == 3) {
            report->passed = false;
            report->fail_count++;
            snprintf(report->error_detail, sizeof(report->error_detail),
                     "V0 Realization ID Failed: Object missing REALIZATION_ID");
            return -1;
        }

        RealizationObject check_id = *real;
        bool id_matches = false;
        if (real->has_machine_id) {
            SemanticId triple_id;
            if (omega_realize_compute_triple_id(&real->semantic_id, &real->machine_id, real, &triple_id) == 0 &&
                omega_compare_semantic_id(&triple_id, &real->realization_id) == 0) {
                id_matches = true;
            }
        } else {
            if (omega_compute_realization_id(&check_id) == 0 &&
                omega_compare_semantic_id(&check_id.realization_id, &real->realization_id) == 0) {
                id_matches = true;
            }
        }

        if (!id_matches) {
            report->passed = false;
            report->fail_count++;
            snprintf(report->error_detail, sizeof(report->error_detail),
                     "V0 Realization ID Failed: REALIZATION_ID cryptographic mismatch");
            return -1;
        }
    }

    return 0;
}

int omega_verify_v1_differential(const OmegaGraph *graph, const RealizationObject *real,
                                 const uint64_t *test_inputs, size_t input_triplet_count,
                                 VerifyReport *report) {
    if (!report || !real) return -1;
    (void)graph;
    memset(report, 0, sizeof(VerifyReport));
    report->tier = VERIFY_TIER_V1;
    report->passed = true;

    if (omega_verify_v0_structural(graph, real, report) != 0) {
        return -1;
    }

    report->tier = VERIFY_TIER_V1;
    size_t count = test_inputs ? input_triplet_count : 7;

    for (size_t i = 0; i < count; ++i) {
        uint64_t a = 0, b = 0, c = 0;
        if (test_inputs) {
            a = test_inputs[i * 3];
            b = test_inputs[i * 3 + 1];
            c = test_inputs[i * 3 + 2];
        } else {
            uint64_t vec[3] = {0, 0, 0};
            uint64_t vr = 0;
            if (omega2_om_ver_v1_defvec(&vr, (uint64_t)i, vec, 3) != OMEGA_OK || (int64_t)vr != 0) abort();
            a = vec[0]; b = vec[1]; c = vec[2];
        }

        uint64_t expected = 0;
        if (omega2_om_ver_v1_ref(&expected, a, b, c) != OMEGA_OK) abort();

        uint64_t observed = 0;
        report->check_count++;
        int rc = omega_exec_native_f3(real, a, b, c, &observed);
        if (rc != 0) {
            report->passed = false;
            report->fail_count++;
            snprintf(report->error_detail, sizeof(report->error_detail),
                     "V1 Differential Execution Failed: Vector %zu (a=%lu, b=%lu, c=%lu) returned rc=%d",
                     i, (unsigned long)a, (unsigned long)b, (unsigned long)c, rc);
            return -1;
        }

        if (observed != expected) {
            report->passed = false;
            report->fail_count++;
            snprintf(report->error_detail, sizeof(report->error_detail),
                     "V1 Differential Mismatch: Vector %zu (a=%lu, b=%lu, c=%lu) expected=%lu observed=%lu",
                     i, (unsigned long)a, (unsigned long)b, (unsigned long)c,
                     (unsigned long)expected, (unsigned long)observed);
            return -1;
        }
    }

    return 0;
}

int omega_verify_v2_properties(const OmegaGraph *graph, const RealizationObject *real, VerifyReport *report) {
    if (!report) return -1;
    (void)graph;
    (void)real;
    memset(report, 0, sizeof(VerifyReport));
    report->tier = VERIFY_TIER_V2;
    report->passed = true;

    uint64_t info[4] = {0, 0, 0, 0};
    uint64_t r = 0;
    if (omega2_om_ver_v2_props(&r, info, 4) != OMEGA_OK) abort();
    if ((int64_t)r < 0) {
        report->passed = false;
        report->fail_count++;
        snprintf(report->error_detail, sizeof(report->error_detail),
                 "V2 Property Violation kind=%lu op=0x%02lx (%lu, %lu)",
                 (unsigned long)info[0], (unsigned long)info[1],
                 (unsigned long)info[2], (unsigned long)info[3]);
        return -1;
    }
    report->check_count = (uint32_t)r;
    return 0;
}

int omega_verify_pipeline(const OmegaGraph *graph, const RealizationObject *real,
                          VerifyTier max_tier, VerifyReport *report) {
    if (!report) return -1;

    if (omega_verify_v0_structural(graph, real, report) != 0) {
        return -1;
    }
    if (max_tier >= VERIFY_TIER_V1) {
        if (omega_verify_v1_differential(graph, real, NULL, 0, report) != 0) {
            return -1;
        }
    }
    if (max_tier >= VERIFY_TIER_V2) {
        if (omega_verify_v2_properties(graph, real, report) != 0) {
            return -1;
        }
    }
    return 0;
}
