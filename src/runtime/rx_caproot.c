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

/*
 * rx_caproot.c -- host reference capability root. See rx_caproot.h.
 *
 * The writable table stays in a separate non-dumpable process. The control
 * socket is not authority. Every privileged operation must present a
 * capability this process previously handed out (the delivered set lives only
 * here, not in the readable table). R7 is not claimed: AIENOS is not this
 * process, and this Linux mint is not the permanent root.
 */
#include "rx_caproot.h"
#include "omega_native.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stddef.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <sys/random.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#ifndef F_SEAL_FUTURE_WRITE
#define F_SEAL_FUTURE_WRITE 0x0010
#endif

typedef struct {
    int32_t status;
    uint32_t pad;
    RxCapRef ref;
} RxCapReply;

typedef struct {
    uint32_t ready;
    uint32_t office_id;
    uint32_t pad;
    uint64_t office_generation;
    int32_t status;
    uint8_t token[RX_CAP_TOKEN_LEN];
} RxCapHello;

/* Next table's starting generation. Taken atomically so two roots in one
 * process cannot share a generation. A later root starts higher, so a
 * reference from a dead root cannot validate against the new table: the
 * start is the larger of one past the last start and the time since boot in
 * nanoseconds shifted left by 8. A slot of the dead root would need more
 * than 256 reclaims per nanosecond to reach it. Same rule as AIENOS. */
static _Atomic uint64_t g_last_boot_gen = 0;

static uint64_t boot_time_seed(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_BOOTTIME, &ts) != 0) return 0;
    uint64_t ns = (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
    if (ns > (UINT64_MAX >> 9)) return 0;
    return ns << 8;
}

static int take_boot_gen(uint64_t *out) {
    uint64_t seed = boot_time_seed();
    uint64_t cur = atomic_load_explicit(&g_last_boot_gen, memory_order_relaxed);
    for (;;) {
        if (cur == UINT64_MAX) return RX_CAP_ERR_EXHAUSTED;
        uint64_t next = cur + 1u;
        if (seed > next) next = seed;
        if (next == UINT64_MAX) return RX_CAP_ERR_EXHAUSTED;
        if (atomic_compare_exchange_weak_explicit(
                &g_last_boot_gen, &cur, next,
                memory_order_acq_rel, memory_order_relaxed)) {
            *out = next;
            return RX_CAP_OK;
        }
    }
}

static int fill_token(uint8_t token[RX_CAP_TOKEN_LEN]) {
    size_t n = 0;
    while (n < RX_CAP_TOKEN_LEN) {
        ssize_t r = getrandom(token + n, RX_CAP_TOKEN_LEN - n, 0);
        if (r < 0 && errno == EINTR) continue;
        if (r <= 0) return -1;
        n += (size_t)r;
    }
    return 0;
}

static int token_ok(const uint8_t *a, const uint8_t *b) {
    uint64_t eq = 0;
    (void)omega2_cap_token_eq(&eq, a, RX_CAP_TOKEN_LEN, b, RX_CAP_TOKEN_LEN);
    return eq != 0;
}

/* ---- root process (the only writer; logic in seed/authority/cap_table_om2.om) ---- */

static void root_begin(RxCapTable *t) {
    atomic_fetch_add_explicit(&t->seq, 1, memory_order_acq_rel);
    atomic_thread_fence(memory_order_release);
}

static void root_end(RxCapTable *t) {
    atomic_thread_fence(memory_order_release);
    atomic_fetch_add_explicit(&t->seq, 1, memory_order_acq_rel);
}

static void table_to_om2(const RxCapTable *t, uint64_t hdr[4], uint64_t slots[RX_CAP_MAX * 13]) {
    hdr[0] = t->capacity;
    hdr[1] = atomic_load_explicit(&t->epoch, memory_order_relaxed);
    hdr[2] = atomic_load_explicit(&t->clock, memory_order_relaxed);
    hdr[3] = 0;
    for (uint32_t i = 0; i < RX_CAP_MAX; i++) {
        const RxCapEntry *e = &t->entries[i];
        uint64_t *s = &slots[(size_t)i * 13];
        s[0] = e->cap_id;
        s[1] = e->generation;
        s[2] = e->state;
        s[3] = e->issuer;
        s[4] = e->subject;
        s[5] = e->rights;
        s[6] = e->resource;
        s[7] = e->epoch;
        s[8] = e->lease_expiry;
        s[9] = e->parent_id;
        s[10] = e->parent_generation;
        s[11] = e->minted_by_id;
        s[12] = e->minted_by_generation;
    }
}

