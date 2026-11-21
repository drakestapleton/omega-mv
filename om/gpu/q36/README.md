# Qwen 3.6 35B-A3B FP8 Pure Seeded-Omega Native GB10 Runner & Arboris Prefetcher

`om/gpu/q36/` implements a **100% pure seeded-Omega, zero-CUDA native GB10 runner (`q36-native`)** for **Qwen 3.6 35B-A3B FP8** (`Qwen3_5MoeForConditionalGeneration`: 40 layers, 30 Gated DeltaNet + 10 Full-Attention `hd=256`, `D=2048`, 256 experts, top-8, `vocab=248320`) with **13 SM121 high-speed SASS kernels** (`emit_fast.om`) and an **Arboris online adaptive sum-over-paths expert prefetcher** (`arboris/prefetch.om`).

The seeded compiler (`seed/out/omc`) compiles `native_run.om` directly to a **281 KB statically linked AArch64 ELF executable** (`ldd: not a dynamic executable` — zero `libcuda.so.1`, zero `libc`, zero Python, zero C, zero Rust). It opens `/dev/nvidiactl`, `/dev/nvidia0`, and `/dev/nvidia-uvm` through Omega's native Blackwell stack (`gpu/nvidia/native/nvrm/context.om`, `gpu/nvidia/native/blackwell/{vector,launch,batch}.om`), runs a live 11-kernel GB10 numerical parity self-test + Arboris self-test, and replays pre-recorded native GPFIFO QMD command buffers for all 40 layers.

## SM121 Kernels (`emit_fast.om`)

