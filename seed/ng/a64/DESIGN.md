# ng a64: ΩIR to AArch64 Linux ELF (design, ng-a64 lane)

Status: IMPLEMENTED and HOST_TESTED for the integer slice below (gates in section 6); the rest is PROPOSED.
Code: `seed/ng/src/a64.om` (unit of `seed/ng/ng.units`, between `ir.om` and `main.om`; functions `a6_*`, globals
`a_*`). Built for the ham fusion head by `seed/out/omc` (sha256 `6d1b1cf5a44803389a831b67f750ea4cd1c9f53edfde9d6d9241d7352887f1f8`, Radicle base `a59a425b4`). Facts about seed omc it copies are in
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
   - shl shr: LSLV/LSRV/ASRV at 64 and (W form) 32 bits, amount masked for 8 and 16; rotl rotr (RORV W/X, rotl by the
     negated amount) at 32 and 64 bits, and at 8 and 16 bits on a copy in x16 that repeats the value across 32 bits
     (ORR with itself shifted by the width, twice for u8; the width divides 32, so the low bits of the 32-bit rotation
     are the narrow rotation by the amount modulo the width), then re-extended; min max: CMP + CSEL; eq..ge: CMP + CSET;
     select: CMP c, #0 + CSEL;
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
   - memory (IR.md s7.5), REF to ARRAY of bool or integers (SLICE values below): a REF is one register holding the
     object's address.
     load/store: LDR/STR register offset, index scaled by the element size (LDRB/LDRH/LDR W/LDR X; LDRSB/LDRSH/
     LDRSW for i8/i16/i32 keep the canonical sign extension); gaddr: the global's absolute address (MOVZ + MOVK);
     len: the ARRAY count from the type; alloca: `ADD Xd, SP, #area`, then `STP XZR, XZR, [X16], #16` per 16 bytes
     (zero-filled at the op, so on every pass of an E loop as well). chk.bounds r i e: a constant e (every access's
     covering form, s8) is `CMP Xi, #(len - e); B.HI trap` (exact, no add that could wrap), e = 0 or e > len a
     plain `B trap`; any other e `CBZ`, `len - e` by SUBS (`B.LO`), then CMP + B.HI. chk.slice r off n: `off > len`
     or `n > len - off`, each CMP + B.HI. The back end trusts ngcheck's coverage (an access follows its check).
   - SLICE values (IR.md s4.2 kind 5) of bool or integer elements: two wires. The value's own wire holds the
     address of element 0; a length wire (`a6_shw`, made after liveness with the value's interval, so the scan
     allocates it like any value: register, callee-saved when it crosses a call, or a slot) holds the count. A move
     of a slice moves both (`a6_mvv`: block arguments, E-tail parameters); a call passes a slice as two machine
     arguments, address then count (`a6_xcall`, `a6_xpar`, `a6_xcnt`), so a slice may straddle x7 and the first
     stack slot. `slice r off n` (r a REF to ARRAY or a SLICE): `ADD X16, Xr, Xoff, LSL #log2(size)` and `X15 = n`
     before either result wire is written (both may reuse operand registers); `len` of a SLICE reads the length
     wire; load and store use the address wire like a REF. chk.bounds on a SLICE: `CBZ e`, `SUBS X15, len, e` +
     `B.LO` (e > len), CMP i + `B.HI`; chk.slice on a SLICE: CMP off, len + `B.HI`, `X15 = len - off`, CMP n +
     `B.HI`. A slice result of any op but `slice` (select, call) and `retv` of a slice are refused (exit 5).
     A select fused into its compare (section 8) meets the same refusal (rgate's `u-*` refusal fixtures).
   - host words read (53) and write (54) (IR.md s7.11): `X17 = A + off`, then x0 fd, x1 X17, x2 n as one parallel
     move, `MOVZ X8, #63/64; SVC #0`, result (count or minus errno) from x0. The SVC preserves every register but x0;
     the arguments use x0..x2, so a host word counts as a call for allocation (values live across it take x19..x27)
     without saving x30. cpufence (199) is `DSB SY` and cpurelax (200) `YIELD`, omc's words. monons (109) and realns
     (130) are omc's hclock (`a6_hclk`, clock id 1 or 0 as omc's): `SUB SP, #16` with the stack-floor check (trap 6),
     `STP XZR, XZR, [SP]`, SVC 113 clock_gettime into that area, `sec > 9223372036` B.HI trap 1, `sec * 10^9 + nsec`
     by MUL and ADDS (B.VS trap 1), then `CMP X0, #0; CSEL X0, X0, X2, LT` returns minus errno for a failed call where
     omc branches (the zeroed area makes the failed path compute 0 without trapping). Every other host word is refused
     (exit 5, `a64: unsupported` with the word id).
   - fill r v (51) on a REF to ARRAY (count from the type) or a SLICE (count from its length wire): `X15 = count;
     CBZ X15, done; loop: SUBS X15, X15, #1; STR v, [base, X15, LSL #size]; B.NE loop` (last element first).
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
| x15, x16, x17 | scratch: spill reloads, check temporaries, parallel-move cycle (x15) and slot-to-slot (x16); never allocated (`a6_free` scans x0..x14 then x19..x27; rgate mutant 16 and fixture lv) |
| x18 | platform register (AAPCS64 6.1.1), unused |
| x19..x27 | allocatable callee-saved (saved in the prologue when used) |
| x28 | stack floor 0x10000000 (omc convention, trap 6 check) |
| x29 | unused (kept for a frame pointer) |
| x30 | link register, saved when the function calls |

