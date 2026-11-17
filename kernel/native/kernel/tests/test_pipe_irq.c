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
 * PASS also needs at least MIN_HANDLED interrupts handled, so a run where the timer barely fired is a FAIL, not a
 * pass. The watchdog thread (SIGUSR1 blocked) is an alarm on stalled progress, not a cap on the run.
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

#define ROUNDS 200000u
#define MIN_HANDLED 1000u
#define TICK_NS 20000L
#define STALL_S 5

static struct ck_pipe_pool pool;
static volatile uint64_t progress, handled;
static volatile int done;

static void on_irq(int sig)
{
    (void)sig;
    (void)ck_pipe_pool_empty(&pool);
    handled++;
    __atomic_add_fetch(&progress, 1, __ATOMIC_RELAXED);
}

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
            printf("test_pipe_irq: FAIL deadlock: no progress for %d s (handled=%llu)\n", STALL_S,
                   (unsigned long long)handled);
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
    if (timer_settime(tm, 0, &it, 0) != 0)
        return 2;

    int bad = 0;
    for (unsigned r = 0; r < ROUNDS; r++) {
        if (!ck_pipe_pool_empty(&pool))
            bad++;
        __atomic_add_fetch(&progress, 1, __ATOMIC_RELAXED);
    }
    timer_delete(tm);
    __atomic_store_n(&done, 1, __ATOMIC_RELEASE);
    pthread_join(wd, 0);
    int ok = bad == 0 && handled >= MIN_HANDLED;
    printf("test_pipe_irq: %s rounds=%u handled=%llu (min %u) bad=%d\n", ok ? "PASS" : "FAIL", ROUNDS,
           (unsigned long long)handled, MIN_HANDLED, bad);
    return ok ? 0 : 1;
}
