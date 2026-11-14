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
  and d8..d15. It builds the per-call context omc expects in x7, whose byte offset 16
  (`[x7, #16]`) holds the trap entry,
  and sign- or zero-extends narrow integer arguments, because omc assumes they are already
  extended. A trap inside Omega code (for example a division by zero) returns the row's TRAP
  value to the C caller with every saved register restored.
- omc code runs on the caller's stack. The generator settles each function's stack need from the
  object's call records, as the module linker does (`need(f) = max(local(f), cost(call) +
  need(callee))`), and refuses a cycle (every call costs at least its save area, so a cycle keeps
  growing and is still changing in the last pass) or a need larger than the 2^48-byte user address
  space of AArch64 Linux. When an export's body needs stack, its wrapper first reads one word in
  each 4 KiB page below its own lowest store (`[sp, #16]`), down past that need, top page first.
  No two touches are more than 4096 bytes apart, so a caller whose stack is too small faults on a
  4 KiB guard page before the body runs, instead of the body writing past the guard into other
  memory. That assumes a guard of at least 4 KiB directly below the stack (a thread created with
  guard size 0 has none) and a caller whose own stack pointer is inside mapped stack. The gate
  checks the probe's words and, with a mutant generator that drops the call cost, fails. The fault
  itself is shown outside the tree (a C caller on an 8 KiB thread stack); no receipt of that is
  kept in this repository.
- The object's code is copied unchanged, at a 16-byte boundary as in the object.
- Before linking, the generator checks the object's metadata as spec/omegese-modules.md asks:
  the export count against the header, each function's flags, address (inside the code,
  4-aligned, increasing), result and parameter records and name padding, unique names, each
  export's entry B slot pointing at its own function, and each call record (a nonzero cost, a BL
  inside its source function that branches to the record's destination). Every BL in the code
  must have exactly one call record. An object that imports a function is refused.

## Limits

- The x7 check refuses every instruction of the load/store group whose base register is x7,
  except the trap-entry load `LDR Xt, [X7, #16]`, because the wrapper's saved registers sit in the
  frame x7 points at. It reads instruction words, so it is a pattern check, not a proof: the
  lasting fix is for omc to record runtime-entry use in the object's metadata.
- The wrappers do not save x18. Linux leaves x18 to the caller, but a caller built with a shadow
  call stack keeps it in x18, and omc code may change it.
- A C caller must hold up the side of each parameter's declaration: a sized `edit` or `view` is a
  pointer to at least that many elements, which omc trusts without a check, and a `fresh`
  parameter must not overlap another argument.
- The wrappers have no frame record and the library has no `.eh_frame`, so debuggers and
  `backtrace()` cannot unwind through a wrapper.
- The probe compares the low 32 bits of each result. Its mismatch status is 1 + the call index,
  capped at 100 so it never collides with the loader's 127 or the register check's 250.
- The module linker refuses a need above 8 MiB (its program's own stack). A library runs on its
  caller's stack, which may be larger, so the generator bounds the need only by the address space.
- Each object refusal names the rule that fired (address, entry slot, call record, its
  destination, BL coverage, runtime entry, x7 use); the remaining malformations share one message.
- The library is position independent only because omc refuses `text` and `global` in object
  mode today; in program mode it builds their addresses as absolute constants. If object mode
  ever allows them, the generator must refuse such constants or relocate them.
- The trap path returns without a matching BL and RET pair, and the library carries no GCS or
  BTI property note. On a system that enforces Guarded Control Stack the trap path would fault.

## Gate

`tests/gates/run.sh shlib` (manifest `tests/gates/omega-shlib.gate`, program `gate.om`, in Omega)
runs these checks; `gate.om`'s header lists each with its exact status:

1. It builds both units in object mode.
2. It builds both libraries and both probes.
3. It runs each probe, which loads its library through the system's dynamic loader. The
   `test.tsv` probe calls constants, int arguments with dirty upper halves, a trapping division
   followed by another call, a pointer write read back by a later call, a uint with a dirty upper
   half, two bodies that need 8 KiB and 16 KiB of stack (one through a private call), a uchar,
   ushort, byte and short each under dirty upper bits, a division inside a private callee that
   traps, and a body whose need sits one call cost past a 4 KiB page. The `nvml.tsv` probe calls
   all 11 NVML exports. Each probe also sets x19..x27, x29 and d8..d15 and checks that they and sp
   come back unchanged.
4. It runs `/usr/bin/readelf -W -S -d --dyn-syms` on each library. readelf reads the symbols
   through the section headers, which the loader never looks at; it must exit 0, print no
   warning, show the table's soname and list every export of the table (at least one) as a
   `FUNC GLOBAL DEFAULT` symbol line. readelf is a read-only verification oracle, not part of the
   build.
5. It reads the test library's wrappers (found through `.dynsym`): the stack probes, each with
   its ADD, MOVZ and MOVKs and the wrapper's BL after it, covering the page counts `gate.om`'s
   header gives; and in each wrapper the 10 STP words that save x19..x30 and d8..d15, with the
   matching LDPs somewhere outside the wrappers (the restore controls check the shared return at
   run time).
6. It requires a second build from the same object to have identical bytes.

Its controls change one thing each (the table, the object, the library or its copy) and must be
caught with their exact exit status and, where one is given, the refusal's own text. Checks 3 to
6 have controls on the test library; the compile checks and the nvml library's copies of the
same checks have none of their own. `gate.om`'s header lists the controls; `run.sh` pins the
summary line.

## NVML status

`nvml.om` declares the 11 functions of CUDApp's `compat/nvml/libnvidia-ml.map` with its
`nvml.h` C signatures. A pointer to a struct or buffer is a sized `edit`, which takes one
register; `nvmlDevice_t` is a `ulong`. The bodies are stubs: every query answers
`NVML_ERROR_NOT_SUPPORTED` (3) and writes nothing, and `nvmlErrorString` answers NULL (also its
trap value). A caller that prints that string will crash, so this library proves the shape and the
calling convention only. `nvmlDeviceGetName` and `nvmlDeviceGetUUID` take a C buffer and its
length; the stubs declare the buffer as one byte, which is safe only because they write nothing.
Real bodies need the unsized form (pointer, then a ulong count), and the wrapper would then have to
zero-extend C's `unsigned int` length into that count. It must not be installed in place of a real
`libnvidia-ml.so.1` until the items below exist.

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