`a6_okreg`'s `lt r 15` (the spill scan's register set) cannot change output on its own: only `a6_give` marks a
register active, with a register from `a6_free` (never x15) or from the spill scan (already active), so x15 is
never active and the scan skips it. Widening it to x15 (review mutant M-C of 8a3680b0) gave byte-identical ELFs
for all 14 mkir fixtures in both forms (28/28, on ng/a64-m1-fix); it is an equivalent mutant and is not in rgate's
list.

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

An operand that does not fit its field is refused (exit 5, `immediate out of range` / `branch out of range`), never
masked. `a6_rsv` also refuses in-field values whose encoding DDI 0487 M.d reserves (exit 5, `reserved operand
value`): shift amounts, UBFM/SBFM immr and imms and EXTR lsb of 32 or more and MOVZ/MOVN hw 2..3 on 32-bit forms; sh
3 (ROR) on ADD/SUB shifted register (logical forms take it); and any sh or amt on the kind-1 forms that have opcode
bits there (multiply, two-source, float). The selector never asks for these; the encoder case lists pin both sides.

## 5. Not in the slice yet (PROPOSED, in order)

1. Shrink-wrapping (saves only on paths that need them) — D8; constant rematerialization (fib keeps the constant 2
   in a callee-saved register across its loop).
2. Memory beyond the slice: STRUCT fields (`fload`, `fstore`, `fref`), VEC (`vload`, `vstore`), `atom`, `atomcas`,
   float elements, SLICE results of calls and select. Bounds checks hoisted out of loops by a pass that
   proves them (IR.md s15).
3. Remaining fusions: ADD/SUB immediates; bitmask immediates; check + op as one ADDS.
4. Floats (FP registers v0..v7, v16..v31 caller-saved, v8..v15 callee-saved), host words beyond
   read, write, monons, realns, cpufence and cpurelax (sleepns 120 has no ngrun reference: ngrun's host words are
   read, write, monons, realns, cpufence, cpurelax).

## 6. Gates (run from the omega-mv root on core 1)

- `gate.om` (encoder): builds ng from `ng.units`, runs `@ng a64-enc` on `tests/enc.cases`, disassembles with GNU
  objdump (referee) and compares each case's text. Negative control: a wrong-bit mutant must fail cases. Then each
  line of `tests/enc-refuse.cases` runs alone: ng must exit 5, write no word and print exactly the line's stderr
  text; mutant M-A (`a6_fld` masks instead of refusing) must fail at least one of them.
