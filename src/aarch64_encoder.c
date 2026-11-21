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

/* AArch64 legacy instruction encoder backed by pure seeded OM-2 (om/aarch64/aarch64_om2.om).
 * All architectural range checks, instruction word formulas, and little-endian buffer writes
 * execute in Omega via omega2_a64* / omega2_a64put. This C file only translates negative
 * field-refusal codes to the legacy abort contract. */
#include "aarch64_encoder.h"
#include "omega_native.h"
#include <stdio.h>
#include <stdlib.h>

static void refuse(const char *emitter, const char *field, long long value) __attribute__((noreturn));
static void refuse(const char *emitter, const char *field, long long value) {
    fprintf(stderr, "A64_LEGACY_FIELD_OUT_OF_RANGE %s %s=%lld\n", emitter, field, value);
    fflush(stderr);
    abort();
}

static int finish_emit(uint8_t *buf, size_t *pos, size_t max_len,
                       const char *emitter, const char *const *fields, const long long *vals,
                       uint32_t st, uint64_t raw) {
    if (st != OMEGA_OK) abort();
    int64_t w = (int64_t)raw;
    if (w <= -2) {
        int idx = (int)(-w - 2);
        refuse(emitter, fields[idx], vals[idx]);
    }
    uint8_t dummy[4] = {0};
    uint8_t *target = (buf && max_len > 0) ? buf : dummy;
    uint64_t target_len = (buf && max_len > 0) ? (uint64_t)max_len : 4ULL;
    uint64_t state[2] = { (uint64_t)*pos, (uint64_t)max_len };
    uint64_t rc = 0;
    if (omega2_a64put(&rc, target, target_len, state, 2, (uint64_t)w) != OMEGA_OK) abort();
    *pos = (size_t)state[0];
    return (int)(int64_t)rc;
}

#define EMIT_RRR(fn, omfn) \
int fn(uint8_t *buf, size_t *pos, size_t max_len, bool sf, uint8_t rd, uint8_t rn, uint8_t rm) { \
    const char *f[] = { "sf", "rd", "rn", "rm" }; \
    const long long v[] = { (long long)sf, (long long)rd, (long long)rn, (long long)rm }; \
    uint64_t r = 0; \
    uint32_t st = omfn(&r, (uint64_t)sf, (uint64_t)rd, (uint64_t)rn, (uint64_t)rm); \
    return finish_emit(buf, pos, max_len, __func__, f, v, st, r); \
}

EMIT_RRR(aarch64_emit_add_reg, omega2_a64addreg)
EMIT_RRR(aarch64_emit_sub_reg, omega2_a64subreg)
EMIT_RRR(aarch64_emit_mul_reg, omega2_a64mulreg)
EMIT_RRR(aarch64_emit_and_reg, omega2_a64andreg)
EMIT_RRR(aarch64_emit_orr_reg, omega2_a64orrreg)
EMIT_RRR(aarch64_emit_eor_reg, omega2_a64eorreg)
EMIT_RRR(aarch64_emit_subs_reg, omega2_a64subsreg)

int aarch64_emit_mov_reg(uint8_t *buf, size_t *pos, size_t max_len, bool sf, uint8_t rd, uint8_t rm) {
    const char *f[] = { "sf", "rd", "rm" };
    const long long v[] = { (long long)sf, (long long)rd, (long long)rm };
    uint64_t r = 0;
    uint32_t st = omega2_a64movreg(&r, (uint64_t)sf, (uint64_t)rd, (uint64_t)rm);
    return finish_emit(buf, pos, max_len, __func__, f, v, st, r);
}

int aarch64_emit_movz(uint8_t *buf, size_t *pos, size_t max_len, bool sf, uint8_t rd, uint16_t imm16, uint8_t shift) {
    const char *f[] = { "sf", "rd", "imm16", "shift" };
    const long long v[] = { (long long)sf, (long long)rd, (long long)imm16, (long long)shift };
    uint64_t r = 0;
    uint32_t st = omega2_a64movz(&r, (uint64_t)sf, (uint64_t)rd, (uint64_t)imm16, (uint64_t)shift);
    return finish_emit(buf, pos, max_len, __func__, f, v, st, r);
}

