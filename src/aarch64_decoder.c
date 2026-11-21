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

/* AArch64 decoder and code-buffer validator backed by pure seeded OM-2 (om/aarch64/aarch64_om2.om).
 * All instruction decoding and validation messages execute in Omega via omega2_a64decode /
 * omega2_a64validate. No decode or validation logic lives in C. */
#include "aarch64_decoder.h"
#include "omega_native.h"
#include <stdlib.h>
#include <string.h>

int aarch64_decode_instruction(uint32_t insn, DecodedInsn *out_dec) {
    if (!out_dec) return -1;
    uint64_t cells[9] = {0};
    uint64_t rc = 0;
    if (omega2_a64decode(&rc, (uint64_t)insn, cells, 9) != OMEGA_OK) abort();
    memset(out_dec, 0, sizeof(DecodedInsn));
    out_dec->op = (DecodedOp)cells[0];
    out_dec->sf = (cells[1] != 0);
    out_dec->rd = (uint8_t)cells[2];
    out_dec->rn = (uint8_t)cells[3];
    out_dec->rm = (uint8_t)cells[4];
    out_dec->imm16 = (uint16_t)cells[5];
    out_dec->hw = (uint8_t)cells[6];
    out_dec->branch_imm = (int32_t)cells[7];
    out_dec->cond = (Aarch64Cond)cells[8];
    return (int)(int64_t)rc;
}

int aarch64_validate_code_buffer(const uint8_t *code, size_t len, char *err_msg, size_t err_msg_len) {
    uint8_t dummy_code[4] = {0};
    uint8_t dummy_msg[1] = {0};
    const uint8_t *cptr = (code && len > 0) ? code : dummy_code;
    uint64_t clen = (code && len > 0) ? (uint64_t)len : 4ULL;
    uint64_t pass_n = code ? (uint64_t)len : 0ULL;
    uint8_t *mptr = (err_msg && err_msg_len > 0) ? (uint8_t *)err_msg : dummy_msg;
    uint64_t mcap = (err_msg && err_msg_len > 0) ? (uint64_t)err_msg_len : 1ULL;
    uint64_t mlim = err_msg ? (uint64_t)err_msg_len : 0ULL;
    uint64_t rc = 0;
    if (omega2_a64validate(&rc, cptr, clen, pass_n, mptr, mcap, mlim) != OMEGA_OK) abort();
    return (int)(int64_t)rc;
}