- `rgate.om` (back end): builds mkir (`tests/mkir.om`), ngcheck, ngas, ngrun and ng. For every mkir fixture (fib,
  deep, press, rot, ck, ar, tsum, mem, oob, zf, wid, bcopy, sort, lv) ngcheck must accept the ΩIR, `@ng a64` and
  `@ng a64 split` must exit with the expected status (computed with Wolfram, or the check's trap code), the omc build of
  `tests/ref/N.om` with its omc expectation (the same, except tsum: omc traps 6 a million calls deep, ng's loop does
  not; BEYOND_OMC), the split and omc runs must print exactly the bytes the `@ng a64` run printed, and every BL
  target in the `@ng a64` ELF must be a multiple of 64. mkir lowers main's `int` as IR.md s13 does (chk.conv i32
  trap 5, then conv); tsum's main and reference take ts(1000000) & 255 first, since 500000500000 does not fit i32
  (review P2-1 of 8a3680b0: the earlier fixture had no chk.conv and its 32 was not Omega's result). bcopy and sort
  are the bench kernels
  (`~/handoffs/OmegaFast/bench/`) lowered by hand per IR.md s13, with the bench source itself as the omc reference;
  their output is also checked against Wolfram (bcopy's SHA-256, sort's four numbers). The memory fixtures store and
  load every integer element width (u8 u64 in mem, i8 u16 i16 u32 i32 in wid); wid compares each loaded value at its
  own type, because a conversion re-extends from its source type and would hide a non-canonical load (rgate's first
  form of mutants 13 and 15 escaped that way). lv keeps 20 values live with no call across chk.add, chk.mul and
  chk.bounds, so an allocator that hands out x15 loses one of them (status 89, not 165).

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
  against omc. `b-chacha` is the ChaCha20 bench (`~/handoffs/OmegaFast/bench/chacha.om` over `om/tls/chacha.om`,
  `chacha20_xor` and everything below it) lowered by hand to ΩIR with SLICE parameters, inline functions inlined and
  unrolled loops unrolled, scaled to a 300-byte buffer (four whole blocks and a 44-byte tail) and 3 rounds. Besides
  ngrun, omc's build of `om2` + `om/tls/chacha.om` + the bench driver with those two numbers changed writes the same
  300 bytes (checked once by hand, 2026-11-07; not part of rgate). The `s-*` fixtures cover SLICE values: `s-slice`
  (slices of a REF and of a slice, u8, u32 and u64 elements, `len`, a shrinking slice carried as a loop block
  parameter, slices straddling x7 and the stack in an 11-parameter call, fourteen slices live across calls so their
  length wires spill, a host write from a slice) and `s-tb`, `s-te`, `s-ts`, `s-ts2` (chk.bounds index = len,
  constant e > len, chk.slice n > len - off and off > len on slices with a run-time length, each after a passing
  call at the boundary). SHA-256 and X25519 are not lowered by hand: their sources use only ops covered here
  (integer arithmetic with div/rem, not, rotr at 32 and 64 bits, shifts, arrays and u8/u64 slices); they run end to
  end once ng-front lowers them. `h-mono` (two monons reads around a loop; exit 7 when the first reading exceeds
  10^9, the second is not smaller and they differ by less than 10^12 ns, whatever the clock says) is ng-front's
  `@ng front-ir` output for an Omega source, as ngdis text; omc's build of the source exits 7 as well. `f-fill`
  (the same route: u32, u8, u64, u16 arrays filled with nonzero values; Wolfram: 37*5 + 64*65535 + 3*9 + 200 =
  4194652) and `f-fills` (a run-time-length u32 slice filled through a call, a zero-length slice, five read-backs;
  Wolfram: 30) cover fill. `h-real` (front-generated the same way: realns between 2023-11-14 and 2100-01-01 in
  nanoseconds, above monons, not decreasing; Wolfram: UnixTime of those dates times 10^9 = 1700000000000000000 and
  4102444800000000000; exit 9) covers realns, and fails if it reads the monotonic clock. The clock traps (seconds
  above 9223372036, the add overflowing) and the failed-call path cannot be reached by a live clock; they are checked
  by reading the encoded sequence (objdump) against omc's hclock, not by a fixture.

  `r-rot` (u8 181 and u16 46531 rotated left and right by 12 amounts each, many past the width; every result printed
  and folded into the exit status; Wolfram on two rows: rotl/rotr u8 by 23 = da/6b, u16 by 2731 = 1dae/b876) and
  `r-s12` (ngrand seed 12 shrunk by `ngrand shrink` to the `rotr u8` that a64 refused, kept as found) cover narrow
  rotations.

  The original twenty-seven mutants (spill reload slot, call clobber, live-out range, parallel-move ordering, callee-saved saves,
  frame size, 16-byte entry alignment, E never matching, E accumulating the wrong value, chk.bounds off by e, half
  zero fill, write count, u64 loads one byte, large frame without its LSL 12 part, i8 loads zero-extending, a wrong
  trap code for chk.divovf, stack parameters read from the first incoming slot, stack arguments stored one slot low,
  a slice's length taken from its offset, slice block arguments keeping the target's length, slice offsets not
  scaled by the element size, monons selecting on GE, fill stores unscaled, realns on the monotonic clock, the u8 and
  the u16 rotate copies shifted wrong, x15 allocatable) must each change at least one fixture's status (against its
  expectation or ngrun's), alignment, or stdout/stderr bytes; section 8 adds seven more forms and mutant 35 (the
  select-of-SLICE refusal never fires), which a refusal fixture must catch.
