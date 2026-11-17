/* spinlock.h -- the kernel's one spinlock type: a fair (FIFO) ticket lock. Its default acquire masks interrupts
 * on the calling CPU for as long as the lock is held.
 *
 * The lock is the ticket lock that core/pipe.c carried privately (pipe.c:40-51 at d01b2f19, pool_lock /
 * pool_unlock, the same __atomic_* orders core/smp.c uses), moved here. Every spinning lock in the kernel tree is
 * this type: the pipe pool lock (core/pipe.c), Allen's note lock (ui/allen_ui.c) and the iMac frame lock
 * (x86/kmain_x86.c draw_lock).
 *
 *   ticket   the next number handed out; a caller takes one with a relaxed fetch-add.
 *   serving  the number now inside; the caller spins (acquire) until serving == its number, and the
 *            holder releases by storing serving + 1 (release). Both equal means unlocked.
 *
 * Fair: callers enter in the order they took tickets. Mutual exclusion holds while fewer than 2^32 callers wait on
 * one lock at once (the counters wrap; only equality is compared). Proof of the arithmetic and of the interrupt
 * ordering below: proofs/TicketLock.lean (make ticketlock-proof).
 *
 * Interrupts (the default pair). ck_spin_lock_irqsave masks interrupts on this CPU BEFORE it takes a ticket and
 * returns the previous mask; ck_spin_unlock_irqrestore releases the lock and THEN puts that mask back. So an
 * interrupt handler on the CPU that holds (or is queued for) a lock cannot spin on that same lock and deadlock
 * the CPU against itself; the interrupt is taken after the unlock instead. Nested locks restore in reverse order
 * and the outermost restore re-opens interrupts. A caller that already had interrupts masked gets them back masked.
 *
 *   aarch64 kernel  DAIF.I and DAIF.F are set ("msr daifset, #3"); the saved DAIF is written back. arch/arch.h
 *                   ck_irq_off masks I only; this lock also masks F so a FIQ handler, if one is ever installed, is
 *                   covered too. SError (A) and debug (D) are not masked.
 *   x86-64 kernel   RFLAGS is saved and "cli" runs; IF is set again only if it was set before. NMI cannot be masked
 *                   by cli: an NMI handler must never take a ck_spinlock. Reading RFLAGS uses pushfq inside inline
 *                   asm, which is safe only because the x86 kernel is built with -mno-red-zone (X86CFLAGS).
 *   hosted build    (host unit tests, __STDC_HOSTED__) a thread's interrupt is the signal CK_SPIN_HOST_IRQ_SIGNAL
 *                   (default SIGUSR1); "masked" means that signal is blocked for the thread, and the saved value
 *                   says whether it already was. Only that one signal is touched: synchronous faults (SIGSEGV,
 *                   SIGBUS) are never deferred. While waiting, a host thread yields its CPU (ck_spin_relax).
 *
 * ck_spin_lock / ck_spin_unlock are the same pair with the saved state kept in the lock itself: only the holder
 * writes l->irq (after it entered) and reads it (before it leaves), so the next holder cannot see or clobber it.
 * Locks must be released in reverse order of taking, with either pair.
 *
 * The _nomask forms (lock, trylock, unlock) take the same ticket lock and leave interrupts as they are. Use them
 * only for a lock that no interrupt handler ever takes AND whose holders or waiters must keep taking interrupts:
 * the iMac kernel's drawing cores keep interrupts on to acknowledge TLB-shootdown IPIs (x86/kmain_x86.c), and a
 * core spinning with interrupts masked for a lock whose holder waits on that acknowledgement would deadlock.
 * A trylock succeeds only when nobody holds or waits (it never jumps the queue).
 *
 * Code that holds a lock must not sleep or park: a wait hook runs after the unlock (see core/pipe.c).
 *
 * Why C and not Omega: every user is a C translation unit of the C kernel, the lock is inlined into the caller's
 * critical section, and it runs privileged instructions (mrs/msr daif, pushfq/cli/sti). The newest omc builds
 * standalone programs, and the omega-bridge freestanding route emits separate units; neither gives an inline unit a
 * C kernel includes, with system-register access (aienux AGENTS.md section 6: C where a hardware reason exists).
 *
 * TEST-ONLY (host builds only; a freestanding build refuses them):
 *   CK_SPIN_TEST_STEP(l)                 called between the two steps of acquire (mask, ticket) and of release
 *                                        (release, restore); test_spinlock raises an interrupt there.
 *   CK_SPIN_TEST_NO_IRQ_MASK             mutant: the mask is a no-op.
 *   CK_SPIN_TEST_TICKET_BEFORE_MASK      mutant: the ticket is taken before the mask.
 *   CK_SPIN_TEST_RESTORE_BEFORE_RELEASE  mutant: the mask is restored before the release.
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

#if (defined(CK_SPIN_TEST_NO_IRQ_MASK) || defined(CK_SPIN_TEST_TICKET_BEFORE_MASK) ||                                \
     defined(CK_SPIN_TEST_RESTORE_BEFORE_RELEASE) || defined(CK_SPIN_TEST_STEP)) &&                                    \
    !__STDC_HOSTED__
#error "CK_SPIN_TEST_* are TEST-ONLY host hooks and mutants"
#endif

#ifndef CK_SPIN_TEST_STEP
#define CK_SPIN_TEST_STEP(l) ((void)(l))
#endif

#if __STDC_HOSTED__
#include <pthread.h>
#include <signal.h>
int sched_yield(void); /* POSIX <sched.h>; declared here because some host builds put core/ (core/sched.h) on -I */
#ifndef CK_SPIN_HOST_IRQ_SIGNAL
#define CK_SPIN_HOST_IRQ_SIGNAL SIGUSR1
#endif
#endif

