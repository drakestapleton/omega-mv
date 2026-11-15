/* test_spinlock.c -- host tests for core/spinlock.h (DRA-556).
 *
 * Mutual exclusion under contention, FIFO order (fairness), counter wrap, and the interrupt mask: on a host a
 * thread's interrupt is CK_SPIN_HOST_IRQ_SIGNAL (SIGUSR1). A handler that takes a lock its own thread holds must
 * be deferred until the unlock; without the mask it spins on its own ticket forever. A watchdog thread turns that
 * hang into "test_spinlock: FAIL" (an alarm, not a cap: a passing run never waits on it).
 * The TEST-ONLY mutant -DCK_SPIN_TEST_NO_IRQ_MASK must FAIL here (make spinlock-mutant).
 */
#define _GNU_SOURCE
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "spinlock.h"

static int failures;
#define CHECK(c)                                                                 \
    do {                                                                         \
        if (!(c)) {                                                              \
            printf("test_spinlock: CHECK failed %s:%d: %s\n", __FILE__, __LINE__, #c); \
            failures++;                                                          \
        }                                                                        \
    } while (0)

/* ---- watchdog: no progress for STALL_S seconds means a deadlock ---- */
#define STALL_S 5
static volatile uint64_t progress;
static volatile int done;
static const char *volatile phase = "start";

static void *watchdog(void *arg)
{
    (void)arg;
    uint64_t last = (uint64_t)-1;
    int still = 0;
    while (!__atomic_load_n(&done, __ATOMIC_ACQUIRE)) {
        sleep(1);
        uint64_t now = __atomic_load_n(&progress, __ATOMIC_RELAXED);
        still = now == last ? still + 1 : 0;
        last = now;
        if (still >= STALL_S) {
            printf("test_spinlock: FAIL deadlock (no progress for %d s) in phase %s\n", STALL_S, phase);
            fflush(stdout);
            _exit(1);
        }
    }
    return 0;
}
static void tick(void) { __atomic_add_fetch(&progress, 1, __ATOMIC_RELAXED); }

/* ---- 1. mutual exclusion ---- */
#define MX_THREADS 4
#define MX_ITERS 200000
static struct ck_spinlock mx = CK_SPINLOCK_INIT;
static uint64_t mx_count; /* plain, only under mx */

static void *mx_worker(void *arg)
{
    (void)arg;
    for (int i = 0; i < MX_ITERS; i++) {
        ck_spin_lock(&mx);
        uint64_t v = mx_count;
        __asm__ volatile("" ::: "memory");
        mx_count = v + 1;
        ck_spin_unlock(&mx);
        if ((i & 1023) == 0)
            tick();
    }
    return 0;
}

static void test_mutex(void)
{
    phase = "mutex";
    pthread_t th[MX_THREADS];
    for (int i = 0; i < MX_THREADS; i++)
        CHECK(pthread_create(&th[i], 0, mx_worker, 0) == 0);
    for (int i = 0; i < MX_THREADS; i++)
        pthread_join(th[i], 0);
    CHECK(mx_count == (uint64_t)MX_THREADS * MX_ITERS);
    CHECK(!ck_spin_busy(&mx));
}

/* ---- 2. FIFO: B queues before C, so B enters before C ---- */
static struct ck_spinlock ff;
static int ff_order[2], ff_n;

static void *ff_worker(void *arg)
{
    int id = (int)(intptr_t)arg;
    ck_spin_lock(&ff);
    ff_order[ff_n++] = id;
    ck_spin_unlock(&ff);
    return 0;
}

static void wait_ticket(const struct ck_spinlock *l, uint32_t want)
{
    while (__atomic_load_n(&l->ticket, __ATOMIC_ACQUIRE) != want)
        sched_yield();
}

static void fifo_round(uint32_t start)
{
    ff.ticket = ff.serving = start;
    ff.irq = 0;
    ff_n = 0;
    ck_spin_lock(&ff); /* A holds: ticket start */
    pthread_t b, c;
    CHECK(pthread_create(&b, 0, ff_worker, (void *)(intptr_t)1) == 0);
    wait_ticket(&ff, start + 2u); /* B took ticket start+1 */
    CHECK(pthread_create(&c, 0, ff_worker, (void *)(intptr_t)2) == 0);
    wait_ticket(&ff, start + 3u); /* C took ticket start+2 */
    ck_spin_unlock(&ff);
    pthread_join(b, 0);
    pthread_join(c, 0);
    CHECK(ff_n == 2 && ff_order[0] == 1 && ff_order[1] == 2);
    CHECK(ff.ticket == start + 3u && ff.serving == start + 3u);
    tick();
}

static void test_fifo(void)
{
    phase = "fifo";
    for (int r = 0; r < 200; r++)
        fifo_round((uint32_t)r * 7919u);
    phase = "fifo-wrap";
    for (uint32_t s = 0xFFFFFFFCu; s != 2u; s++) /* rounds that cross 2^32 */
        fifo_round(s);
}

/* ---- 3. interrupt mask ---- */
static struct ck_spinlock ia = CK_SPINLOCK_INIT, ib = CK_SPINLOCK_INIT;
static volatile sig_atomic_t irq_ran, irq_saw_busy;

static void on_irq(int sig)
{
    (void)sig;
    if (ck_spin_busy(&ia))
        irq_saw_busy = 1;
    ck_spin_lock(&ia); /* the interrupt takes the lock its own CPU (thread) may hold */
    irq_ran++;
    ck_spin_unlock(&ia);
}

static int irq_blocked(void)
{
    sigset_t cur;
    pthread_sigmask(SIG_SETMASK, 0, &cur);
    return sigismember(&cur, CK_SPIN_HOST_IRQ_SIGNAL) == 1;
}

static void test_irq(void)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_irq;
    sigemptyset(&sa.sa_mask);
    CHECK(sigaction(CK_SPIN_HOST_IRQ_SIGNAL, &sa, 0) == 0);

    phase = "irq-open";
    irq_ran = 0;
    pthread_kill(pthread_self(), CK_SPIN_HOST_IRQ_SIGNAL); /* lock free: the handler runs at once */
    CHECK(irq_ran == 1);
    tick();

    phase = "irq-held";
    irq_ran = irq_saw_busy = 0;
    ck_spin_lock(&ia);
    CHECK(irq_blocked());
    pthread_kill(pthread_self(), CK_SPIN_HOST_IRQ_SIGNAL); /* raised while held: must wait */
    tick();
    CHECK(irq_ran == 0);
    ck_spin_unlock(&ia); /* delivered here, after the release */
    CHECK(irq_ran == 1);
    CHECK(irq_saw_busy == 0);
    CHECK(!irq_blocked());
    tick();

    phase = "irq-nested";
    irq_ran = 0;
    ck_irqflags_t fa = ck_spin_lock_irqsave(&ib);
    ck_spin_lock(&ia);
    pthread_kill(pthread_self(), CK_SPIN_HOST_IRQ_SIGNAL);
    tick();
    ck_spin_unlock(&ia); /* inner restore keeps the outer mask */
    CHECK(irq_ran == 0);
    CHECK(irq_blocked());
    ck_spin_unlock_irqrestore(&ib, fa);
    CHECK(irq_ran == 1);
    tick();

    phase = "irq-premasked";
    sigset_t one;
    sigemptyset(&one);
    sigaddset(&one, CK_SPIN_HOST_IRQ_SIGNAL);
    pthread_sigmask(SIG_BLOCK, &one, 0);
    ck_spin_lock(&ia);
    ck_spin_unlock(&ia);
    CHECK(irq_blocked()); /* a caller that had interrupts off gets them back off */
    pthread_sigmask(SIG_UNBLOCK, &one, 0);
    tick();
}

int main(void)
{
    pthread_t wd;
    if (pthread_create(&wd, 0, watchdog, 0) != 0)
        return 2;
    ck_spin_init(&ff);
    test_mutex();
    test_fifo();
    test_irq();
    __atomic_store_n(&done, 1, __ATOMIC_RELEASE);
    pthread_join(wd, 0);
    printf("test_spinlock: %s (%d failures)\n", failures ? "FAIL" : "PASS", failures);
    return failures ? 1 : 0;
}
