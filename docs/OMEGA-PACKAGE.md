# The omega package: one command, the native build for the machine

Status (2026-11-23): IMPLEMENTED. Every program in the package was built from seed and run by
`sh tools/omega/gate.sh` on Linux AArch64 (Lima VM, Debian 13); the x86-64 programs ran under
qemu-x86_64 (EMULATED); no run on a physical x86-64 machine is recorded yet. GPU kernels are built and
checked on the host; no GPU ran them (device execution NOT_RUN).

## Layout

```
bin/omega                      POSIX sh: reads `uname -m`, runs lib/<cpu>/omega
lib/aarch64/  lib/x86_64/      one native build per CPU:
  omega                          the command (tools/omega/{driver,kernels,main}.om + seed/build/common.om)
  omc                            the compiler (seed/omc/omc.om); lib/aarch64/omc is seed/out/omc byte for byte
  omega-console                  the Visor console (tools/omega.om and src/visor, src/language)
  kernel-check                   gpu/targets.om (code-object loader checks)
  spirv-emit spirv-val spirv-run spirv-conform   gpu/spirv/{emit,val,run,conform}.om
  amd-hsaco                      gpu/amd/gfx942/hsaco.om
src/<cpu>/<program>.om         the exact source each program was compiled from
share/                         the registry, model op lists and kernel sources `omega kernels` builds from
MANIFEST.tsv                   SHA-256 of the compiler, every program, its composed source, every part
```

A Linux program file is either x86-64 or AArch64, so the only non-Omega file is `bin/omega`, which picks
the directory. `OMEGA_CPU=x86_64` (or `aarch64`) forces a CPU, for example to run the x86-64 build through
qemu-user binfmt on an AArch64 host.

## Build

```sh
sh seed/omega-from-seed.sh                       # seed0.hex -> ... -> seed/out/omc (fixpoint)
cat seed/build/common.om tools/omega/build.om | seed/out/omc > build/om-package && chmod +x build/om-package
./build/om-package build/package                 # every row of tools/omega/package.tsv
build/package/bin/omega hw
```

`tools/omega/build.om` refuses to run unless `seed/out/omc` hashes to `seed/out/omc.sha256`. Each program
is the concatenation of the parts its `tools/omega/package.tsv` row names, compiled by that compiler; the
composed source is kept under `src/` and every hash is in `MANIFEST.tsv`.

## Commands

| Command | What it does |
| --- | --- |
| `omega hw` | CPU, GPU PCI functions per vendor, device nodes, the selected GPU backend |
| `omega compile SRC [-o OUT] [--cpu C]` | compile for this CPU (prefixes `target x86linux` on x86-64 unless SRC names a target) |
| `omega run SRC [ARG]...` | compile for this CPU, run with ARGs, exit with the program's status |
| `omega check SRC` | the compiler's `check` mode for this CPU (on x86-64 `target x86linux` comes first, then `check`) |
| `omega console [ARG]...` | the Visor console |
| `omega omc` | the compiler on stdin and stdout |
| `omega version` | the CPU and the SHA-256 of every program in lib/<cpu> |
| `omega kernels list\|select\|get\|model` | model kernels for this device (below) |

GPU backend: `OMEGA_GPU` when set (cpu, nvidia, amd, amd-gfx942, intel); else the first of nvidia, amd,
intel whose GPU PCI function (`/sys/bus/pci/devices/*/class` base class 0x03 display or 0x12 processing
accelerator, which AMD Instinct cards report, with vendor 0x10de, 0x1002, 0x8086) and device node
(`/dev/nvidiactl`, `/dev/kfd`, `/dev/dri/renderD128`) are both present; else cpu. For AMD the ISA comes
from the KFD topology (`/sys/class/kfd/kfd/topology/nodes/*/properties`, `gfx_target_version 90402` is
gfx942); `OMEGA_GPU=amd-gfx942` asserts it on a host without the card.
`omega run` gives the program `OMEGA_CPU` and `OMEGA_GPU`, plus PATH, HOME, USER, LOGNAME, LANG, LC_ALL,
TERM, TMPDIR, PWD, TZ and every `OMEGA_*` and `OMC_*` entry (execenv allows 64 entries and 4096 bytes; an
entry that does not fit is named on stderr). `compile`, `run` and `check` write their temporary files in a
private directory `TMPDIR/omega-PID-N` made by mkdir with mode 0700 (an existing name is never reused) and
remove it when done. An argument over 4095 bytes is refused, never dropped. A program killed by signal N
gives 128 + N.

## Kernels

`gpu/kernels/registry.tsv` maps (op, shape, target) to how the kernel is built and how it is checked. A
device has an order of targets: nvidia `nvidia-sm121, cpu`; amd `amd-gfx942` (only with a gfx942 KFD
agent), then `cpu`; intel `spirv-cl, cpu`; cpu `cpu`. `omega kernels select OP [SHAPE]` takes the first
target in that order with a row, and names every target it skipped and why.

