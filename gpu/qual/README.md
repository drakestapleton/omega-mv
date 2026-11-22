# gpu/qual: Pure-Omega Physical Hardware Qualification Kit (x86-64 Linux & Non-NVIDIA GPUs)

This directory holds standalone pure-Omega (`seed/out/omc`) qualification binaries designed to prove
**physical hardware execution** for targets that still require physical hardware qualification rather
than emulator or CPU-only checks:

| File | Target | Purpose |
| --- | --- | --- |
| `x86linux_qual.om` | `target x86linux` | Native x86-64 Linux physical qualification: detects emulation (`qemu-x86_64` / non-x86 kernel) and refuses (`exit 3`, `BLOCKED_HARDWARE`) unless run on real x86-64 Linux hardware; exercises integer/overflow/shift semantics, IEEE-754 `f32`/`f64` + `sqrt` + `bitcast`, NIST SHA-256 vectors, `cpufence`/`cpurelax`/`monons`, and `fork`+`waitpid` trap controls (traps 1, 2, 3, 5 -> exits 101, 102, 103, 105); prints a SHA-256 receipt. |
| `non_nvidia_qual.om` | `aarch64` & `target x86linux` | Non-NVIDIA physical GPU discovery & pre-flight qualification: scans PCI display devices (`0x1002` AMD, `0x8086` Intel, `0x10de` NVIDIA), `/dev/kfd`, `/dev/dri/renderD128`, and `/etc/OpenCL/vendors`; refuses (`exit 3`, `BLOCKED_HARDWARE`) on NVIDIA-only or CPU-only hosts. |
| `qual_test.om` | host | Pure-Omega host classification & negative-control test suite. |
| `gate.sh` | host / target | Compiles all units with `seed/out/omc`, checks synthetic AMD/Intel/NVIDIA-only fixtures, verifies `x86linux_qual` refuses under QEMU (`exit 3`) and passes `--allow-emulated-selftest`, and runs live host inventory. |

## Running on physical target hardware

1. **Physical x86-64 Linux host**:
   ```sh
   OMC=seed/out/omc sh gpu/qual/gate.sh
   ```
   On a real x86-64 Linux machine, `x86linux_qual` reports `EXEC_CLASS=PHYSICAL_X86_64`, `VERDICT=PASS`, and a `RECEIPT_SHA256=...`.
2. **Physical AMD (MI300X / gfx942) host**:
   `non_nvidia_qual` confirms PCI `0x1002` + `/dev/kfd`, then run `gpu/amd/kfd/launch/` and `tests/gates/run.sh gpu-amd`.
3. **Physical Intel Xe2/Xe3 (Panther Lake) host**:
   `non_nvidia_qual` confirms PCI `0x8086` + `/dev/dri/renderD128`, then run `launch probe` and `launch fence-test` from `gpu/intel/xe/launch.om`.
4. **Physical OpenCL/SPIR-V non-NVIDIA GPU host**:
   Run `OMC=seed/out/omc sh gpu/spirv/check.sh` and `sh gpu/spirv/omega-run.sh`.

## Current Hardware Status

- **x86-64 Linux physical qualification**: `BLOCKED_HARDWARE` / `NOT_RUN` (no physical x86-64 Linux machine attached; verified under `qemu-x86_64` on DGX Spark AArch64 where default invocation properly returns `exit 3` `BLOCKED_HARDWARE` and `--allow-emulated-selftest` passes all 12 checks + 4/4 trap controls).
- **AMD / Intel / non-NVIDIA GPU physical qualification**: `BLOCKED_HARDWARE` / `NOT_RUN` (DGX Spark carries only NVIDIA GB10 `0x10de:0x2e12`; `non_nvidia_qual` confirms `GPU_AMD_PCI count=0`, `GPU_INTEL_PCI count=0`, `GPU_NVIDIA_PCI count=1`, `VERDICT=BLOCKED_HARDWARE`).
