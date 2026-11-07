# nga64: ΩIR to AArch64 Linux ELF (design, ng-a64 lane)

Status: PROPOSED design, implementation in progress on branch `ng/a64-m1`. Pin: omega-mv `943d9555`, built by
`seed/out/omc` sha256 `5f90edea…`. The facts about seed omc it relies on are in
`~/handoffs/hive-ng/a64/REALITY.md` (file:line at `943d9555`).

## 1. Job

`nga64 < unit.oir > prog` reads one ΩIR unit (binary, `seed/ng/IR.md`) on stdin and writes a static AArch64 Linux
ELF executable on stdout. Exit 0 on success; a refusal exits with a nonzero code and one stderr line
`nga64: <class> at <offset>`, nothing on stdout. It is one `.om` unit compiled by seed omc.

Observable behaviour must equal seed omc on the same source (D5): stdout and stderr bytes, exit status, trap code.
Instruction bytes, register choice and frame layout are free.

## 2. Pipeline inside nga64

1. **Read**: strict ΩIR reader into flat global tables (functions, blocks, block parameters, ops, operands). The reader
   trusts nothing; `ngcheck` is the validator, but nga64 still refuses what it cannot lower (exit 3, class `UNSUPPORTED`).
2. **Select**: each ΩIR op becomes one or more MIR instructions over virtual registers (vregs). MIR is a
   one-to-one picture of A64 instructions (opcode, def vreg, use vregs, immediate, condition), so the allocator and
   the encoder see exactly what will run. Known fusions:
   - `add`/`sub`/`neg` followed by its overflow check on the same operands: `ADDS`/`SUBS` + `B.VS` (i64) or `B.CS`/`B.CC` (qty).
   - compare feeding a branch: `CMP` + `B.cond` (no `CSET`); compare feeding a value: `CSET`.
   - constant operands: ADD/SUB imm12 (optionally `LSL #12`), logical bitmask immediates, shift immediates.
   - bounds check + load: `CMP idx, len; B.HS trap3; LDR Xd, [base, idx, LSL #s]`.
   Narrow integer types keep omc's canonical form (zero/sign extended to 64 bits) so comparisons and stores stay
   correct; checks on narrow types follow omc's sequences (REALITY.md rows add/mul/div/shift).
3. **Order**: blocks in ΩIR order (the front end emits a dominator-compatible order); fall-through edges remove `B`.
4. **Liveness**: backward dataflow over blocks with one bitset per block (live-in/live-out), iterated to a fixed point.
   Block parameters are defined at block entry; the edge arguments are uses at the end of the predecessor.
5. **Intervals**: every MIR instruction gets an even position (2i; odd positions are reserved for split moves).
   A vreg's interval is `[first def, last use]`, widened to cover every block where it is live-in or live-out
   (one range per vreg; holes are ignored in v1). Each interval records whether it crosses a call.
6. **Linear scan** (Poletto & Sarkar, 1999) over intervals sorted by start, with two register classes:
   - GPR allocatable: x0..x15 (caller-saved), x19..x27 (callee-saved). 25 registers.
   - FP allocatable: v0..v7, v18..v31 (caller-saved), v8..v15 (callee-saved, low 64 bits). 30 registers.
   - An interval that crosses a call takes only callee-saved registers. Hints: a vreg that is a call argument or
     result prefers x0..x7/v0..v7 at that call; a block parameter prefers the register of its incoming argument.
   - When none is free, spill the interval (active or current) whose end is farthest; its home is an 8-byte stack
     slot. A spilled vreg is reloaded into a scratch register before each use and stored after each def (spill
     everywhere). **This retires error 12**: there is no limit on live values except stack size.
7. **Rewrite**: replace vregs by physical registers; insert spill loads/stores; resolve block-parameter moves on each
   edge as a parallel move (cycles broken through x16 / v16); a critical edge gets its own move block.
