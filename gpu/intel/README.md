# gpu/intel: pure-Omega Intel Xe2/Xe3 (Panther Lake) GPU backend

Pure seeded-Omega (`om2`) Intel Xe GPU layer built by `seed/out/omc`, following the same architecture as `gpu/amd/` (`gpu/amd/kfd/` + `gpu/amd/gfx942/`).

## Layout

| Path | Role |
| --- | --- |
| `gpu/intel/xe/requests.tsv` | Linux `drm/xe` UAPI ioctl numbers, struct sizes, and field offsets (verified against `/usr/include/drm/xe_drm.h`). |
| `gpu/intel/xe/records.om` | Little-endian wire-record serializer for `requests.tsv` (zero-initialized reserved/pad fields, strict bounds). |
| `gpu/intel/xe/batch.om` | Intel Xe2/Xe3 Compute Command Streamer (CCS) batch buffer builder & validator (`PIPELINE_SELECT`, `STATE_BASE_ADDRESS`, `CFE_STATE`, `COMPUTE_WALKER`, `PIPE_CONTROL` user-fence write, `MI_BATCH_BUFFER_END`). |
| `gpu/intel/xe/isa.om` | Intel Xe2/Xe3 EU 128-bit instruction encoder & validator (`vadd`, `fsum16`, `gemm16`, `rmsnorm`, separate FP32 `mul`/`add`, LSC stateless load/store `send`, mandatory EOT termination). |
| `gpu/intel/xe/plan.om` | Deterministic 12-step `drm/xe` compute submission plan for `vadd`, `fsum16`, `gemm16`, and `rmsnorm`. |
| `gpu/intel/xe/launch.om` | Direct Linux `drm/xe` `kfdctl` ioctl launcher & 11-ioctl kernel syscall selftest (compiles for both AArch64 and `target x86linux`). |
| `gpu/intel/gate.sh` | Host-only verification gate (compiles all 5 `.om` units, runs 11-ioctl selftest, checks wire sizes, validates CCS batches and Xe ISA binaries, runs negative controls). |

## Status

- **Compiler ioctl allowlist (`seed/omc/omc.om`)**: All 11 `DRM_IOCTL_XE_*` / `DRM_IOCTL_GEM_CLOSE` requests are in `omc`'s checked `kfdctl` allowlist (rebuilt from the 408-byte seed to fixpoint `210c52566e782cf15ece6e478d45bfb67f1ad338f29e41546dad9b6c4f85b54c`, matching `seed/out/omc.sha256`).
- **Host gate (`sh gpu/intel/gate.sh`)**: `PASS` on AArch64 Linux (`seed/out/omc`), including `x86linux` cross-compile of `launch.om` and 11-ioctl kernel `-EBADF` selftest.
- **Physical Intel Panther Lake hardware execution**: `NOT_RUN` (no Panther Lake device attached to this host).
