# Pure Seeded-Omega Build, Release, and Automation Coordinators (`seed/build/`)

Every build, release, and delivery coordinator in this directory is pure seeded OM-2 compiled by `seed/out/omc` into a static AArch64 Linux ELF (`ldd: not a dynamic executable`), using dynamic run-time pools (`global ... *` + `enlarge`) and streaming 64 KiB FIPS 180-4 SHA-256 with zero shell, zero Python, and zero libc on the delivery path.

## Coordinators

| File | Binary | Replaces | Role |
|---|---|---|---|
| `common.om` | *(shared OM-2 lib)* | — | Dynamic byte pools, streaming SHA-256, file/dir I/O, atomic rename, `envread`, `execprog`/`execenv` spawner |
| `birth.om` | `om-birth` | `seed/omega-from-seed.sh`, `seed/rung4/mk4.sh`, `seed/omc/tests/size-record.py` | Full compiler birth `seed0 -> hex1 -> asm2 -> om4 -> omc` 3-stage fixpoint, `diaggen` source identity, all 8 `size-record` cases, and all 4 names-pass probes (`--verify` for non-mutating check) |
| `units.om` | `om-units` | `om/units.sh` | Byte-for-byte regeneration and `--check` of `src/omega_om_units.{c,ident,fs.c}` and `src/omega_{native,api_decl}.h` |
| `tlsbuild.om` | `om-tlsbuild` | `om/tls/build.sh` | Composes the 15 `om/tls/` units with a program, compiles with `omc`, and stamps the FIPS FKIH HMAC-SHA-256 slot (`-p` for stamp-only) |
| `sparkefi.om` | `om-sparkefi` | `aienux/spark/build_spark_efi.sh` (including both inline Python 3 scripts) | Word-boundary namespacing, 6-slice `target a64efi` composition, `PLAT` safety guards, and PE32+ header + SHA-256 verification |
| `gpucoord.om` | `om-gpucoord` | `gpu/spirv/{omega-run,check}.sh`, `gpu/intel/gate.sh`, `om/gpu/{spec,dsv41,inkling2}/build.sh` | SPIR-V `emit`/`val`/`run`/`conform` runner & check suite, Intel Xe gate, and SM121 model package builders (`build-spec`, `build-dsv41`, `build-inkling2`) |
| `release.om` | `om-release` | `Makefile` lock checks, `tools/uxl/{windows_paths,run_all}.py`, `uxl-run.sh` (AArch64 Linux), layer/release orchestration | `check-locks` (omc pin + `*.lock` 40-hex + `.env` scan), `check-paths` (Windows path & case-collision check), `layers` (all 8 SI `units-gate.om`), `uxl` (host + 65-file Level 1 + SPIR-V + Xe), `package OUTDIR VERSION`, `verify OUTDIR` |
| `gate.om` | `om-build-gate` | — | Self-qualification gate (`OMEGA-BUILD-COORD`): 2× deterministic builds of all 6 coordinators, end-to-end positive checks, and 6 planted negative controls |

## Direct Pure-Omega Invocation (No `make`, No `sh`, No Python)

On AArch64 Linux from the repository root:

```sh
# Build and run the self-qualification gate (compiles & tests all 6 coordinators + negative controls):
cat seed/build/common.om seed/build/gate.om | seed/out/omc > build/om-build-gate
chmod +x build/om-build-gate
./build/om-build-gate build/om-build-gate-work

# Build the top-level release/delivery coordinator once, then package the full pure-Omega toolchain:
cat seed/build/common.om seed/build/release.om | seed/out/omc > build/om-release
chmod +x build/om-release
./build/om-release check-locks
./build/om-release check-paths
./build/om-release uxl build/uxl-work
./build/om-release package build/release-1.0 1.0.0
./build/om-release verify build/release-1.0
```

Once packaged into `OUTDIR/bin/`, every coordinator binary (`omc`, `om-birth`, `om-units`, `om-tlsbuild`, `om-sparkefi`, `om-gpucoord`, `om-release`) runs directly with zero shell or Python dependencies.

Legacy `.sh` scripts (`seed/omega-from-seed.sh`, `om/units.sh`, `om/tls/build.sh`, `aienux/spark/build_spark_efi.sh`, `gpu/spirv/{omega-run,check}.sh`, `gpu/intel/gate.sh`, `om/gpu/{spec,dsv41,inkling2}/build.sh`, `uxl-run.sh`) and `mk/omega-from-seed.mk` now act as thin compatibility shims that compile and `exec` these pure-Omega coordinators directly on AArch64 Linux, keeping existing callers (including `BLOCKED_OPERATOR` `tests/gates/run.sh`) working unchanged.
