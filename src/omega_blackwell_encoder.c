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

#include "omega_blackwell_encoder.h"
#include "omega_native.h"
#include "sha256.h"
#include <string.h>

int omega_blackwell_encode_vecadd(uint8_t *code_buf, size_t max_len, size_t *out_len) {
    if (!code_buf || max_len < OMEGA_BW_VECADD_CODE_SIZE) return -1;
    uint64_t written = 0;
    if (omega2_bw_encode_vecadd(&written, code_buf, OMEGA_BW_VECADD_CODE_SIZE) != OMEGA_OK ||
        written != OMEGA_BW_VECADD_CODE_SIZE) {
        return -1;
    }
    if (out_len) *out_len = OMEGA_BW_VECADD_CODE_SIZE;
    return 0;
}

int omega_blackwell_compute_code_digest(const uint8_t *code_buf, size_t len, uint8_t *out_digest) {
    if (!code_buf || len == 0 || !out_digest) return -1;
    sha256_ctx ctx;
    sha256_init(&ctx);
    sha256_update(&ctx, code_buf, len);
    sha256_final(&ctx, out_digest);
    return 0;
}

static uint32_t read_le32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

int omega_blackwell_verify_encoder_fixtures(void) {
    uint8_t code_buf[OMEGA_BW_VECADD_CODE_SIZE];
    size_t out_len = 0;
    if (omega_blackwell_encode_vecadd(code_buf, sizeof(code_buf), &out_len) != 0) {
        return -1;
    }
    if (out_len != OMEGA_BW_VECADD_CODE_SIZE) {
        return -1;
    }

    uint8_t digest[32];
    if (omega_blackwell_compute_code_digest(code_buf, out_len, digest) != 0) {
        return -1;
    }

    static const char HEXDIGITS[] = "0123456789abcdef";
    char hex[65];
    for (int i = 0; i < 32; i++) { /* no sprintf: this file is part of the freestanding link target */
        hex[i * 2] = HEXDIGITS[digest[i] >> 4];
        hex[i * 2 + 1] = HEXDIGITS[digest[i] & 0x0f];
    }
    hex[64] = 0;

    if (strcmp(hex, OMEGA_BW_VECADD_EXPECTED_SHA256) != 0) {
        return -1;
    }

    /* Verify critical instruction patterns: */
    /* 1. S2R R9, SR_CTAID.X */
    if (read_le32(code_buf + 1 * 16) != 0x00097919) return -1;
    /* 2. S2R R0, SR_TID.X */
    if (read_le32(code_buf + 3 * 16) != 0x00007919) return -1;
    /* 3. IADD3 R9, PT, PT, R2, R5, RZ */
    if (read_le32(code_buf + 17 * 16) != 0x02097210) return -1;
    /* 4. STG.E desc[UR4][R6.64], R9 */
    if (read_le32(code_buf + 18 * 16) != 0x06007986) return -1;

    return 0;
}