static void om2_to_table(RxCapTable *t, const uint64_t hdr[4], const uint64_t slots[RX_CAP_MAX * 13]) {
    atomic_store_explicit(&t->epoch, hdr[1], memory_order_relaxed);
    atomic_store_explicit(&t->clock, hdr[2], memory_order_relaxed);
    for (uint32_t i = 0; i < RX_CAP_MAX; i++) {
        RxCapEntry *e = &t->entries[i];
        const uint64_t *s = &slots[(size_t)i * 13];
        e->cap_id = (uint32_t)s[0];
        e->generation = s[1];
        e->state = (uint32_t)s[2];
        e->issuer = (uint32_t)s[3];
        e->subject = (uint32_t)s[4];
        e->rights = (uint32_t)s[5];
        e->resource = s[6];
        e->epoch = s[7];
        e->lease_expiry = s[8];
        e->parent_id = (uint32_t)s[9];
        e->parent_generation = s[10];
        e->minted_by_id = (uint32_t)s[11];
        e->minted_by_generation = s[12];
    }
}

static void om2_unpack_entry(const uint64_t s[13], RxCapEntry *e) {
    e->cap_id = (uint32_t)s[0];
    e->generation = s[1];
    e->state = (uint32_t)s[2];
    e->issuer = (uint32_t)s[3];
    e->subject = (uint32_t)s[4];
    e->rights = (uint32_t)s[5];
    e->resource = s[6];
    e->epoch = s[7];
    e->lease_expiry = s[8];
    e->parent_id = (uint32_t)s[9];
    e->parent_generation = s[10];
    e->minted_by_id = (uint32_t)s[11];
    e->minted_by_generation = s[12];
}

static int auth_use(RxCapTable *t, const uint8_t *delivered, RxCapRef a,
                    uint32_t need, const RxCapEntry **out) {
    uint64_t hdr[4], slots[RX_CAP_MAX * 13], rc = 0;
    table_to_om2(t, hdr, slots);
    uint64_t args[3] = { a.cap_id, a.generation, need };
    (void)omega2_cap_table_auth_use(&rc, hdr, 4, slots, RX_CAP_MAX * 13, delivered, RX_CAP_MAX,
                                    args, 3);
    int res = (int)(int64_t)rc;
    if (res == RX_CAP_OK && out) *out = &t->entries[a.cap_id];
    return res;
}

static int root_mint(RxCapTable *t, const uint8_t *delivered, uint8_t *delivered_mut,
                     const RxCapMint *m, RxCapRef *out) {
    (void)delivered;
    uint64_t hdr[4], slots[RX_CAP_MAX * 13], ref[2] = { 0, 0 }, rc = 0;
    table_to_om2(t, hdr, slots);
    uint64_t req[9] = {
        m->issuer, m->subject, m->resource, m->rights, m->lease_ticks,
        m->parent.cap_id, m->parent.generation, m->authority.cap_id, m->authority.generation
    };
    (void)omega2_cap_table_mint(&rc, hdr, 4, slots, RX_CAP_MAX * 13, delivered_mut, RX_CAP_MAX,
                                req, 9, ref, 2);
    int res = (int)(int64_t)rc;
    if (res == RX_CAP_OK) {
        root_begin(t);
        om2_to_table(t, hdr, slots);
        root_end(t);
        out->cap_id = (uint32_t)ref[0];
        out->generation = ref[1];
    }
    return res;
}

static int root_revoke(RxCapTable *t, const uint8_t *delivered, RxCapRef authority, RxCapRef r) {
    uint64_t hdr[4], slots[RX_CAP_MAX * 13], rev_list[257] = { 0 }, rc = 0;
    table_to_om2(t, hdr, slots);
    uint64_t args[4] = { authority.cap_id, authority.generation, r.cap_id, r.generation };
    (void)omega2_cap_table_revoke(&rc, hdr, 4, slots, RX_CAP_MAX * 13, delivered, RX_CAP_MAX,
                                  args, 4, rev_list, 257);
    int res = (int)(int64_t)rc;
    if (res == RX_CAP_OK) {
        root_begin(t);
        om2_to_table(t, hdr, slots);
        root_end(t);
    }
    return res;
}

