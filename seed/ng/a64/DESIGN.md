# ng a64: ΩIR to AArch64 Linux ELF (design, ng-a64 lane)

Status: IMPLEMENTED and HOST_TESTED for the integer slice below and for scalar f32/f64 (section 9) (gates in
section 6); the rest is PROPOSED.
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
| `@ng a64 macho` | binary ΩIR | dynamic arm64 Mach-O for macOS on stdout (form A; section 11) |
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
   - fill r v (51) on a REF to ARRAY (count from the type) or a SLICE (count from its length wire), of integer,
     f32 or f64 elements: a 64-bit pattern, 16-byte blocks of it from the end down, then 8/4/2/1-byte tails
     (section 10).
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
| v0..v7 | float arguments and result (d0 / s0), allocatable caller-saved (location 32 + V) |
| v8..v15 | allocatable callee-saved: d8..d15 saved in the prologue when used (the low 64 bits, all a scalar needs) |
| v16..v28 | allocatable caller-saved |
| v29, v30, v31 | float scratch: operand reloads, a result bound for a slot, chk.conv bounds; never allocated |

`a6_okreg`'s `lt r 15` (the spill scan's register set) cannot change output on its own: only `a6_give` marks a
register active, with a register from `a6_free` (never x15) or from the spill scan (already active), so x15 is
never active and the scan skips it. Widening it to x15 (review mutant M-C of 8a3680b0) gave byte-identical ELFs
for all 14 mkir fixtures in both forms (28/28, on ng/a64-m1-fix); it is an equivalent mutant and is not in rgate's
list.

Calls between ng functions follow the scalar AAPCS64 banks (`a6_abi`): integer, reference and slice wires take
x0..x7 in order, f32/f64 arguments v0..v7 in order, and the rest of either bank the caller's outgoing slots
`[sp, 8j]` in argument order (at most 64 arguments, IR.md s12); the result is x0, or d0/s0 for a float. The callee
reads stack argument j at `[sp + F + 8j]` after its prologue (x17 = SP + F, then `LDR` X or D, `a6_inpar`), once the
register parameters are in place. There is no outside caller in program mode, so this is the only contract. With
integers only, every argument's place is the one before floats (argument k < 8 in xk, slot k - 8 after), so the
bytes are unchanged.

## 4. Encoder layer

`a6_enc f a b c d e` builds the word of form f (163 forms, base word + operand kind, each group citing its DDI 0487
M.d section); `a6_ew` appends it. Forms: ADD/SUB/ADDS/SUBS (shifted register, immediate, extended register),
AND/ORR/EOR/ANDS/BIC/ORN (shifted register, bitmask immediate), MOVZ/MOVN/MOVK, MUL/MADD/MSUB/SMULH/UMULH/SDIV/UDIV,
LSLV/LSRV/ASRV/RORV (X and W), UBFM/SBFM/EXTR, CSEL/CSINC/CSINV/CSNEG, loads and stores of every width (unsigned
offset and register offset), LDP/STP (signed offset, pre-, post-index), B, BL, B.cond, CBZ/CBNZ, TBZ/TBNZ, RET, BR,
BLR, SVC, ADR and the FP set, with FCSEL S/D (kind 8, the CSEL shape) and MSR FPCR, Xt (kind 22: one Rt field)
added for scalar floats.

An operand that does not fit its field is refused (exit 5, `immediate out of range` / `branch out of range`), never
masked. `a6_rsv` also refuses in-field values whose encoding DDI 0487 M.d reserves (exit 5, `reserved operand
value`): shift amounts, UBFM/SBFM immr and imms and EXTR lsb of 32 or more and MOVZ/MOVN hw 2..3 on 32-bit forms; sh
3 (ROR) on ADD/SUB shifted register (logical forms take it); and any sh or amt on the kind-1 forms that have opcode
bits there (multiply, two-source, float). The selector never asks for these; the encoder case lists pin both sides.

## 5. Not in the slice yet (PROPOSED, in order)

1. Shrink-wrapping (saves only on paths that need them) — D8; constant rematerialization (fib keeps the constant 2
   in a callee-saved register across its loop).
2. Memory beyond the slice: STRUCT fields (`fload`, `fstore`, `fref`), VEC other than the 128-bit float vectors of
   section 12 (`vload`, `vstore` of integer and wider vectors), `atom`, `atomcas`, SLICE results of calls and select;
   bulk copy (PROPOSAL-ir-bulk-copy.md, IR and optimizer lanes). Bounds checks hoisted out of loops by a pass that
   proves them (IR.md s15).
