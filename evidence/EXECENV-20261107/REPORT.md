# EXECENV-20261107: execenv (keyword 233)

Agent: ExecEnv (omp subagent of omp-queen-spark). Host: DGX Spark (aarch64), core 17, CPU only.
Base: origin/main 943d95553.

## Status

| Stage | State |
|---|---|
| IMPLEMENTED | Yes |
| EXERCISED | Yes, on AArch64. x86linux runs under binfmt qemu-x86_64, which is emulator evidence only. |
| QUALIFIED | No |
| MERGED | No |

## Compiler

| | omc sha256 | Source (`seed/omc/omc.om`) sha256 |
|---|---|---|
| New | `cfd96b48b0460ab5557853d6856f9c741b96ac8d0d624e06198defb4cbfa0d8a` | `062c9649af6a1d499b911e5b2f39b5419d7b75047616fe59fbcdc25f7b7b5b73` |
| Previous | `5f90edea61bac241398df5036990d899361a5acd9decb37954ce088ec0f6f6df` | |

- `sh seed/omega-from-seed.sh` gives rc=0, and the second rebuild produces identical bytes.
- No function was added: 508 functions, against the 512-function om4 seed.

## Results

| File | Command | Result |
|---|---|---|
| `gate-cfd96b48.log` | `build/execenv/gate seed/out/omc cfd96b48… seed/host/execenv/execenv.cases SCRATCH` | `OM2GATE PASS cases=11 pass=11 fail=0 invalid=0 not_run=0`. The cases are the AArch64 and x86 fixture, the printenv ORACLE, the execprog negative control, the function-mode and contract refusals, and 4 omc.om mutants, each detected at its named fixture check. |
| `negative-control-omc-5f90edea.log` | The same cases with the previous compiler | `OM2GATE FAIL pass=4 fail=7`. The previous compiler has no execenv. |
| `old-vs-new-compile.tsv` | All 1357 tracked `.om` files, compiled under 5f90edea and under cfd96b48 | 1357 SAME: identical output bytes, exit status and stderr. |
| `semhash.log` | | `SEMHASH PASS cases=269 controls=14` |
| `effects-branch.log` and `effects-main-943d9555.log` | | Both FAIL with the same 2 checks. The closure check is missing `eventfd` and `fma`, and the corpus check fails eventfd, irqnovfio, vfio and vfioirq. This failure already exists on main and is not caused by this change; `execenv` itself matches its table row. |
| `objdump-a64-envp.txt` | | Shows `add x2, sp, #0x3, lsl #12`, the AArch64 envp. |

Other checks:
- `gate18.sh`: `PASS gate18 169 literal packs`.
- `om/units.sh` regenerate, then `--check`: PASS. The only change is the `omc=` identity.
- `crumb verify .`: OK, 188 crumbs current. The crumb tool was built from aien-architecture d0f0b95d.

## Host tools

| Tool | Version | Role |
|---|---|---|
| `/usr/bin/printenv` | GNU coreutils 9.4 | ORACLE, never shipped |
| `qemu-x86_64` | binfmt registration | Prerequisite for the x86 cases |
| GNU objdump | 2.42 | Evidence only |
| strace | | Evidence only |

## NOT_RUN

- `seed/omc/gate5.sh`: the C path tools are not built in this tree.
- `tests/gates/run.sh seed`.
- The om parity scripts.
- Hardware x86.