static int root_reclaim(RxCapTable *t, const uint8_t *delivered, uint8_t *delivered_mut,
                        RxCapRef authority, uint32_t id) {
    (void)delivered;
    uint64_t hdr[4], slots[RX_CAP_MAX * 13], rc = 0;
    table_to_om2(t, hdr, slots);
    uint64_t args[3] = { authority.cap_id, authority.generation, id };
    (void)omega2_cap_table_reclaim(&rc, hdr, 4, slots, RX_CAP_MAX * 13, delivered_mut, RX_CAP_MAX,
                                   args, 3);
    int res = (int)(int64_t)rc;
    if (res == RX_CAP_OK) {
        root_begin(t);
        om2_to_table(t, hdr, slots);
        root_end(t);
    }
    return res;
}

static int root_clock(RxCapTable *t, const uint8_t *delivered, RxCapRef authority, uint64_t ticks) {
    uint64_t hdr[4], slots[RX_CAP_MAX * 13], rc = 0;
    table_to_om2(t, hdr, slots);
    uint64_t args[3] = { authority.cap_id, authority.generation, ticks };
    (void)omega2_cap_table_clock(&rc, hdr, 4, slots, RX_CAP_MAX * 13, delivered, RX_CAP_MAX,
                                 args, 3);
    int res = (int)(int64_t)rc;
    if (res == RX_CAP_OK) {
        root_begin(t);
        atomic_store_explicit(&t->clock, hdr[2], memory_order_relaxed);
        root_end(t);
    }
    return res;
}

static int root_epoch(RxCapTable *t, const uint8_t *delivered, RxCapRef authority) {
    uint64_t hdr[4], slots[RX_CAP_MAX * 13], rc = 0;
    table_to_om2(t, hdr, slots);
    (void)omega2_cap_table_epoch(&rc, hdr, 4, slots, RX_CAP_MAX * 13, delivered, RX_CAP_MAX,
                                 authority.cap_id, authority.generation);
    int res = (int)(int64_t)rc;
    if (res == RX_CAP_OK) {
        root_begin(t);
        atomic_store_explicit(&t->epoch, hdr[1], memory_order_relaxed);
        root_end(t);
    }
    return res;
}

static int read_full(int fd, void *buf, size_t n) {
    uint8_t *p = buf;
    while (n) {
        ssize_t r = read(fd, p, n);
        if (r < 0 && errno == EINTR) continue;
        if (r <= 0) return -1;
        p += r;
        n -= (size_t)r;
    }
    return 0;
}

static int write_full(int fd, const void *buf, size_t n) {
    const uint8_t *p = buf;
    while (n) {
        ssize_t r = write(fd, p, n);
        if (r < 0 && errno == EINTR) continue;
        if (r <= 0) return -1;
        p += r;
        n -= (size_t)r;
    }
    return 0;
}

