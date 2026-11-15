# What Omega cannot say yet

The GEMV is a gfx942 instruction table (`fp8gemv_stream.isa`) packed by
`gpu/amd/gfx942/hsaco.om`. That is the path this tree already uses for a kernel.
The numeric references in `check.om` (a column-order loop and the kernel's own
order, composed with `exec/fma.om`) are OM-2. The table is data. It is not a
typed Omega load.

These are the operations the kernel needs and OM-2 does not have as operations.
Each one is emitted as instruction fields instead.

1. A 128-bit global load with a cache policy. `global_load_dwordx4` plus the
   nt bit is three fields in format 7 (OP 23, NT at the bit `llvm-mc` sets, SADDR).
   A language operation would be a typed load of four u32, or sixteen u8, with an
   enum for the Table 48 row (wave temporal, wave nontemporal, and the scoped
   rows) rather than a raw bit.

2. `V_CVT_PK_F32_FP8`. Table 31 names it as a VOP1 packed convert, destination
   even. The kernel uses the `e32` form `llvm-mc` encodes (opcode 86) on the low
   16 bits, then `v_lshrrev_b32` by 16 and the same convert. The ISA sentence on
   8-bit converts says SRC0 is SDWA and the byte select lives in the SDWA word.
   This kernel does not invent an SDWA select code. A language operation would
   name the source bytes.

3. DPP `row_shr` with the assembler's default row mask and bank mask, and with
   bounds control clear (ISA §13.3.9, BC = 0 means do not write when the source
   is out of the row). The reduction is four of those adds and four
   `v_readlane_b32`. A language reduction would name the row sum. It would not
   make the programmer pick lane 15.

4. `buffer_wbl2` and `buffer_inv` with the sc0/sc1 pairs LLVM's GFX942 acquire
   and release sequences use, and a global atomic whose sc1 is the scope bit.
   The probe encodes them. The GEMV does not issue them. OM-2 has no memory
   scope on a store.

5. A cross-wave reduction. The fused epilogue multiplies by an `inv_rms` the
   host passes in. One wave owns one row and cannot compute the RMS of the
   whole vector. A workgroup or device reduction would have to exist before the
   kernel could produce that scale itself.

The closest expressible program is the one in this directory: the table, the
probe, and the CPU reference. Per-block scales and OCP E4M3 are reference-only.
The device code object is Table 30 FP8 and a per-row scale.
