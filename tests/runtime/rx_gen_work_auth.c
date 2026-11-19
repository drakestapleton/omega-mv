/* SPDX-License-Identifier: Apache-2.0
 * Copyright 2026 Drake Stapleton (AIEN / aien-dev)
 *
 * Proposer-owned generation work, without the aienos capability library.
 * Cross-compile and run:
 *   aarch64-linux-gnu-gcc -std=gnu11 -Wall -Wextra -Werror -D_GNU_SOURCE -O2 -Isrc -pthread \
 *     -o rx_gen_work_auth tests/runtime/rx_gen_work_auth.c src/runtime/rx_generation.c \
 *     src/omega_om_units.c -lm
 *   qemu-aarch64 -L /usr/aarch64-linux-gnu ./rx_gen_work_auth
 */
#include "runtime/rx_generation.h"
#include "sha256.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int failures;

static void expect_int(const char *what, int got, int want) {
    if (got != want) {
        failures++;
        printf("FAIL %s: got %d want %d\n", what, got, want);
    }
}

static int caller_ok(void *ctx, uint32_t subject, const RxCallerCred *cred, int op) {
    (void)ctx;
    if (op == RX_CALLER_OP_RELEASE) return 0;
    if (!cred || cred->generation != 1 || cred->secret[0] != (uint8_t)subject || subject == 0)
        return RX_CALLER_ERR_FORGED;
    return 0;
}

typedef struct {
    uint32_t cap_id;
    uint64_t generation;
    uint32_t worker;
    uint64_t resource;
    uint32_t rights;
} ExpectAuth;

static int auth_exact(void *ctx, uint32_t cap_id, uint64_t generation, uint32_t subject,
                      uint64_t resource, uint32_t rights) {
    ExpectAuth *e = ctx;
    if (rights == RX_GEN_RIGHT_PROMOTE)
        return resource == RX_GEN_RES_PROMOTION && subject == e->worker ? 0 : -1;
    if (rights != RX_GEN_RIGHT_FINISH) return -1;
    return cap_id == e->cap_id && generation == e->generation && subject == e->worker &&
                   resource == e->resource && rights == e->rights
               ? 0
               : -1;
}

static RxCallerCred cred_for(uint32_t subject) {
    RxCallerCred c;
    memset(&c, 0, sizeof c);
    c.generation = 1;
    c.secret[0] = (uint8_t)subject;
    return c;
}

static int open_store(char *dir, RxGenStore **out) {
    if (!mkdtemp(dir)) return -1;
    return rx_gen_open(dir, out);
}

static int propose(RxGenStore *g, uint32_t who, const RxCallerCred *cred, int bound,
                   const uint8_t *ev, size_t n, uint64_t *id) {
    RxGenDraft d;
    memset(&d, 0, sizeof d);
    d.proofs_ok = 1;
    d.evidence = ev;
    d.evidence_len = n;
    if (bound) return rx_gen_propose_as(g, who, cred, &d, id);
    return rx_gen_propose(g, who, &d, id);
}