3. Remaining fusions: ADD/SUB immediates; bitmask immediates; check + op as one ADDS.
4. f16, bf16, fp8, `fmath` and vector floats other than `vec f32 4` and `vec f64 2` (section 12) (refused, exit 5: no
   accuracy-stated implementation), host words beyond read, write, monons, realns, cpufence and cpurelax (sleepns 120
   has no ngrun reference: ngrun's host words are read, write, monons, realns, cpufence, cpurelax).

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
  rotations. `n-s7821` and `n-s10623` (in `seed/ng/tests/ir/`, ng-ir's N cases too) are ngrand seeds 7821 and
  10623, the two random-phase divergences of a 20000-seed run, shrunk by `ngrand shrink` with ngrun before 26f67fbb
  as the failing side and kept as found: a u64 outside i32 reaches `chk.conv i32`, which must trap 5 (IR.md s7.9),
  where that ngrun read the u64 as signed and printed; a64 trapped 5 throughout.

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
- `rgate.om` step 8, the float phase (section 9): `tests/frand.om` writes canonical ΩIR text of 56 deterministic
  edge programs and of random seeds 1..1000; ngas assembles each and it goes through the ngrun-fixture checks
  (status, stdout and stderr byte for byte against ngrun, both save forms, BL alignment). Negative control: ngrun's
  run of float seed 1 against the ELF of float seed 2 must be sound and differ. Mutants 36..69 are the float ones
  and 70..79 the fill ones (section 10): each also runs the 66 edge programs (56 float, 10 fill) and float seeds
  1..8. The ngrun fixtures add ng-ir's float run pairs x-float, x-convlo and x-minnan, and the front phase compares
  x-float and the linear kernel (f32 arrays filled by `fill`) against omc; no front case is left as a refusal
  (`tfz` is empty).
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

## 9. Scalar floats (ham/ng-a64-float, NgFloatFill)

Design: `~/handoffs/hive/ham/reports/NgA64Float-design.md` (PROPOSED there, implemented here). IR semantics:
IR.md s7.2, s7.3 (min/max as OMEGESE fmin/fmax, FMINNM/FMAXNM), s7.4, s7.5 and s7.9; ngrun is the oracle.

**Representation and allocation.** An f32/f64 wire (`a_vf`) is allocated from the V registers, move locations
32..63 (V = location - 32), by the same linear scan: `a6_ffree` hands out v0..v7 and v16..v28 unless the interval
crosses a call, then d8..d15; `a6_spill` evicts within the class. Slots stay 8 bytes (`LDR/STR D`); an f32 rides in
the low 32 bits of its D view. Saves: x19..x27, then x30, then d8..d15; a pair (STP/LDP X or D) is two registers of
one class, a mixed neighbour is stored alone (`a6_rcls`). Parallel moves take any two classes: FMOV D,D; FMOV D,X or
X,D (raw bits, never a conversion); LDR/STR D for a slot; a cycle breaks through x15 holding raw bits (`a6_mvf`).
Integer-only functions take the same path as before: no float wire, no V location, so every output byte is the same
(checked on every a64 fixture, mkir fixture, run pair, front kernel and ngrand seeds 1..300 in both save forms).

**Selection** (`a6_sflt`, before every integer case in `a6_sel`):

| IR | A64 |
|---|---|
| const | MOVZ/MOVN/MOVK the raw bits into x16, FMOV D,X or S,W (sign and every NaN payload bit kept) |
| add sub mul div | FADD FSUB FMUL FDIV S/D, one rounding each, never contracted |
| min max | FMINNM FMAXNM S/D, no extra guards |
| neg fabs fsqrt | FNEG FABS (sign bit only, NaNs included) FSQRT |
| eq ne lt le gt ge | FCMP, CSET EQ NE MI LS GT GE: unordered sets C and V, so only ne is true then. Float compares are never fused into their consumer, and an integer compare is not fused into a float select (`a6_cuse`) |
| select | CMP c, #0; FCSEL S/D NE |
| bitcast | FMOV X,D / W,S then the integer's canonical extension; FMOV D,X / S,W; FMOV D for float to float |
| conv int to float | SCVTF/UCVTF S/D from the canonical X |
| conv f32 to f64 | FCVT D,S (exact) |
| conv f64 to f32 | FCVT S,D; with imm bit 2 an infinite result of a finite source becomes the largest finite of its sign (`a6_fsat`: the result bits minus 1 when its exponent is 255 and the source exponent is below 2047; the source bits are read into x17 before the result may reuse its register) |
| conv float to int | FCVTZS/FCVTZU X (toward zero, 64-bit saturation, NaN 0), then CMP/CSEL clamps for 8, 16 and 32 bits |
| fma (46 only) | FMADD d, a, b, c (a x b + c, rounded once) |
| load store | LDR/STR S or D, register offset, the index scaled by the element size; REF and SLICE of f32/f64 elements |
| chk.conv of a float | the value as f64 (FCVT D,S for f32), FCMP with itself, B.VS trap 5; then B.LS lo / B.GE hi trap 5 (i64: B.MI -2^63) |
| call, retv, block parameters | the banks of section 3, d0 for a float result |

Toward-zero rounding (conv imm 1 to a float destination) writes FPCR = 0xc00000 (RMode 11) through x15 right
before the one rounding instruction and FPCR = 0 (MSR FPCR, XZR) right after it. When the module has any f32/f64
value (`a6_hasf`), `_start` writes FPCR = 0 (round to nearest even, no flush to zero, no default NaN, no traps)
before `BL main`; an integer-only module has no such word.

Wolfram checks (MODELED encoding and constant arithmetic; the words are also checked against GNU objdump by
`gate.om`):

- `{IntegerString[FromDigits["d5100000",16] + 2^19 + 3*2^16 + 4*2^12 + 4*2^8, 16], IntegerString[3*2^22, 16],
  IntegerString[BitShiftLeft[16^^c0, 16], 16]}` gave `{"d51b4400", "c00000", "c00000"}`: the MSR FPCR word and the
  RMode 11 value as MOVZ #0xc0, LSL 16.
- The chk.conv bounds as f64 bits: `u64[-(2^(w-1)+1)] == BitOr[2^63, BitShiftLeft[1022+w, 52], 2^(53-w)]`,
  `u64[2^(w-1)] == BitShiftLeft[1022+w, 52]` and `u64[2^w] == BitShiftLeft[1023+w, 52]` for w in {8, 16, 32}, and
  `u64[-2^63] == BitOr[2^63, BitShiftLeft[1086, 52]]`, `u64[2^64] == BitShiftLeft[1087, 52]`,
  `IntegerString[u64[-1.], 16]` (u64 = the IEEE binary64 bits through `ExportString[x, "Real64"]`) gave True for
  every case and `"bff0000000000000"`.
- The largest finite f32: `IntegerString[bits32[(2 - 2^-23) 2^127], 16]` and `IntegerString[16^^7f800000 - 1, 16]`
  both gave `"7f7fffff"` (`a6_fsat` subtracts 1 from the infinity's bits).

Not here: `fload`/`fstore` (no STRUCT field access in the back end for any type), f16/bf16/fp8, `fmath`, integer
vectors, vectors wider than 16 bytes, `vinsert`/`vreduce`, and float atomics stay refused (exit 5). `fill` of f32/f64
elements is section 10; 128-bit packed `vec f32 4` and `vec f64 2` are section 12.

**Gates** (section 6): `gate.om` adds FCSEL S/D and MSR FPCR cases plus the float operand shapes (FPCR value, exponent
extracts, D pairs and spills) and two refusals; `rgate.om` adds the float ngrun fixtures, x-float to the front phase,
the float phase (`tests/frand.om`: 56 edge programs, seeds 1..1000, a negative control) and 34 float mutants:

36..39 the lt, le, gt and ge conditions take the integer LT, LE, HI and HS forms; 40 f64 add becomes sub (form
table); 41 f32 add uses the D form; 42 FCSEL operands swapped; 43 f64 neg becomes fabs; 44 the toward-zero
FPCR value becomes RMode 01 (toward +infinity); 45 FPCR is not restored after a toward-zero conversion; 46 `_start`
writes x16 (RMode 10) to FPCR; 47 the signed narrow clamp uses LE; 48 the unsigned clamp uses LS; 49 f64 to signed
integer through FCVTZU; 50 chk.conv lets NaN through (B.VC); 51 the signed chk.conv upper bound halved; 52 an f32
chk.conv source is not widened; 53 float element loads unscaled; 54 f64 stores 4 bytes; 55 the callee takes float
parameters from the integer registers; 56 the caller takes a float result from x0; 57 d8..d15 never saved; 58 a
float reload reads the next slot; 59 f64 min is FMIN (NaN rule); 60 f32 max is FMINNM; 61 signed i64 to f64 by
UCVTF; 62 saturation adds 1; 63 float constants from x17; 64 V-to-V moves read the next register; 65 float stack
arguments stored one slot low; 66 float stack parameters all read slot 0; 67 fma addend and multiplier swapped; 68
f32 to f64 conv uses FCVT S,D; 69 float spills stored one slot low. Two candidates are equivalent and not listed: the
argument and result bank moved together in caller and callee (`a6_abi`, `a_d0`), since every caller and callee is
ng code.

## 10. Fill (op 51, ham/ng-a64-fill, NgFloatFill)

Design: the "Fill (51) lowering plan" of `NgA64Float-design.md`, in the back end only (no copy-loop recognition, no
bulk copy). `a6_sfill` takes a REF to an ARRAY (count from the type) or a SLICE (count from its length wire) of
integer, f32 or f64 elements (an ΩIR array or slice holds numbers, IR.md s4.2, so there is no bool fill):

1. x17 = the value's raw bits: an integer's low 8 << sz bits (`AND #0xff`, `#0xffff`, `#0xffffffff`: a signed
   value's canonical extension is dropped), an f32 by FMOV W17, S, an f64 by FMOV X17, D (every bit, NaN payloads
   and -0 included; no float arithmetic touches it). Then ORR x17, x17, x17, LSL #8 / #16 / #32 until it holds 64
   bits of whole elements (`a6_fpat`).
2. x15 = the byte count: `ADD x15, XZR, len, LSL #sz` for a slice, a constant for a REF. A slice's elements lie in
   one storage object (at most 2^24 elements of at most 8 bytes, IR.md s4.2), so the shift cannot overflow.
3. DUP v31.2D, x17 (v31 is float scratch; no allocated V register is touched).
4. From the end down: `CMP x15, #16; B.LO tails; SUB x15, x15, #16; STR Q31, [base, x15]; B` the compare, then for
   8, 4, 2 and 1 bytes `TBZ x15, #k, next; SUB x15, x15, #2^k; STR X/W/H/B 17, [base, x15]`, the tails narrower
   than the element omitted (an 8-byte element has only the 8-byte tail).

Every store begins a whole number of elements past the base (the remaining count is a multiple of the element size
throughout), so the pattern lines up with the elements whatever the base's alignment; unaligned STR Q/X/W/H are
allowed on normal memory. A count of 0 stores nothing; nothing outside the span is written; nothing is read. The
base, value and count registers are the operand's own or the x16/x17/x15 scratch, as before.

Gates: `gate.om` adds DUP and STR Q (register offset) cases and refusals, and the fill's operand shapes. rgate's
edge programs 57..66 (`frand edge K`, `efill`: u8, i8, u16, i16, u32, i32, u64, i64, f32, f64): per case a
300-element local array is filled whole with a sentinel, a slice (one case in three a slice of a slice) at offset
0..31 is filled with a value, and all 300 elements are folded and printed, so sentinels before and after the span
and every element are compared with ngrun; lengths 0..257 for the 1-byte types, 0..40 and 63..65, 127..129,
255..257 for the wider ones; values and sentinels random, for floats half from the edge tables (NaN payloads,
signaling NaNs, -0). Fill mutants 70..79: block threshold 32, each tail testing bit 4 instead of its own (8, 4, 2,
1), the block loop's B.LO taken as B.HS (zero length and short spans store out of span), STR Q index scaled by 16,
the u8 replication shifted by 9, the integer mask one bit wide, the float pattern read from x16; mutant 23 (no
element-size scale) now acts on the byte count.

## 11. Mach-O for macOS (`@ng a64 macho`)

The same code generator with one switch, `a_tgt` 1. Three things differ from the ELF; nothing else does, and
`@ng a64` output is byte for byte what it was (checked on the hopfuzz unit: same sha256 before and after).

1. **Position independence.** arm64 macOS runs only slid (PIE) images, so no instruction holds an absolute address.
   The start code takes its own address with `ADR X16, .` and adds a constant: x28, the stack floor, is the image
   base plus 16 MiB; SP is x28 plus 8 MiB. A global's address (op 52) is `x28 + (8 MiB + offset)` for class 0 and
   `x28 - (16 MiB - file offset)` for class 1 (bytes in the text image): the constant through `a6_movi`, then one
   ADD or SUB with x28. x28 never changes after the start code.
2. **Calls into the system.** Darwin numbers and convention: number in x16, `SVC #0x80`, carry set on failure with
   errno in x0. exit is 1 (the trap tail, the exit op and the start code share `a6_exit`), read 3, write 4; after
   read and write `CSNEG X0, X0, X0, CC` gives the count or minus errno, the shape the Linux words return (the
   errno numbers are those of Darwin). monons 109 and realns 130 are refused (class 5, `unsupported`): Darwin has
   no clock_gettime call. The other refused words are the ones the ELF refuses.
3. **Container** (`a6_macho`; section 13 changes the __DATA start and __LINKEDIT). A 16 KiB header page (mach_header_64, 12 load commands, 680 bytes: __PAGEZERO 4 GiB,
   __TEXT with one section, __DATA zero-filled, __LINKEDIT, empty DYLD_INFO_ONLY, empty SYMTAB with a 16-byte
   string table, DYSYMTAB, LOAD_DYLINKER, LOAD_DYLIB libSystem, BUILD_VERSION macOS 11.0, a fixed UUID, MAIN), the
   code from file offset 16384 (function entries stay on 64-byte boundaries), zero padding to a 16 KiB multiple,
   then 16 zero bytes of __LINKEDIT. __DATA sits at base + 16 MiB: 8 MiB of stack, then the class-0 globals. The
   layout follows the bounded adapter of ports/macos-arm64 (L615), which ran on macOS 26.6.2. dyld and libSystem
   are loaded and never called. The code signature arm64 macOS requires is added on the Mac with
   `codesign --force --sign -`; the header page leaves room for its load command. That signing step is a disclosed
   host dependency: ng does not compute it.

Check: `sh seed/ng/a64/tests/macho/run.sh bundle NG DIR` on Linux AArch64, then `sh run.sh run DIR` on an arm64 Mac.
The bundle step compiles every `seed/ng/tests/ir/x-*.om`, `a64/tests/front/*.om` and `a64/tests/macho/*.om` both
ways (a unit one target refuses must be refused by both with the same line), runs each ELF and records its status
and stdout. The run step signs and runs each Mach-O and compares. Its two negative controls are mutant compilers the
bundle step builds: without the CSNEG a write to a closed descriptor (`badfd.om`) must change status; with a class-1
global address added instead of subtracted `gtext.om` must lose its output.

Measured 2026-11-10 (HOST_TESTED on a MacBook, macOS 26.6.2, arm64; ELF side on the Spark): 22 of 22 fixtures equal
their ELF in exit status and stdout bytes (statuses 0, 3, 5, 7, 9, 17, 42, 158, 224, 243, 255 and traps 101, 103,
104, 105, 107; three write stdout); 21 are refused by both targets with the same `unsupported` line; both controls
are caught (badfd 247 for 9; gtext prints nothing). `a64/gate.om` passes on this head. A 300-block unit with read
and write (the Hop matcher and a stdin batch driver) answered 40610 of 40610 cases as its Swift reference. NOT_RUN:
floats on macOS, globals over 16 KiB, a control for the start code and for the exit call (a wrong exit number is
another system call, so it is not run as a mutant). The Mac run is not part of gate or rgate, which run on Linux.

## 12. Packed 128-bit float vectors (`vec f32 4`, `vec f64 2`; NgVecA64)

Scope: the two 16-byte Advanced SIMD packed IEEE-754 vector types `vec f32 4` (`i_tk = 1, i_t1 = 13, i_t2 = 4`,
arrangement `.4S`) and `vec f64 2` (`i_tk = 1, i_t1 = 14, i_t2 = 2`, arrangement `.2D`) in `seed/ng/src/a64.om` and the
differential reference interpreter `seed/ng/ngrun.om` (`r_v[k]` low 64 bits = lanes 0..1 of `f32` or lane 0 of `f64`,
`r_w[k]` high 64 bits = lanes 2..3 of `f32` or lane 1 of `f64`). Integer vectors, half/brain-float vectors, 32B/64B
vectors, and vector `div`/`min`/`max`/`select`/`vinsert`/`vreduce` stay refused (`a64: unsupported K`, exit 5); an
integer compare followed by `select` of a `VEC` is excluded from compare fusion in `a6_cuse` (`not a6_isvv`) so it
hits `a6_unsup 2` cleanly (`tests/oir/u-selvec.oir`).

### Encodings (Arm DDI 0487, C7.2)

| Form | Mnemonic | Base word | Fields |
|---|---|---|---|
| `a_strq` (165) | `STR Qt, [Xn, #imm12*16]` | `0x3d800000` | `Rt[4:0]`, `Rn[9:5]`, `imm12[21:10]` (`0..4095`) |
| `a_ldrq` (166) | `LDR Qt, [Xn, #imm12*16]` | `0x3dc00000` | `Rt[4:0]`, `Rn[9:5]`, `imm12[21:10]` (`0..4095`) |
| `a_ldrqr` (167) | `LDR Qt, [Xn, Xm]` | `0x3ce06800` | `Rt[4:0]`, `Rn[9:5]`, `Rm[20:16]`, `S = 0` (`c = 0`, unscaled byte offset; `c = 1` refused) |
| `a_orr16b` (168) | `ORR Vd.16B, Vn.16B, Vm.16B` | `0x4ea01c00` | `Rd[4:0]`, `Rn[9:5]`, `Rm[20:16]` (`Vn = Vm` disassembles as `MOV Vd.16B, Vn.16B`) |
| `a_dupv4s` (169) | `DUP Vd.4S, Vn.S[0]` | `0x4e040400` | `Rd[4:0]`, `Rn[9:5]` |
| `a_dupv2d` (170) | `DUP Vd.2D, Vn.D[0]` | `0x4e080400` | `Rd[4:0]`, `Rn[9:5]` |
| `a_dups` (171) | `DUP Sd, Vn.S[idx]` | `0x5e040400` | `Rd[4:0]`, `Rn[9:5]`, `idx[20:19]` (`0..3`, `imm5 = (idx << 3) | 4`) |
| `a_dupd` (172) | `DUP Dd, Vn.D[idx]` | `0x5e080400` | `Rd[4:0]`, `Rn[9:5]`, `idx[20]` (`0..1`, `imm5 = (idx << 4) | 8`) |
| `a_fadd4s` / `a_fadd2d` (173, 174) | `FADD Vd.4S/2D, Vn, Vm` | `0x4e20d400` / `0x4e60d400` | `Rd[4:0]`, `Rn[9:5]`, `Rm[20:16]`, `sz[22] = 0/1` |
| `a_fsub4s` / `a_fsub2d` (175, 176) | `FSUB Vd.4S/2D, Vn, Vm` | `0x4ea0d400` / `0x4ee0d400` | `Rd[4:0]`, `Rn[9:5]`, `Rm[20:16]`, `sz[22] = 0/1` |
| `a_fmul4s` / `a_fmul2d` (177, 178) | `FMUL Vd.4S/2D, Vn, Vm` | `0x6e20dc00` / `0x6e60dc00` | `Rd[4:0]`, `Rn[9:5]`, `Rm[20:16]`, `sz[22] = 0/1` |
| `a_fmla4s` / `a_fmla2d` (179, 180) | `FMLA Vd.4S/2D, Vn, Vm` | `0x4e20cc00` / `0x4e60cc00` | `Rd[4:0]`, `Rn[9:5]`, `Rm[20:16]`, `sz[22] = 0/1` |

### Lowering, AAPCS64 Call-Clobber Rule, and Stack Alignment

- **Operations (`a6_svec`)**:
  - `58 vload`: `REF` to `ARRAY` or `SLICE` of `f32`/`f64`. When the element index `iv` is a constant whose byte offset
    `idx << sz` is a multiple of 16 in `[0, 65520]` (`a6_vqimm`), emits `LDR Qd, [base, #q]`; otherwise computes the
    scaled byte offset in `x15` (`ADD x15, XZR, idx, LSL #sz`) and emits `LDR Qd, [base, x15]` (unaligned 128-bit loads
    are permitted on normal memory).
  - `59 vstore`: symmetric `STR Qx, [base, #q]` or `ADD x15, XZR, idx, LSL #sz; STR Qx, [base, x15]`.
  - `100 vsplat`: `DUP Vd.4S, Sa[0]` (`a_dupv4s`) or `DUP Vd.2D, Da[0]` (`a_dupv2d`).
  - `101 vextract`: checks `imm < lanes`, emits `DUP Sd, Va.S[imm]` (`a_dups`) or `DUP Dd, Va.D[imm]` (`a_dupd`).
  - `10 add`, `11 sub`, `12 mul`: `FADD`, `FSUB`, `FMUL` on `.4S` or `.2D` (one IEEE-754 rounding per lane; `_start`
    sets `FPCR = 0` whenever `a6_hasf` sees scalar or vector floats).
  - `46 fma` (`a * b + c`, single rounding per lane): `FMLA Vd, Va, Vb` computes `Vd + Va * Vb`. When `Vd = Vc`, emits
    `FMLA Vd, Va, Vb` directly. When `Vd` aliases `Va` or `Vb` (`d = a` or `d = b`, possible when `a` or `b` dies at the
    op), copying `Vc` into `Vd` first would overwrite a live multiplicand, so `a6_vfma` copies `Vc` to scratch `v31`,
    runs `FMLA v31, Va, Vb`, and moves `v31` to `Vd` via `ORR Vd.16B, v31.16B, v31.16B`. Otherwise copies `Vc` to `Vd`
    and emits `FMLA Vd, Va, Vb`.
- **AAPCS64 `BL` clobber safety (`a6_alloc`)**: under AAPCS64, `v8..v15` only preserve their low 64 bits (`d8..d15`)
  across a subroutine call; any scalar `D` write or callee epilogue `LDP D` zeroes bits `64..127`. `a6_alloc` therefore
  spills every 128-bit `VEC` (`a_vf[w] = 2`) whose live range crosses a `BL` (`a_vx[w] != 0`) to a 16-byte stack slot,
  never placing a cross-call 128-bit vector in `v8..v15`.
- **16-byte stack slots, parallel moves, and ABI (`600..631`, `700..955`, `3000 + ks`)**: `a6_slot` aligns `s` upward to
  an even 8-byte slot index and reserves 2 slots (`16` bytes, `[sp, 16*(s/2)]`, aligned mod 16 because `sp` is 16-byte
  aligned) so `STR Q` / `LDR Q` unsigned scaled immediates (`q = (a_vsl[w] - 1) >> 1`) address exact 16-byte boundaries.
  Parallel moves encode allocated 128-bit `V` registers as `600 + r` (`v0..v28` = `600..628`), reserve `631` (`v31`)
  exclusively as the `a6_mvbrk` parallel-move cycle breaker, encode 16-byte frame slots as `700 + q` where `a6_mvq`
  slot-to-slot copies use disjoint scratch `v30` (mirroring GP `x16` slot copy vs `x15` cycle breaker so 2-slot swaps
  across `BL` never clobber `v31`), and encode 16-byte stack ABI arguments past `v0..v7` as `3000 + ks` (`ks`
  even-aligned).

### Proofs, Wolfram Checks, and Gates

- **Lean 4 (`evidence/NG-A64-VEC/lean/NgA64Vec.lean`)**: 24 kernel-checked theorems (`lake env lean`, zero `sorryAx`,
  zero `native_decide`), proving R3 bitfield injectivity, `4S` vs `2D` encoding disjointness across all register triples,
  `DUP` lane-index round-trip, 128-bit `Vec128` lane homomorphism (`vsplat`, `vbin`, `vfma` vs `vextract`), `a6_vfma`
  register-aliasing correctness across all register assignments, 16-byte stack slot alignment, `a6_mvq` (`v30`) +
  `a6_mvbrk` (`v31`) 2-cycle parallel swap correctness across registers and 16B stack slots, and four negative controls
  (AAPCS64 64-bit `d8` save truncating upper lanes, naive `vfma` clobbering `d = a`, `sz`-bit drop colliding `4S` with
  `2D`, and shared-`v31` slot copy clobbering a 2-slot swap).
- **Wolfram (`evidence/NG-A64-VEC/wolfram-query.wl`, `wolfram-raw.json`)**: independently verified all 16 reference
  instruction words, IEEE-754 single-rounding `fma` lane values vs unfused `mul+add`, and Cortex-X925 `monons` speedup
  ratios (`v4f32`: `3.37534x` median speedup over scalar `omc`, `11.8477 GFLOP/s` vs `3.51008 GFLOP/s`; `v2f64`:
  `1.68362x` median speedup, `5.99903 GFLOP/s` vs `3.56317 GFLOP/s`, bit-identical checksums).
- **Gates**: `gate.om` adds 27 `objdump`-checked encoder cases (`263/263`) and 10 refusal cases (`37/37`); `rgate.om`
  adds 7 differential execution fixtures (`v-f32-ops`, `v-f64-ops`, `v-fma-alias`, `v-call-clobber`, `v-spill-loop`,
  `v-spill-swap`, `v-swap-nocall`), refusal fixture `u-selvec`, and 6 `VEC` mutants (`80..85`).

## 13. Calls into system libraries (`target macos`: `libfn`, `libptr`, `libcall`)

Until here a Mach-O program could only read, write and exit. These three words (IR.md s7.11, host ids 241..243) let
an Omega program call any function of any library on the Mac: libSystem, the Objective-C runtime, AppKit. They are
keywords only in a unit whose first line is `target macos`; elsewhere the names are free, as in omc. Linux output is
untouched (`a_tgt` 0 refuses the words).

**What the language gives up, and where.** Omega exposes no raw address and no arbitrary system call. That stays
true for every unit without the target line. A `target macos` unit has one gateway: `libptr` hands out the address
of a checked slice, and `libcall` runs code the compiler never saw. Nothing behind the gateway is checked.

**The link page.** __DATA now starts 16 KiB below the stack floor (base + 16 MiB - 16 KiB); the stack and the globals
are where they were. The page holds three words, reached as `x28 - 16384` (`SUB Xn, X28, #4, LSL #12`):

| offset | word | written by |
|---|---|---|
| 0 | address of `dlopen` | dyld, before the program starts |
| 8 | address of `dlsym` | dyld |
| 16 | the stack pointer dyld entered with | the start code (`MOV X9, SP; SUB X10, X28, #4, LSL #12; STR X9, [X10, #16]`) |

dyld fills the first two from 24 bytes of bind records at the start of __LINKEDIT (LC_DYLD_INFO_ONLY bind_off,
bind_size 24): dylib ordinal 1 (libSystem), `_dlopen`, type pointer, segment 2 offset 0, bind; `_dlsym`, bind;
done. Every other function is found at run time with `dlsym`, so the container never grows with the program. The
text may be at most 16 MiB less 16 KiB (`a6_die` otherwise).

**Lowering** (`a6_hlib`). A host word counts as a call for allocation, so no live value is in x0..x14 or a
caller-saved V register; x16, x17 and x9 are free.

- `libfn k`: `MOV X0, #0; CMP X16, #2; B.HS +8; LDR X0, [X17, X16, LSL #3]` with x17 the link page.
- `libptr A off n`: x17 = A + off, as read and write form it; the value is x17.
- `libcall F A off n`: x17 = A + off; `CMP n, #128; B.LO` trap 3; x16 = F; `CMP X16, #0; B.EQ` trap 3. Then
  `STP X19, X20, [SP, #-16]!` (stack floor checked, trap 6), x19 = sp, x20 = x17, sp = link page word 16, eight
  `LDP` load x0..x7 and d0..d7 from the file, `BLR X16`, `STP X0, X1, [X20]`, `STP D0, D1, [X20, #64]`,
  `STP D2, D3, [X20, #80]`, sp = x19, `LDP X19, X20, [SP], #16`. Library code runs on the system stack, 16-byte
  aligned as dyld left it, and never on the Omega stack; the C convention keeps x19..x28 and the low halves of
  v8..v15, which is what ng keeps across any call.

**Limits.** Eight integer and eight float arguments in registers; no stack arguments (so no C variadic call on
arm64 macOS), no x8 (functions that return a large struct through memory). Results: x0, x1, d0..d3. A library
can call back into Omega only through the callback entries of section 14. One thread. `exit` leaves through the system call as before: C `atexit` handlers and stdio buffers are not run.

Check: the library fixtures of `sh seed/ng/a64/tests/macho/run.sh` (`a64/tests/macho/lib/`, what each must give in
`lib/expect.txt`): `libwrite` (dlsym, then write, 35 bytes), `libmath` (sqrt and pow through d0 and d1, exact bits),
`libobjc` (dlopen Foundation, `objc_getClass`, `sel_registerName`, `objc_msgSend`: the processor count equals
`sysconf`), `libloop` (200 calls with eight integer sums and one f64 live across them), `libshort` and `libnull`
(trap 3). `libname.om` uses the three names as variables without the target line and runs on both targets. Two
mutant compilers: without the store of d0 and d1 `libmath` must change; with `libfn` always giving `dlopen`
`libwrite` must change.

Measured 2026-11-11 (HOST_TESTED on a MacBook, macOS 26.6.2, arm64; bundle step on the Spark): 23 of 23 fixtures
equal their ELF (the 22 of section 11 and `libname`, all with the new start code and container), 21 refused by both
targets, 6 of 6 library fixtures give their expected status and stdout, and all four controls are caught (libmath 2
for 1; libwrite 139 for 35). NOT_RUN: a second thread, more than one library call
deep in recursion near the stack floor.

## 14. Callbacks from library code (`libback`)

A window's buttons, an Objective-C method, the comparison function of `qsort`: library code calls a C function it
was handed. A `target macos` unit may define one callback function,

    fn libback k ulong a ulong b ulong c ulong d ulong e ulong to ulong

(the front end marks it with function flags bit 1, IR.md s6.1; any other signature is refused). With it the
program has sixteen callback entries, C functions whose addresses are `libfn 2` .. `libfn 17` (0 without a callback
function, and for every other number above 1). When library code calls entry k with the C convention, `libback`
runs with k and the first five integer arguments x0..x4, and its result goes back in x0. One function and a number
keep the language free of function values: the program dispatches on k.

**The entries** (`a6_back`, emitted once after the exit code): sixteen pairs `MOVZ X16, #k; B body`, then one body.
`libfn k`, k 2..17, is the class-1 address `x28 - (16 MiB - offset of the entries) + 8 (k - 2)`, chosen with a
`CSEL` after the table read of section 13.

**The body.** A callback only ever arrives inside a `libcall`, on the thread that made it, on the C stack.

- `STP X29, X30, [SP, #-48]!; MOV X29, SP; STP X27, X28, [SP, #16]`: a C frame. C code keeps x28 across calls but
  may hold anything in it during one, so the body finds it again as the start code does: `ADR X9, .` plus a constant.
- Link words 16 and 24 are saved in the frame. Word 16 becomes the C stack pointer here, so a `libcall` made by the
  callback runs below the C frames that are live (the start code's value would run over them). Word 24 is the Omega
  stack pointer of the enclosing `libcall`, which `libcall` now stores there (`STR X19, [X9, #24]`): the body moves
  to it, so Omega frames of the callback sit below the frames of the Omega code that is waiting in the `libcall`.
- x0..x4 move to x1..x5, x0 = k, `BL libback`. Back: sp = the C frame, the two link words are put back, the saved
  registers reloaded, `RET`. `libback` is an ordinary ng function: it keeps x19..x27 and v8..v15 itself, checks the
  stack floor (trap 6) and may trap; a trap ends the program as anywhere.

Callbacks nest (a `libcall` in a callback may be called back again); each level restores what it found.

**Limits.** Five integer arguments; no float arguments (a view's `drawRect:` gets its rectangle in d0..d3, which is
lost: ask the view for its bounds instead), no arguments on the stack, an integer result only. Sixteen entries. The
thread that started the program only: a library that calls an entry from another thread breaks the program.
An entry called when no `libcall` is active does not happen on one thread.

Check: `lib/libback.om` (`qsort` sorts eight numbers with `libback` as the comparison, which reads its two
elements with `memcpy`, a `libcall` inside a callback; entry 5, so k must be 5) and `lib/libbackobjc.om` (a class
made with `objc_allocateClassPair` whose methods `poke:` and `twice:` are entries 0 and 3: self, the selector and
the argument must arrive, and 2 x 21 must come back through `objc_msgSend`). Two more mutant compilers: without
`MOV X1, X0` in the body `libback` (the fixture) no longer sorts; without the store of link word 24 it cannot run.
The IR cases `a-back`, `r13-backsig`, `r13-backtwo` and `r13-fnflags4` pin the flag's rule in ngcheck.

Measured 2026-11-11 (HOST_TESTED on a MacBook, macOS 26.6.2, arm64; bundle step on the Spark): 23 of 23 fixtures
equal their ELF, 8 of 8 library fixtures give their status and stdout, and all six controls are caught (libback 6
for 1 without the move, 139 without the store). NOT_RUN: callbacks nested more than one deep, a callback from
another thread, a callback that traps.
