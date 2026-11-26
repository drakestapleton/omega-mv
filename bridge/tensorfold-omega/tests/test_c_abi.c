/* SPDX-License-Identifier: Apache-2.0
 * bridge/tensorfold-omega/tests/test_c_abi.c
 *
 * Independent C ABI v2 caller verifying:
 *   1. omega2_ident_tf_omega_unit() + omega2_tf_omega_ident()
 *   2. Zero-drift Live Arboris MoE observe/predict + read-only table preservation
 *   3. SM121 stall-floor >= 6 (negative control: raw_floor=5 traps 9, stall=4 returns 1, BB escape returns 2)
 *   4. EGP3 single-cert positive & tampered negative control
 *   5. ABI v2 status 32 (null pointer & aliased result/out buffer) + out-buffer isolation on trap
 */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "../include/tf_omega_plugin.h"

static void fail(const char *msg, uint64_t a, uint64_t b) {
    fprintf(stderr, "C_ABI_FAIL: %s (got=%llu want=%llu)\n",
            msg, (unsigned long long)a, (unsigned long long)b);
    exit(1);
}

static uint64_t pack_flags(uint16_t bb, uint16_t orig_bb, uint64_t extra) {
    return extra | ((uint64_t)bb << 8) | ((uint64_t)orig_bb << 24);
}