static void test_unbound(void) {
    char dir[] = "/tmp/omega-wu-XXXXXX";
    RxGenStore *g = NULL;
    expect_int("unbound open", open_store(dir, &g), RX_GEN_OK);
    if (!g) return;
    const uint8_t ev[] = "evidence-v1";
    uint64_t cand = 0;
    expect_int("unbound propose", propose(g, 7, NULL, 0, ev, sizeof ev - 1, &cand), RX_GEN_OK);
    RxGenWork item = {.id = 3, .class = RX_WORK_EVIDENCE, .state = RX_WORK_PENDING, .required = 1};
    expect_int("unbound add", rx_gen_add_work(g, cand, &item), RX_GEN_OK);
    expect_int("unbound finish", rx_gen_finish_work(g, cand, item.id), RX_GEN_OK);
    ExpectAuth promo = {.worker = 9};
    RxPromotionRequest req;
    memset(&req, 0, sizeof req);
    req.candidate_id = cand;
    req.subject = 9;
    req.cap_id = 1;
    req.cap_generation = 1;
    req.resource = RX_GEN_RES_PROMOTION;
    req.rights = RX_GEN_RIGHT_PROMOTE;
    expect_int("unbound promote",
               rx_gen_promote(g, &req, auth_exact, &promo, NULL, NULL, NULL, NULL), RX_GEN_OK);
    uint8_t blob[2048];
    size_t n = 0;
    expect_int("unbound work blob", rx_gen_read_blob(g, cand, "work", blob, sizeof blob, &n), RX_GEN_OK);
    uint8_t digest[32];
    sha256_hash(ev, sizeof ev - 1, digest);
    expect_int("unbound provenance",
               n == 16u + 80u && memcmp(blob, "R9WORK1", 7) == 0 && memcmp(blob + 16 + 48, digest, 32) == 0,
               1);
    rx_gen_close(g);

    char dir2[] = "/tmp/omega-wu-XXXXXX";
    expect_int("unbound open 2", open_store(dir2, &g), RX_GEN_OK);
    if (!g) return;
    expect_int("unbound propose 2", propose(g, 7, NULL, 0, ev, sizeof ev - 1, &cand), RX_GEN_OK);
    req.candidate_id = cand;
    expect_int("unbound add 2", rx_gen_add_work(g, cand, &item), RX_GEN_OK);
    expect_int("unbound finish 2", rx_gen_finish_work(g, cand, item.id), RX_GEN_OK);
    const uint8_t swapped[] = "swapped-evidence";
    expect_int("swap after finish", rx_gen_set_evidence(g, cand, swapped, sizeof swapped - 1), RX_GEN_OK);
    expect_int("swapped evidence refused",
               rx_gen_promote(g, &req, auth_exact, &promo, NULL, NULL, NULL, NULL), RX_GEN_ERR_VERIFY);
    rx_gen_close(g);
}

static void test_bound(void) {
    enum { PROP = 4, OTHER = 5, WORKER = 6, PROM = 8 };
    char dir[] = "/tmp/omega-wb-XXXXXX";
    RxGenStore *g = NULL;
    ExpectAuth auth = {.worker = PROM, .rights = RX_GEN_RIGHT_FINISH};
    expect_int("bound open", open_store(dir, &g), RX_GEN_OK);
    if (!g) return;
    expect_int("bind", rx_gen_bind_authority(g, caller_ok, NULL, auth_exact, &auth), RX_GEN_OK);
    RxCallerCred prop = cred_for(PROP), other = cred_for(OTHER), worker = cred_for(WORKER),
                 prom = cred_for(PROM);
    const uint8_t ev[] = "bound-evidence";
    uint64_t cand = 0;
    expect_int("bound propose", propose(g, PROP, &prop, 1, ev, sizeof ev - 1, &cand), RX_GEN_OK);
    RxGenWork item = {.id = 11, .class = RX_WORK_EVIDENCE, .state = RX_WORK_PENDING, .required = 1};
    item.finish_cap_id = 41;
    item.finish_cap_generation = 7;
    uint64_t resource = 0;
    expect_int("resource", rx_gen_work_resource(g, cand, item.id, &resource), RX_GEN_OK);
    auth.cap_id = item.finish_cap_id;
    auth.generation = item.finish_cap_generation;
    auth.worker = OTHER;
    auth.resource = resource;
    expect_int("other subject adds", rx_gen_add_work_as(g, OTHER, &other, cand, &item),
               RX_GEN_ERR_AUTHORITY);
    auth.worker = PROP;
    auth.resource = resource ^ 1;
    expect_int("wrong resource", rx_gen_add_work_as(g, PROP, &prop, cand, &item), RX_GEN_ERR_AUTHORITY);
    auth.resource = resource;
    expect_int("proposer adds", rx_gen_add_work_as(g, PROP, &prop, cand, &item), RX_GEN_OK);
    expect_int("other finishes", rx_gen_finish_work_as(g, OTHER, &other, cand, item.id),
               RX_GEN_ERR_AUTHORITY);
    expect_int("bare finish", rx_gen_finish_work(g, cand, item.id), RX_GEN_ERR_IDENTITY);
    expect_int("proposer finishes", rx_gen_finish_work_as(g, PROP, &prop, cand, item.id), RX_GEN_OK);

    RxGenWork delegated = {.id = 12, .class = RX_WORK_EVIDENCE, .state = RX_WORK_PENDING, .required = 1};
    delegated.worker = WORKER;
    delegated.worker_set = 1;
    delegated.finish_cap_id = 42;
    delegated.finish_cap_generation = 8;
    uint64_t dres = 0;
    expect_int("delegate resource", rx_gen_work_resource(g, cand, delegated.id, &dres), RX_GEN_OK);
    expect_int("resources differ", dres != resource, 1);
    auth.cap_id = item.finish_cap_id;
    auth.generation = item.finish_cap_generation;
    auth.worker = WORKER;
    auth.resource = dres;
    expect_int("cap reused across work", rx_gen_add_work_as(g, PROP, &prop, cand, &delegated),
               RX_GEN_ERR_AUTHORITY);
    auth.cap_id = delegated.finish_cap_id;
    auth.generation = delegated.finish_cap_generation;
    expect_int("delegate add", rx_gen_add_work_as(g, PROP, &prop, cand, &delegated), RX_GEN_OK);
    auth.worker = PROP;
    expect_int("proposer cannot finish delegate",
               rx_gen_finish_work_as(g, PROP, &prop, cand, delegated.id), RX_GEN_ERR_AUTHORITY);
    auth.worker = WORKER;
    expect_int("delegate finishes", rx_gen_finish_work_as(g, WORKER, &worker, cand, delegated.id),
               RX_GEN_OK);
    RxGenWork done = {.id = 13, .class = RX_WORK_EVIDENCE, .state = RX_WORK_DONE, .required = 1};
    expect_int("already done refused", rx_gen_add_work_as(g, PROP, &prop, cand, &done), RX_GEN_ERR_ARG);
    expect_int("duplicate id", rx_gen_add_work_as(g, PROP, &prop, cand, &item), RX_GEN_ERR_ARG);

    auth.worker = PROM;
    RxPromotionRequest req;
    memset(&req, 0, sizeof req);
    req.candidate_id = cand;
    req.subject = PROM;
    req.cap_id = 1;
    req.cap_generation = 1;
    req.resource = RX_GEN_RES_PROMOTION;
    req.rights = RX_GEN_RIGHT_PROMOTE;
    req.caller = prom;
    expect_int("bound promote", rx_gen_promote(g, &req, auth_exact, &auth, NULL, NULL, NULL, NULL),
               RX_GEN_OK);
    rx_gen_close(g);
}

