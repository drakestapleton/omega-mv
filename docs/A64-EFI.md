# AArch64 UEFI backend (`target a64efi`)

Status (2026-11-17): **IMPLEMENTED; EXERCISED under emulation only** (QEMU `virt`, cortex-a72,
TCG, AAVMF). Not run on any physical machine. Not run on the DGX Spark. First cut of DRA-938: an
image the firmware can start, a console, and raw memory access. It is not a kernel target yet.

The compiler source is `seed/omc/omc.om` (`aaddr`, `arun`, `aeof`, `aefival` and hooks in the target
line parser and the exits). The committed `seed/out/omc` predates this change until the reseed; build
a candidate from the source to use the target.

## Selection

The exact first line `target a64efi` selects an AArch64 PE32+ EFI application for a whole program.
Without it the default AArch64 Linux program is unchanged, and `target x86linux` and `target x86efi`
are unchanged: every `.om` file tracked before this change compiles to the same bytes or the same
refusal with the old and new compiler, as stored and with `target x86linux` prepended (1,501 files
each way; the six that differ are new `tests/a64efi/refuse` inputs).

## What changes against the default AArch64 program

The code generator is the default one. Five things differ:

- **Image.** PE32+, Machine 0xAA64, subsystem 10 (EFI application), DllCharacteristics 0x0140
  (dynamic base, NX compatible). `.text` at file offset 4096 = RVA 4096, read and execute. `.bss`
  read and write: a 64 KiB guard, the 8 MiB stack, then the pools. One empty base relocation block:
  nothing in the image needs relocating.
- **Addresses.** The image is position independent. Pool addresses are formed from X28 (the stack
  floor); text addresses with ADRP and ADD.
- **Entry.** The firmware enters with X0 = ImageHandle, X1 = SystemTable, X30 = its return. The entry
  saves the firmware SP, X19..X30, D8..D15 and FPCR in 256 private bytes at the stack top, clears
  FPCR (the state a Linux process starts with), sets SP and X28 and calls `main`.
- **Exit.** Return, `exit` and every trap branch to one firmware return that restores what the entry
  saved. `main`'s value is the EFI_STATUS. A trap T returns `2^63 | (100 + T)`, as on x86efi.
- **X18** is never used by generated code (the firmware may own it).

## The `efi` word

`r = efi OP ARG A OFF N`, the x86efi form: OP a literal, ARG a ulong, A a writable uchar array with
`OFF + N <= len A` (else trap 3, checked first). The result is a ulong; bit 63 set means an error.

| OP | Operation | Status |
|---|---|---|
| 13 | console: write `A[OFF..OFF+N)` to ConOut. ARG must be 0 (else 32). Bytes 9, 10, 13, 32..126 (else 42). LF becomes CR LF. ConOut NULL or a failed OutputString: 43. Result N. Needs 64 KiB of stack (trap 6). | EXERCISED (EMULATED) |
| 20 | copy N bytes from physical address ARG into A. Result N. | EXERCISED (EMULATED) |
| 21 | copy N bytes from A to physical address ARG. Result N. | EXERCISED (EMULATED) |
| 15, 16 | port I/O: does not exist on AArch64 | compile error 25 |
| any other | not implemented on this target | compile error 25 |

For 20 and 21, N of 2, 4 or 8 at an address that is a multiple of N is one access of that width, so
a device register is read or written once. Anything else goes a byte at a time, ascending. The
numbers match the x86efi machine-access operations (DRA-937) so one program text can serve both.

## Evidence (2026-11-17, x86-64 container, emulated)

Compiler built from this source: seed omc to stage 1, 2 and 3, and om4 to stage 1, all sha256
`721ce058f856a9c5…` before the merge with DRA-937 (the merged source has a different hash; see the
reseed commit). 512 functions.

`sh tests/a64efi/run.sh <x86-hosted candidate>`: `SUMMARY pass=34 fail=0 not_run=0`.

| Group | What it checks |
|---|---|
| `refuse` | target-line variants (case, longer, shorter, extra token), host words and `read`/`write` refused, `efi` accepted only for 13, 20, 21 |
| `exit` | return 0, return `2^63|77`, `exit -3` two calls deep, trap 3 four calls deep, seven 1 MiB frames fit and the eighth is trap 6 |
| `con` | 15 console lines, OFF and N handling, codes 32 and 42, trap 3 past the array, every LF as CR LF |
| `float` | the 41 lines of `tests/x86efi/float/expected.txt` |
| `addr` | text, view argument, global and OM-2 unsized view addresses in a relocated image |
| `pl011` | the QEMU `virt` PL011 at 0x09000000 by byte and by word, its flag and ID registers, 16 flash bytes at every width, the RTC match register |

`sh tests/a64efi/mutants.sh <x86-hosted candidate>` (needs AArch64 user emulation registered, since
each mutant compiler is an AArch64 program): `SUMMARY mutants killed=4 failed=0 not_run=0`.
`trapbit` (trap status without bit 63), `adrp0` (page distance dropped), `mem4` (wrong access
width), `nocr` (no CR before LF).

## NOT_RUN

- Any physical machine, including the DGX Spark.
- Any firmware other than AAVMF; any CPU model other than cortex-a72 under TCG.
- `efi` operations 0..12 and 14 (not implemented here).
- System registers (MRS/MSR), exception vectors, leaving boot services, page tables, secondary
  cores, cache and barrier instructions: the rest of DRA-938.
- The seed gates that need the C oracles and a native AArch64 host.

## Runtime