static void root_main(int memfd, int sock) {
    prctl(PR_SET_DUMPABLE, 0, 0, 0, 0);
    prctl(PR_SET_PDEATHSIG, SIGKILL, 0, 0, 0);
    uint64_t boot_gen = 0;
    if (read_full(sock, &boot_gen, sizeof(boot_gen)) != 0) _exit(2);
    if (boot_gen == 0 || boot_gen == UINT64_MAX) _exit(2);

    RxCapTable *t = mmap(NULL, sizeof(RxCapTable), PROT_READ | PROT_WRITE,
                         MAP_SHARED, memfd, 0);
    close(memfd);
    if (t == MAP_FAILED) _exit(2);
    memset(t, 0, sizeof(*t));
    t->magic = RX_CAP_TABLE_MAGIC;
    t->capacity = RX_CAP_MAX;
    atomic_store(&t->epoch, 1);
    for (uint32_t i = 0; i < RX_CAP_MAX; i++) {
        t->entries[i].cap_id = i;
        t->entries[i].generation = boot_gen;
        t->entries[i].state = RX_CAP_FREE;
        t->entries[i].parent_id = UINT32_MAX;
    }

    /* Bootstrap office. Not requested over the socket. Privileged rights only,
     * no DELEGATE, so they cannot be handed on by attenuation. */
    uint8_t delivered[RX_CAP_MAX];
    memset(delivered, 0, sizeof(delivered));
    RxCapEntry *office = &t->entries[0];
    office->state = RX_CAP_LIVE;
    office->issuer = 0;
    office->subject = 0;
    office->resource = RX_CAP_RES_AUTHORITY;
    office->rights = RX_RIGHT_PRIVILEGED;
    office->epoch = 1;
    office->parent_id = UINT32_MAX;
    delivered[0] = 1;

    RxCapHello hello;
    memset(&hello, 0, sizeof(hello));
    hello.ready = 1;
    hello.office_id = office->cap_id;
    hello.office_generation = office->generation;
    hello.status = RX_CAP_OK;
    if (fill_token(hello.token) != 0) _exit(2);
    if (write_full(sock, &hello, sizeof(hello)) != 0) _exit(3);
    uint8_t token[RX_CAP_TOKEN_LEN];
    memcpy(token, hello.token, sizeof(token));

    RxCapRequest q;
    while (read_full(sock, &q, sizeof(q)) == 0) {
        RxCapReply r;
        memset(&r, 0, sizeof(r));
        if (!token_ok(q.token, token)) {
            r.status = RX_CAP_ERR_UNAUTHORIZED;
            if (write_full(sock, &r, sizeof(r)) != 0) break;
            continue;
        }
        switch (q.op) {
        case RX_OP_MINT:
            r.status = root_mint(t, delivered, delivered, &q.mint, &r.ref);
            break;
        case RX_OP_REVOKE:
            r.status = root_revoke(t, delivered, q.authority, q.ref);
            break;
        case RX_OP_RECLAIM:
            r.status = root_reclaim(t, delivered, delivered, q.authority, q.ref.cap_id);
            break;
        case RX_OP_CLOCK:
            r.status = root_clock(t, delivered, q.authority, q.arg);
            break;
        case RX_OP_EPOCH:
            r.status = root_epoch(t, delivered, q.authority);
            break;
        case RX_OP_SHUTDOWN:
            r.status = auth_use(t, delivered, q.authority, RX_RIGHT_MINT, NULL);
            if (write_full(sock, &r, sizeof(r)) != 0) _exit(4);
            if (r.status == RX_CAP_OK) _exit(0);
            continue;
        default:
            r.status = RX_CAP_ERR_STATE;
            break;
        }
        if (write_full(sock, &r, sizeof(r)) != 0) break;
    }
    _exit(0);
}

/* ---- runtime side ------------------------------------------------------- */

int rx_caproot_start(RxCapRoot *root, RxCapAdmin *admin) {
    if (!root || !admin) return RX_CAP_ERR_STATE;
    memset(root, 0, sizeof(*root));
    memset(admin, 0, sizeof(*admin));
    root->ro_fd = -1;
    admin->ctl_fd = -1;
    admin->office.cap_id = UINT32_MAX;
    uint64_t boot = 0;
    int brc = take_boot_gen(&boot);
    if (brc != RX_CAP_OK) return brc;
    int memfd = memfd_create("aien-capability-root", MFD_ALLOW_SEALING | MFD_CLOEXEC);
    if (memfd < 0) return RX_CAP_ERR_IO;
    if (ftruncate(memfd, sizeof(RxCapTable)) != 0) { close(memfd); return RX_CAP_ERR_IO; }
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, sv) != 0) {
        close(memfd);
        return RX_CAP_ERR_IO;
    }
    pid_t pid = fork();
    if (pid < 0) { close(memfd); close(sv[0]); close(sv[1]); return RX_CAP_ERR_IO; }
    if (pid == 0) {
        close(sv[0]);
        root_main(memfd, sv[1]);
    }
    close(sv[1]);
    if (write_full(sv[0], &boot, sizeof(boot)) != 0) goto fail;
    RxCapHello hello;
    memset(&hello, 0, sizeof(hello));
    if (read_full(sv[0], &hello, sizeof(hello)) != 0 || hello.ready != 1 ||
        hello.status != RX_CAP_OK)
        goto fail;
    if (fcntl(memfd, F_ADD_SEALS,
              F_SEAL_SHRINK | F_SEAL_GROW | F_SEAL_FUTURE_WRITE | F_SEAL_SEAL) != 0)
        goto fail;
    const RxCapTable *t = mmap(NULL, sizeof(RxCapTable), PROT_READ, MAP_SHARED, memfd, 0);
    if (t == MAP_FAILED) goto fail;
    if (t->magic != RX_CAP_TABLE_MAGIC) { munmap((void *)t, sizeof(RxCapTable)); goto fail; }
    root->table = t;
    root->ro_fd = memfd;
    root->root_pid = pid;
    root->running = true;
    admin->ctl_fd = sv[0];
    admin->root_pid = pid;
    admin->running = true;
    admin->office.cap_id = hello.office_id;
    admin->office.generation = hello.office_generation;
    memcpy(admin->token, hello.token, RX_CAP_TOKEN_LEN);
    return RX_CAP_OK;
