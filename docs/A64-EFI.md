# AArch64 UEFI backend (`target a64efi`)

Status (2026-11-12): **IMPLEMENTED; EXERCISED on one physical machine** (NVIDIA DGX Spark, American
Megatrends firmware, two recorded boots, see Evidence) and under virtualization (QEMU `virt` with KVM on a
Cortex-X925 host, EDK2 `QEMU_EFI.fd` 2024.02). One machine and one firmware are not a qualification.

The purpose is a program that runs on an Arm machine with nothing beneath it but the machine's own
firmware: no operating system and no driver. The first user is `ollm`, the Omega LLM of aien-train,
whose x86 UEFI image already boots an Intel iMac.
Omega LLM's `.om` sources now live in this repository at [`train/omega-llm/`](../train/omega-llm/) (unit
`ollm_a64efi` in `train/units.tsv`); the aien-train commits and paths cited below are the historical
record of the runs.

## Selection

The exact first line `target a64efi` selects a PE32+ EFI application (machine 0xAA64) for a whole
program. Function mode is error 25. Without the line nothing changes: the default AArch64 Linux
output is byte for byte what it was (see Evidence).

## What is different from the default AArch64 program

The instruction selection, register model and floats are the default backend's. Three things change.

1. **Addresses.** A Linux program is linked at fixed addresses (code at 0x400000, pools at
   0x10000000). A UEFI image is loaded wherever the firmware has memory, so `mataddr` makes every
   address relative: a global or stack-pool address is its offset plus X27, which the entry sets to
   the base of the image's `.bss`; a `text` address is `ADRP` + `ADD` from the instruction that
   needs it. Numbers are never relocated; only the address of a name is.
2. **Exit.** `ret` from `main`, `exit` and every trap branch to one return sequence at file offset
   520 (`aefx`). It restores X19..X30, D8..D15 and the firmware's stack and returns `main`'s value as
   the EFI_STATUS. A trap T returns `2^63 | (100 + T)`, as on x86efi.
3. **No host words.** Every Linux host word is error 25, `read` and `write` included, and so is a
   run-time pool (`global NAME T *`).

Image layout, as x86efi's: headers in the first 512 bytes, `.text` from file offset 512 at RVA
4096 (its first 8 bytes are an empty base relocation block), `.bss` after it, zero filled by the
loader. The first 16 KiB of `.bss` are private (saved registers, ImageHandle, SystemTable), the
rest of the first 8 MiB is the Omega stack (X28 is its floor), the globals follow.
`DllCharacteristics` has NX_COMPAT: code is never written and data never executed.

## Words

`efi OP ARG A OFF N` keeps x86efi's contract ([X86-EFI.md](X86-EFI.md)): OP a literal 0..14, A
writable `uchar` storage with `OFF + N` inside it (trap 3), result `ulong`, an error is
`2^63 | code`. On this target the operation itself is Omega code. The word compiles to a call of
the program's own `fn efirt op ulong arg ulong addr ulong n ulong to ulong`. A program that uses
`efi` without defining it is error 16 at the use; an `efirt` that does not take four `ulong` parameters
and give a `ulong` is error 9 at the use. It may be defined anywhere in the unit. `seed/a64efi/efirt.om` is that function: put it first in the
program. It implements

| OP | Operation | Status |
|---|---|---|
| 1 | key read (ConIn ReadKeyStroke) | EXERCISED (virtualized, no key pressed) |
| 2 | Boot Services Stall | EXERCISED (virtualized) |
| 10 | milliseconds since the first efi call (CNTVCT_EL0 / CNTFRQ_EL0) | EXERCISED (virtualized) |
| 12 | general file, x86efi's sub-operations and error codes | EXERCISED (virtualized) |
| 13 | console | EXERCISED (virtualized) |
| 14 | identity: FirmwareVendor, FirmwareRevision, SMBIOS as on x86efi; "leaf 0" is MIDR_EL1 | EXERCISED (virtualized); SMBIOS path NOT_RUN |
| 0, 3..9, 11 | info, Blt, time, entropy, network, pointer, boot file | not implemented: `2^63 | 3` |

`efirt.om` also defines `fn efiexit to void`. When a program has a function of that name, the return
sequence calls it once on every exit path, on a fresh stack; a function of that name with a
parameter or a result is error 9 (reported at the end of the unit, where the entry is emitted). `efirt.om` uses it to flush and close
a file left open, and then, when the boot volume holds `\OLLM\REBOOT.TXT`, to restart the machine
(ResetSystem, cold): a firmware that shows its menu after an application returns would otherwise
leave an unattended machine there.

The firmware words exist under `target a64efi` only; elsewhere the names are ordinary names. They
carry raw addresses, which no other Omega word does. That is deliberate: code with no operating
system under it has to call the firmware and, later, touch devices.

| Word | Meaning |
|---|---|
| `fwcall F A0 A1 A2 A3 A4 A5` | `BLR` F with A0..A5 in X0..X5 (AAPCS64), result X0. 64 KiB of the Omega stack must be free (trap 6) |
| `fwld ADDR W` | load W = 1, 2, 4 or 8 bytes at ADDR (any other W loads 1) |
| `fwst ADDR W V` | store the low W bytes of V at ADDR; result 0 |
| `fwsys K` | 0 ImageHandle, 1 SystemTable, 2 CNTVCT_EL0 (after ISB), 3 CNTFRQ_EL0, anything else MIDR_EL1 |
| `fwadr A OFF N` | the address of `A[OFF]`, with `OFF + N` inside A (trap 3); A may be a global |

