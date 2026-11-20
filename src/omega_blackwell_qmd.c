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

#include "omega_blackwell_qmd.h"
#include "omega_native.h"
#include <string.h>

/*
 * Driver constant buffer 0 base template (224 words, 896 bytes).
 * Empirically captured from physical Blackwell GB10 compute channel bring-up.
 */
const uint32_t omega_bw_cbank_driver_template[OMEGA_BW_CBANK_DRIVER_WORDS] = {
    0x26420000, 0x00000003, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x94fe5d00, 0xe811c39b, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x000fffff, 0x00000000,
    0x20000000, 0x00000003, 0x22000000, 0x00000003, 0x24280000, 0x00000003, 0x24010000, 0x00000003,
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000001, 0x00000000, 0x0400c000, 0x00000002, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000400, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x04ba32c8, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000001, 0x00000000, 0x00000000, 0x00000000, 0x00000120, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x25b66900, 0x00000003,
    0x00000001, 0x00000001, 0x00000001, 0x00000000, 0x3f800000, 0x3f800000, 0x3f800000, 0x00000400,
    0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x04ba32c8, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000001, 0x00000000, 0x00000000, 0x00000000, 0x00000120, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x25b66900, 0x00000003,
    0x00000001, 0x00000001, 0x00000001, 0x00000000, 0x3f800000, 0x3f800000, 0x3f800000, 0x00000400,
    0x00000001, 0x00000001, 0x00000001, 0x00000001, 0x00000030, 0x00000000, 0x00000000, 0x01000000,
    0x00000000, 0x0000e9c0, 0x00000000, 0x00000000, 0x00000000, 0x0000e9c0, 0x01000000, 0x0000e9bf,
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x24280380, 0x00000003, 0x2428039c, 0x00000003, 0x00000000, 0x00000000,
    0x00000040, 0x00000001, 0x00000001, 0x00000000, 0x00000001, 0x00000001, 0x00000001, 0x00fffdc0,
};

int omega_blackwell_build_qmd0(uint32_t *qmd0_words, uint64_t qmd0_va, uint64_t qmd1_va) {
    if (!qmd0_words) return -1;
    (void)qmd0_va;
    uint64_t res = 1;
    if (omega2_bw_qmd0(&res, qmd0_words, OMEGA_BW_QMD_WORDS, qmd1_va) != OMEGA_OK || res != 0) return -1;
    return 0;
}

int omega_blackwell_build_qmd1(uint32_t *qmd1_words, const OmegaBlackwellQmdConfig *cfg) {
    if (!qmd1_words || !cfg) return -1;
    const uint64_t m[16] = {
        cfg->code_va, cfg->cbank_va, cfg->scratch_va, cfg->sem_va, cfg->qmd0_va,
        cfg->num_elements, cfg->threads_per_block, cfg->grid_width,
        cfg->threads_x, cfg->threads_y, cfg->grid_x, cfg->grid_y,
        cfg->gpr_count, cfg->shared_bytes, 0, 0
    };
    uint64_t res = 1;
    if (omega2_bw_qmd1(&res, m, 16, qmd1_words, OMEGA_BW_QMD_WORDS) != OMEGA_OK || res != 0) return -1;
    return 0;
}

int omega_blackwell_build_cbank_driver(uint32_t *cbank_words, uint64_t cbank_va) {
    if (!cbank_words) return -1;
    memcpy(cbank_words, omega_bw_cbank_driver_template, sizeof(omega_bw_cbank_driver_template));

    /* Patch driver template addresses with actual cbank_va */
    cbank_words[68] = (uint32_t)(cbank_va >> 32);
    cbank_words[69] = (uint32_t)cbank_va;

    cbank_words[210] = (uint32_t)((cbank_va + 0x380) >> 32);
    cbank_words[211] = (uint32_t)(cbank_va + 0x380);
    cbank_words[212] = (uint32_t)((cbank_va + 0x39c) >> 32);
    cbank_words[213] = (uint32_t)(cbank_va + 0x39c);

    return 0;
}

int omega_blackwell_build_cbank_args(uint32_t *args_words, uint64_t a_va, uint64_t b_va,
                                    uint64_t c_va, uint32_t n) {
    if (!args_words) return -1;

    args_words[0] = (uint32_t)a_va;
    args_words[1] = (uint32_t)(a_va >> 32);
    args_words[2] = (uint32_t)b_va;
    args_words[3] = (uint32_t)(b_va >> 32);
    args_words[4] = (uint32_t)c_va;
    args_words[5] = (uint32_t)(c_va >> 32);
    args_words[6] = n;

    return 0;
}

int omega_blackwell_build_cbank_driver_2d(uint32_t *cbank_words, uint64_t cbank_va,
                                         uint32_t threads_x, uint32_t threads_y,
                                         uint32_t grid_x, uint32_t grid_y) {
    if (!cbank_words) return -1;
    if (omega_blackwell_build_cbank_driver(cbank_words, cbank_va) != 0) return -1;
    if (threads_x > 0) cbank_words[216] = threads_x;
    if (threads_y > 0) cbank_words[217] = threads_y;
    if (grid_x > 0) cbank_words[220] = grid_x;
    if (grid_y > 0) cbank_words[221] = grid_y;
    return 0;
}

int omega_blackwell_build_cbank_args_matmul(uint32_t *args_words, uint64_t a_va, uint64_t b_va,
                                           uint64_t c_va, uint32_t m, uint32_t k, uint32_t n) {
    if (!args_words) return -1;
    args_words[0] = (uint32_t)a_va;
    args_words[1] = (uint32_t)(a_va >> 32);
    args_words[2] = (uint32_t)b_va;
    args_words[3] = (uint32_t)(b_va >> 32);
    args_words[4] = (uint32_t)c_va;
    args_words[5] = (uint32_t)(c_va >> 32);
    args_words[6] = m;
    args_words[7] = k;
    args_words[8] = n;
    args_words[9] = 0;
    return 0;
}

int omega_blackwell_verify_qmd_invariants(const uint32_t *qmd1_words) {
    if (!qmd1_words) return -1;
    uint64_t res = 1;
    if (omega2_bw_qmd_verify(&res, qmd1_words, OMEGA_BW_QMD_WORDS) != OMEGA_OK || res != 0) return -1;
    return 0;
}
