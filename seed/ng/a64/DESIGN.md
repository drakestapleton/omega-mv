# ng a64: ΩIR to AArch64 Linux ELF (design, ng-a64 lane)

Status: IMPLEMENTED and HOST_TESTED for the integer slice below (gates in section 6); the rest is PROPOSED.
Code: `seed/ng/src/a64.om` (unit of `seed/ng/ng.units`, between `ir.om` and `main.om`; functions `a6_*`, globals
`a_*`). Built by `seed/out/omc` (sha256 `5f90edea…`, omega-mv `943d9555`). Facts about seed omc it copies are in
`~/handoffs/hive-ng/a64/REALITY.md` (file:line at `943d9555`).

## 1. Job

`ng` modes owned by this unit (`a6_mode`, called from `main.om` before the unknown-mode exit):

| first line | payload | output |
|---|---|---|
| `@ng a64` | binary ΩIR (`seed/ng/IR.md`) | static AArch64 Linux ELF on stdout; saves as STP/LDP pairs (form A) |
| `@ng a64 split` | binary ΩIR | the same with separate STR/LDR saves (form B) |
| `@ng a64-enc` | encoder case list (`tests/enc.cases`) | one 4-byte word per case |

Exit 0 on success. A refusal writes one stderr line `a64: <class> <n>` and exits with the class: the ΩIR reader's
class (s11) for a refused unit (message `refused IR class, at byte` and `ir_badat`), 5 for `unsupported` (an op,
type or limit outside the slice). The input is trusted to have passed `ngcheck` (IR.md s14: `ir_read` builds sound
tables and leaves semantic rules to ngcheck).

Observable behaviour must equal seed omc on the same source (D5): exit status and trap code. Instruction bytes,
register choice and frame layout are free.

D13 (clean v2 rounds): the default is form A (`@ng a64`, STP/LDP pairs); form B stays behind the `a_sform` switch
(`@ng a64 split`). Every function entry is aligned to 64 bytes: on A725 placement explained A's loss (D/A 0.816 on
fib38), so any future codegen A/B reports an aligned control.

## 2. Pipeline (per function, `a6_func`)

1. **Read**: `ir_read` into ir.om's tables; `ir_num f` numbers the values (wire ids index every per-value array).
   Kernels (kind 1) are refused.
2. **Layout** (`a6_lay`): blocks in ΩIR order. Positions: function parameters are defined at 0; block x starts at
   `a_bst[x]` (its parameters are defined there); op o sits at an even `a_opos[o]`, reads its operands there and
   defines its result at `a_opos[o] + 1`. `a_ccnt[q]` = calls at positions below q.
3. **Liveness** (`a6_lgen`, `a6_lflow`): per block bitsets of upward-exposed uses, definitions, live-in and live-out,
   iterated backwards to a fixed point. Successors: `br` slot 0, `cbr` slots 2 and 3. Tokens get no location.
4. **Intervals** (`a6_ivinit`, `a6_ivuse`, `a6_ivlive`): one range `[start, end]` per value from its definition and
   uses, widened to the start of every block where it is live-in and the end of every block where it is live-out.
   A value crosses a call when a call position lies strictly inside its range (`a_ccnt[end] > a_ccnt[start+1]`).
5. **Linear scan** (Poletto and Sarkar 1999, `a6_scan`): intervals in start order (bucket by start). Allocatable:
   x0..x14 (caller-saved, preferred) and x19..x27 (callee-saved); an interval crossing a call takes only x19..x27.
   With no free register, the active interval of the allowed class that ends last gives up its register if it ends
   after the current one (it moves to a stack slot); otherwise the current interval gets a slot. Slots are 8 bytes at
   `[sp, 8k]`. A spilled value is loaded into x16/x17/x15 before each use and stored after its definition. There is no
   limit on live values but the frame size.