The image starts with 126 fixed words at 4104: the firmware return (16 words), `efi 13` (63 words
from 4168) and `efi 20`/`21` (47 words from 4420). The first function starts at 4608. The listing
below is a disassembly (GNU objdump, binutils) of those words as the compiler emits them, taken from
`tests/a64efi/exit/ret0.om`. The assembler source the words were first produced from was not kept.

```
    1008: add x17, x28, #0x800, lsl #12
    100c: ldr x9, [x17, #192]
    1010: msr fpcr, x9
    1014: ldr x9, [x17]
    1018: mov sp, x9
    101c: ldp x19, x20, [x17, #32]
    1020: ldp x21, x22, [x17, #48]
    1024: ldp x23, x24, [x17, #64]
    1028: ldp x25, x26, [x17, #80]
    102c: ldp x29, x30, [x17, #112]
    1030: ldp d8, d9, [x17, #128]
    1034: ldp d10, d11, [x17, #144]
    1038: ldp d12, d13, [x17, #160]
    103c: ldp d14, d15, [x17, #176]
    1040: ldp x27, x28, [x17, #96]
    1044: ret 
    1048: stp x29, x30, [sp, #-48]!
    104c: stp x19, x20, [sp, #16]
    1050: stp x21, x22, [sp, #32]
    1054: sub sp, sp, #0x210
    1058: cbnz x0, 0x1118
    105c: mov x19, x1
    1060: mov x20, x2
    1064: mov x21, x2
    1068: mov x9, x1
    106c: mov x10, x2
    1070: cbz x10, 0x10a4
    1074: ldrb w11, [x9], #1
    1078: sub x10, x10, #0x1
    107c: cmp w11, #0x9
    1080: b.eq 0x1070  // b.none
    1084: cmp w11, #0xa
    1088: b.eq 0x1070  // b.none
    108c: cmp w11, #0xd
    1090: b.eq 0x1070  // b.none
    1094: sub w12, w11, #0x20
    1098: cmp w12, #0x5e
    109c: b.hi 0x1120  // b.pmore
    10a0: b 0x1070
    10a4: add x16, x28, #0x800, lsl #12
    10a8: ldr x16, [x16, #16]
    10ac: ldr x22, [x16, #64]
    10b0: cbz x22, 0x1128
    10b4: cbz x20, 0x1110
    10b8: mov x9, sp
    10bc: mov x10, #0x0                   
    10c0: cbz x20, 0x10f4
    10c4: cmp x10, #0xfd
    10c8: b.hi 0x10f4  // b.pmore
    10cc: ldrb w11, [x19], #1
    10d0: sub x20, x20, #0x1
    10d4: cmp w11, #0xa
    10d8: b.ne 0x10e8  // b.any
    10dc: mov w12, #0xd                   
    10e0: strh w12, [x9], #2
    10e4: add x10, x10, #0x1
    10e8: strh w11, [x9], #2
    10ec: add x10, x10, #0x1
    10f0: b 0x10c0
    10f4: strh wzr, [x9]
    10f8: mov x0, x22
    10fc: mov x1, sp
    1100: ldr x16, [x22, #8]
    1104: blr x16
    1108: tbnz x0, #63, 0x1128
    110c: b 0x10b4
    1110: mov x0, x21
    1114: b 0x1130
    1118: mov x0, #0x20                  
    111c: b 0x112c
    1120: mov x0, #0x2a                  
    1124: b 0x112c
    1128: mov x0, #0x2b                  
    112c: orr x0, x0, #0x8000000000000000
    1130: add sp, sp, #0x210
    1134: ldp x21, x22, [sp, #32]
    1138: ldp x19, x20, [sp, #16]
    113c: ldp x29, x30, [sp], #48
    1140: ret 
    1144: mov x9, x2
    1148: cbz x2, 0x11f8
    114c: cmp x2, #0x8
    1150: b.eq 0x1190  // b.none
    1154: cmp x2, #0x4
    1158: b.eq 0x11b4  // b.none
    115c: cmp x2, #0x2
    1160: b.eq 0x11d8  // b.none
    1164: cbnz x3, 0x117c
    1168: ldrb w10, [x0], #1
    116c: strb w10, [x1], #1
    1170: subs x2, x2, #0x1
    1174: b.ne 0x1168  // b.any
    1178: b 0x11f8
    117c: ldrb w10, [x1], #1
    1180: strb w10, [x0], #1
    1184: subs x2, x2, #0x1
    1188: b.ne 0x117c  // b.any
    118c: b 0x11f8
    1190: tst x0, #0x7
    1194: b.ne 0x1164  // b.any
    1198: cbnz x3, 0x11a8
    119c: ldr x10, [x0]
    11a0: str x10, [x1]
    11a4: b 0x11f8
    11a8: ldr x10, [x1]
    11ac: str x10, [x0]
    11b0: b 0x11f8
    11b4: tst x0, #0x3
    11b8: b.ne 0x1164  // b.any
    11bc: cbnz x3, 0x11cc
    11c0: ldr w10, [x0]
    11c4: str w10, [x1]
    11c8: b 0x11f8
    11cc: ldr w10, [x1]
    11d0: str w10, [x0]
    11d4: b 0x11f8
    11d8: tst x0, #0x1
    11dc: b.ne 0x1164  // b.any
    11e0: cbnz x3, 0x11f0
    11e4: ldrh w10, [x0]
    11e8: strh w10, [x1]
    11ec: b 0x11f8
    11f0: ldrh w10, [x1]
    11f4: strh w10, [x0]
    11f8: mov x0, x9
    11fc: ret 
```
