#!/usr/bin/env bash
# ck_spinlock_asm_check.sh A64.dis X86.dis -- reads `objdump -dr` of native/kernel/tests/spinlock_tu.c (function
# ck_spin_asm_locked: ck_spin_lock_irqsave + ck_spin_unlock_irqrestore on struct ck_spinlock ck_spin_asm_lock) built
# freestanding for aarch64 and x86-64 (make spinlock-asm-check, DRA-556). Checks the order core/spinlock.h promises
# and that the atomics touch the right fields (ticket at offset 0, serving at offset 4):
#   aarch64  mrs daif < msr daifset #3 < ticket atomic (ldxr/ldaxr/ldadd/cas on [xT]) ; stlr to [xS] < msr daif,
#            where xS = xT + 4 (an "add xS, xT, #0x4").
#   x86-64   pushf < cli < lock xadd whose relocation is ck_spin_asm_lock-0x4 (PC32 addend for offset 0) ;
#            the last mov to memory before sti has relocation ck_spin_asm_lock (offset 4), then sti.
# Only this one translation unit is checked; the inlined copies elsewhere rely on the same asm volatile "memory"
# clobbers. Last line: CK_SPINLOCK_ASM: PASS|FAIL.
set -uo pipefail
if [[ "${1:-}" == "--selftest" ]]; then
    # Negative controls: each mutated dump must FAIL. swap A B: exchange the first line matching A and the last line
    # matching B (order mutants); drop A: delete lines matching A.
    shift; A=$1; X=$2; t=$(mktemp -d); bad=0
    swap() { awk -v a="$2" -v b="$3" '{l[NR]=$0} $0~a&&!i{i=NR} $0~b{j=NR} END{if(i&&j){t=l[i];l[i]=l[j];l[j]=t} for(k=1;k<=NR;k++)print l[k]}' "$1"; }
    neg() { if bash "$0" "$2" "$3" > "$t/out" 2>&1; then cat "$t/out"; echo "NEG FAIL: $1 not caught"; bad=1;
            else grep -qF "CK_SPINLOCK_ASM: FAIL" "$t/out" && echo "NEG PASS: $1 caught" || { echo "NEG FAIL: $1 (no verdict)"; bad=1; }; fi; }
    grep -v daifset "$A" > "$t/a1"; neg "a64 mask removed" "$t/a1" "$X"
    swap "$A" 'daifset' '[[:space:]]ldxr[[:space:]]' > "$t/a2"; neg "a64 ticket atomic before mask" "$t/a2" "$X"
    swap "$A" '[[:space:]]stlr[[:space:]]' 'msr[[:space:]]+daif, x' > "$t/a3"; neg "a64 restore before release" "$t/a3" "$X"
    grep -vE '[[:space:]]cli' "$X" > "$t/x1"; neg "x86 cli removed" "$A" "$t/x1"
    swap "$X" '[[:space:]]cli' 'lock xadd' > "$t/x2"; neg "x86 xadd before cli" "$A" "$t/x2"
    sed 's/ck_spin_asm_lock$/ck_spin_asm_count/' "$X" > "$t/x3"; neg "x86 release store to another symbol" "$A" "$t/x3"
    rm -rf "$t"; echo "CK_SPINLOCK_ASM_SELFTEST: $([[ $bad == 0 ]] && echo PASS || echo FAIL)"; exit $bad
fi
fn() { awk '/<ck_spin_asm_locked>:/{on=1;next} on&&/^$/{exit} on{print}' "$1"; }
line() { grep -nE "$2" <<<"$1" | head -n1 | cut -d: -f1 || true; }
lastline() { grep -nE "$2" <<<"$1" | tail -n1 | cut -d: -f1 || true; }
fail=0
check() { if [[ -n "$2" && -n "$3" && "$2" -lt "$3" ]]; then echo "PASS  $1 (line $2 < line $3)"; else echo "FAIL  $1 (lines '$2' '$3')"; fail=1; fi; }
truth() { if [[ "$2" == 1 ]]; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi; }

a=$(fn "$1")
mrs=$(line "$a" 'mrs[[:space:]]+x[0-9]+, daif')
set3=$(line "$a" 'msr[[:space:]]+daifset, #0x3')
atom=$(line "$a" '[[:space:]](ldxr|ldaxr|ldadd[a-z]*|cas[a-z]*)[[:space:]]')
stlr=$(lastline "$a" '[[:space:]]stlr[[:space:]]')
rest=$(lastline "$a" 'msr[[:space:]]+daif, x[0-9]+')
check "a64: DAIF saved before the mask" "$mrs" "$set3"
check "a64: mask (daifset #3) before the ticket atomic" "$set3" "$atom"
check "a64: releasing stlr before msr daif restore" "$stlr" "$rest"
treg=$(sed -n "${atom:-0}p" <<<"$a" | grep -oE '\[x[0-9]+\]' | tr -d '[]' || true)
sreg=$(sed -n "${stlr:-0}p" <<<"$a" | grep -oE '\[x[0-9]+\]' | tr -d '[]' || true)
ok=0; [[ -n "$treg" && -n "$sreg" ]] && grep -qE "add[[:space:]]+$sreg, $treg, #0x4" <<<"$a" && ok=1
truth "a64: stlr writes serving (ticket base $treg + 4 = $sreg)" "$ok"

x=$(fn "$2")
pushf=$(line "$x" 'pushf')
cli=$(line "$x" '[[:space:]]cli')
xadd=$(line "$x" 'lock xadd')
sti=$(lastline "$x" '[[:space:]]sti')
rel=$(awk -v s="${sti:-0}" 'NR<s && /mov[l]?[[:space:]]+%[a-z0-9]+,.*\(%rip\)/{n=NR} END{print n}' <<<"$x")
check "x86: RFLAGS read (pushf) before cli" "$pushf" "$cli"
check "x86: cli before the ticket xadd" "$cli" "$xadd"
check "x86: releasing store before sti" "$rel" "$sti"
reloc_after() { awk -v n="${2:-0}" 'NR>n && /R_X86_64_PC32/{print $NF; exit}' <<<"$1"; }
ok=0; [[ "$(reloc_after "$x" "$xadd")" == "ck_spin_asm_lock-0x4" ]] && ok=1
truth "x86: xadd targets ticket (reloc ck_spin_asm_lock-0x4)" "$ok"
ok=0; [[ "$(reloc_after "$x" "$rel")" == "ck_spin_asm_lock" ]] && ok=1
truth "x86: releasing store targets serving (reloc ck_spin_asm_lock)" "$ok"
echo "CK_SPINLOCK_ASM: $([[ $fail == 0 ]] && echo PASS || echo FAIL)"
exit $fail