fail:
    kill(pid, SIGKILL);
    waitpid(pid, NULL, 0);
    close(memfd);
    close(sv[0]);
    return RX_CAP_ERR_IO;
}

static int request(RxCapAdmin *admin, RxCapRequest *q, RxCapReply *r) {
    if (!admin || !admin->running) return RX_CAP_ERR_IO;
    memcpy(q->token, admin->token, RX_CAP_TOKEN_LEN);
    if (write_full(admin->ctl_fd, q, sizeof(*q)) != 0) return RX_CAP_ERR_IO;
    if (read_full(admin->ctl_fd, r, sizeof(*r)) != 0) return RX_CAP_ERR_IO;
    return r->status;
}

void rx_caproot_stop(RxCapRoot *root, RxCapAdmin *admin) {
    if (!root || !admin) return;
    if (admin->running) {
        RxCapRequest q;
        memset(&q, 0, sizeof(q));
        q.op = RX_OP_SHUTDOWN;
        q.authority = admin->office;
        RxCapReply r;
        if (request(admin, &q, &r) != RX_CAP_OK && admin->root_pid > 0)
            kill(admin->root_pid, SIGKILL);
    }
    if (admin->root_pid > 0) waitpid(admin->root_pid, NULL, 0);
    if (root->table) munmap((void *)root->table, sizeof(RxCapTable));
    if (admin->ctl_fd >= 0) close(admin->ctl_fd);
    if (root->ro_fd >= 0) close(root->ro_fd);
    memset(admin->token, 0, sizeof(admin->token));
    root->table = NULL;
    root->ro_fd = -1;
    root->running = false;
    admin->ctl_fd = -1;
    admin->running = false;
}

RxCapRef rx_capadmin_office(const RxCapAdmin *admin) {
    return admin ? admin->office : (RxCapRef){ UINT32_MAX, 0 };
}

int rx_capadmin_mint(RxCapAdmin *admin, const RxCapMint *req, RxCapRef *out) {
    RxCapRequest q;
    memset(&q, 0, sizeof(q));
    q.op = RX_OP_MINT;
    q.mint = *req;
    RxCapReply r;
    int rc = request(admin, &q, &r);
    if (rc == RX_CAP_OK && out) *out = r.ref;
    return rc;
}

int rx_capadmin_revoke(RxCapAdmin *admin, RxCapRef authority, RxCapRef ref) {
    RxCapRequest q;
    memset(&q, 0, sizeof(q));
    q.op = RX_OP_REVOKE;
    q.authority = authority;
    q.ref = ref;
    RxCapReply r;
    return request(admin, &q, &r);
}

int rx_capadmin_reclaim(RxCapAdmin *admin, RxCapRef authority, uint32_t cap_id) {
    RxCapRequest q;
    memset(&q, 0, sizeof(q));
    q.op = RX_OP_RECLAIM;
    q.authority = authority;
    q.ref.cap_id = cap_id;
    RxCapReply r;
    return request(admin, &q, &r);
}

int rx_capadmin_advance_clock(RxCapAdmin *admin, RxCapRef authority, uint64_t ticks) {
    RxCapRequest q;
    memset(&q, 0, sizeof(q));
    q.op = RX_OP_CLOCK;
    q.authority = authority;
    q.arg = ticks;
    RxCapReply r;
    return request(admin, &q, &r);
}

