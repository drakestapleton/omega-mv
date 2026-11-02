# x86-64 UEFI backend (`target x86efi`)

Status: **DRAFT; IMPLEMENTED and EXERCISED under emulation (QEMU q35 + OVMF)**, 2026-11-01.
Draft aien-dev/aien-train#53 at `e08443c3` records one physical iMac run of an image built with this omc
(`b4f45121`, `evidence/OMEGALLM/imac/`): EXERCISED on physical hardware (one machine).
This repository has no physical-firmware gate. The compiler was built on main `ba5559d9`.
This branch also contains main `f9a9a40b` (#995). That merge did not change `seed/omc/omc.om` or `seed/out/omc`.
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

`r = efi OP ARG A OFF N`: OP is a literal 0..13, ARG a ulong, A a uchar array with `OFF+N <= len A`
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
| 11 | boot-file read/write, fixed path `\EFI\BOOT\BOOTX64.EFI` (Allen fork contract, #981) | shipped, NOT_RUN |
| 12 | general file, below | EXERCISED (EMULATED) |
| 13 | console, below | EXERCISED (EMULATED) |

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

## GUIDs

GOP, SNP, RNG, Simple Pointer, Absolute Pointer, Simple File System, LoadedImage and FileInfo are
embedded as packed constants (`xg` in `omc.om`); all eight were checked against the UEFI
specification values and the Allen fork. Exercised: Simple File System, LoadedImage and FileInfo
(efi 12). GOP, SNP, RNG and the pointer protocols are NOT_RUN in this branch.

## Evidence (2026-11-01, omc sha256 `b4f45121f6c6d5d8a6ed0f5c4f3934b7cc4bec369bfa89523699bd33928f9b55`)

All runs are emulated: OVMF `OVMF_CODE_4M` on QEMU q35, the image as `\EFI\BOOT\BOOTX64.EFI` on a
16 MiB FAT16 usb-storage disk, serial console captured to a file. The programs, their expected
output and the runner are in `tests/x86efi/` (`sh tests/x86efi/run.sh [OMC]`; it prints NOT_RUN for
each check it cannot run and exits 77 when nothing could run).

| Gate | Result |
|---|---|
| AArch64 as stored | 1305 tracked `.om` files, `tools/x86efi/corpus_diff.sh` asis, omc `b4f45121` against main's omc `be8c5130`: 663 identical, 638 same-refusal, 4 differ. The 4 are `tests/x86efi/exit/e1.om`, `exit/e2.om`, `file/t1.om` and `refusals/g4.om`: `b4f45121` accepts them and `be8c5130` refuses error 25. `tests/x86efi/float/efi-pre.om` is error 25 from both. TSV: `evidence/x86efi/corpus_b4f45121_vs_be8c5130.tsv`. Run on x86_64 under qemu-user. A native AArch64 run is NOT_RUN |
| x86linux | the same 1305 files with mode x86linux (a `target x86linux` line is prepended only when the file has no target line): 647 identical, 654 same-refusal, 4 differ. Those 4 are the same `target x86efi` programs. TSV: `evidence/x86efi/corpus_b4f45121_vs_be8c5130_x86linux.tsv` |
| Float parity (`float/`) | one program printing 41 bit patterns (add, sub, mul, div, sqrt, exp, log, int/float conversions, saturating casts, NaN, f32) gives identical output as x86efi, x86linux (qemu-x86_64) and AArch64; floats survive 40+ firmware calls. An MXCSR round-toward-zero mutant fails it |
| efi 12 refusals (`refusals/`) | 21 results (codes above, path lengths 0/255/256, busy, nothing open, read-only write, bad volume) match; OFF+N past the array traps 3 |
| efi 12 round trip (`file/`) | create, write, close, reopen, positioned write, read back: results and the bytes on disk match. A mutant with the Read/Write protocol offsets 32/40 swapped fails it |
| Exit flush (`exit/`) | a file written with sub 3 and left open is on disk with all 10 bytes after `return` and after trap 3. The previous omc (`d0f756d9…`, no exit cleanup) leaves a 0-byte file in both cases |
| GUIDs | values checked; see above |

NOT_RUN in this repository's gates: efi ops 0..11, the ConOut NULL refusal, GOP Blt, network,
entropy, pointer, native x86 execution of the seed. The iMac run cited above is
EXERCISED on physical hardware (one machine).

## Limits

The compiler uses 510 of the om4 cap of 512 functions (`seed/omc/size-history.tsv`). Allen's stack (#977, #983, #980, #981) carries
an older x86efi on a different base; its register slots and live-slot saves are not ported here.
