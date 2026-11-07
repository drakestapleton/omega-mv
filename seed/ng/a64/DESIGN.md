# ng a64: ΩIR to AArch64 Linux ELF (design, ng-a64 lane)

Status: IMPLEMENTED and HOST_TESTED for the integer slice below (gates in section 6); the rest is PROPOSED.
Code: `seed/ng/src/a64.om` (unit of `seed/ng/ng.units`, between `ir.om` and `main.om`; functions `a6_*`, globals
`a_*`). Built by `seed/out/omc` (sha256 `5f90edea…`, omega-mv `943d9555`). Facts about seed omc it copies are in
`~/handoffs/hive-ng/a64/REALITY.md` (file:line at `943d9555`).

## 1. Job

`ng` modes owned by this unit. `main.om` reads the mode line apart and asks `a6_mode m` (through `ng_mlb`, since
an earlier unit cannot name main's globals) before its unknown-mode exit; it then reads the payload into `i_in` from
offset 0 with ir-copy's limit and refusals, and calls `a6_run`, which runs the mode and exits:

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
   defines its result at `a_opos[o] + 1`. `a_ccnt[q]` = calls and host words at positions below q.
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
6. **Frame** (`a6_frame`, `a6_alay`, `a6_pro`, `a6_epi`): round16(8 x (outgoing slots + spill slots + callee-saved
   registers used + x30 if the function calls)) <= 4095, then one 16-byte aligned area per `alloca` (its type's size
   rounded to 16); the frame F < 2^24. The outgoing slots (`a6_outm`: the most arguments past the eighth of any call in
   the function) are slots 0.., the spill slots follow them. Prologue `SUB SP, SP, #F` (as `#hi, LSL 12` and `#lo`
   when F > 4095), `CMP SP, X28; B.LO trap6` (before any store, omc's stack-floor rule), then the saves above the
   slots. Epilogue: reloads, `ADD SP` the same way, `RET`. A function with F = 0 has no frame code. Save form A uses
   pairs while the save area ends at or below byte 504, else form B.
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
     call: arguments 8.. stored to the outgoing slots `[sp, 8j]` (through x16 from a spill slot), arguments 0..7 to
     x0..x7 as one parallel move, BL (patched when every function is placed), result from x0; SP never moves inside a
     function, so the frame's stack check covers the outgoing area;
     ret retv; trap: B to the stub; exit: `MOVZ X8, #93; SVC #0`;
   - checks: chk.add/sub/neg 64-bit by flags (B.VS signed; B.HS / B.LO / B.NE unsigned), chk.mul 64-bit by SMULH
     against the sign of the low half or UMULH = 0, narrower types by computing the exact 64-bit result and comparing
     it with its own re-extension; chk.divz CBZ; chk.divovf `((b + 1) | (a ^ MIN)) = 0`; chk.shl; chk.shift
     (unsigned CMP with the width); chk.conv between integers; chk.fuel CMP + B.HS; chk.true CBZ. Facts emit nothing.
   - memory (IR.md s7.5), REF to ARRAY of bool or integers only: a REF is one register holding the object's address.
     load/store: LDR/STR register offset, index scaled by the element size (LDRB/LDRH/LDR W/LDR X; LDRSB/LDRSH/
     LDRSW for i8/i16/i32 keep the canonical sign extension); gaddr: the global's absolute address (MOVZ + MOVK);
     len: the ARRAY count from the type; alloca: `ADD Xd, SP, #area`, then `STP XZR, XZR, [X16], #16` per 16 bytes
     (zero-filled at the op, so on every pass of an E loop as well). chk.bounds r i e: a constant e (every access's
     covering form, s8) is `CMP Xi, #(len - e); B.HI trap` (exact, no add that could wrap), e = 0 or e > len a
     plain `B trap`; any other e `CBZ`, `len - e` by SUBS (`B.LO`), then CMP + B.HI. chk.slice r off n: `off > len`
     or `n > len - off`, each CMP + B.HI. The back end trusts ngcheck's coverage (an access follows its check).
   - host words read (53) and write (54) (IR.md s7.11): `X17 = A + off`, then x0 fd, x1 X17, x2 n as one parallel
     move, `MOVZ X8, #63/64; SVC #0`, result (count or minus errno) from x0. The SVC preserves every register but x0;
     the arguments use x0..x2, so a host word counts as a call for allocation (values live across it take x19..x27)
     without saving x30. cpufence (199) is `DSB SY` and cpurelax (200) `YIELD`, omc's words. Every other host word is
     refused (exit 5, `a64: unsupported` with the word id).
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
10. **ELF** (`a6_elf`, `a6_glay`): omc's map: 176-byte header, two PT_LOAD (text R+X at 0x400000 from file offset 0;
    RW 0x10000000, memsz 8 MiB of stack + the class-0 globals rounded up to 4096), entry 0x4000b0: `MOVZ X28,
    #0x1000, LSL 16; MOVZ X16, #0x1080, LSL 16; MOV SP, X16; BL main; MOVZ X8, #93; SVC #0`. Class-0 globals sit in
    the RW pool from 0x10800000 (16-byte aligned, zero-filled by the loader, at most 1 GiB), class-1 globals' bytes
    right after that start code in the text image (word-padded), as omc. Program entry (D11): the single export with
    no parameters and result i32. Each function starts on a 64-byte boundary (`a6_al64`: NOP padding after the
    previous function's trap stubs or the class-1 bytes).

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

Calls between ng functions use x0..x7 for arguments 0..7, the caller's outgoing slots `[sp, 8j]` for argument 8 + j
(at most 64 arguments, IR.md s12), and x0 for the result. The callee reads argument 8 + j at `[sp + F + 8j]` after its
prologue (x17 = SP + F, then `LDR`, `a6_inpar`), once the x0..x7 parameters are in place. There is no outside caller
in program mode, so this is the only contract.

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
2. Memory beyond the slice: SLICE values (`slice`, `len` of a SLICE; two words per value; the ChaCha20, SHA-256 and
   X25519 bench kernels pass `view uchar *` and need them), STRUCT fields (`fload`, `fstore`, `fref`), VEC (`vload`,
   `vstore`), `fill`, `atom`, `atomcas`, float elements. Bounds checks hoisted out of loops by a pass that proves
   them (IR.md s15).
3. Fusions: compare feeding cbr as CMP + B.cond; ADD/SUB immediates; bitmask immediates; check + op as one ADDS.
4. Floats (FP registers v0..v7, v16..v31 caller-saved, v8..v15 callee-saved), u8/u16 rotations, host words beyond
   read, write, cpufence and cpurelax.

## 6. Gates (run from the omega-mv root on core 1)

- `gate.om` (encoder): builds ng from `ng.units`, runs `@ng a64-enc` on `tests/enc.cases`, disassembles with GNU
  objdump (referee) and compares each case's text. Negative control: a wrong-bit mutant must fail cases.
- `rgate.om` (back end): builds mkir (`tests/mkir.om`), ngcheck, ngas, ngrun and ng. For every mkir fixture (fib, deep, press, rot,
  ck, ar, tsum, mem, oob, zf, wid, bcopy, sort) ngcheck must accept the ΩIR, `@ng a64` and `@ng a64 split` must
  exit with the expected status (computed with Wolfram, or the check's trap code), the omc build of
  `tests/ref/N.om` with its omc expectation (the same, except tsum: omc traps 6 a million calls deep, ng's loop does
  not; BEYOND_OMC), the split and omc runs must print exactly the bytes the `@ng a64` run printed, and every BL
  target in the `@ng a64` ELF must be a multiple of 64. bcopy and sort are the bench kernels
  (`~/handoffs/OmegaFast/bench/`) lowered by hand per IR.md s13, with the bench source itself as the omc reference;
  their output is also checked against Wolfram (bcopy's SHA-256, sort's four numbers). The memory fixtures store and
  load every integer element width (u8 u64 in mem, i8 u16 i16 u32 i32 in wid); wid compares each loaded value at its
  own type, because a conversion re-extends from its source type and would hide a non-canonical load (rgate's first
  form of mutants 13 and 15 escaped that way).

  Then the ngrun fixtures (D9): ΩIR text assembled by ngas, accepted by ngcheck and run by ngrun (ng-ir's reference
  interpreter, IR.md s7); both ng forms must give ngrun's exit status (a program's, never 125) and its stdout and
  stderr byte for byte. They are ng-ir's run pairs (`seed/ng/tests/ir/x-*.oir` but x-float, each already judged
  against omc by ng-ir's gate) and `tests/oir/`: `c-OP-TYPE` for every check op 70..82 on narrow and 64-bit types
  (a call at the boundary that must pass, its 8 result bytes written, then one past it that must trap with the op's
  code; chk.true with codes 1, 9, 10, 13), `wide` (20-, 10- and 9-parameter functions: stack arguments, a callee
  that calls with stack arguments, an unused parameter, u8 and i32 among them, values live across calls; Wolfram:
  a99d319d002e6e04 and 599bcde54693cac2), `mem2` (a class-1 data global read through a view, zero globals of u8, i64,
  u16, i32 stored and reloaded in block-parameter loops, an FNV-style checksum; Wolfram ff234afefa35d586), `eloop`
  (D13 item 4: two E-shaped self calls, 50000 and 60000 deep for ngrun, one wrapping in u32; Wolfram 4a81de28 and
  3550e837), and the bench kernels as text: `b-fib` (fib 27 and the bench's decimal printer; 196418), `b-bcopy` and
  `b-sort` (ngdis of mkir's bcopy and sort, scaled to 8 rounds and 400 elements so ngrun finishes inside rgate's
  30 s child limit; Wolfram for sort: 214018279158 0 2818 3982316). The full-size kernels stay in the mkir set
  against omc.

  Eighteen mutants (spill reload slot, call clobber, live-out range, parallel-move ordering, callee-saved saves,
  frame size, 16-byte entry alignment, E never matching, E accumulating the wrong value, chk.bounds off by e, half
  zero fill, write count, u64 loads one byte, large frame without its LSL 12 part, i8 loads zero-extending, a wrong
  trap code for chk.divovf, stack parameters read from the first incoming slot, stack arguments stored one slot low)
  must each change at least one fixture's status (against its expectation or ngrun's) or alignment.
- ΩIR gap met by sort: a call argument must have exactly the parameter's type (IR.md row 64), so Omega passing an
  `edit` array to a `view` parameter has no ΩIR form while `view` maps to REF access 0. The fixture types sorted's
  parameter as access 1 (the machine code is the same); the rule belongs to ng-ir (proposal on the BOARD).

## 7. Scheduling facts used (Cortex-X925 Software Optimization Guide, `~/docs/arm-cores`)

- ALU basic (ADD, AND, …): latency 1, throughput 8 per cycle; flag-setting ADDS: latency 1, throughput 4 (p15).
- B: throughput 2 per cycle; CBZ/CBNZ/TBZ: throughput 2 (p15).
- LDP: latency 4; STP: throughput 2 (p19-20).
The slice does no instruction scheduling.
