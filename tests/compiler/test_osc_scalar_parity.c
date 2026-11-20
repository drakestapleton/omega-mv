/* SPDX-License-Identifier: Apache-2.0 */
/* Exercise the retired 128-bit interpreter on canonical input independently
 * of both production consumers of the Omega scalar unit. */
#include "osc_interp_reference.c"
#include "omega_api_decl.h"

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

static OscRt runtime;
static Ctx context = {.rt = &runtime};
static unsigned long checks;

static unsigned reference(unsigned ins, unsigned op, OscScalar t, OscScalar other,
                          uint64_t a, uint64_t b, uint64_t *result)
{
    if (setjmp(runtime.jb)) return runtime.trap_code;
    switch (ins) {
    case OSC_I_BIN: *result = do_bin(&context, op, t, other, a, b); break;
    case OSC_I_UN: *result = do_un(&context, op, t, a); break;
    case OSC_I_CAST: *result = do_cast(&context, other, t, a); break;
    case OSC_I_CMP: *result = do_cmp(op, t, a, b); break;
    default: abort();
    }
    return 0;
}

static void check(unsigned ins, unsigned op, OscScalar t, OscScalar other, uint64_t a, uint64_t b)
{
    uint64_t got = 0, want = 0, code = 0;
    unsigned expected = reference(ins, op, t, other, a, b, &want);
    switch (ins) {
    case OSC_I_BIN: code = osc_alu_bin(op, t, a, b, &got); break;
    case OSC_I_UN: code = osc_alu_un(op, t, a, &got); break;
    case OSC_I_CAST: code = osc_alu_cast(other, t, a, &got); break;
    case OSC_I_CMP: got = osc_alu_cmp(op, t, a, b); break;
    default: abort();
    }
    if (code != expected || (!code && got != want)) {
        fprintf(stderr, "FAIL ins=%u op=%u types=%u/%u a=%" PRIx64 " b=%" PRIx64
                " trap=%u/%" PRIu64 " result=%" PRIx64 "/%" PRIx64 "\n",
                ins, op, (unsigned)t, (unsigned)other, a, b, expected, code, want, got);
        exit(1);
    }
    ++checks;
}

static void pair(OscScalar t, uint64_t a, uint64_t b)
{
    for (unsigned op = OSC_B_ADD; op <= OSC_B_SHR; ++op)
        check(OSC_I_BIN, op, t, t, a, b);
    for (unsigned cc = OSC_C_EQ; cc <= OSC_C_GE; ++cc)
        check(OSC_I_CMP, cc, t, t, a, b);
}

static void unary(OscScalar t, uint64_t a)
{
    check(OSC_I_UN, OSC_U_NEG, t, t, a, 0);
    check(OSC_I_UN, OSC_U_BNOT, t, t, a, 0);
    for (OscScalar dest = OSC_T_U8; dest <= OSC_T_I64; ++dest)
        check(OSC_I_CAST, 0, t, dest, a, 0);
}

int main(void)
{
    for (unsigned i = 0; i <= 1; ++i)
        check(OSC_I_UN, OSC_U_LNOT, OSC_T_BOOL, OSC_T_BOOL, i, 0);
    for (OscScalar t = OSC_T_U8; t <= OSC_T_I64; ++t) {
        unsigned w = osc_scalar_width(t);
        uint64_t sign = UINT64_C(1) << (w - 1);
        uint64_t mask = w == 64 ? UINT64_MAX : (UINT64_C(1) << w) - 1;
        uint64_t values[] = {0, 1, 2, 3, w - 1, w, w + 1, sign - 2, sign - 1, sign,
                             sign + 1, mask - 1, mask, UINT64_C(0x5555555555555555)};
        unsigned count = w == 8 ? 256 : sizeof values / sizeof *values;
        for (unsigned i = 0; i < count; ++i) {
            uint64_t a = canon(t, w == 8 ? i : values[i]);
            unary(t, a);
            for (unsigned j = 0; j < count; ++j)
                pair(t, a, canon(t, w == 8 ? j : values[j]));
            for (OscScalar ct = OSC_T_U8; ct <= OSC_T_I64; ++ct) {
                for (size_t j = 0; j < sizeof values / sizeof *values; ++j) {
                    uint64_t count_value = canon(ct, values[j]);
                    check(OSC_I_BIN, OSC_B_SHL, t, ct, a, count_value);
                    check(OSC_I_BIN, OSC_B_SHR, t, ct, a, count_value);
                }
            }
        }
    }
    printf("OSC_SCALAR_PARITY_PASS checks=%lu\n", checks);
    return 0;
}
