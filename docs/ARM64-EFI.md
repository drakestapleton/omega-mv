# ARM64 EFI application target

`target aarch64efi` selects a whole-program PE32+ EFI application (COFF
machine `0xaa64`, subsystem 10). It reuses the AArch64 instruction generator.
This is an application under UEFI boot services, not a standalone kernel.
Linux host words and bare units are refused with compiler error 25. No Linux
syscall or C runtime supplies the firmware operations.

The entry adapter preserves x19..x30, d8..d15, FPCR and FPSR, installs IEEE
round-to-nearest floating-point state, disables the firmware watchdog, and
uses an 8 MiB private stack with a 16 KiB reserved floor. Image-relative
ADRP/ADD addresses are relocated; numeric constants are not. Return, explicit
exit and traps restore the firmware register/stack state and release owned
file, timer-event and network resources. Trap T returns EFI_STATUS
`2^63 | (100 + T)`.

## Firmware interface

`r = efi OP ARG A OFF N` checks the buffer range before calling firmware.
The result is `ulong`; bit 63 indicates an error. OP must be a literal.

| OP | ARM64 behavior |
|---|---|
| 0 | 64-byte boot/network information, including the active SNP MAC |
| 1 | Console key input |
| 2 | Firmware Stall, retained for callers that explicitly need it |
| 5 | Firmware RNG protocol |
| 6 | SNP receive into a bounded caller buffer with an eight-byte length prefix |
| 7 | SNP transmit through a bounded private copy, retained until firmware returns ownership |
| 8 | Enumerate, validate and exclusively open an Ethernet SNP candidate |
| 10 | Monotonic firmware milliseconds, eight-byte little-endian result |
| 12 | Read-only files on the boot volume; write/create modes refused |
| 13 | Firmware text console output |
| 15 | Event wait, ARG milliseconds in 0..1000, using a firmware timer event |

Other declared operations return an explicit unsupported error. OP 15 caches
its timer event and optional Timer Architectural Protocol. A nonzero wait
adjusts the firmware tick to at most 100 ms, retaining the original period
for restoration on image exit. It calls WaitForEvent rather than a Stall
loop. Network receive is pumped by the caller; the wait does not register SNP
WaitForPacket, avoiding duplicate polling by firmware event callbacks. Firmware that polls SNP still requires bounded wakeups; this interface
does not promise hardware packet interrupts or an idle-CPU result.

SNP selection checks Ethernet address size, interface type and receive filter
support. It bounds enumeration, frees the handle list, cleans up a rejected
candidate, and never closes another application's protocol ownership.

## Ordered vector kernels

Both new statements require binary64 arrays and AArch64 program mode,
including `aarch64efi`. x86 targets refuse them with error 25; IR mode refuses
with error 9. Read-only destinations are error 20. Operands are evaluated and
ranges checked before stores. Frozen/unknown-initialization arrays are
conservatively refused as for other bulk operations.

- `vmadd2 D DI W WI A` computes two independent lanes
  `D[DI+j] = D[DI+j] + A * W[WI+j]`. DI and WI are `ulong`, A is `f64`.
  Both source lanes and destination lanes are read before stores, including
  when they alias. Separate FMUL and FADD preserve binary64 rounding.
- `vdot4 D X XO W WO ROWS STRIDE` computes four independent dot products
  into D[0..3]. Each starts at positive zero and visits rows in ascending
  order, multiplying X[XO+r] by W[WO+r*STRIDE+j]. All integer operands are
  `ulong`. Nonzero rows require STRIDE >= 4. ROWS is at most 999999 (trap 4);
  invalid array ranges trap 3. Zero rows write four positive zeros and do
  not read X or W. All four results are stored after all reads, so aliases
  preserve the original input. There is no fused arithmetic or reassociation.

`seed/net/http-core.om` contains HTTP and SSE protocol logic. The transport
contract is implemented by `http-linux.om`; `http.om` remains their exact
concatenation for existing Linux consumers. An EFI consumer supplies the
same transport functions using its network implementation.

## Qualification

`tests/aarch64efi/run.py` checks the compiler pin before creating output and
requires an ARM64 Mac with QEMU HVF. It checks ARM PE headers, ABI-sensitive
floating-point execution, file access, repeated event waits, bounds and
refusals, 41 scalar floating-point outputs, ordered vector corner cases,
and deliberately incorrect arithmetic instructions. Each run uses a fresh
output directory and retains compile diagnostics and serial logs.

The seeded compiler and host suites run separately on ARM64 Linux. Host
results do not qualify physical ARM firmware, and HVF execution does not
qualify a standalone kernel. Application performance, idle CPU and browser
behavior belong to the Aienux consumer's separate acceptance measurements.