All are `ulong` in and out. Ids: efi 178, fwcall 250, fwld 251, fwst 252, fwsys 253, fwadr 254. They
are recognised by `fn kwa`, where a value starts, and are not in the keyword chain `fn kw`. Under this
target the six names (`efi` and the five firmware words) are reserved: defining a variable, parameter,
global, constant, text or function with one of them is error 16, as for a keyword. Without the target
line they are ordinary names.

## Limits known today

- A wrong address given to `fwld`, `fwst` or `fwcall` is not caught: there is no memory protection
  beneath a UEFI application.
- `om2` may be the line after the target line (`om2` first is error 16 at line 2). The unit is then
  OM-2 in language, without the AArch64 OM-2 code improvements: no global is pinned in a register, as
  on the x86 targets. X18 is never touched, as UEFI asks: the OM-2 word `scrub` clears X19..X26 here and leaves X18
  (on the Linux target it clears X18..X26). `efirt.om` compiles under both profiles. (At `50485583`
  and before, the combination pinned globals in X18..X26, registers the entry never set, and `scrub`
  cleared X18.)
- The firmware's interrupts run on the Omega stack while the program runs.
- The OM-2 word `dit` sets the processor's data-independent-timing bit, and the return to the firmware
  does not put it back: a program that ends with `dit 1` in force returns with it set. The bit changes
  how long some instructions take, never their results; clear it (`dit 0`) before returning if the
  firmware should get the bit as it gave it.

## Evidence (2026-11-12)

The compiler is `seed/out/omc` of the commit that carries this file, rebuilt from the seed chain by
`seed/omega-from-seed.sh` (self-rebuild fixpoint).

| Check | Result |
|---|---|
| Default output | gate17 (300 programs byte-identical to the pinned reference compiler) and the other `seed/host/check.sh` gates |
| `tests/a64efi/run.sh` | tests/x86efi's float, refusals, file, exit and ident programs compiled for this target and booted under QEMU virt + EDK2, an OM-2 program (`om2.om`), the compile-time refusals of this target and the default-target control: every check PASS, 1 NOT_RUN (efi 11 is x86efi only) |
| `ollm` acceptance job, virtualized | aien-train `bb19fba9` `native/omegallm` with `efirt.om` first, the 11 jobs of `tests/omegallm/efi-job.txt`: OUT.TXT body EQUAL to the AArch64 Linux reference (`efi-check.sh`), TR.BIN, HE.BIN and S.CK byte-identical, `fsck.vfat -n` clean; with `\OLLM\REBOOT.TXT` the machine restarts at exit |
| `ollm` with the 15.8M-parameter checkpoint, virtualized | two 120-token samples from the rung-10 checkpoint and its BPE merges complete |
| **Physical machine** | `evidence/a64efi-dgx-spark-20261112/`: the same `ollm` image plus `pciid.om`, started once by the firmware of a DGX Spark from its EFI system partition (`BootNext`), no operating system loaded. `OLLM DONE 11`; OUT.TXT body EQUAL to the Linux reference; TR.BIN, HE.BIN and S.CK byte-identical; the image then restarted the machine. `pciid.om` read, through the firmware's PCI I/O protocol and with no NVIDIA software, the display device `10de:2e12` at 000f:01:00.0 and two identity registers of its BAR 0 (offset 0: `1bb000a1`, offset 0xA00: `1bba1000`). The image (sha256 `f2e31985…ecaba`) was built by an earlier candidate of this branch; the committed `seed/out/omc` builds the same bytes from the same source |

Corrected on 2026-11-12, after an independent review of the guide written for this target: the
first landing (`d7fbd565`) compiled `read` and `write` under this target to a Linux system call
instead of refusing them, silently ignored a function the program named like one of the six words,
and did not check the shape of `efirt` (its parameter count, result and parameter types) or of
`efiexit`. The compiler of the commit that carries this sentence refuses
all of them (errors 25, 16 and 9; cases in `tests/a64efi/run.sh`). No program built so far used
them: the source of the image that ran on the DGX Spark (aien-train `bb19fba9` with `efirt.om` and
`evidence/a64efi-dgx-spark-20261112/pciid.om`) compiles to the same sha256, `f2e31985…ecaba`, with
this compiler.

A key press on the physical machine: EXERCISED once (2026-11-12, one session, two typed lines at
the DGX Spark's own keyboard, both answers equal to the Linux build's; aien-train
`evidence/OMEGALLM/a64efi/dgx-spark-ask/RESULT.txt` at main 7b4445ecaa2719cea458d591e4a90d9310bbdc17).

NOT_RUN: any other machine or firmware; the 15.8M-parameter checkpoint on the physical machine (it
does not fit on that machine's 298 MiB EFI system partition); efi 14 SMBIOS on physical
firmware beyond the banner line; any device access other than the two register reads above.
