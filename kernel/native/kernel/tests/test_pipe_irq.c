/* test_pipe_irq.c -- race test for DRA-556: a pipe op reached from an interrupt on the CPU that holds the pool lock.
 *
 * Uses only the public pipe API (pipe.h), so the same file builds against the tree before and after DRA-556.
 * On a host a thread's interrupt is SIGUSR1 (core/spinlock.h, CK_SPIN_HOST_IRQ_SIGNAL). The main thread calls
 * ck_pipe_pool_empty in a loop (it holds the pool lock while it scans every pipe); a second thread raises SIGUSR1
 * at the main thread as fast as it can, and the handler calls ck_pipe_pool_empty too.
 *   before (private ticket lock, interrupts open): a signal lands inside the lock, the handler takes the next
 *          ticket and spins forever on its own thread -> no progress -> "test_pipe_irq: FAIL deadlock".
 *   after  (shared spinlock, interrupts masked while held): the signal waits for the unlock -> PASS.
 * The watchdog is an alarm on stalled progress, not a cap on the run.
 */
#define _GNU_SOURCE
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "pipe.h"

#define ROUNDS 50000u
#define STALL_S 5

static struct ck_pipe_pool pool;
static pthread_t main_th;
static volatile uint64_t progress, handled, raised;
static volatile int stop, done;

static void on_irq(int sig)
{
    (void)sig;
    (void)ck_pipe_pool_empty(&pool);
    handled++;
    __atomic_add_fetch(&progress, 1, __ATOMIC_RELAXED);
}

static void *irq_source(void *arg)
{
    (void)arg;
    while (!__atomic_load_n(&stop, __ATOMIC_ACQUIRE)) {
        pthread_kill(main_th, SIGUSR1);
        __atomic_add_fetch(&raised, 1, __ATOMIC_RELAXED);
        for (volatile int i = 0; i < 200; i++)
            ;
    }
    return 0;
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
            printf("test_pipe_irq: FAIL deadlock: no progress for %d s (raised=%llu handled=%llu)\n", STALL_S,
                   (unsigned long long)raised, (unsigned long long)handled);
            fflush(stdout);
            _exit(1);
        }
    }
    return 0;
}

int main(void)
{
    ck_pipe_pool_init(&pool, 0);
    main_th = pthread_self();
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_irq;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_RESTART;
    if (sigaction(SIGUSR1, &sa, 0) != 0)
        return 2;

    pthread_t wd, src;
    if (pthread_create(&wd, 0, watchdog, 0) != 0 || pthread_create(&src, 0, irq_source, 0) != 0)
        return 2;
    int bad = 0;
    for (unsigned r = 0; r < ROUNDS; r++) {
        if (!ck_pipe_pool_empty(&pool))
            bad++;
        __atomic_add_fetch(&progress, 1, __ATOMIC_RELAXED);
    }
    __atomic_store_n(&stop, 1, __ATOMIC_RELEASE);
    pthread_join(src, 0);
    __atomic_store_n(&done, 1, __ATOMIC_RELEASE);
    pthread_join(wd, 0);
    int ok = bad == 0 && handled > 0;
    printf("test_pipe_irq: %s rounds=%u raised=%llu handled=%llu bad=%d\n", ok ? "PASS" : "FAIL", ROUNDS,
           (unsigned long long)raised, (unsigned long long)handled, bad);
    return ok ? 0 : 1;
}