8. **Frame**: `SUB SP` by frame size (spill slots + local arrays + saved callee-saved registers + x30 if the function
   calls), `CMP SP, X28; B.LO trap6` (omc's stack-floor rule), callee-saved and x30 saved with `STP` pairs,
   restored with `LDP` before `RET`. A leaf with no callee-saved use and no spill has no frame at all.
9. **Emit**: encoder functions (section 4) write words into the code buffer; branches are patched after layout.
   Every function shares one trap tail per program: `B.cond` to per-code stubs `MOVZ X1,#code; B tail`,
   tail `ADD X0, X1, #100; MOVZ X8, #93; SVC #0` (omc `finish`, REALITY.md), so exit status 100+code is identical.
10. **ELF**: omc's layout (REALITY.md): 176-byte header, code at 0x400000 entry 0x4000b0, RW pool at 0x10000000
    (8 MiB stack, X28 floor = 0x10000000, SP = 0x10800000), globals from 0x10800000, texts in the code image.

## 3. Registers reserved (documented, never allocated)

| Register | Use |
|---|---|
| x16, x17 | scratch: spill reloads, large immediates and offsets, parallel-move cycle breaking |
| x18 | platform register (AAPCS64 6.1.1), left alone |
| x28 | stack floor 0x10000000 (omc convention, trap 6 check) |
| x29 | reserved as frame pointer (kept free so that backtraces stay possible; may become allocatable after A/B) |
| x30 | link register |
| SP | stack |
| v16, v17 | FP scratch (spill reloads, parallel-move cycles) |

Calls between nga64 functions use x0..x7 / v0..v7 for arguments and x0 / v0 for the result (AAPCS64 shape,
`~/docs/arm-cores/aapcs64-2025Q4.txt` 6.4). There is no outside caller in program mode, so the only contract is the
one nga64 makes with itself; host words are inline `SVC #0` sequences that clobber x0..x8 only (Linux arm64 syscall ABI:
number in x8, arguments x0..x5, result x0).

## 4. Encoder layer

One function per instruction form, `fn eNAME operands to ulong` returning the 32-bit word; `emit` appends it. Every
form cites its DDI 0487 M.d section (the same source as `seed/rung2/table.s2`). Forms (v1): ADD/SUB/ADDS/SUBS
(shifted register, immediate, extended register), AND/ORR/EOR/ANDS (shifted register, bitmask immediate),
MOVZ/MOVN/MOVK, MADD/MSUB/SMULH/UMULH/SDIV/UDIV, LSLV/LSRV/ASRV/RORV, UBFM/SBFM/EXTR, CSEL/CSINC/CSNEG,
LDR/STR/LDRB/LDRH/LDRSB/LDRSH/LDRSW/STRB/STRH (unsigned offset and register offset), LDP/STP (signed offset,
pre-index, post-index), B, BL, B.cond, CBZ, CBNZ, TBZ, TBNZ, RET, BR, BLR, SVC, ADR, and the FP set FADD/FSUB/FMUL/FDIV/
FSQRT/FABS/FNEG/FMIN/FMAX/FCMP/FMOV/SCVTF/UCVTF/FCVTZS/FCVTZU/FCVT and LDR/STR S/D.

Constants: MOVZ/MOVN + MOVK (fewest halfwords), or ORR from XZR with a bitmask immediate when that is one word.

**Encoder gate** (`seed/ng/a64/gate-enc.om`): `nga64` run with the test magic writes one word per case; the gate
disassembles them with GNU objdump (referee, never builder) and compares each line with the hand-written expected
text in the case table. Negative control: a mutant encoder with one wrong bit must fail the gate.

## 5. Gates

- `gate-enc.om`: encoder forms vs objdump (above), with a wrong-bit mutant.
- `gate-ra.om`: generated high-pressure functions (more simultaneously live values than the 25 GPRs and 30 FP
  registers, values live across calls, loops with block parameters) compiled by nga64 from ΩIR and by seed omc from the
  equivalent Omega source where omc can compile it; stdout and exit must match. The spill path is counted (nga64 prints
  spill statistics on stderr in test mode) and must be nonzero. Negative controls: an allocator mutant that ignores
  call clobbers, and one that drops a spill store, must both fail.
- `gate-diff.om` (with ng-front): `ngfront | nga64` vs seed omc on `examples/` and the OmegaFast bench kernels.

## 6. Scheduling facts used (Cortex-X925 Software Optimization Guide, `~/docs/arm-cores`)

- ALU basic (ADD, AND, …): latency 1, throughput 8 per cycle; flag-setting ADDS: latency 1, throughput 4 (p15).
- B: throughput 2 per cycle; CBZ/CBNZ/TBZ: throughput 2 (p15).
- LDP: latency 4; STP: throughput 2 (p19-20).
v1 does no instruction scheduling; it prefers fused compare-and-branch, LDP/STP for frames, and fewer instructions.
