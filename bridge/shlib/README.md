# bridge/shlib: shared libraries from Omega alone

`shlib.om` writes an AArch64 Linux shared object (ELF64 `ET_DYN`) from two inputs: the native
object `seed/out/omc` emits for an OM-2 unit in object mode (`OMOBJ001`, `spec/omegese-modules.md`)
and a table naming the soname, the libraries it needs, its states, its lock, its imports and its
exports. No C compiler, assembler or linker takes part. The same program writes a probe executable
that the system's dynamic loader runs against the library.

```
seed/out/omc < bridge/shlib/shlib.om > shlib
{ printf 'object\nom2\n'; cat bridge/shlib/rmfake.om bridge/shlib/nvrmfake.om; } | seed/out/omc > fake.obj
./shlib lib bridge/shlib/nvrmfake.tsv fake.obj libomega-nvrm.so.1
N=gpu/nvidia/native/nvml
{ printf 'object\nom2\n'; cat $N/nvml.om $N/query.om $N/step.om
  sed '/^note/!s/\bat\b/at_/g' $N/errstr.om; cat bridge/shlib/nvml.om; } | seed/out/omc > nvml.obj
./shlib lib bridge/shlib/nvml.tsv nvml.obj libnvidia-ml.so.1
./shlib call bridge/shlib/nvml.tsv nvprobe && ./nvprobe; echo $?
```

The `sed` line is the OM-2 view of `errstr.om`: its parameter `at` is a reserved word in OM-2,
so the whole-word token becomes `at_` outside note lines (the gate does the same in Omega). The
table format, the refusals and the exit codes are at the top of `shlib.om`.

## What the library holds

- `.hash` (SysV), `.dynsym` (one global function per export row, then one undefined function per
  import), `.dynstr` (soname first), `.text`, `.dynamic` (`DT_NEEDED` per needed row, `DT_RUNPATH`,
  the hash, string and symbol tables, `DT_SONAME`, and `DT_RELA` when there are imports),
  `.rela.dyn` (one `R_AARCH64_GLOB_DAT` per import), `.got` and `.bss` (the states).
- One wrapper per export turns a C call (AAPCS64) into an omc function call. It saves x19..x30
  and d8..d15. It builds the per-call context omc expects in x7, whose byte offset 16
  (`[x7, #16]`) holds the trap entry,
  and sign- or zero-extends narrow integer arguments, because omc assumes they are already
  extended. A trap inside Omega code (for example a division by zero) returns the row's TRAP
  value to the C caller with every saved register restored.
- A frame export gets, as its first parameter, a frame holding the C argument registers x0..x7 as
  they came, the address of every state and the address of the caller's stack arguments (C argument 9
  on); each state it names in its row is passed as a further
  sized parameter. States are zero-filled, 64-byte aligned, one copy per process. That is how
  `nvml.om` keeps the NVML state between calls and reaches C pointers whose length is only known at
  run time (through the `memcpy` import).
- A lock row makes every frame export call LOCK with the lock state's address before its body, and
  UNLOCK on both the return and the trap path. LOCK answering nonzero returns the TRAP value
  without running the body.
- An `extern fn` of the object is an import: omc's BL goes to a veneer that saves x7 and x30, makes
  the C arguments from omc's parameter slots (an import row can reorder them and add byte offsets,
  so one omc slot can feed two C arguments), calls through the GOT and extends a narrow result.
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
  must have exactly one call record. An import must have no address and no stack need.

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
- The probe compares the low 32 bits of each result, and a `bufeq OFF VALUE` row compares the u64
  the buffer holds at OFF. A call row passes up to ten arguments (`buf`, `buf+N`, `bufword` or a
  number), the ninth and tenth on the stack. Its mismatch status is 1 + the row index, capped at
  100 so it never collides with the loader's 127 or the register check's 250.
