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
- The object's code is copied unchanged.

## Gate

`tests/gates/run.sh shlib` (manifest `tests/gates/omega-shlib.gate`, program `gate.om`, in Omega)
has 10 checks:

1. It builds both units in object mode.
2. It builds both libraries and both probes.
3. It runs each probe, which loads its library through the system's dynamic loader. The
   `test.tsv` probe makes 10 calls: constants, int arguments with dirty upper halves, a trapping
   division followed by another call, and a pointer write read back by a later call. The
   `nvml.tsv` probe calls all 11 NVML exports. Each probe also checks that x19..x27 and sp come
   back unchanged.
4. It requires a second build to have identical bytes.

The gate also runs 5 controls, and each must be caught with its exact exit status:

| Control | Change | Required exit status |
|---|---|---|
| row | a malformed row in the table | 1 |
| export | an export removed from the library while the probe still needs it | 127 |
| hash | every hash bucket zeroed | 127 |
| expect | a wrong expected value | 1 |
| stack | the wrapper's stack restore off by 16 bytes | 250 |

## NVML status

`nvml.om` declares the 11 functions of CUDApp's `compat/nvml/libnvidia-ml.map` with its
`nvml.h` C signatures. A pointer to a struct or buffer is a sized `edit`, which takes one
register; `nvmlDevice_t` is a `ulong`. The bodies are stubs: every query answers
`NVML_ERROR_NOT_SUPPORTED` (3) and writes nothing, and `nvmlErrorString` answers NULL. A C program
compiled against CUDApp's `nvml.h` links with `-lnvidia-ml` and runs against this library.

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