`omega kernels get OP [SHAPE]` selects, then looks in the cache. The cache key is the SHA-256 of the
registry row, the CPU, the SHA-256 of every `lib/<cpu>` program the build and its check run (omc always),
and every file the build reads, each framed as path, NUL, bytes, NUL, length; so a change to any of them is
a new key, never a stale hit. A hit is served only when the kernel's SHA-256 equals its receipt's; else it
is rebuilt. On a miss it builds the kernel itself, from the package's own sources and programs, in
`kernels/KEY.tmp-PID`, which is removed when the build or check fails:

| BUILD | How | CHECK before it enters the cache |
| --- | --- | --- |
| `omc` | the INPUT parts (openaccel-lab harness + workload) compiled by `lib/<cpu>/omc` for this CPU | ELF64, ET_EXEC, e_machine of this CPU |
| `spirv-emit` | `lib/<cpu>/spirv-emit K cl` | `spirv-val`, `kernel-check load SPIRV_CL`, then `spirv-run` on `spirv-conform`'s inputs, compared bit for bit (0 ulp) with its reference |
| `amd-hsaco` | `lib/<cpu>/amd-hsaco TABLE` | `kernel-check load AMDGPU_HSACO kernel gfx942` must print LOAD ACCEPT |

Only a kernel whose check passed is renamed to `kernels/KEY/kernel`, next to `receipt.tsv` (row, CPU,
omc SHA-256, key, kernel SHA-256, the check, and `device_execution NOT_RUN` for a GPU target). When another
`omega` installed the same key first, its checked kernel is used. The cache root is `OMEGA_CACHE`, else
`XDG_CACHE_HOME/omega`, else `HOME/.cache/omega`.

`omega kernels model FILE` gets every `OP<TAB>SHAPE` line of FILE and exits 1 if one failed;
`share/gpu/kernels/models/decoder-step.ops` lists the ops of one decoder-only transformer step.

### What exists, and what does not

- cpu: all 25 openaccel-lab workloads (`train/openaccel-lab/workloads/*`), any shape, on both CPUs.
- spirv-cl: vecadd (any), rmsnorm (row16), reduce_sum (row16), tmatmul16 (tile16), the fixed kernels of
  `gpu/spirv/emit.om`. The check runs the host executor, not a GPU.
- amd-gfx942: vecadd, reduce_sum (row16), rmsnorm (row5120), packed from the hand-written instruction
  tables in `gpu/amd/gfx942/`. The check is the loader's offline check, not a GPU.
- nvidia-sm121: no rows. Its generators (`gpu/nvidia/om/*`) have no stdin/stdout entry point yet, so an
  NVIDIA device is given the CPU kernel and `select` says why (MISSING_IMPLEMENTATION).
- A CPU kernel is checked for its machine only: the openaccel-lab oracle cases are not in this repository,
  so a CPU kernel's numbers are not compared on build.

## Measured (2026-11-23, Lima VM omega-llm, AArch64; x86-64 under qemu-x86_64 binfmt, EMULATED)

- Compiler born from `seed/rung0/seed0.hex` (seed0 408 B, hex1 776 B, asm2 2464 B, om4 16200 B) and the
  independent Strand B seed (`seed/helix/helix-from-seeds.sh`: seedB0 396 B, omB2 15464 B) to the same
  `seed/out/omc`; the x86-64 compiler rebuilds itself byte for byte and builds the AArch64 compiler byte
  for byte (`seed/omc/gate-pools.sh` section X); `python3 seed/omc/decode-x86.py` decodes every byte of
  the x86-64 compiler with an independent objdump.
- `sh tools/omega/gate.sh` on both CPUs: `hw`, `compile`, `run` (status passed through), `check` (0 and
  3), `console`, `version`, an empty TMPDIR afterwards; all 25 CPU kernels built; `kernels get vecadd`
  with `OMEGA_GPU=intel`: SPIR-V built, validated, loaded and executed on the host, `CONFORM vadd
  n=1048576 wrong=0`, the same output SHA-256 on both CPUs; `OMEGA_GPU=amd` without a gfx942 agent: the
  amd-gfx942 skip and the CPU kernel; `reduce_sum row16` with `OMEGA_GPU=amd-gfx942`: `LOAD ACCEPT
  AMDGPU_HSACO ... gfx942`; `select gemm_nn` with `OMEGA_GPU=nvidia`: the sm121 skip and the CPU kernel;
  `kernels model decoder-step.ops`: 8 ops, 0 failed. Controls: an unknown op exits 1; the emitter's own
  mutant SPIR-V kernel fails the 0-ulp compare and is not cached; a changed omc and a changed spirv-emit
  each give a new key; a cached kernel whose bytes no longer match its receipt is rebuilt.
