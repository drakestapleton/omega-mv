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
| `gpu/intel/gate.sh` | Host-only verification gate (compiles all 4 `.om` units, checks wire sizes, validates CCS batches and Xe ISA binaries, runs negative controls). |

## Status

- **Host gate (`sh gpu/intel/gate.sh`)**: `PASS` on AArch64 Linux (`seed/out/omc`).
- **Compiler ioctl allowlist (`seed/omc/omc.om`)**: `kfdmap` already admits `/dev/dri/renderD*`; adding the 11 `DRM_IOCTL_XE_*` / `DRM_IOCTL_GEM_CLOSE` requests from `requests.tsv` into `seed/omc/omc.om` is a pin-moving compiler change (`seed/out/omc.sha256`).
- **Physical Intel Panther Lake hardware execution**: `NOT_RUN` (no Panther Lake device attached to this host).
