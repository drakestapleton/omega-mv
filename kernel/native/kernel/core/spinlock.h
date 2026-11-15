/* spinlock.h -- the kernel's one spinlock type: a fair (FIFO) ticket lock that masks interrupts on the
 * calling CPU for as long as it is held.
 *
 * The lock is the ticket lock that core/pipe.c carried privately (pool_lock / pool_unlock, the same
 * __atomic_* orders core/smp.c uses), moved here so every kernel lock is the same type.
 *
 *   ticket   the next number handed out; a caller takes one with a relaxed fetch-add.
 *   serving  the number now inside; the caller spins (acquire) until serving == its number, and the
 *            holder releases by storing serving + 1 (release). Both equal means unlocked.
 *
 * Fair: callers enter in the order they took tickets. Mutual exclusion holds while fewer than 2^32
 * callers wait on one lock at once (the counters wrap; only equality is compared).
 *
 * Interrupts. ck_spin_lock_irqsave masks interrupts on this CPU BEFORE it takes a ticket and returns the
 * previous mask; ck_spin_unlock_irqrestore releases the lock and THEN puts that mask back. So an
 * interrupt handler on the CPU that holds (or is queued for) a lock cannot spin on that same lock and
 * deadlock the CPU against itself; the interrupt is taken after the unlock instead. Nested locks
 * restore in reverse order and the outermost restore re-opens interrupts.
 *
 *   aarch64 kernel  DAIF.I and DAIF.F are set ("msr daifset, #3"); the saved DAIF is written back.
 *   x86-64 kernel   RFLAGS is saved and "cli" runs; IF is set again only if it was set before.
 *   hosted build    (host unit tests, __STDC_HOSTED__) a thread's interrupt is the signal
 *                   CK_SPIN_HOST_IRQ_SIGNAL (default SIGUSR1); "masked" means that signal is blocked
 *                   for the thread, and the saved value says whether it already was. Only that one
 *                   signal is touched: synchronous faults (SIGSEGV, SIGBUS) are never deferred.
 *
 * ck_spin_lock / ck_spin_unlock are the same pair with the saved state kept in the lock itself: only the
 * holder writes l->irq (after it entered) and reads it (before it leaves), so the next holder cannot see
 * or clobber it. Locks must be released in reverse order of taking, with either pair.
 *
 * Code that holds a lock must not sleep or park: a wait hook runs after the unlock (see core/pipe.c).
 * CK_SPIN_TEST_NO_IRQ_MASK (TEST-ONLY, host mutant) turns the mask into a no-op so the race test can be
 * shown to catch the self-deadlock; a freestanding build refuses it.
 */
#ifndef AIENOS_CK_SPINLOCK_H
#define AIENOS_CK_SPINLOCK_H

#include <stdint.h>

/* Saved interrupt state returned by ck_spin_lock_irqsave; pass it back unchanged. */
typedef uint64_t ck_irqflags_t;

struct ck_spinlock {
    uint32_t ticket;   /* next number handed out */
    uint32_t serving;  /* number now inside */
    ck_irqflags_t irq; /* ck_spin_lock only: the holder's saved state; written after entry, read before exit */
};

#define CK_SPINLOCK_INIT { 0u, 0u, 0u }

#if defined(CK_SPIN_TEST_NO_IRQ_MASK) && !__STDC_HOSTED__
#error "CK_SPIN_TEST_NO_IRQ_MASK is a TEST-ONLY host mutant"
#endif

#if __STDC_HOSTED__
#include <signal.h>
#ifndef CK_SPIN_HOST_IRQ_SIGNAL
#define CK_SPIN_HOST_IRQ_SIGNAL SIGUSR1
#endif
#endif

static inline void ck_spin_relax(void)
{
#if defined(__aarch64__)
    __asm__ volatile("yield" ::: "memory");
#elif defined(__x86_64__) || defined(__i386__)
    __asm__ volatile("pause" ::: "memory");
#else
    __asm__ volatile("" ::: "memory");
#endif
}