/* A shorter directory plus a parent id whose first byte continues that path
 * must not share a finish resource with the longer directory. */
static void test_path_prefix(void) {
    char base[] = "/tmp/omega-wp-XXXXXX";
    if (!mkdtemp(base)) {
        failures++;
        printf("FAIL mkdtemp prefix\n");
        return;
    }
    char short_dir[256], long_dir[256];
    snprintf(short_dir, sizeof short_dir, "%s/a", base);
    snprintf(long_dir, sizeof long_dir, "%s/ab", base);
    RxGenStore *a = NULL, *b = NULL;
    expect_int("open a", rx_gen_open(short_dir, &a), RX_GEN_OK);
    expect_int("open ab", rx_gen_open(long_dir, &b), RX_GEN_OK);
    if (!a || !b) return;
    const uint8_t ev[] = "p";
    uint64_t ida = 0, idb = 0;
    expect_int("propose a", propose(a, 1, NULL, 0, ev, 1, &ida), RX_GEN_OK);
    expect_int("propose ab", propose(b, 1, NULL, 0, ev, 1, &idb), RX_GEN_OK);
    uint64_t ra = 0, rb = 0;
    expect_int("res a", rx_gen_work_resource(a, ida, 1, &ra), RX_GEN_OK);
    expect_int("res ab", rx_gen_work_resource(b, idb, 1, &rb), RX_GEN_OK);
    expect_int("path prefix resources differ", ra != rb, 1);
    rx_gen_close(a);
    rx_gen_close(b);
}

int main(void) {
    test_unbound();
    test_bound();
    test_path_prefix();
    if (failures) {
        printf("rx_gen_work_auth: FAIL %d\n", failures);
        return 1;
    }
    printf("rx_gen_work_auth: PASS\n");
    return 0;
}