6. **Frame** (`a6_frame`, `a6_pro`, `a6_epi`): F = round16(8 x (slots + callee-saved registers used + x30 if the
   function calls)), F <= 4095. Prologue `SUB SP, SP, #F; CMP SP, X28; B.LO trap6` (before any store, omc's
   stack-floor rule), then the saves above the slots. Epilogue: reloads, `ADD SP, SP, #F`, `RET`. A function with
   F = 0 has no frame code. Save form A uses pairs while the save area ends at or below byte 504, else form B.
7. **Selection** (`a6_sel`), one op at a time, operands read before the result register is written (the result may
   reuse an operand's register):
   - narrow integers live extended to 64 bits by their type (zero u8..u32, sign i8..i32); arithmetic results are
     re-extended (`UBFM`/`SBFM`), so 64-bit compares are exact and ΩIR's modulo-2^w results hold;
   - const: MOVZ, MOVN, or MOVZ + MOVK on the nonzero halfwords; add sub mul and or xor neg not; div (SDIV/UDIV gives
     ΩIR's divisor-0 and MIN/-1 results); rem = `a - (a/b) b` via MSUB, then CSEL to 0 when b = 0;
   - shl shr: LSLV/LSRV/ASRV at 64 and (W form) 32 bits, amount masked for 8 and 16; rotl rotr at 32 and 64 (RORV W/X,
     rotl by the negated amount); min max: CMP + CSEL; eq..ge: CMP + CSET; select: CMP c, #0 + CSEL;
     integer conv and bitcast: move + re-extend;
   - br: block arguments as one parallel move, `B` omitted on fall-through; cbr: CBNZ/CBZ (+ B);
     call: arguments to x0..x7 as one parallel move, BL (patched when every function is placed), result from x0;
     ret retv; trap: B to the stub; exit: `MOVZ X8, #93; SVC #0`;
   - checks: chk.add/sub/neg 64-bit by flags (B.VS signed; B.HS / B.LO / B.NE unsigned), chk.mul 64-bit by SMULH
     against the sign of the low half or UMULH = 0, narrower types by computing the exact 64-bit result and comparing
     it with its own re-extension; chk.divz CBZ; chk.divovf `((b + 1) | (a ^ MIN)) = 0`; chk.shl; chk.shift
     (unsigned CMP with the width); chk.conv between integers; chk.fuel CMP + B.HS; chk.true CBZ. Facts emit nothing.
8. **Parallel moves** (`a6_pmove`): a move fires when no pending move reads its destination; when all are blocked
   (a cycle), one source goes to x15 and its readers read x15. Slot-to-slot moves go through x16.
8a. **E loop shape** (`a6_tre`, D13): a block ending `r = call f(...); s = add a r` (either operand order)
   `; retv s` in f itself, with r and s used once each, becomes `acc = acc + a; parameters = arguments (parallel
   move); B head`, and every other `retv x` of f returns `acc + x`. acc is one extra wire defined at 0 and live to
   the end (callee-saved when f still calls); it is 0 at the head, right after the entry parameter moves. The tail
   call is not counted as a call. Integer add is modulo 2^w, so the result is exact; a signed add carries
   `chk.add` on r (a second use) and keeps its call. Stack depth falls, which IR.md s7.9 / D9 allow (trap 6 is
   compared only when both compilers trap). Fib keeps its first call and loses the second (0.35x omc on X925 for
   the hand-built form, D13); ts(n) = ts(n-1) + n becomes a frameless loop.
9. **Traps**: each function ends with omc's tail `ADD X0, X1, #100; MOVZ X8, #93; SVC #0` and one stub per used code,
   `MOVZ X1, #code; B tail`, so the exit status is 100 + code as with omc.
10. **ELF** (`a6_elf`): omc's map: 176-byte header, two PT_LOAD (text R+X at 0x400000 from file offset 0; RW
    0x10000000, memsz 8 MiB), entry 0x4000b0: `MOVZ X28, #0x1000, LSL 16; MOVZ X16, #0x1080, LSL 16; MOV SP, X16;
    BL main; MOVZ X8, #93; SVC #0`. Program entry (D11): the single export with no parameters and result i32.
    Each function starts on a 64-byte boundary (`a6_al64`: NOP padding after the previous function's trap stubs).

## 3. Registers

| Register | Use |
|---|---|
| x0..x7 | arguments and result (x0), allocatable caller-saved |
| x8..x14 | allocatable caller-saved |
| x15, x16, x17 | scratch: spill reloads, check temporaries, parallel-move cycle (x15) and slot-to-slot (x16) |
| x18 | platform register (AAPCS64 6.1.1), unused |
| x19..x27 | allocatable callee-saved (saved in the prologue when used) |
| x28 | stack floor 0x10000000 (omc convention, trap 6 check) |
| x29 | unused (kept for a frame pointer) |
| x30 | link register, saved when the function calls |

Calls between ng functions use x0..x7 for arguments (more than 8 is refused) and x0 for the result; there is no
outside caller in program mode, so this is the only contract.

## 4. Encoder layer

`a6_enc f a b c d e` builds the word of form f (160 forms, base word + operand kind, each group citing its DDI 0487
M.d section); `a6_ew` appends it. Forms: ADD/SUB/ADDS/SUBS (shifted register, immediate, extended register),
AND/ORR/EOR/ANDS/BIC/ORN (shifted register, bitmask immediate), MOVZ/MOVN/MOVK, MUL/MADD/MSUB/SMULH/UMULH/SDIV/UDIV,
LSLV/LSRV/ASRV/RORV (X and W), UBFM/SBFM/EXTR, CSEL/CSINC/CSINV/CSNEG, loads and stores of every width (unsigned
offset and register offset), LDP/STP (signed offset, pre-, post-index), B, BL, B.cond, CBZ/CBNZ, TBZ/TBNZ, RET, BR,
BLR, SVC, ADR and the FP set.

## 5. Not in the slice yet (PROPOSED, in order)

1. Shrink-wrapping (saves only on paths that need them) — D8; constant rematerialization (fib keeps the constant 2
   in a callee-saved register across its loop).
2. Memory ops (load, store, alloca, globals, slices, chk.bounds, chk.slice) and host words (inline `SVC`).
3. Fusions: compare feeding cbr as CMP + B.cond; ADD/SUB immediates; bitmask immediates; check + op as one ADDS.
4. Floats (FP registers v0..v7, v16..v31 caller-saved, v8..v15 callee-saved), u8/u16 rotations, > 8 arguments,
   frames over 4095 bytes.

## 6. Gates (run from the omega-mv root on core 1)

- `gate.om` (encoder): builds ng from `ng.units`, runs `@ng a64-enc` on `tests/enc.cases`, disassembles with GNU
  objdump (referee) and compares each case's text. Negative control: a wrong-bit mutant must fail cases.
- `rgate.om` (back end): builds mkir (`tests/mkir.om`), ngcheck and ng. For every fixture (fib, deep, press, rot,
  ck, ar, tsum) ngcheck must accept the ΩIR, `@ng a64` and `@ng a64 split` must exit with the expected status
  (computed with Wolfram, or the check's trap code), the omc build of `tests/ref/N.om` with its omc expectation
  (the same, except tsum: omc traps 6 a million calls deep, ng's loop does not; BEYOND_OMC), and every BL target in
  the `@ng a64` ELF must be a multiple of 64. Nine mutants (spill reload slot, call clobber, live-out range,
  parallel-move ordering, callee-saved saves, frame size, 16-byte entry alignment, E never matching, E accumulating
  the wrong value) must each change at least one fixture's status or alignment.

## 7. Scheduling facts used (Cortex-X925 Software Optimization Guide, `~/docs/arm-cores`)

- ALU basic (ADD, AND, …): latency 1, throughput 8 per cycle; flag-setting ADDS: latency 1, throughput 4 (p15).
- B: throughput 2 per cycle; CBZ/CBNZ/TBZ: throughput 2 (p15).
- LDP: latency 4; STP: throughput 2 (p19-20).
The slice does no instruction scheduling.