/* Mask interrupts on this CPU; return the previous state. */
static inline ck_irqflags_t ck_irq_save(void)
{
#if defined(CK_SPIN_TEST_NO_IRQ_MASK)
    return 0;
#elif __STDC_HOSTED__
    sigset_t one, old;
    sigemptyset(&one);
    sigaddset(&one, CK_SPIN_HOST_IRQ_SIGNAL);
    pthread_sigmask(SIG_BLOCK, &one, &old);
    return (ck_irqflags_t)(sigismember(&old, CK_SPIN_HOST_IRQ_SIGNAL) == 1);
#elif defined(__aarch64__)
    uint64_t daif;
    __asm__ volatile("mrs %0, daif\n\tmsr daifset, #3" : "=r"(daif) : : "memory");
    return daif;
#elif defined(__x86_64__)
    uint64_t rflags;
    __asm__ volatile("pushfq\n\tpopq %0\n\tcli" : "=r"(rflags) : : "memory");
    return rflags;
#else
#error "ck_irq_save: no interrupt mask for this architecture"
#endif
}

/* Put back a state returned by ck_irq_save. */
static inline void ck_irq_restore(ck_irqflags_t f)
{
#if defined(CK_SPIN_TEST_NO_IRQ_MASK)
    (void)f;
#elif __STDC_HOSTED__
    if (!f) {
        sigset_t one;
        sigemptyset(&one);
        sigaddset(&one, CK_SPIN_HOST_IRQ_SIGNAL);
        pthread_sigmask(SIG_UNBLOCK, &one, 0);
    }
#elif defined(__aarch64__)
    __asm__ volatile("msr daif, %0" : : "r"(f) : "memory");
#elif defined(__x86_64__)
    if (f & (1u << 9)) /* RFLAGS.IF */
        __asm__ volatile("sti" ::: "memory");
#endif
}

/* Unlocked. Single-threaded, before the lock is shared. */
static inline void ck_spin_init(struct ck_spinlock *l)
{
    __atomic_store_n(&l->ticket, 0u, __ATOMIC_RELAXED);
    __atomic_store_n(&l->serving, 0u, __ATOMIC_RELAXED);
    l->irq = 0;
}

/* Mask interrupts, then wait for this caller's turn. Returns the state to restore. */
static inline ck_irqflags_t ck_spin_lock_irqsave(struct ck_spinlock *l)
{
    ck_irqflags_t f = ck_irq_save();
    uint32_t me = __atomic_fetch_add(&l->ticket, 1u, __ATOMIC_RELAXED);
    while (__atomic_load_n(&l->serving, __ATOMIC_ACQUIRE) != me)
        ck_spin_relax();
    return f;
}

/* Hand the lock to the next ticket, then restore the interrupt state saved by the matching lock. */
static inline void ck_spin_unlock_irqrestore(struct ck_spinlock *l, ck_irqflags_t f)
{
    uint32_t next = __atomic_load_n(&l->serving, __ATOMIC_RELAXED) + 1u;
    __atomic_store_n(&l->serving, next, __ATOMIC_RELEASE);
    ck_irq_restore(f);
}

/* The same pair, with the saved state kept in the lock (see the header comment). */
static inline void ck_spin_lock(struct ck_spinlock *l)
{
    ck_irqflags_t f = ck_spin_lock_irqsave(l);
    l->irq = f;
}

static inline void ck_spin_unlock(struct ck_spinlock *l)
{
    ck_spin_unlock_irqrestore(l, l->irq);
}

/* 1 while some caller holds or waits for the lock. A snapshot, for assertions and tests only. */
static inline int ck_spin_busy(const struct ck_spinlock *l)
{
    return __atomic_load_n(&l->ticket, __ATOMIC_RELAXED) != __atomic_load_n(&l->serving, __ATOMIC_RELAXED);
}

#endif