static uint64_t pack_srcs(uint8_t s0, uint8_t s1, uint8_t s2) {
    return (uint64_t)s0 | ((uint64_t)s1 << 8) | ((uint64_t)s2 << 16);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: test_c_abi <egp3_cert_path>\n");
        return 2;
    }

    /* 1. Identity + capability metadata */
    const char *ident = omega2_ident_tf_omega_unit();
    if (!ident || strncmp(ident, "omega-ident 1 unit=tf_omega_unit abi=2 profile=OM-2 src=", 56) != 0)
        fail("bad omega2_ident_tf_omega_unit", 0, 1);

    uint64_t res = 0;
    uint64_t meta[6] = {0};
    uint32_t st = omega2_tf_omega_ident(&res, meta);
    if (st != OMEGA_OK) fail("tf_omega_ident status", st, OMEGA_OK);
    if (res != TF_OMEGA_MAGIC || meta[0] != TF_OMEGA_MAGIC || meta[1] != 2 ||
        meta[2] != 2 || meta[3] != 7 || meta[4] != 6 || meta[5] != 5)
        fail("tf_omega_ident metadata mismatch", meta[4], 6);

    /* 2. Zero-drift Live Arboris MoE observe & predict */
    uint32_t table[128 * 8];
    uint32_t snapshot[128 * 8];
    memset(table, 0, sizeof(table));
    uint64_t cfg[4] = {128, 8, 4, 60000};
    uint32_t cur_a[2] = {17, 42};
    uint32_t cur_b[2] = {17, 99};

    st = omega2_tf_arboris_observe(&res, table, 1024, cfg, 4, 3, cur_a, 2);
    if (st != OMEGA_OK || res != 2) fail("observe #1", st, OMEGA_OK);
    st = omega2_tf_arboris_observe(&res, table, 1024, cfg, 4, 3, cur_a, 2);
    if (st != OMEGA_OK || res != 2) fail("observe #2", st, OMEGA_OK);
    st = omega2_tf_arboris_observe(&res, table, 1024, cfg, 4, 3, cur_b, 2);
    if (st != OMEGA_OK || res != 2) fail("observe #3", st, OMEGA_OK);

    memcpy(snapshot, table, sizeof(table));
    uint32_t q[1] = {3};
    uint32_t pred[16];
    memset(pred, 0xaa, sizeof(pred));
    st = omega2_tf_arboris_predict(&res, table, 1024, cfg, 4, q, 1, pred);
    if (st != OMEGA_OK || res != 3) fail("predict status/count", res, 3);
    if (pred[0] != 17 || pred[1] != 42 || pred[2] != 99 || pred[3] != TF_OMEGA_NONE)
        fail("predict ranking", pred[0], 17);
    if (memcmp(table, snapshot, sizeof(table)) != 0)
        fail("predict mutated read-only table", 1, 0);

    /* Out-buffer isolation on trap 9 (bad cfg top_k=0) */
    uint64_t bad_cfg[4] = {128, 8, 0, 60000};
    uint32_t guard_pred[16];
    for (int i = 0; i < 16; i++) guard_pred[i] = 0x55555555u;
    st = omega2_tf_arboris_predict(&res, table, 1024, bad_cfg, 4, q, 1, guard_pred);
    if (st != OMEGA_TRAP_REQ) fail("bad_cfg trap 9", st, OMEGA_TRAP_REQ);
    for (int i = 0; i < 16; i++) {
        if (guard_pred[i] != 0x55555555u) fail("out buffer touched on trap", guard_pred[i], 0x55555555u);
    }

    /* 3. SM121 scoreboard stall-floor >= 6 & BB pinning */
    uint64_t ok_insns[8] = {
        6, 4, pack_srcs(255, 255, 255), pack_flags(0, 0, TF_SM121_FLAG_FIX_ALU),
        2, 5, pack_srcs(4, 255, 255),   pack_flags(0, 0, 0)
    };
    st = omega2_tf_sm121_check_stall(&res, ok_insns, 8, 2, 6);
    if (st != OMEGA_OK || res != 0) fail("sm121 valid schedule", res, 0);

    /* Negative control: raw_floor < 6 refused via trap 9 (REQUIRES) */
    st = omega2_tf_sm121_check_stall(&res, ok_insns, 8, 2, 5);
    if (st != OMEGA_TRAP_REQ) fail("sm121 raw_floor=5 must trap 9", st, OMEGA_TRAP_REQ);

    /* Negative control: fixed-ALU stall < 6 refused (code 4) */
    uint64_t bad_fix[8] = {
        5, 4, pack_srcs(255, 255, 255), pack_flags(0, 0, TF_SM121_FLAG_FIX_ALU),
        2, 5, pack_srcs(4, 255, 255),   pack_flags(0, 0, 0)
    };
    st = omega2_tf_sm121_check_stall(&res, bad_fix, 8, 2, 6);
    if (st != OMEGA_OK || res != 4) fail("sm121 fixed_alu stall=5 must return 4", res, 4);

    /* Negative control: RAW stall gap < 6 refused (code 1) */
    uint64_t bad_raw[8] = {
        3, 4, pack_srcs(255, 255, 255), pack_flags(0, 0, 0),
        2, 5, pack_srcs(4, 255, 255),   pack_flags(0, 0, 0)
    };
    st = omega2_tf_sm121_check_stall(&res, bad_raw, 8, 2, 6);
    if (st != OMEGA_OK || res != 1) fail("sm121 RAW stall=3 must return 1", res, 1);

    /* Negative control: cross-BB instruction move refused (code 2) */
    uint64_t bad_bb[8] = {
        6, 4, pack_srcs(255, 255, 255), pack_flags(1, 0, 0),
        6, 5, pack_srcs(4, 255, 255),   pack_flags(1, 1, 0)
    };
    st = omega2_tf_sm121_check_stall(&res, bad_bb, 8, 2, 6);
    if (st != OMEGA_OK || res != 2) fail("sm121 BB escape must return 2", res, 2);

    /* 4. EGP3 single-cert check from disk + fail-closed negative controls */
    FILE *fp = fopen(argv[1], "rb");
    if (!fp) fail("open egp3 cert", 0, 1);
    uint8_t orig_cert[512];
    size_t n = fread(orig_cert, 1, sizeof(orig_cert), fp);
    fclose(fp);
    if (n != 240) fail("egp3 cert size", n, 240);

    uint8_t cert[512];
    memcpy(cert, orig_cert, n);
    st = omega2_tf_egp3_check_cert(&res, cert, (uint64_t)n);
    if (st != OMEGA_OK || res != 0) fail("valid EGP3 cert", res, 0);

    /* Negative control 4a: corrupt Rule 1 RHS operand -> must refuse with code 8 */
    cert[36 + 5 * 32 + 3 * 4] ^= 1;
    st = omega2_tf_egp3_check_cert(&res, cert, (uint64_t)n);
    if (st != OMEGA_OK || res != 8) fail("tampered EGP3 cert must return 8", res, 8);

    /* Negative control 4b: corrupt RHS + switch rule_id=3 (verifier #35 attack) -> must refuse with code 8 */
    cert[228] = 3;
    st = omega2_tf_egp3_check_cert(&res, cert, (uint64_t)n);
    if (st != OMEGA_OK || res != 8) fail("bogus rule_id=3 must return 8", res, 8);

    /* Negative control 4c: rule_id=19 out of range -> must refuse with code 7 */
    cert[228] = 19;
    st = omega2_tf_egp3_check_cert(&res, cert, (uint64_t)n);
    if (st != OMEGA_OK || res != 7) fail("invalid rule_id=19 must return 7", res, 7);

    /* Negative control 4d: disconnected root_before=0, root_after=1 with valid step 4->5 -> must refuse with code 11 */
    memcpy(cert, orig_cert, n);
    cert[24] = 0; cert[25] = 0; cert[26] = 0; cert[27] = 0;
    cert[28] = 1; cert[29] = 0; cert[30] = 0; cert[31] = 0;
    st = omega2_tf_egp3_check_cert(&res, cert, (uint64_t)n);
    if (st != OMEGA_OK || res != 11) fail("disconnected roots must return 11", res, 11);

    /* Negative control 4e: tc=0 with root_before=4 != root_after=5 (228-byte cert) -> must refuse with code 11 */
    memcpy(cert, orig_cert, 228);
    cert[32] = 0; cert[33] = 0; cert[34] = 0; cert[35] = 0;
    st = omega2_tf_egp3_check_cert(&res, cert, 228);
    if (st != OMEGA_OK || res != 11) fail("zero-trace distinct roots must return 11", res, 11);

    /* 5. ABI v2 null pointer & aliased buffer -> status 32 (OMEGA_BAD_ARG) */
    st = omega2_tf_egp3_check_cert(&res, NULL, 36);
    if (st != OMEGA_BAD_ARG) fail("null ptr must return 32", st, OMEGA_BAD_ARG);

    st = omega2_tf_omega_ident(&meta[0], meta);
    if (st != OMEGA_BAD_ARG) fail("aliased result/out must return 32", st, OMEGA_BAD_ARG);

    st = omega2_tf_arboris_observe(&res, table, 1024, cfg, 3 /* wrong fixed len */, 3, cur_a, 2);
    if (st != OMEGA_BAD_ARG) fail("wrong fixed cfg len must return 32", st, OMEGA_BAD_ARG);

    printf("C_ABI_V2_PASS ident=%s arboris=OK sm121_floor=6 egp3=OK neg_controls=11\n", ident);
    return 0;
}