- The module linker refuses a need above 8 MiB (its program's own stack). A library runs on its
  caller's stack, which may be larger, so the generator bounds the need only by the address space.
- Each object refusal names the rule that fired (address, entry slot, call record, its
  destination, BL coverage, runtime entry, x7 use); the remaining malformations share one message.
- The code is position independent because omc refuses `text` and `global` in object mode and
  states are reached with ADRP. If object mode ever allows them, the generator must refuse such
  constants or relocate them.
- The trap path returns without a matching BL and RET pair, and the library carries no GCS or
  BTI property note. On a system that enforces Guarded Control Stack the trap path would fault.
- A trap skips the rest of the Omega body: whatever the body would have done after it (a cleanup
  write, a counter) does not happen. A body that needs such a step after a trap in a callee must do
  it in the callee.

## Gate

`tests/gates/run.sh shlib` (manifest `tests/gates/omega-shlib.gate`, program `gate.om`, in Omega)
runs these checks; `gate.om`'s header lists each with its exact status:

1. It builds six objects: `test.om`, `dep.om`, `imp.om`, the test transport (`rmfake.om` then
   `nvrmfake.om`), the NVML unit (four files of `gpu/nvidia/native/nvml` then `nvml.om`) and the Ampere
   QMD unit (`gpu/nvidia/om/encoder/amp_runtime.om`, `amp_qmd.om`, then `ampqmd.om`).
2. It builds each library and its probe.
3. It runs each probe from one scratch directory, so `libnvidia-ml.so.1` finds its transport and
   `libomshimp.so.1` its dependency through `$ORIGIN`. The `test.tsv` probe calls constants, int
   arguments with dirty upper halves, a trapping division followed by another call, a pointer write
   read back by a later call, a uint with a dirty upper half, two bodies that need 8 KiB and 16 KiB
   of stack (one through a private call), a uchar, ushort, byte and short each under dirty upper
   bits, a division inside a private callee that traps, and a body whose need sits one call cost
   past a 4 KiB page. The `imp.tsv` probe calls across imports (live registers kept, a swapped and
   an offset argument, the C library's `strlen`), keeps a counter in a state, and shows that a trap
   releases the lock. The `nvml.tsv` probe drives the real NVML bodies against the RM fake: init,
   count, handles, name, UUID, temperature, memory, utilization, the running processes, refused
   arguments and shutdown, and compares every byte they write with what the C library writes.
   Each probe also sets x19..x27, x29 and d8..d15 and checks that they and sp come back unchanged.
4. It runs `/usr/bin/readelf -W -S -d --dyn-syms` on each library. readelf reads the symbols
   through the section headers, which the loader never looks at; it must exit 0, print no
   warning, show the table's soname and every needed library and list every export of the table
   (at least one) as a `FUNC GLOBAL DEFAULT` symbol line. readelf is a read-only verification
   oracle, not part of the build.
5. It reads the test library's wrappers (found through `.dynsym`): the stack probes, each with
   its ADD, MOVZ and MOVKs and the wrapper's BL after it, covering the page counts `gate.om`'s
   header gives; and in each wrapper the 10 STP words that save x19..x30 and d8..d15, with the
   matching LDPs somewhere outside the wrappers (the restore controls check the shared return at
   run time).
6. It requires a second build from the same object to have identical bytes.

Its controls change one thing each (the table, the object, the library or its copy, the composed
source) and must be caught with their exact exit status and, where one is given, the refusal's own
text. `gate.om`'s header lists the controls; `run.sh` pins the summary line.

## NVML

`libnvidia-ml.so.1` built from `nvml.tsv` exports the 11 functions of CUDApp's
`compat/nvml/libnvidia-ml.map` with its `nvml.h` C signatures, with real bodies: `nvml.om` is
CUDApp's `native/nvml/api.om` shell and the checks its generated C glue made, in Omega, calling
the unchanged request protocol (`nvml_step`) and error text (`nvml_errstr`) directly. It needs
`libomega-nvrm.so.1`, the transport (`omega2_nvrm_open_file`, `omega2_nvrm_close_file`,
`omega2_nvrm_ioctl`), and runs every call under one pthread mutex. In the gate the transport is the
Omega RM fake (`nvrmfake.om` over CUDApp's `tests/nvml/rmfake.om`, copied unchanged). No device is
opened by the gate; a run against `/dev/nvidia*` needs the real transport and the GPU.

Where it can differ from the C library, only after a bug (a trap): the call returns 999
(`nvmlErrorString`: NULL) at once, and a trap inside the step does not reset the step's resume
point as the C does after its own trap.

## CUDApp C entry points

`ampqmd.om` with `ampqmd.tsv` is CUDApp's `src/omega_ampere_qmd.c` (its default build) as
`libomega-ampere-qmd.so.1`: `omega_ampere_policy` and `omega_ampere_build_qmd` over the unchanged
`amp_qmd` unit. `omega_ampere_build_qmd` has ten parameters; the last two come on the caller's stack,
which a frame export reaches through the frame word after its states. The gate's probe checks the three
refusals and one accepted build whose last two arguments it passes on the stack, every narrow argument with
its upper bits set, and compares all 256 QMD bytes with what the C writes for the same arguments; 200000
random builds are compared with the C outside this tree.
