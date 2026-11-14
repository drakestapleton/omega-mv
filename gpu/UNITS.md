# gpu/: Omega GPU units from CUDApp om/, backend/ and native/ (ADR 0047, steps 3 and 4)

Omega GPU is the GPU layer of Sovereign Intelligence (SI), the stack Drake named, with Omega as its language and
compiler. This step brought CUDApp's seeded-Omega units here with the history of those files. Source: CUDApp main
`84b524cadaaa8bc9b556adfaea9d6dd2e0d67a66`. Command and maps: `gpu/import/step3-om-backend/`.

| CUDApp path | Here | What |
| --- | --- | --- |
| `om/**/*.om` (484 files) | `gpu/nvidia/om/` | CUDApp's seeded-Omega components: encoders, codegen, kernel generators, cache, pipeline, graph, numeric, platform, API, sessions, tools and the rest. The three files step 2 brought are the ones `seed/ng/cudapp.lock` pins (see below). |
| `backend/spirv/*.om` | `gpu/spirv/` | `emit.om` (SPIR-V kernel builder) and `conform.om` (host reference and bit-exact compare). |
| `backend/hw/*.om`, `backend/hw/manifest.tsv` | `gpu/hw/` | `hwman`, the hardware capability manifest (`core.om`, `cpu.om`, `tpm.om`, `main.om`) and the table it reads. |
| `backend/targets.om` | `gpu/targets.om` | The portable target table and code-object loader checks. Same bytes as CUDApp `dc536882`, the version step 1 also carries. |

`om/` keeps its CUDApp layout under `gpu/nvidia/om/`, as step 2 did, so that a CUDApp path maps to its new path by
one prefix. Some of these units are not NVIDIA-specific (cache, pipeline, graph, numeric); regrouping them is a later
change, not part of the move.

## The units and their gate

`gpu/units.tsv` lists 405 units, NAME and its parts: 372 from step 3 and 33 from step 4. It was written from the
unit list of CUDApp `om/units.sh` at the source commit (default selection, `om/` read as `gpu/nvidia/om/` and
`native/` as `gpu/nvidia/native/`), plus `emit`, `conform`, `targets`, `hwman` and the `native/` programs that compile
on their own. `gpu/units-gate.om` (OMEGA-GPU-UNITS, `tests/gates/run.sh gpu-units`) is seeded Omega. It
refuses any compiler but `seed/out/omc` (by `seed/out/omc.sha256`), composes every unit as `om/units.sh` does (each
part followed by a newline), compiles it twice and requires exit 0, empty stderr and identical bytes. Unit names are
`A-Z a-z 0-9 _` and unique; a malformed row, a missing part or a table with no unit fails. The runner requires the
exact summary line, so a shortened table fails. Every hardware row stays NOT_RUN.

This gate shows that the units compile, reproducibly, with this repository's compiler. It does not show that they
behave correctly. In CUDApp the units are lowered to portable C by the omega-bridge converter (`om/units.sh`), and
their behaviour checks are C, Python and shell (`make test-*`, `tests/`). Those checks are not Omega and did not
move.

The unit `bw_enc_sm121` compiles to the same bytes `seed/ng/gpu/gate.cases` pins for the encoder (`enc-pin`,
sha256 `460fb3a4...`).

## Versions from step 2

`gpu/nvidia/om/encoder/bw_enc_sm121.om` and `gpu/nvidia/om/cubin/cubin_elf.om` are CUDApp main's (84b524ca) since
2026-11-14; `gpu/nvidia/om/components/bw_alloc.om` is the same at 1988c50e (step 2) and at 84b524ca. All three are the
bytes `seed/ng/cudapp.lock` pins. The six units that use them (`bw_enc_sm121`, `cubin_elf`, `compose`, `encode`,
`validate`, `q38_emit`) compile with them. The other copy of the encoder, the top-level `om/encoder/bw_enc_sm121.om`
that the Makefile uses, is not touched.

## Not here yet

- Units with parts in CUDApp `tools/` (`c5`): with the tools move (step 6). The note is at the top of
  `gpu/units.tsv`.
- 41 of the 487 moved `.om` files under `gpu/nvidia/om/` are compiled by no row of the table (446 are, after step
  4). They are files `om/units.sh` does not list (tests, fixtures, drivers such as `cache/*_test.om`,
  `encoder/*_test.om`, `q38-head/driver.om`), which CUDApp builds from make targets and shell tests, whose
  compositions are not Omega.
- Everything in CUDApp `om/` that is not Omega stayed there: 34 `.md`, 31 `.json`, 27 `.py`, 22 `.c`, 8 `.h`, 7 `.sh`
  (`units.sh`, `no-posix.sh`, `native-freest.sh` and four more), 5 `.lock`, 2 `.patch`, 2 `.log`, 1 `.gitignore` and
  39 crumb files (retired, history only). So did `backend/hw/README.md`, the multitarget and hw test drivers
  (`tests/multitarget/run.sh`, `tests/hw/run.sh`) and the C SPIR-V launcher.

## Step 4: CUDApp native/

Step 4 brought the Omega files of CUDApp `native/` (57 `.om`) to `gpu/nvidia/native/` with the history of those
files (64 commits), from the same CUDApp commit `84b524ca`. Two `native/` files were already here from step 2 at
1988c50e (`native/blackwell/launch.om`, `native/nvrm/context.om`); step 4 left them at that version. Since
2026-11-14 `launch.om` is 84b524ca's too (`context.om` is the same at both). `native/blackwell/batch.om` calls
`gbbody` and `gbtail`, which only the newer `launch.om` defines. Command and maps:
`gpu/import/step4-native/`.

`gpu/units.tsv` gained 33 rows (405 in all). 26 are the `om/units.sh` units whose parts are in `native/` (the
`closure_*` units, `nvrm_*`, `nvml_*`, `aiengpu`, `nvrm_policy`, `nvrm_va`, `nvrm_alloc_*`, `nvrm_counts`); with
them the 12 `om/` files that were only their parts are now compiled too. The other 7 are `native/` programs that
compile on their own (`aiengpu/effects.om`, `models/fp8.om`, `models/mxfp4.om`, `nvml/api.om`, `nvrm/transport.om`,
`share/share_native.om`, `streams/submit.om`). The other 31 moved `native/` files (abft, the rest of blackwell, gsp,
learn53, models, shader-pilot, share, smi, speculation, trace) are compiled by no row: CUDApp composes them in make
targets and shell tests, which are not Omega. Step 2's `launch.om` and `context.om` are checked by
`seed/ng/gpu/gate.cases` instead.

Not here, because they are not Omega:

- CUDApp `nvrm/` (the NVIDIA driver client: 10 C files, `nvrm.c` and its tests and gates, 6 headers and a README) and `m16/` (4 C and 2 header
  files), which the plan's step 4 row names. Their gates (`physics-nvrm-lifecycle.gate`, `physics-m16-requal.gate` in
  CUDApp) build and run that C, so they stay in CUDApp too, and physics-mv's duplicate `nvrm/nvrm.c` is not touched.
  The Omega parts of the driver client that exist (`native/nvrm/*.om`) are here; rewriting the rest in Omega is its
  own work.
- In `native/`: `aiengpu/units.sh`, `nvrm/units.sh`, `learn53/moe-closure.lock`, `learn53/omega653.lock`, the gsp,
  nvml and smi READMEs and the crumb files.

Nothing here opens a device; chip tiers stay NOT_RUN.
