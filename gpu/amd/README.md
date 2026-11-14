# gpu/amd: the AMD gfx942 back end

Seeded Omega that targets the AMD Instinct MI300X (gfx942) through the Linux KFD interface, without
ROCr or HIP in the production path.

| Path | What it is |
| --- | --- |
| `gfx942/hsaco.om` | Writes HSA code objects (ELF, code object v5) from declarative kernel tables (`gfx942/*.isa`). |
| `gfx942/*.isa` | The kernel tables: instruction words and kernel metadata, read by `hsaco.om`. Data, not code. |
| `gfx942/exec/` | A host executor for the gfx942 instructions the kernels use (`fp.om`, `fma.om`, `main.om`), so kernels can be checked on a CPU. |
| `gfx942/rope.om` | Rotary position tables for the Qwen3.8-27B configuration: one u32 position in, 32 cos and 32 sin binary32 words out. |
| `kfd/` | KFD ioctl requests, AQL dispatch packets, kernel arguments, records and the queue ring, with a shared CLI (`kfd/cli.om`); `kfd/requests.tsv` is the request table they read. |
| `kfd/launch/` | The direct-KFD launcher (`omega-launch`); its x86-64 build ran Qwen3.8-27B-FP8 on an MI300X. |
| `tests/amd-exec/*-probe.om` | Probe programs for the executor (semantics, rows, FMA, transcendental, rope frequencies). |
| `gate.om`, `card.tsv` | The gate and the receipt-recorded bytes it checks. |
| `import/` | How this came from CUDApp. |

This code came from CUDApp main `dc536882c06a692991be97dc65cd2d037d82b129` with the history of these
files (`import/filter-repo-command.txt`). Old paths: `backend/amd/` became `gpu/amd/`, `backend/targets.om`
became `gpu/targets.om`, `tests/amd-exec/*-probe.om` became `gpu/amd/tests/amd-exec/`.

## The gate

```
tests/gates/run.sh gpu-amd
```

That builds `gpu/amd/gate.om` (with `seed/ng/sha256.om`) using `seed/out/omc` and runs it. The gate,
in Omega:

1. refuses any compiler whose sha256 is not the one in `seed/out/omc.sha256` (exit 69, nothing built);
2. builds every unit (the writer, the loader table, the executor, rope, the four KFD units, the launcher
   for AArch64 and x86-64, the five probes) twice and requires exit 0, empty stderr and identical bytes;
3. checks the bytes in `card.tsv` against the sha256 their receipts record: the 18 model kernel objects,
   `vadd.hsaco` and the x86-64 launcher, which ran on the MI300X, and the AArch64 launcher, a host-built
   reference that never ran on the card (printed as `reference`); each object must also pass
   `targets load AMDGPU_HSACO FILE gfx942`;
4. runs three controls that must be caught: a compiler one byte longer, a kernel table with one
   descriptor word changed, a missing table.

It ends with `OMEGA-GPU-AMD PASS ... hardware=NOT_RUN`. It opens no device.

## What ran on hardware

The receipt for the MI300X run stays in CUDApp where it was written:
`evidence/amd-qwen38-native-refusal-20261113/` (Qwen3.8-27B-FP8 through the direct-KFD launcher on an
x86-64 host). Its `native/MANIFEST.json` records the x86-64 launcher (`omega-launch`), `vadd.hsaco` and the
18 model kernel objects. Those results carry over to this code only through byte identity, which the gate
checks for each of them. The AArch64 launcher never ran on the card.

## Not yet Omega (still in CUDApp at dc536882)

These are not here, because they are not Omega. Each is to be rewritten in Omega before it moves:

- the LLVM assembly oracles `backend/amd/gfx942/*-gfx942.s` (34 files) and `backend/amd/vadd-gfx1151.s`,
  which `tests/amd/run.sh` compares with the writer's words through `llvm-mc-18`;
- the Python oracles and instruments under `tests/amd/`, `tests/amd-exec/`, `tests/amd-kfd/` and
  `tests/amd-kfd-launch/` (48 files), the C instruments and layout oracle (8 `.c`, 1 `.h`), the shell
  drivers (4 `.sh`) and the notebook template (`.in`, `.inc`): the value-level checks of each kernel
  against an independent reference, the semantics suites of the executor and their mutants, the KFD
  record oracles and the launcher's syscall instruments. Their fixtures and notes (9 `.json`, 5 `.log`,
  6 `.md`, `reference/SHA256SUMS`) stay with them, except the object list, whose hashes are in `card.tsv`;
- the launcher documents `backend/amd/kfd/launch/README.md` and `PLAN.md`, which describe those checks.

Not imported and not to be rewritten: `backend/amd/kfd/launch/COMPILER`, the launcher's own compiler pin.
Under ADR 0047 Decision 4 a moved piece carries no pin of its own; the gate uses `seed/out/omc.sha256`.

Until they are rewritten, the value-level and syscall-level checks of this back end run only in CUDApp;
in this repository the gate checks build reproducibility and byte identity with the bytes the receipts record.
