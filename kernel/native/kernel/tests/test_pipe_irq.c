/* test_pipe_irq.c -- race test for DRA-556: a pipe op reached from an interrupt on the CPU that holds the pool lock.
 *
 * Uses only the public pipe API (pipe.h), so the same file builds against the tree before and after DRA-556.
 * On a host a thread's interrupt is SIGUSR1 (core/spinlock.h, CK_SPIN_HOST_IRQ_SIGNAL). A periodic POSIX timer
 * (CLOCK_MONOTONIC, every 20 us) raises SIGUSR1 at the main thread itself (SIGEV_THREAD_ID), so it lands wherever
 * the main thread is, asynchronously, on any number of CPUs. The main thread calls ck_pipe_pool_empty in a loop (it
 * holds the pool lock while it scans every pipe); the handler calls ck_pipe_pool_empty too.
 *   before (private ticket lock, interrupts open): a tick lands inside the lock, the handler takes the next ticket and
 *          spins forever on its own thread -> no progress -> "test_pipe_irq: FAIL deadlock".
 *   after  (shared spinlock, interrupts masked while held): the tick waits for the unlock -> PASS.
 * The run is measured in interrupts, not rounds: it loops until MIN_INSIDE interrupts have been handled that arrived
 * while the main thread was inside ck_pipe_pool_empty (the case DRA-556 is about; with the lock masking interrupts
 * they run at its unlock, still inside the call). How many rounds that takes depends on the host and does not
 * decide the verdict (before: a fixed 200000 rounds had to see 1000 interrupts, so a faster host could FAIL).
 * The watchdog thread (SIGUSR1 blocked) has two alarms, not caps: no progress at all for STALL_S seconds (the
 * deadlock), and rounds going on while no interrupt was handled for STALL_S seconds (the timer stopped).
 */
#define _GNU_SOURCE
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

#include "pipe.h"

#define MIN_INSIDE 1000u
/* TEST-ONLY overrides (make spinlock-mutant): -DTICK_NS=2000000, a timer 100 times slower (the same as a host
 * 100 times faster), must still PASS; -DTEST_PIPE_IRQ_NO_TIMER must FAIL with the timer alarm, not loop forever. */
#ifndef TICK_NS
#define TICK_NS 20000L
#endif
#define STALL_S 5

static struct ck_pipe_pool pool;
static volatile uint64_t progress, handled, inside;
static volatile int done, in_op;

static void on_irq(int sig)
{
    (void)sig;
    if (in_op)
        inside++;
    (void)ck_pipe_pool_empty(&pool);
    handled++;
    __atomic_add_fetch(&progress, 1, __ATOMIC_RELAXED);
}

static void *watchdog(void *arg)
{
    (void)arg;
    uint64_t last = (uint64_t)-1, last_h = (uint64_t)-1;
    int still = 0, still_h = 0;
    while (!__atomic_load_n(&done, __ATOMIC_ACQUIRE)) {
        sleep(1);
        uint64_t now = __atomic_load_n(&progress, __ATOMIC_RELAXED);
        uint64_t h = __atomic_load_n(&handled, __ATOMIC_RELAXED);
        still = now == last ? still + 1 : 0;
        still_h = h == last_h ? still_h + 1 : 0;
        last = now;
        last_h = h;
        if (still >= STALL_S) {
            printf("test_pipe_irq: FAIL deadlock: no progress for %d s (handled=%llu)\n", STALL_S,
                   (unsigned long long)h);
            fflush(stdout);
            _exit(1);
        }
        if (still_h >= STALL_S) {
            printf("test_pipe_irq: FAIL no interrupt handled for %d s (handled=%llu inside=%llu of %u): the timer "
                   "stopped\n", STALL_S, (unsigned long long)h, (unsigned long long)inside, MIN_INSIDE);
            fflush(stdout);
            _exit(1);
        }
    }
    return 0;
}

int main(void)
{
    ck_pipe_pool_init(&pool, 0);
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_irq;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_RESTART;
    if (sigaction(SIGUSR1, &sa, 0) != 0)
        return 2;

    /* The watchdog never takes the interrupt: block SIGUSR1 before creating it (it inherits the mask). */
    sigset_t one;
    sigemptyset(&one);
    sigaddset(&one, SIGUSR1);
    pthread_sigmask(SIG_BLOCK, &one, 0);
    pthread_t wd;
    if (pthread_create(&wd, 0, watchdog, 0) != 0)
        return 2;
    pthread_sigmask(SIG_UNBLOCK, &one, 0);

    struct sigevent ev;
    memset(&ev, 0, sizeof ev);
    ev.sigev_notify = SIGEV_THREAD_ID;
    ev.sigev_signo = SIGUSR1;
    ev._sigev_un._tid = (pid_t)syscall(SYS_gettid);
    timer_t tm;
    if (timer_create(CLOCK_MONOTONIC, &ev, &tm) != 0)
        return 2;
    struct itimerspec it = { { 0, TICK_NS }, { 0, TICK_NS } };
#ifndef TEST_PIPE_IRQ_NO_TIMER
    if (timer_settime(tm, 0, &it, 0) != 0)
        return 2;
#else
    (void)it;
#endif

    int bad = 0;
    uint64_t rounds = 0;
    while (inside < MIN_INSIDE) {
        in_op = 1;
        int empty = ck_pipe_pool_empty(&pool);
        in_op = 0;
        if (!empty)
            bad++;
        rounds++;
        __atomic_add_fetch(&progress, 1, __ATOMIC_RELAXED);
    }
    timer_delete(tm);
    __atomic_store_n(&done, 1, __ATOMIC_RELEASE);
    pthread_join(wd, 0);
    int ok = bad == 0 && inside >= MIN_INSIDE;
    printf("test_pipe_irq: %s rounds=%llu handled=%llu inside=%llu (min %u) bad=%d\n", ok ? "PASS" : "FAIL",
           (unsigned long long)rounds, (unsigned long long)handled, (unsigned long long)inside, MIN_INSIDE, bad);
    return ok ? 0 : 1;
}