- Front phase of `rgate.om` (rgate step 6; branch ng/slice-m1, where ng.units holds ir, front, a64, main): for each
  source of rgate's list `tfr` (ng-ir's 14 integer `x-*.om` run pairs and ng-front's nine integer bench kernels
  arith, branch, leafcall, fib38, fib40, isort, sieve, sort, matmul at full size) ng reads `@ng front-ir` and the
  source and must exit 0, ngcheck must accept the ΩIR, `@ng a64` and `@ng a64 split` of it must both run with omc's
  exit status, stdout byte for byte (each kernel prints a 9 to 41 byte checksum line) and stderr byte for byte,
  except that when omc's stderr is one line of decimal digits (OMC-EFF-2: the kernel's elapsed nanoseconds,
  different every run) ng's must be one such line too; BL targets must be multiples of 64. x-float and the linear
  kernel (list `tfz`, f64) must pass front-ir and ngcheck and be refused by both a64 forms (exit 5): counted as
  refused, never as compared (floats are M4). Negative control (list `tfd`): fib40's ng path against omc's build of
  `tests/front/fib39.om` must be sound and must differ in stdout (Wolfram: Fibonacci[39] = 63245986, Fibonacci[40] =
  102334155), so a comparison that cannot see a different result fails the gate. Mutants run on the mkir and ngrun
  phases only.
- Random phase of `rgate.om` (rgate step 7, D9; branch ng/a64-rand, which merges ng-ir's ng/ir-rand): ngrand (ng-ir's
  generator, `seed/ng/ngrand.om`) writes a unit valid by construction for each seed 1..1000 (helpers with narrow
  parameters, every value op and check, memory under chk.bounds, calls, diamonds, counted loops, traps and exits);
  each goes through the ngrun-fixture checks above, with ngrand's status in place of ngas's. A refusal by ng fails
  the seed: before the narrow rotations, 147 of seeds 1..1000 were refused (all `rotr`/`rotl` on u8 or u16) and none
  gave a wrong result. Negative control: ngrun's run of seed 1 against the `@ng a64` ELF of seed 2 must be sound
  and differ. Mutants do not run this phase (a 1..200 hunt with mutant 1 gave 29 wrong seeds, outside rgate).
- ΩIR gap met by sort and chacha: a call argument must have exactly the parameter's type (IR.md row 64), so Omega
  passing an `edit` array or slice to a `view` parameter has no ΩIR form while `view` maps to access 0. The fixtures
  type such parameters as access 1 (the machine code is the same); the rule belongs to ng-ir (proposal on the BOARD).

## 7. Scheduling facts used (Cortex-X925 Software Optimization Guide, `~/docs/arm-cores`)

- ALU basic (ADD, AND, …): latency 1, throughput 8 per cycle; flag-setting ADDS: latency 1, throughput 4 (p15).
- B: throughput 2 per cycle; CBZ/CBNZ/TBZ: throughput 2 (p15).
- LDP: latency 4; STP: throughput 2 (p19-20).
The slice does no instruction scheduling.

## 8. Local compare fusion (ham/ng-a64-float)

A compare whose boolean has exactly one use by the immediately following cbr or select is selected at the compare site. No instruction, check, token effect or operand lifetime moves. A compare with another use remains CMP + CSET. cbr becomes CMP + B.cond; eq/ne against a zero constant becomes CBZ/CBNZ. A single-bit AND result compared with zero uses TBZ/TBNZ at the actual bit number, including bits 32 through 63. The AND itself remains, so no earlier input lifetime is extended. A compare feeding select uses its flags directly in CSEL rather than materialising a boolean and comparing it again.

