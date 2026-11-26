# Omega Universal Optimizer Ecosystem

> Hub-and-spoke fleet of 11 public standalone repositories pinned to `omega-mv` (`5132074dcc8a4a55e7acaa06be9d9b8698ead402`, `seed/out/omc` SHA-256 `85b84c6de85083e4d9d2368015c1ddcab3d863aada922be0e63d774dddf23134`, `OMEGA_ABI_2.0`).

## Zero-Config Quickstart (MacBook, DGX Spark, Steam Deck, Linux, Windows/WSL2)

```sh
git clone https://github.com/drakestapleton/omega-auto.git && cd omega-auto
./omega-auto              # Auto-detect CPU, GPU, live HW media encoders, and thermal/power envelope
./omega-auto bench-4k5m   # Paired A/B 5-minute 4K60 (3840x2160 @ 60fps, 18,000 frames) benchmark
./omega-auto render in.mp4
./omega-auto game
./omega-auto stream
```

## Standalone Spoke Repositories

| Repository | Layer | Pinned Commit (`main`) | Scope & Gate (`x86_64` Host) |
|---|---|---|---|
| [drakestapleton/omega-auto](https://github.com/drakestapleton/omega-auto) | `apps` | `8dbb3e09` | Zero-config front door: hardware/encoder live probe, pure seeded OM-2 convex bitrate brain (`om/omega_auto_brain.om`), Semantic GOP-DAG + LPT renderer, and 5-minute 4K60 paired A/B benchmark (`OMEGA-AUTO GATE PASS`). |
| [drakestapleton/omega-play](https://github.com/drakestapleton/omega-play) | `apps` | `79fcac3c` | 1-click anti-cheat-safe Steam Deck & Linux/SteamOS game optimizer: `DeckCBF` + Lean 4 proof (`proof/DeckCBF.lean`), Arboris `.pak` prefetch, X3D/P-core/Steam Deck scheduler, 40/45/60/90 Hz frame pacer, and Khronos Vulkan implicit layer (`OMEGA-PLAY GATE PASS`). |
| [drakestapleton/omega-stream](https://github.com/drakestapleton/omega-stream) | `apps` | `720fafeb` | Zero-bloat video rendering & streaming optimizer: 8 ABI v2 exports (`libobs_omega.so`, BT.709 `RGBA8->NV12`, 10-bit BT.2020 `RGBA8->P010`, 2x downscale, Luma SAD scene cut, 16x16 AQ, Arboris lookahead, zero-OOM VRAM admission, MSE/PSNR), parallel closed-GOP dispatcher, zero-heap replay ring, X3D/E-core isolator (`OMEGA-STREAM GATE PASS`). |
| [drakestapleton/omega-spirv](https://github.com/drakestapleton/omega-spirv) | `gpu` | `4bd57313` | Universal Vulkan `GLCompute` & OpenCL SPIR-V optimizer: 14 kernel x `{cl, vk}` 0-ULP checks + mutant, `irspirv`, Helix `EGP2`/`EGP3` 12/12 antibodies, `spirv_opt` `NoContraction` guard (`OMEGA-SPIRV GATE PASS`). |
| [drakestapleton/omega-intel](https://github.com/drakestapleton/omega-intel) | `gpu` | `c49b45e3` | Intel Xe2/Xe3 (`drm/xe`) GPU engine + OpenCL/Vulkan connector: live 11-ioctl native x86-64 `-EBADF` selftest, Xe3 CCS batch/ISA checks, Panther Lake/Battlemage/Lunar Lake contract router (`OMEGA-INTEL GATE PASS`). |
| [drakestapleton/omega-cpu-x86](https://github.com/drakestapleton/omega-cpu-x86) | `gpu` | `949821d6` | Intel & AMD x86-64 CPU optimizer: unified `TargetDesc` (AVX2/AVX-512/AMX/X3D V-Cache/Steam Deck Zen 2), `NG-TARGET-GATE` (73 checks, crystallized x64 ELF exit 36), `x86linux_qual` (`OMEGA-CPU-X86 GATE PASS`). |
| [drakestapleton/omega-cpu-arm](https://github.com/drakestapleton/omega-cpu-arm) | `gpu` | `c67be350` | ARM64 CPU optimizer: Grace 20-core `X925/A725`, Graviton4 SVE2, Apple Silicon `a64macos`, big.LITTLE routing, 61 checks / 12 negative controls (`OMEGA-CPU-ARM GATE PASS`). |
| [drakestapleton/omega-amd](https://github.com/drakestapleton/omega-amd) | `gpu` | `2c46309b` | AMD GPU engine: 19/19 MI300X `gfx942` HSACO byte-identity matches + Steam Deck `gfx1033` / ROG Ally `gfx1103` / RDNA3/4 occupancy & TDP contract verifier (`OMEGA-AMD GATE PASS`). |
| [drakestapleton/omega-tensorfold](https://github.com/drakestapleton/omega-tensorfold) | `bridge` | `d675b9cf` | Zero-touch TensorFold Zig + C ABI v2 plugin: Arboris MoE prefetch, SM121 stall floor, `EGP3` cert check, 40 native C ABI v2 checks + 5 1-bit tamper controls (`OMEGA-TENSORFOLD GATE PASS`; Zig `NOT_RUN` where `zig` is absent). |
| [drakestapleton/omega-llamacpp](https://github.com/drakestapleton/omega-llamacpp) | `bridge` | `6db7e93b` | Zero-touch `llama.cpp` / GGML ABI v2 backend (`-DGGML_OMEGA=ON`): 24 pure-OM kernels + `libggml_omega.a`, 500 Q8 dot & 200 0-ULP RMSNorm parity tests, Arboris prefetcher (`OMEGA-LLAMACPP GATE PASS`). |
| [drakestapleton/omega-pytorch](https://github.com/drakestapleton/omega-pytorch) | `bridge` | `e8b9d651` | Zero-touch PyTorch optimizer (`torch.compile(backend="omega")`): `libomega_pytorch.so` (`OMEGA_ABI_2.0`), Helix `EGP3` fusion verifier, static zero-OOM workspace planner, `ArborisMoEPrefetcher` (`OMEGA-PYTORCH GATE PASS`; live `torch` `NOT_RUN` where `torch` is absent). |

## Honest Baseline Measurements (`MEASURED_CLOUD_VM_X86_64`)

Measured on a 2-core Intel Xeon @ 2.30 GHz Linux `x86_64` VM (`ffmpeg 6.1.1`, `gcc 13.2.0`, zero GPU attached; physical MacBook, Steam Deck, and DGX Spark GB10 hardware qualification remains `NOT_RUN` until executed on those devices):

### 1. Real 5-Minute 4K60 (`300.000 s`, `3840x2160 @ 60fps`, `18,000` Frames, YouTube `68 Mbps`)

| Metric | Traditional Single-Stream FFmpeg | Omega Semantic GOP-DAG + LPT + OM-2 Convex Bitrate | Delta |
|---|---:|---:|---|
| Cold Full 5-Min 4K60 Render | `582.74 s` (`30.89 FPS`) | `171.53 s` (`104.94 FPS`, `29` unique dirty / `121` folded) | `3.40x` faster |
| Creator Edit Re-Export (`10 s` = `5/150` GOPs edited) | `582.74 s` (`100%` re-encoded) | `22.41 s` (`803.28 FPS`, `145/150` SHA-256 hits = `0 ms` lossless splice) | `26.01x` faster |
| 4K60 Action Scene (`GOP 10`) Avg / Min PSNR | `49.05 dB` / `40.74 dB` | `54.23 dB` / `53.27 dB` | `+5.18 dB` avg / `+12.53 dB` worst-frame |
| 4K60 Action Scene (`GOP 10`) SSIM / Peak Bitrate | `0.998316` / `150.14 Mbps` | `0.999216` / `126.11 Mbps` | Higher SSIM at `16%` less peak bitrate |

### 2. Scalar `omc` Micro-Kernel Regressions Recorded Honestly (`omega-llamacpp` ABI v2 vs `gcc -O3 -march=native`)

- `ggml_arboris_predict`: `1.71 us`/call (control/prefetch plane).
- `ggml_q8_dot_i32` (4,096 elems, exact parity): `34.90 us` vs `1.29 us` (`27.1x` slower than AVX2 `gcc -O3`).
- `ggml_rmsnorm_f32_bits` (4,096 elems): `100.39 us` vs `7.96 us` (`12.6x` slower than AVX2 `gcc -O3`).
- Takeaway: use `seed/out/omc` for verified control/scheduling/DAG/proof planes; route heavy SIMD inner loops to Omega NG (`seed/ng/`) and hardware media/GPU engines.