int rx_capadmin_bump_epoch(RxCapAdmin *admin, RxCapRef authority) {
    RxCapRequest q;
    memset(&q, 0, sizeof(q));
    q.op = RX_OP_EPOCH;
    q.authority = authority;
    RxCapReply r;
    return request(admin, &q, &r);
}

static int writer_dead(const RxCapRoot *root) {
    if (!root->running || root->root_pid <= 0) return 1;
    if (kill(root->root_pid, 0) == 0) return 0;
    return errno == ESRCH;
}

int rx_caproot_inspect(const RxCapRoot *root, RxCapRef ref, RxCapEntry *out) {
    const RxCapTable *t = root->table;
    if (!t || ref.cap_id >= RX_CAP_MAX) return RX_CAP_ERR_BOUNDS;
    for (;;) {
        uint64_t s0 = atomic_load_explicit(&t->seq, memory_order_acquire);
        if (s0 & 1u) {
            if (writer_dead(root)) return RX_CAP_ERR_IO;
            continue;
        }
        uint64_t hdr[4], slots[RX_CAP_MAX * 13];
        table_to_om2(t, hdr, slots);
        atomic_thread_fence(memory_order_acquire);
        if (atomic_load_explicit(&t->seq, memory_order_relaxed) != s0) continue;
        uint64_t ent[13] = { 0 }, rc = 0;
        (void)omega2_cap_table_inspect(&rc, hdr, 4, slots, RX_CAP_MAX * 13,
                                       ref.cap_id, ref.generation, ent, 13);
        int res = (int)(int64_t)rc;
        if (res == RX_CAP_OK && out) om2_unpack_entry(ent, out);
        return res;
    }
}

int rx_caproot_validate(const RxCapRoot *root, RxCapRef ref,
                        uint32_t subject, uint64_t resource, uint32_t rights,
                        RxCapEntry *out_entry) {
    const RxCapTable *t = root->table;
    if (!t || ref.cap_id >= RX_CAP_MAX) return RX_CAP_ERR_BOUNDS;
    for (;;) {
        uint64_t s0 = atomic_load_explicit(&t->seq, memory_order_acquire);
        if (s0 & 1u) {
            if (writer_dead(root)) return RX_CAP_ERR_IO;
            continue;
        }
        uint64_t hdr[4], slots[RX_CAP_MAX * 13];
        table_to_om2(t, hdr, slots);
        atomic_thread_fence(memory_order_acquire);
        if (atomic_load_explicit(&t->seq, memory_order_relaxed) != s0) continue;
        uint64_t args[5] = { ref.cap_id, ref.generation, subject, resource, rights };
        uint64_t ent[13] = { 0 }, rc = 0;
        (void)omega2_cap_table_validate(&rc, hdr, 4, slots, RX_CAP_MAX * 13, args, 5, ent, 13);
        int res = (int)(int64_t)rc;
        if (res == RX_CAP_OK && out_entry) om2_unpack_entry(ent, out_entry);
        return res;
    }
}

const char *rx_cap_strerror(int code) {
    switch (code) {
    case RX_CAP_OK: return "ok";
    case RX_CAP_ERR_BOUNDS: return "bounds";
    case RX_CAP_ERR_STALE_GEN: return "stale-generation";
    case RX_CAP_ERR_REVOKED: return "revoked";
    case RX_CAP_ERR_EPOCH: return "epoch";
    case RX_CAP_ERR_SUBJECT: return "wrong-subject";
    case RX_CAP_ERR_RESOURCE: return "wrong-resource";
    case RX_CAP_ERR_RIGHTS: return "insufficient-rights";
    case RX_CAP_ERR_EXPIRED: return "lease-expired";
    case RX_CAP_ERR_CHAIN: return "delegation-chain-invalid";
    case RX_CAP_ERR_AMPLIFY: return "rights-amplification";
    case RX_CAP_ERR_NOT_DELEGABLE: return "not-delegable";
    case RX_CAP_ERR_FULL: return "table-full";
    case RX_CAP_ERR_IO: return "root-io";
    case RX_CAP_ERR_STATE: return "bad-state";
    case RX_CAP_ERR_UNAUTHORIZED: return "unauthorized";
    case RX_CAP_ERR_OVERFLOW: return "overflow";
    case RX_CAP_ERR_EXHAUSTED: return "generation-exhausted";
    default: return "unknown";
    }
}