- **`bf16_gemv_fast`** (`a`): Packed BF16 streaming GEMV (`LDG.E.128`, SMEM `x`, 8 warps × 4 rows = 32 rows/CTA; achieves **`224.2 GB/s` = `94.6%`** of GB10's `236.9 GB/s` ceiling on the 1.017 GB `[248320, 2048]` BF16 `lm_head`).
- **`fp8_b128_gemv_fast`** (`b`): Streaming FP8 E4M3FN block-128×128 GEMV (`LDG.E.64` 128B full-cacheline coalescing, SMEM `x` + SMEM 256-entry FP32 LUT, batched 8-`LDS` decode, 1 scale load per 128-element tile; achieves **`206.0 GB/s` = `87.0%`** of ceiling on the 0.509 GB `[248320, 2048]` FP8 `lm_head` screen).
- **`fp8_b128_grouped8_fast`** (`c`): 1-launch 8-expert FP8 block-128×128 MoE GEMV reading `ids[8]` directly on GPU (`gate_up [8, 1024, 2048]` and `down [8, 2048, 512]`).
- **`router_top8_256_fast`** (`d`): 1-launch 256-expert Softmax + Top-8 + Renormalize (`Block=256`, warp+SMEM reductions).
- **`swiglu8_q36_fast`** (`e`): Fused 8-expert SwiGLU (`silu(gate) * up * weight`).
- **`moe_combine_rms_fast`** (`f`): Fused 8-expert sum + shared-expert + residual add + RMSNorm (`D=2048`) in 1 CTA.
- **`gdn_step_bf16_fast`** (`g`): Fused Gated DeltaNet 1-token step with coalesced `[h, r, c]` packed BF16 state (`[32, 128, 128]` = 1 MiB/layer, cutting state bandwidth `126 MB -> 63 MB/tok` across 30 GDN layers).
- **`attn_hd256_split_fast` & `attn_hd256_reduce_gate_fast`** (`h`, `i`): Warp-only (`Block=32`, `SMEM=0`, zero inner-loop `BAR.SYNC`, `LDG.E.128` for K & V) Split-K Flash-Decoding for `16 Q / 2 KV`, `hd=256`, BF16 KV cache + fused sigmoid output gate.
- **`w4_lmhead_screen_fast` & `bf16_rescore_cands`** (`j`, `k`): Straight-line unrolled 2-block `LDG.E.128` W4 block-32 `lm_head` screen (`0.286 GB`) + Top-64 exact BF16 rescore (`+1.23–1.36 ms` end-to-end inside `q36-native` = **`233.3 GB/s` / `98.5%`** of GB10's `236.9 GB/s` ceiling).
- **`w4_b32_grouped8_fast`** (`l`): 1-launch 8-expert W4 block-32 MoE GEMV (16 half-warp lanes × 32 weights/lane via `LDG.E.128`, zero LUT, `1` iter for `K=512` and `4` iters for `K=2048`), shrinking routed MoE traffic `1.015 GB -> 0.286 GB` (`-2.18 ms/tok`).
- **`w4_b32_gemv_fast`** (`m`): Streaming W4 block-32 dense-trunk GEMV (`LDG.E.128`, 16 half-warp lanes × 32 weights/lane, zero LUT, zero SMEM) for all dense projections (`in_proj_qkvz`, `attn_qkvg`, `out_proj`, `shared_gu`, `shared_dn`), shrinking total 40L backbone traffic `1.85 GB -> 0.79 GB` (`-3.08 ms/tok`) and full-token traffic with W4 Two-Pass Exact `lm_head` to `1.07 GB/tok`.

## Arboris Prefetcher (`arboris/prefetch.om`)

Online adaptive sum-over-paths co-activation prefetcher (`39` cross-layer transitions `L -> L+1` × `256` source experts × `16` Space-Saving slots = `159,744` uints). Measured overhead across all 40 layers: **`47–100 µs/tok`** (`0.047–0.10 ms/tok`, `0.31%` of decode latency) with **`93%` online hit rate** on repeating domain transitions.

## Verified GB10 Silicon Receipts (Zero CUDA)

- Latest receipt (Full-W4 40L trunk + W4-MoE + W4 Two-Pass Exact `lm_head` + warp-only `LDG.E.128` HD256 attn): `/home/drakestapleton/yardsticks/receipts/2026-11-21-q36-native-full-w4.json` (exclusive quiet Spark window `20261121T211943Z-2646ce`, `exit: 0`, `nvrm_errors_delta: 4`, `281 KB` static AArch64 ELF `ldd: not a dynamic executable`, `11/11` live GB10 parity PASS).
- Earlier zero-CUDA receipts (`nvrm_errors_delta: 0`): `2026-11-21-q36-native-w4-moe.json` (window `20261121T211501Z-f26c8b`), `2026-11-21-q36-native-w4-warp-attn.json`, `2026-11-21-q36-native-zero-cuda-victory.json`, `2026-11-21-q36-native-zero-cuda-fast.json`.

| Configuration (40 layers, 30 GDN BF16-state + 10 Full-Attn `T=1024`, cold 4-bank weights) | Median Latency | Throughput | Notes |
|---|---:|---:|---|
| 40L FP8 Backbone (`2.57 GB/tok`) | `19.21 ms/tok` | **`52.05 tok/s`** | `finite=OK`, zero CUDA |
| 40L FP8 + W4 Two-Pass Exact `lm_head` (`2.86 GB/tok`) | `20.45–20.59 ms/tok` | **`48.55–48.91 tok/s`** | W4 head delta: `+1.23 ms` (`98.5%` ceiling) |
| 40L W4-MoE Backbone (`1.85 GB/tok`) | `17.04 ms/tok` | **`58.69 tok/s`** | W4 routed MoE saves `-2.18 ms/tok` |
| 40L W4-MoE + W4 Two-Pass Exact `lm_head` (`2.13 GB/tok`) | `18.29–18.39 ms/tok` | **`54.36–54.67 tok/s`** | Beats C/Rust `aien-serve-http` (`50.43 tok/s`) with ZERO CUDA |
| **40L Full-W4 Backbone (`0.79 GB/tok`)** | **`14.06 ms/tok`** | **`71.12 tok/s`** | W4 dense trunk (`w4_b32_gemv_fast`) + W4 MoE |
| **40L Full-W4 + W4 Two-Pass Exact `lm_head` (`1.07 GB/tok`)** | **`15.21 ms/tok`** | **`65.75 tok/s`** | **`+1.15 ms` W4 head delta; `1.30×` faster than `aien-serve-http` with ZERO CUDA!** |
| Arboris 40L × 256E online prefetcher | `0.047 ms/tok` | — | `93%` hit rate, pure OM-2 |

*(Measurements use checkpoint-exact synthetic weights across 4 cold weight banks > 110× L2; real-checkpoint end-to-end greedy-parity measurements on `~/models/qwen3.6-35b-a3b-fp8-95a723d0` are recorded in `2026-11-21-q36-35b-verified-kit.json`: `50.43 tok/s` `N=1`, `105.31 tok/s` `N=4`, `119.39 tok/s` `N=8`.)*

## Real-Weight W4 Two-Pass Exact `lm_head` (`om/gpu/q36/head/` -> `q36-head`)

`q36-head` (`162 KB` static AArch64 ELF, zero CUDA/libc) loads the real `lm_head.weight` (`BF16 [248320, 2048]`, `1.017 GB`) and `model.language_model.norm.weight` directly from `outside.safetensors`, quantizes it on-GPU to **block-32 symmetric INT4 (`0.286 GB`, `3.56×` smaller)** in **`10.16 ms`**, screens all `248,320` vocabulary rows with straight-line unrolled 2-block `LDG.E.128` (`dot(q, x) - 8*sum(x)`), and rescores the top-64 candidates in exact BF16.

- Receipt: `/home/drakestapleton/yardsticks/receipts/2026-11-21-q36-head-w4-top64.json` (window `20261121T184921Z-bdb379`, `exit: 0`, `nvrm_errors_delta: 0`).
- **Real-weight parity:** **`8/8` (`100%`) BIT-EXACT `argmax` parity** against Full BF16 across real embedding probes.
- **Full BF16 `lm_head` (`1.017 GB`):** `4.453 ms` (`228.4 GB/s`, `96.4%` of `236.9 GB/s` ceiling).
- **W4 Two-Pass Exact `lm_head` (`0.286 GB` + Top-64 BF16 rescore):** **`1.258 ms`** (`227.6 GB/s`, `96.1%` of ceiling) — **`3.54×` faster than Full BF16** (`-3.195 ms/tok` saved per token) and **`1.96×` faster than FP8 screen** (`2.47 ms`).

## Build and Run

```sh
sh seed/omega-from-seed.sh
sh om/gpu/q36/build.sh build/q36
spark-window run build/q36/q36-native
spark-window run build/q36/q36-head ~/models/qwen3.6-35b-a3b-fp8-95a723d0/outside.safetensors
```
