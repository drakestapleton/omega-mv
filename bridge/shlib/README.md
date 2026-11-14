# bridge/shlib: shared libraries from Omega alone

`shlib.om` writes an AArch64 Linux shared object (ELF64 `ET_DYN`) from two inputs: the native
object `seed/out/omc` emits for an OM-2 unit in object mode (`OMOBJ001`, `spec/omegese-modules.md`)
and a table naming the soname and the exports. No C compiler, assembler or linker takes part. The
same program writes a probe executable that the system's dynamic loader runs against the library.

```
seed/out/omc < bridge/shlib/shlib.om > shlib
{ printf 'object\n'; cat bridge/shlib/nvml.om; } | seed/out/omc > nvml.obj
./shlib lib bridge/shlib/nvml.tsv nvml.obj libnvidia-ml.so.1
./shlib call bridge/shlib/nvml.tsv nvprobe && ./nvprobe; echo $?
```

The table format, the refusals and the exit codes are at the top of `shlib.om`.

## What the library holds

- `.hash` (SysV), `.dynsym` (one global function per export row), `.dynstr` (soname first),
  `.text` and `.dynamic` (`DT_HASH`, `DT_STRTAB`, `DT_SYMTAB`, `DT_STRSZ`, `DT_SYMENT`, `DT_SONAME`).
  The code is position independent, so the library needs no relocations.
- One wrapper per export turns a C call (AAPCS64) into an omc function call. It saves x19..x30
  and d8..d15. It builds the per-call context omc expects in x7, where entry 16 is a trap entry,
  and sign- or zero-extends narrow integer arguments, because omc assumes they are already
  extended. A trap inside Omega code (for example a division by zero) returns the row's TRAP
  value to the C caller with every saved register restored.
- omc code runs on the caller's stack. The generator settles each function's stack need from the
  object's call records, as the module linker does (`need(f) = max(local(f), cost(call) +
  need(callee))`), and refuses a cycle or a need above the linker's 8 MiB. When an export's body
  needs stack, its wrapper first reads one word in each 4 KiB page down past that need, top page
  first. A caller whose stack is too small then faults on its guard page before the body runs,
  instead of the body writing past the guard into other memory.
- The object's code is copied unchanged, at a 16-byte boundary as in the object.

## Limits

- The check that refuses runtime entries other than the trap entry reads the code for
  `LDR Xt, [X7, #imm]` in its unsigned-offset form, the only form omc emits for those loads today.
  It is a pattern check, not a proof. A future omc that reached the context another way would get
  past it, so the lasting fix is for omc to record runtime-entry use in the object's metadata.
- The wrappers have no frame record and the library has no `.eh_frame`, so debuggers and
  `backtrace()` cannot unwind through a wrapper.
- The probe compares the low 32 bits of each result. Its mismatch status is 1 + the call index,
  capped at 100 so it never collides with the loader's 127 or the register check's 250.

## Gate

`tests/gates/run.sh shlib` (manifest `tests/gates/omega-shlib.gate`, program `gate.om`, in Omega)
has 12 checks:

1. It builds both units in object mode.
2. It builds both libraries and both probes.
3. It runs each probe, which loads its library through the system's dynamic loader. The
   `test.tsv` probe makes 13 calls: constants, int arguments with dirty upper halves, a trapping
   division followed by another call, a pointer write read back by a later call, a uint with a
   dirty upper half, and two bodies that need 8 KiB and 16 KiB of stack (one through a private
   call). The `nvml.tsv` probe calls all 11 NVML exports. Each probe also checks that x19..x27 and
   sp come back unchanged.
4. It runs `/usr/bin/readelf -W -S --dyn-syms` on each library. readelf reads the symbols through
   the section headers, which the loader never looks at; it must exit 0, print no warning, and
   list every export of the table. readelf (GNU Binutils 2.42 here) is a read-only verification
   oracle, not part of the build.
5. It requires a second build to have identical bytes.

The gate also runs 9 controls. Each must be caught with its exact exit status and, where one is
given, with that text in the failing program's error output:

| Control | Change | Required |
|---|---|---|
| row | a malformed row in the table | 1, `malformed number` |
| export | an export removed from the library while the probe still needs it | 127, `undefined symbol: omega_shlib_div` |
| hash | every hash bucket zeroed | 127, `undefined symbol: ` |
| expect | a wrong expected value | 1 |
| stack | the wrapper's stack restore off by 16 bytes | 250 |
| extend | the wrappers' sign extensions removed (omc's int add then traps on call 1) | 2 |
| uextend | the wrappers' zero extensions removed | 10 |
| restore | the shared return reloads x19 and x20 from the wrong slot | 250 |
| runtime | the object's trap-entry load turned into a load of another runtime entry | 1, `runtime entry` |

## NVML status

`nvml.om` declares the 11 functions of CUDApp's `compat/nvml/libnvidia-ml.map` with its
`nvml.h` C signatures. A pointer to a struct or buffer is a sized `edit`, which takes one
register; `nvmlDevice_t` is a `ulong`. The bodies are stubs: every query answers
`NVML_ERROR_NOT_SUPPORTED` (3) and writes nothing, and `nvmlErrorString` answers NULL (also its
trap value). A caller that prints that string will crash, so this library proves the shape and the
calling convention only. It must not be installed in place of a real `libnvidia-ml.so.1` until the
items below exist.

The real bodies in `gpu/nvidia/native/nvml/api.om` need things omc's callable units do not yet
offer:

1. **State that lasts between calls.** `api.om` keeps about 85 KB of process state (`NvS`, `NvB`,
   `NvR`, `NvT`, `NvO` and the device pool) across calls. Neither om2 function mode nor object mode
   accepts a `global` (error 9 in both). This is a compiler change: a writable data section in
   objects plus a relocation that lets function code address it. A second option needs no compiler
   change: the generator reserves the state in the library's RW segment and the wrapper passes it as
   leading `edit` arguments. That option runs into the 6-slot parameter limit for the larger calls.
2. **Device and file calls in object mode.** `fopen` and `devctl` compile in om2 function mode but
   are error 9 in object mode. `spec/omegese-modules.md` excludes "host effects" from objects, and
   `seed/omc/omc.om` (`hostval`, d2site 174) refuses every host word when `objmode` is set. The
   compiler change is to accept the om2 function-unit host subset in object mode. The generator
   already refuses code that loads any runtime entry other than the trap entry, so it would also
   need the entries those words use.
3. **Imports.** `api.om` calls `omega_nvml_step` and the `omega2_nvrm_*` transport as separate C
   symbols. The generator refuses imports; they would need a `DT_NEEDED` entry and GOT entries in
   the library, or all units compiled into one object.
4. **A lock and a C string.** `api.om` assumes a process mutex, and `nvmlErrorString` returns a
   pointer into library data. Both depend on item 1.
5. **Hardware.** Real bodies issue NVIDIA RM ioctls on `/dev/nvidiactl`, and checking them needs
   the GPU.