int aarch64_emit_movk(uint8_t *buf, size_t *pos, size_t max_len, bool sf, uint8_t rd, uint16_t imm16, uint8_t shift) {
    const char *f[] = { "sf", "rd", "imm16", "shift" };
    const long long v[] = { (long long)sf, (long long)rd, (long long)imm16, (long long)shift };
    uint64_t r = 0;
    uint32_t st = omega2_a64movk(&r, (uint64_t)sf, (uint64_t)rd, (uint64_t)imm16, (uint64_t)shift);
    return finish_emit(buf, pos, max_len, __func__, f, v, st, r);
}

int aarch64_emit_ret(uint8_t *buf, size_t *pos, size_t max_len) {
    uint64_t r = 0;
    uint32_t st = omega2_a64ret(&r);
    return finish_emit(buf, pos, max_len, __func__, NULL, NULL, st, r);
}

int aarch64_emit_b(uint8_t *buf, size_t *pos, size_t max_len, int32_t imm26) {
    const char *f[] = { "imm26" };
    const long long v[] = { (long long)imm26 };
    uint64_t r = 0;
    uint32_t st = omega2_a64b(&r, (uint64_t)(int64_t)imm26);
    return finish_emit(buf, pos, max_len, __func__, f, v, st, r);
}

int aarch64_emit_b_cond(uint8_t *buf, size_t *pos, size_t max_len, Aarch64Cond cond, int32_t imm19) {
    const char *f[] = { "cond", "imm19" };
    const long long v[] = { (long long)(int)cond, (long long)imm19 };
    uint64_t r = 0;
    uint32_t st = omega2_a64bcond(&r, (uint64_t)(int64_t)(int)cond, (uint64_t)(int64_t)imm19);
    return finish_emit(buf, pos, max_len, __func__, f, v, st, r);
}

int aarch64_emit_cbz(uint8_t *buf, size_t *pos, size_t max_len, bool sf, uint8_t rt, int32_t imm19) {
    const char *f[] = { "sf", "rt", "imm19" };
    const long long v[] = { (long long)sf, (long long)rt, (long long)imm19 };
    uint64_t r = 0;
    uint32_t st = omega2_a64cbz(&r, (uint64_t)sf, (uint64_t)rt, (uint64_t)(int64_t)imm19);
    return finish_emit(buf, pos, max_len, __func__, f, v, st, r);
}

int aarch64_emit_cbnz(uint8_t *buf, size_t *pos, size_t max_len, bool sf, uint8_t rt, int32_t imm19) {
    const char *f[] = { "sf", "rt", "imm19" };
    const long long v[] = { (long long)sf, (long long)rt, (long long)imm19 };
    uint64_t r = 0;
    uint32_t st = omega2_a64cbnz(&r, (uint64_t)sf, (uint64_t)rt, (uint64_t)(int64_t)imm19);
    return finish_emit(buf, pos, max_len, __func__, f, v, st, r);
}

int aarch64_emit_adr(uint8_t *buf, size_t *pos, size_t max_len, uint8_t rd, int32_t imm21) {
    const char *f[] = { "rd", "imm21" };
    const long long v[] = { (long long)rd, (long long)imm21 };
    uint64_t r = 0;
    uint32_t st = omega2_a64adr(&r, (uint64_t)rd, (uint64_t)(int64_t)imm21);
    return finish_emit(buf, pos, max_len, __func__, f, v, st, r);
}

int aarch64_emit_ldr_uoff(uint8_t *buf, size_t *pos, size_t max_len, bool sf, uint8_t rt, uint8_t rn, uint16_t uoff) {
    const char *f[] = { "sf", "rt", "rn", "uoff" };
    const long long v[] = { (long long)sf, (long long)rt, (long long)rn, (long long)uoff };
    uint64_t r = 0;
    uint32_t st = omega2_a64ldruoff(&r, (uint64_t)sf, (uint64_t)rt, (uint64_t)rn, (uint64_t)uoff);
    return finish_emit(buf, pos, max_len, __func__, f, v, st, r);
}

int aarch64_emit_str_uoff(uint8_t *buf, size_t *pos, size_t max_len, bool sf, uint8_t rt, uint8_t rn, uint16_t uoff) {
    const char *f[] = { "sf", "rt", "rn", "uoff" };
    const long long v[] = { (long long)sf, (long long)rt, (long long)rn, (long long)uoff };
    uint64_t r = 0;
    uint32_t st = omega2_a64struoff(&r, (uint64_t)sf, (uint64_t)rt, (uint64_t)rn, (uint64_t)uoff);
    return finish_emit(buf, pos, max_len, __func__, f, v, st, r);
}

