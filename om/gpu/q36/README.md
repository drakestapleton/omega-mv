# Qwen 3.6 35B-A3B FP8 Pure Seeded-Omega Native GB10 Runner & Arboris Prefetcher

`om/gpu/q36/` implements a **100% pure seeded-Omega, zero-CUDA native GB10 runner (`q36-native`)** for **Qwen 3.6 35B-A3B FP8** (`Qwen3_5MoeForConditionalGeneration`: 40 layers, 30 Gated DeltaNet + 10 Full-Attention `hd=256`, `D=2048`, 256 experts, top-8, `vocab=248320`) with **9 SM121 high-speed SASS kernels** (`emit_fast.om`) and an **Arboris online adaptive sum-over-paths expert prefetcher** (`arboris/prefetch.om`).

The seeded compiler (`seed/out/omc`) compiles `native_run.om` directly to a **225 KB statically linked AArch64 ELF executable** (`ldd: not a dynamic executable` — zero `libcuda.so.1`, zero `libc`, zero Python, zero C, zero Rust). It opens `/dev/nvidiactl`, `/dev/nvidia0`, and `/dev/nvidia-uvm` through Omega's native Blackwell stack (`gpu/nvidia/native/nvrm/context.om`, `gpu/nvidia/native/blackwell/{vector,launch,batch}.om`), runs a live 9-kernel GB10 numerical parity self-test + Arboris self-test, and replays pre-recorded native GPFIFO QMD command buffers for all 40 layers.

## SM121 Kernels (`emit_fast.om`)

- **`bf16_gemv_fast`** (`a`): Packed BF16 streaming GEMV (`LDG.E.128`, SMEM `x`, 8 warps × 4 rows = 32 rows/CTA; achieves **`224.2 GB/s` = `94.6%`** of GB10's `236.9 GB/s` ceiling on the 1.017 GB `[248320, 2048]` BF16 `lm_head`).
- **`fp8_b128_gemv_fast`** (`b`): Streaming FP8 E4M3FN block-128×128 GEMV (`LDG.E.64` 128B full-cacheline coalescing, SMEM `x` + SMEM 256-entry FP32 LUT, batched 8-`LDS` decode, 1 scale load per 128-element tile; achieves **`206.0 GB/s` = `87.0%`** of ceiling on the 0.509 GB `[248320, 2048]` FP8 `lm_head` screen).
- **`fp8_b128_grouped8_fast`** (`c`): 1-launch 8-expert FP8 block-128×128 MoE GEMV reading `ids[8]` directly on GPU (`gate_up [8, 1024, 2048]` and `down [8, 2048, 512]`).
- **`router_top8_256_fast`** (`d`): 1-launch 256-expert Softmax + Top-8 + Renormalize (`Block=256`, warp+SMEM reductions).
- **`swiglu8_q36_fast`** (`e`): Fused 8-expert SwiGLU (`silu(gate) * up * weight`).
- **`moe_combine_rms_fast`** (`f`): Fused 8-expert sum + shared-expert + residual add + RMSNorm (`D=2048`) in 1 CTA.
- **`gdn_step_bf16_fast`** (`g`): Fused Gated DeltaNet 1-token step with coalesced `[h, r, c]` packed BF16 state (`[32, 128, 128]` = 1 MiB/layer, cutting state bandwidth `126 MB -> 63 MB/tok` across 30 GDN layers).
- **`attn_hd256_split_fast` & `attn_hd256_reduce_gate_fast`** (`h`, `i`): Split-K Flash-Decoding for `16 Q / 2 KV`, `hd=256`, BF16 KV cache + fused sigmoid output gate.

## Arboris Prefetcher (`arboris/prefetch.om`)

Online adaptive sum-over-paths co-activation prefetcher (`39` cross-layer transitions `L -> L+1` × `256` source experts × `16` Space-Saving slots = `159,744` uints). Measured overhead across all 40 layers: **`101 µs/tok`** (`0.10 ms/tok`, `0.46%` of decode latency) with **`93%` online hit rate** on repeating domain transitions.

## Verified GB10 Silicon Receipts (Zero CUDA, `nvrm_errors_delta: 0`)

- Receipt: `/home/drakestapleton/yardsticks/receipts/2026-11-21-q36-native-zero-cuda-victory.json` (exclusive quiet Spark window `20261121T183329Z-c59a8b`, `exit: 0`, `nvrm_errors_delta: 0`, static AArch64 ELF `ldd: not a dynamic executable`).
- Receipt (coalesced GDN + fused `qkvz`): `/home/drakestapleton/yardsticks/receipts/2026-11-21-q36-native-zero-cuda-fast.json` (window `20261121T183447Z-189b63`).

| Configuration (40 layers, 30 GDN BF16-state + 10 Full-Attn `T=1024`, cold 4-bank weights) | Median Latency | Throughput | Notes |
|---|---:|---:|---|
| 40L Backbone (`2.57 GB/tok`) | `19.46 ms/tok` | **`51.38 tok/s`** | `finite=OK`, zero CUDA |
| 40L + FP8 Two-Pass `lm_head` (`3.08 GB/tok`) | `21.93 ms/tok` | **`45.59 tok/s`** | FP8 head delta: `2.47 ms` (`206.0 GB/s`, `87.0%` ceiling) |
| 40L + Full 248k BF16 `lm_head` (`3.59 GB/tok`) | `23.92 ms/tok` | **`41.81 tok/s`** | BF16 head delta: `4.54 ms` (`224.2 GB/s`, `94.6%` ceiling) |
| Arboris 40L × 256E online prefetcher | `0.101 ms/tok` | — | `93%` hit rate, pure OM-2 |

*(Measurements use checkpoint-exact synthetic weights across 4 cold weight banks > 110× L2; real-checkpoint end-to-end greedy-parity measurements on `~/models/qwen3.6-35b-a3b-fp8-95a723d0` are recorded in `2026-11-21-q36-35b-verified-kit.json`: `50.43 tok/s` `N=1`, `105.31 tok/s` `N=4`, `119.39 tok/s` `N=8`.)*

## Build and Run

```sh
sh seed/omega-from-seed.sh
sh om/gpu/q36/build.sh build/q36
spark-window run build/q36/q36-native
```
