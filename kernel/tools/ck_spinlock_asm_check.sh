#!/usr/bin/env bash
# ck_spinlock_asm_check.sh A64.dis X86.dis -- reads objdump -d of native/kernel/tests/spinlock_tu.c (function
# ck_spin_asm_locked) built freestanding for aarch64 and x86-64 (make spinlock-asm-check, DRA-556) and checks the
# order core/spinlock.h promises: interrupts masked before the first atomic of the acquire, the releasing store
# before the restore. Last line: CK_SPINLOCK_ASM: PASS|FAIL.
set -uo pipefail
fn() { awk '/<ck_spin_asm_locked>:/{on=1;next} on&&/^$/{exit} on{print}' "$1"; }
line() { grep -nE "$2" <<<"$1" | head -n1 | cut -d: -f1 || true; }
lastline() { grep -nE "$2" <<<"$1" | tail -n1 | cut -d: -f1 || true; }
fail=0
check() { if [[ -n "$2" && -n "$3" && "$2" -lt "$3" ]]; then echo "PASS  $1 (line $2 < line $3)"; else echo "FAIL  $1 (lines '$2' '$3')"; fail=1; fi; }

a=$(fn "$1")
mrs=$(line "$a" 'mrs[[:space:]]+x[0-9]+, daif')
set3=$(line "$a" 'msr[[:space:]]+daifset, #0x3')
atom=$(line "$a" 'ldadd|ldxr|ldaxr|cas')
stlr=$(lastline "$a" 'stlr')
rest=$(lastline "$a" 'msr[[:space:]]+daif, x[0-9]+')
check "a64: DAIF saved before the mask" "$mrs" "$set3"
check "a64: mask (daifset #3) before the ticket atomic" "$set3" "$atom"
check "a64: releasing stlr before msr daif restore" "$stlr" "$rest"

x=$(fn "$2")
pushf=$(line "$x" 'pushf')
cli=$(line "$x" '[[:space:]]cli')
xadd=$(line "$x" 'lock xadd|lock add|xadd')
sti=$(lastline "$x" '[[:space:]]sti')
# the releasing store of serving is the last mov to memory before sti
rel=$(awk -v s="$sti" 'NR<s && /mov[l]?[[:space:]]+%[a-z0-9]+,.*\(/{n=NR} END{print n}' <<<"$x")
check "x86: RFLAGS read (pushf) before cli" "$pushf" "$cli"
check "x86: cli before the ticket xadd" "$cli" "$xadd"
check "x86: releasing store before sti" "$rel" "$sti"
echo "CK_SPINLOCK_ASM: $([[ $fail == 0 ]] && echo PASS || echo FAIL)"
exit $fail