static inline void ck_spin_relax(void)
{
#if __STDC_HOSTED__
    /* A host thread is not a CPU: the holder or the next ticket may be descheduled on this very CPU, so give it the
     * CPU (with fewer CPUs than threads a fair lock otherwise convoys for seconds per handoff). */
    sched_yield();
#elif defined(__aarch64__)
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

/* Take a ticket and wait for it. Interrupts are left as they are. */
static inline void ck_spin_lock_nomask(struct ck_spinlock *l)
{
    uint32_t me = __atomic_fetch_add(&l->ticket, 1u, __ATOMIC_RELAXED);
    while (__atomic_load_n(&l->serving, __ATOMIC_ACQUIRE) != me)
        ck_spin_relax();
}

/* 1 and the lock is held if nobody held or waited for it; 0 and nothing changed otherwise. */
static inline int ck_spin_trylock_nomask(struct ck_spinlock *l)
{
    uint32_t s = __atomic_load_n(&l->serving, __ATOMIC_ACQUIRE); /* pairs with the last holder's release */
    uint32_t t = s;
    return __atomic_compare_exchange_n(&l->ticket, &t, s + 1u, 0, __ATOMIC_ACQUIRE, __ATOMIC_RELAXED);
}

/* Hand the lock to the next ticket. Interrupts are left as they are. */
static inline void ck_spin_unlock_nomask(struct ck_spinlock *l)
{
    uint32_t next = __atomic_load_n(&l->serving, __ATOMIC_RELAXED) + 1u;
    __atomic_store_n(&l->serving, next, __ATOMIC_RELEASE);
}

/* Mask interrupts, then wait for this caller's turn. Returns the state to restore. */
static inline ck_irqflags_t ck_spin_lock_irqsave(struct ck_spinlock *l)
{
#if defined(CK_SPIN_TEST_TICKET_BEFORE_MASK)
    uint32_t me = __atomic_fetch_add(&l->ticket, 1u, __ATOMIC_RELAXED);
    CK_SPIN_TEST_STEP(l);
    ck_irqflags_t f = ck_irq_save();
    while (__atomic_load_n(&l->serving, __ATOMIC_ACQUIRE) != me)
        ck_spin_relax();
#else
    ck_irqflags_t f = ck_irq_save();
    CK_SPIN_TEST_STEP(l);
    ck_spin_lock_nomask(l);
#endif
    return f;
}

/* Hand the lock to the next ticket, then restore the interrupt state saved by the matching lock. */
static inline void ck_spin_unlock_irqrestore(struct ck_spinlock *l, ck_irqflags_t f)
{
#if defined(CK_SPIN_TEST_RESTORE_BEFORE_RELEASE)
    ck_irq_restore(f);
    CK_SPIN_TEST_STEP(l);
    ck_spin_unlock_nomask(l);
#else
    ck_spin_unlock_nomask(l);
    CK_SPIN_TEST_STEP(l);
    ck_irq_restore(f);
#endif
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
