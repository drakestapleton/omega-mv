# gpu/intel: pure-Omega Intel Xe2/Xe3 (Panther Lake) GPU backend

Pure seeded-Omega (`om2`) Intel Xe GPU layer built by `seed/out/omc`, following the same architecture as `gpu/amd/` (`gpu/amd/kfd/` + `gpu/amd/gfx942/`).

## Layout

| Path | Role |
| --- | --- |
| `gpu/intel/xe/requests.tsv` | Linux `drm/xe` UAPI ioctl numbers, struct sizes, and field offsets (verified against `/usr/include/drm/xe_drm.h`). |
| `gpu/intel/xe/records.om` | Little-endian wire-record serializer for `requests.tsv` (zero-initialized reserved/pad fields, strict bounds). |
| `gpu/intel/xe/batch.om` | Intel Xe3 (Panther Lake / `Xe3Core`) CCS batch buffer builder & validator, bitfield-verified against Intel `compute-runtime` `hw_cmds_generated_xe3_core.inl` (`PIPELINE_SELECT` `0x69040302`, `STATE_BASE_ADDRESS` `0x61010014`, `STATE_COMPUTE_MODE` `0x61050001`, `CFE_STATE` `0x72000004`, `COMPUTE_WALKER` `0x72080026` with IDD DW19..26 / PostSync DW27..31 / InlineData DW32..39, `PIPE_CONTROL` `0x7a000a04`, `MI_BATCH_BUFFER_END` `0x05000000`, plus `batch fence`). |
| `gpu/intel/xe/isa.om` | Intel Xe2/Xe3 EU 128-bit instruction encoder & validator (`vadd`, `fsum16`, `gemm16`, `rmsnorm`, explicit SWSB dependency tokens, exact LSC stateless A64 D32 `send` descriptors from IGC `MessageDecoderLSC.cpp`, separate FP32 `mul`/`add`, IEEE `math.invm` + `madm` 0-ulp reciprocal refinement for `rmsnorm`, mandatory EOT termination). |
| `gpu/intel/xe/plan.om` | Deterministic 12-step `drm/xe` compute submission plan for `vadd`, `fsum16`, `gemm16`, and `rmsnorm`. |
| `gpu/intel/xe/launch.om` | Full pure-Omega Panther Lake `drm/xe` userspace driver (`selftest`, `probe`, `fence-test`): discovers `DRM_XE_ENGINE_CLASS_COMPUTE` + SYSMEM placement via `XE_DEVICE_QUERY`, allocates/maps BOs (`XE_GEM_CREATE` WB + `XE_GEM_MMAP_OFFSET` + `kfdmap`), binds with Panther Lake `pat_index=1` (`product_helper_ptl.cpp`), submits Xe3 `PIPE_CONTROL` QWORD fence batch (`XE_EXEC`), and polls completion via `mapread` + `cpufence`/`cpurelax`. Compiles for both AArch64 and `target x86linux`. |
| `gpu/intel/gate.sh` | Host-only verification gate (compiles all 5 `.om` units, runs 11-ioctl selftest, checks wire sizes, validates CCS batches and Xe ISA binaries, runs negative controls). |

## Status

- **Compiler ioctl allowlist (`seed/omc/omc.om`)**: All 11 `DRM_IOCTL_XE_*` / `DRM_IOCTL_GEM_CLOSE` requests are in `omc`'s checked `kfdctl` allowlist (rebuilt from the 408-byte seed to fixpoint `210c52566e782cf15ece6e478d45bfb67f1ad338f29e41546dad9b6c4f85b54c`, matching `seed/out/omc.sha256`).
- **Host gate (`sh gpu/intel/gate.sh`)**: `PASS` on AArch64 Linux (`seed/out/omc`), including `x86linux` cross-compile of `launch.om` and 11-ioctl kernel `-EBADF` selftest.
- **Physical Intel Panther Lake hardware execution**: `NOT_RUN` (no Panther Lake device attached to this host).