int aarch64_emit_ldrb_uoff(uint8_t *buf, size_t *pos, size_t max_len, uint8_t rt, uint8_t rn, uint16_t uoff) {
    const char *f[] = { "rt", "rn", "uoff" };
    const long long v[] = { (long long)rt, (long long)rn, (long long)uoff };
    uint64_t r = 0;
    uint32_t st = omega2_a64ldrbuoff(&r, (uint64_t)rt, (uint64_t)rn, (uint64_t)uoff);
    return finish_emit(buf, pos, max_len, __func__, f, v, st, r);
}

int aarch64_emit_strb_uoff(uint8_t *buf, size_t *pos, size_t max_len, uint8_t rt, uint8_t rn, uint16_t uoff) {
    const char *f[] = { "rt", "rn", "uoff" };
    const long long v[] = { (long long)rt, (long long)rn, (long long)uoff };
    uint64_t r = 0;
    uint32_t st = omega2_a64strbuoff(&r, (uint64_t)rt, (uint64_t)rn, (uint64_t)uoff);
    return finish_emit(buf, pos, max_len, __func__, f, v, st, r);
}

int aarch64_emit_ldr_post(uint8_t *buf, size_t *pos, size_t max_len, uint8_t rt, uint8_t rn, int16_t simm9) {
    const char *f[] = { "rt", "rn", "simm9" };
    const long long v[] = { (long long)rt, (long long)rn, (long long)simm9 };
    uint64_t r = 0;
    uint32_t st = omega2_a64ldrpost(&r, (uint64_t)rt, (uint64_t)rn, (uint64_t)(int64_t)simm9);
    return finish_emit(buf, pos, max_len, __func__, f, v, st, r);
}

int aarch64_emit_str_post(uint8_t *buf, size_t *pos, size_t max_len, uint8_t rt, uint8_t rn, int16_t simm9) {
    const char *f[] = { "rt", "rn", "simm9" };
    const long long v[] = { (long long)rt, (long long)rn, (long long)simm9 };
    uint64_t r = 0;
    uint32_t st = omega2_a64strpost(&r, (uint64_t)rt, (uint64_t)rn, (uint64_t)(int64_t)simm9);
    return finish_emit(buf, pos, max_len, __func__, f, v, st, r);
}

int aarch64_emit_ldr_x_post(uint8_t *buf, size_t *pos, size_t max_len, uint8_t rt, uint8_t rn, int16_t simm9) {
    const char *f[] = { "rt", "rn", "simm9" };
    const long long v[] = { (long long)rt, (long long)rn, (long long)simm9 };
    uint64_t r = 0;
    uint32_t st = omega2_a64ldrxpost(&r, (uint64_t)rt, (uint64_t)rn, (uint64_t)(int64_t)simm9);
    return finish_emit(buf, pos, max_len, __func__, f, v, st, r);
}

int aarch64_emit_str_x_post(uint8_t *buf, size_t *pos, size_t max_len, uint8_t rt, uint8_t rn, int16_t simm9) {
    const char *f[] = { "rt", "rn", "simm9" };
    const long long v[] = { (long long)rt, (long long)rn, (long long)simm9 };
    uint64_t r = 0;
    uint32_t st = omega2_a64strxpost(&r, (uint64_t)rt, (uint64_t)rn, (uint64_t)(int64_t)simm9);
    return finish_emit(buf, pos, max_len, __func__, f, v, st, r);
}

int aarch64_emit_subs_imm(uint8_t *buf, size_t *pos, size_t max_len, bool sf, uint8_t rd, uint8_t rn, uint16_t imm12) {
    const char *f[] = { "sf", "rd", "rn", "imm12" };
    const long long v[] = { (long long)sf, (long long)rd, (long long)rn, (long long)imm12 };
    uint64_t r = 0;
    uint32_t st = omega2_a64subsimm(&r, (uint64_t)sf, (uint64_t)rd, (uint64_t)rn, (uint64_t)imm12);
    return finish_emit(buf, pos, max_len, __func__, f, v, st, r);
}
