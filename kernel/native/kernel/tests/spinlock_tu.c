/* spinlock_tu.c -- one freestanding translation unit around core/spinlock.h, compiled by "make spinlock-asm-check"
 * for aarch64 and x86-64 so tools/ck_spinlock_asm_check.sh can check the instruction order. Not linked anywhere. */
#include "spinlock.h"

struct ck_spinlock ck_spin_asm_lock;
unsigned ck_spin_asm_count;

void ck_spin_asm_locked(void);
void ck_spin_asm_locked(void)
{
    ck_irqflags_t f = ck_spin_lock_irqsave(&ck_spin_asm_lock);
    ck_spin_asm_count++;
    ck_spin_unlock_irqrestore(&ck_spin_asm_lock, f);
}
