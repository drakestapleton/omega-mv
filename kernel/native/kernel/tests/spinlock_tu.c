/* spinlock_tu.c -- one freestanding translation unit around core/spinlock.h, compiled by "make spinlock-asm-check"
 * for aarch64 and x86-64 so tools/ck_spinlock_asm_check.sh can check the instruction order. Not linked anywhere.
 *
 * ck_spin_asm_locked: the explicit pair (ck_spin_lock_irqsave / ck_spin_unlock_irqrestore).
 * ck_spin_asm_slot_lock, ck_spin_asm_slot_unlock: the form core/pipe.c uses (ck_spin_lock / ck_spin_unlock), whose
 * saved state lives in the lock (l->irq). Two functions, as in pipe.c, so the unlock has to load l->irq from memory. */
#include "spinlock.h"

struct ck_spinlock ck_spin_asm_lock;
struct ck_spinlock ck_spin_asm_slot;
unsigned ck_spin_asm_count;

void ck_spin_asm_locked(void);
void ck_spin_asm_locked(void)
{
    ck_irqflags_t f = ck_spin_lock_irqsave(&ck_spin_asm_lock);
    ck_spin_asm_count++;
    ck_spin_unlock_irqrestore(&ck_spin_asm_lock, f);
}

void ck_spin_asm_slot_lock(void);
void ck_spin_asm_slot_lock(void)
{
    ck_spin_lock(&ck_spin_asm_slot);
}

void ck_spin_asm_slot_unlock(void);
void ck_spin_asm_slot_unlock(void)
{
    ck_spin_unlock(&ck_spin_asm_slot);
}