Use counts are computed once per function. Branch fall-through polarity follows the existing block order. Short branch fixup checks signed displacement ranges. If a conditional branch is too far, the function is emitted again with inverted short branches over ordinary B instructions, retaining trap stub and call fixups; the code buffer fits B range. No range is silently masked.

`tests/fusion.om`, composed after `src/ir.om`, generates `tests/oir/f-fusion.oir`: every integer type and comparison in branch/select forms, true and false paths, every TBZ bit, and a far bit target. rgate includes the generated fixture and seven additional mutants for B.cond condition, CBZ, CBNZ, TBZ, TBNZ, bit packing and CSEL operand order. `tests/fusion-bench.om` records the before-timing NG benchmark protocol.

Fusion emits the consumer at the compare and `a6_sel` skips it at its own turn (`a_skip`, one slot), but only after `a6_sel`'s refusals. Bay 11's review of 3ad3ef7b found the skip placed before them: a fused select of SLICE values compiled to a CSEL of the address wires alone, the result's length wire was never written, and the program ran with a wrong length (ngrun 3, ELF 7) where the unfused select is refused. The other fused consumer, cbr, has no refusal in `a6_sel`, `a6_sterm` or `a6_scbr`; the compare's own refusal (`a6_isint` on its operand type) runs before `a6_cuse`; and the consumer is the next op, so no op can redefine or slice an operand between the compare and its use. rgate's refusal fixtures `tests/oir/u-selslice-*.oir` (eq true and false, signed lt, ne against zero, a single-bit AND, the result passed to a call, and one select not fused) must assemble, pass ngcheck and run under ngrun, and both a64 forms must refuse them with exit 5 and exactly `a64: unsupported 2`. The pre-fix back end compiles six of the seven.

`ngas.om` and `ngdis.om` are the canonical IR text tools, not AArch64 instruction encoders/decoders. Their unchanged compare/select/branch row encodings already cover these programs. Encoder instruction forms are in a64.om and checked against GNU objdump by gate.om. IR round trips are checked separately.

### Fusion measurements (2026-11-10, MEASURED, not QUALIFIED)

Same front-generated IR, same seeded compiler, baseline a64 unit 0120a15a vs fusion unit 27b64b75. NG bench used nine measured ABBA blocks after two warm blocks, core 11 (A725) and core 19 (X925), under their pool locks with nice 19. Both arms keep 64-byte function alignment. Every core/case had nine clean blocks under the K-row rule; both runs ended S rows=88 ok=88 fail=0 refused=0. Nine blocks do not meet the older 21-clean-block qualification criterion, so these are measurements, not a performance qualification.

| Core | Case | Baseline median wall ms | Fused median wall ms | Median paired fused/base wall ratio |
|---|---|---:|---:|---:|
| A725 | branch | 531.791 | 478.156 | 0.898969 |
| A725 | arith | 178.697 | 180.079 | 1.008854 |
| X925 | branch | 259.285 | 237.284 | 0.913879 |
| X925 | arith | 121.405 | 121.185 | 0.997848 |

The arithmetic case is retained, including its measured A725 regression; no global speed claim is inferred. Ratios are the median of per-block sums, not the ratio of the two displayed medians. Wolfram computed statistics and formatting. Numeric T/K/H/A/S records: tests/fusion-a725.txt and tests/fusion-x925.txt; method/results: tests/fusion-stats.txt. Full process-contamination rows and exact Wolfram queries are retained with the READY's EVBACK paths, not copied into public process inventories.

Acceptance on the fusion head 3ad3ef7b: gate.om 213/213 encoder cases, 23/23 refusals, wrong-bit mutant 3 mismatches and M-A 8 refusal failures; rgate fixtures 14/14, ngrun fixtures 78/78, front cases 23/23, expected float refusals 2/2, random seeds 1000/1000 in both save forms, controls differ, mutants 34/34 killed. f-fusion prints every per-call result so swapping complementary true/false results cannot cancel in its exit checksum; mutant checks compare stdout/stderr as well as status. The generated IR also passes ngas/ngdis byte-exact round trip. The answer to bay 11 (branch ham/ng-a64-float-2) adds the seven refusal fixtures and mutant 35 to rgate (35 mutants); its gate results are in its READY, not here.
