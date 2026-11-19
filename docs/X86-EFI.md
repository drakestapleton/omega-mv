# x86-64 UEFI backend (`target x86efi`)

Status (2026-11-04): **IMPLEMENTED; EXERCISED under emulation (QEMU q35 + OVMF)**; not QUALIFIED on hardware.
Draft aien-dev/aien-train#53 at `e08443c3` records one physical iMac run of an image built with this omc
(`b4f45121`, `evidence/OMEGALLM/imac/`): EXERCISED on physical hardware (one machine).
Omega LLM's `.om` sources now live in this repository at [`train/omega-llm/`](../train/omega-llm/) (unit `ollm_x86efi`);
the aien-train references here are the historical record of that run.
This repository has no physical-firmware gate. The compiler was built on main `ba5559d9`.
The x86efi branch (PR #1015) also merged main `f9a9a40b` (#995) and main `19b8340d` (#996). Neither merge changed `seed/omc/omc.om` or `seed/out/omc`.
Implementation: `seed/omc/omc.om` (functions `xp` through `xf12`, plus hooks in `kw`, the value
parser, the driver, `xleave`, `xfinish`, `xlead` and `xeof`). It reuses the x86linux instruction
selection, register model and SSE2 float code of [X86-LINUX.md](X86-LINUX.md); only the image
format, entry/exit and the `efi` word are new.

## Selection

The exact first line `target x86efi` selects a PE32+ EFI application for a whole program. Without
it the AArch64 default is unchanged; `target x86linux` is unchanged. `efi` is a keyword (id 178)
only under `target x86efi`; elsewhere it remains an ordinary name (gate18 checks the scoped entry).

## Entry, exit and traps

The entry saves RBX, RBP, RSI, RDI, R12-R15, the firmware RSP, MXCSR and XMM6-XMM15 (the UEFI x64
callee-saved set) in a private area, loads MXCSR 0x1F80 (all exceptions masked, round to nearest,
as on x86 Linux), and runs the program on its own stack. Firmware calls reserve 64 KiB of that
stack (trap 6 when it is short) and align RSP to 16 bytes with the 32-byte home area of the
Microsoft x64 convention. Floats stay in their frame slots across firmware calls.
The exit (shared by return, `exit` and every trap) first flushes and closes an efi 12 file that is
still open (Flush when it was opened writable, then Close on the file and its volume root, then the
slot is cleared), so data written with sub 3 reaches the disk without sub 4. It then restores every
saved register and returns `main`'s value as the EFI_STATUS. A trap T returns
`2^63 | (100 + T)`: OVMF reports trap 3 as `failed to start ... : 00000067`.

Startup cost: when CPUID reports an invariant TSC (leaf 1 TSC, leaf 0x80000007 EDX bit 8) the entry
calibrates it once with Boot Services `Stall(100000)`, so every image pays a 100 ms stall before
`main`, whether or not it reads time. Without an invariant TSC, op 10 calibrates on first use.

## The `efi` word

`r = efi OP ARG A OFF N`: OP is a literal 0..14, ARG a ulong, A a uchar array with `OFF+N <= len A`
(else trap 3, the same check as `read`/`write`). The result is a ulong; bit 63 set means an error
whose code is in the low bits.

| OP | Operation (from the code) | Status |
|---|---|---|
| 0 | info: 64-byte record (version, GOP/net/RNG/pointer flags, mode, MAC, state) | shipped, NOT_RUN |
| 1 | key read (ConIn ReadKeyStroke) | shipped, NOT_RUN |
| 2 | Boot Services Stall | shipped, NOT_RUN |
| 3 | GOP Blt | shipped, NOT_RUN |
| 4 | Runtime Services GetTime | shipped, NOT_RUN |
| 5 | entropy (RNG protocol, else RDRAND) | shipped, NOT_RUN |
| 6, 7 | network receive, transmit (SNP) | shipped, NOT_RUN |
| 8 | network start (SNP) | shipped, NOT_RUN |
| 9 | pointer state | shipped, NOT_RUN |
| 10 | milliseconds (TSC) | shipped, NOT_RUN |
| 11 | boot-file read/write, fixed path `\EFI\BOOT\BOOTX64.EFI` (Allen fork contract, #981) | EXERCISED (EMULATED): `tests/x86efi/file11` |
| 12 | general file, below | EXERCISED (EMULATED) |
| 13 | console, below | EXERCISED (EMULATED) |
| 14 | machine identity, below | EXERCISED (EMULATED) |

### efi 13 console

Writes `A[OFF..OFF+N)` to ConOut. Accepted bytes are 9, 10, 13 and 32..126 (else 42); LF becomes
CRLF. ARG must be 0 (else 32). When ConOut (SystemTable+64) is NULL, as on some headless firmware,
the result is 43 and no call is made; 43 is also the result when OutputString fails. The NULL case
is NOT_RUN: OVMF always installs ConOut and a program cannot clear it.

### efi 12 general file

ARG bits 0-7 sub, 8-15 volume (255 = the volume this image was loaded from, else the index among
Simple File System handles), 16-63 the byte position for subs 2 and 3. Paths are `A[OFF..OFF+N)`:
1..255 bytes, the first `\`, each 32..126.

| Sub | Operation | Result |
|---|---|---|
| 0 | open read-only | FileSize |
| 1 | create empty, replacing an existing file (Delete, then Create) | 0 |
| 2 | read up to N bytes at the position into A | bytes read, 0 at end |
| 3 | write N bytes at the position (needs sub 1 or 5) | N |
| 4 | flush (when writable) and close | 0 |
| 5 | open an existing file read/write, no truncation | FileSize |

One file at a time. Error codes: 32 bad sub, 33 bad path, 34 busy (a file is open), 35 nothing
open, 36 open/create/delete failed, 37 read, 38 write or not writable, 39 short write, 40 flush,
41 GetInfo; volume errors 16..22 as efi 11 (19 = no such volume).

Slot state after an error:
- Refusals 32, 33, 34, 35 and 38 (not writable) leave the slot exactly as it was; the caller still
  owns any open file and must close it with sub 4.
- The firmware errors of subs 2 and 3 (37, 38, 39) also leave the file open.
- Volume errors (16..22) happen before anything is stored and leave the slot empty.
- 36 and 41 close the file and its root; the slot is empty.
- Sub 4 with a file open closes the file and the root and empties the slot on every path; it
  returns 40 when Flush failed. With nothing open it is refusal 35.
- A file still open when the program returns, exits or traps is flushed and closed by the exit.

### efi 14 identity

Read-only facts about the machine, selected by ARG; the result is the number of bytes written to
`A[OFF..)` unless noted.

| ARG | Result |
|---|---|
| `L << 16` (bits 0..15 zero) | CPUID leaf L (L < 2^32, ECX 0): EAX, EBX, ECX, EDX as 16 little-endian bytes; N < 16 is error 5; result 16 |
| 1 | SystemTable FirmwareVendor (SystemTable+24): its UCS-2 code units up to the NUL, whole units only, at most N bytes; 0 when the pointer is NULL |
| 2 | SystemTable FirmwareRevision (SystemTable+32), the u32 itself; nothing is written |
| `3 + (P << 16)` | the SMBIOS structure table from byte P: min(N, length − P) bytes, 0 when P ≥ length. The table is found in the ConfigurationTable through the SMBIOS 3 GUID (anchor `_SM3_`, of which the code compares the first 4 bytes `_SM3`; 64-bit address at +16, maximum size at +12) when present, else the SMBIOS GUID (anchor `_SM_`, 32-bit address at +24, length at +22); neither, a wrong anchor or a zero address is error 44. On SMBIOS 3 the length is the entry point's maximum size, which the specification allows to exceed the real table, so a read near the end can return bytes past the last structure (identity-mapped firmware memory under Boot Services); callers stop at the type 127 end-of-table structure |
| anything else | error 32 |

The structures are left to the program. A program that must not reveal the machine reads only the
fields it prints; `tests/x86efi/ident/id.om` reads type 1 Manufacturer, Product Name and Version and
never the serial number (offset 7) or the UUID (8..23). Error 44 is NOT_RUN: OVMF always installs
SMBIOS.

## GUIDs

GOP, SNP, RNG, Simple Pointer, Absolute Pointer, Simple File System, LoadedImage and FileInfo are
embedded as packed constants (`xg` in `omc.om`); all eight were checked against the UEFI
specification values and the Allen fork. Exercised: Simple File System, LoadedImage and FileInfo
(efi 12). GOP, SNP, RNG and the pointer protocols are NOT_RUN in this repository.

## Evidence (2026-11-01, omc sha256 `b4f45121f6c6d5d8a6ed0f5c4f3934b7cc4bec369bfa89523699bd33928f9b55` unless a row names another omc)

All runs are emulated: OVMF `OVMF_CODE_4M` on QEMU q35, the image as `\EFI\BOOT\BOOTX64.EFI` on a
16 MiB FAT16 usb-storage disk, serial console captured to a file. The programs, their expected
output and the runner are in `tests/x86efi/` (`sh tests/x86efi/run.sh [OMC]`; it prints NOT_RUN for
each check it cannot run and exits 77 when nothing could run).

| Gate | Result |
|---|---|
| AArch64 as stored | 1305 tracked `.om` files, `tools/x86efi/corpus_diff.sh` asis, omc `b4f45121` against main's omc `be8c5130`: 663 identical, 638 same-refusal, 4 differ. The 4 are `tests/x86efi/exit/e1.om`, `exit/e2.om`, `file/t1.om` and `refusals/g4.om`: `b4f45121` accepts them and `be8c5130` refuses error 25. `tests/x86efi/float/efi-pre.om` is error 25 from both. TSV: `evidence/x86efi/corpus_b4f45121_vs_be8c5130.tsv`, first recorded on x86_64 under qemu-user. On 2026-11-04 a native AArch64 run (DGX Spark, Linux aarch64, both compilers native) reproduced it byte for byte (TSV sha256 `e07c912bb0c8c05375190ed6b2e7518d7bac4441ca224490c07809f94fb9f78e`), once in the PR review and once again after the corpus_diff.sh fixes |
| x86linux | the same 1305 files with mode x86linux (a `target x86linux` line is prepended only when the file has no target line): 647 identical, 654 same-refusal, 4 differ. Those 4 are the same `target x86efi` programs. TSV: `evidence/x86efi/corpus_b4f45121_vs_be8c5130_x86linux.tsv`; the 2026-11-04 native AArch64 runs reproduced it byte for byte (sha256 `04604a9d3cbf037d08c4ae431159b880e7a855564e54db24504e9e18a1cdac35`) |
| Float parity (`float/`) | one program printing 41 bit patterns (add, sub, mul, div, sqrt, exp, log, int/float conversions, saturating casts, NaN, f32) gives identical output as x86efi, x86linux (qemu-x86_64) and AArch64; floats survive 40+ firmware calls. An MXCSR round-toward-zero mutant fails it. The AArch64 leg ran natively on 2026-11-04 (DGX Spark, `PASS float aarch64: same lines as x86efi` from `tests/x86efi/run.sh`) |
| efi 12 refusals (`refusals/`) | 21 results (codes above, path lengths 0/255/256, busy, nothing open, read-only write, bad volume) match; OFF+N past the array traps 3 |
| efi 12 round trip (`file/`) | create, write, close, reopen, positioned write, read back: results and the bytes on disk match. A mutant with the Read/Write protocol offsets 32/40 swapped fails it |
| Exit flush (`exit/`) | a file written with sub 3 and left open is on disk with all 10 bytes after `return` and after trap 3. The previous omc (`d0f756d9…`, no exit cleanup) leaves a 0-byte file in both cases |
| GUIDs | values checked; see above |
| Machine identity (`ident/`, omc sha256 `3ad9f10f64309e7acf8a725082b28e23a2a4aeb07e98322fb4dc0fcd8fc93194`) | under `-smbios type=1,manufacturer=OmegaTest,product=IdentBox,version=7.1,serial=…,uuid=…` and both `smbios-entry-point-type=64` and `=32`: brand `QEMU TCG CPU version 2.5+`, FirmwareVendor `Ubuntu distribution of EDK II`, `sm=OmegaTest/IdentBox/7.1`, a positioned read equal to the table bytes, 8 results (N 0, P past the end, CPUID 16, N 15 → 5, L ≥ 2^32 and three bad subs → 32) match `expected.txt`; FirmwareRevision is 8 hex digits (`00010000` on Ubuntu OVMF); the serial and UUID are not in the output. Negative control: manufacturer `OtherMaker` changes the output. Manual mutants (not in the runner): a wrong SMBIOS 2 GUID gives `sm=-` under the 32-bit entry point and is still correct under the 64-bit one, so the SMBIOS 3 path is the one used there; a wrong SMBIOS 3 GUID still gives the right strings through the SMBIOS 2 fallback, which OVMF also publishes under the 64-bit setting. Every tracked `.om` file (1297), as is and with `target x86linux`, gives the same bytes and status from this omc as from `b4f45121` (2594 compiles) |

NOT_RUN in this repository's gates: efi ops 0..11, the ConOut NULL refusal, GOP Blt, network,
entropy, pointer, native x86 execution of the seed. The iMac run cited above is
EXERCISED on physical hardware (one machine).

## Limits

The compiler uses 511 of the om4 cap of 512 functions (`seed/omc/size-history.tsv`). Allen's stack (#977, #983, #980, #981) carries
an older x86efi on a different base; its register slots and live-slot saves are not ported here.
