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

## Real-Weight End-to-End 35B Decoder (`om/gpu/q36/decode/` -> `q36-decode`)

`q36-decode` (`460 KB` static AArch64 ELF, `ldd: not a dynamic executable`, zero CUDA / zero `libc` / zero C / zero Rust / zero Python) loads **all 40 real layers** (`layers-0..39.safetensors`, `~33.6 GB`) + `outside.safetensors` (`1.017 GB` BF16 `lm_head` + `embed_tokens` + `norm.weight`) directly from `~/models/qwen3.6-35b-a3b-fp8-95a723d0` into GB10 UVM, quantizes `lm_head` on-GPU to W4 block-32 (`1.26 ms` two-pass exact), and replays **ONE single pre-recorded native GPFIFO submit for all 40 real layers + `lm_head`** (100% GPU-resident `QDW_X`, zero CPU hops between layers).

Supports two verified real-weight execution modes in the same static binary:
- **Exact FP8 mode** (`q36-decode <dir> 24`): `10` UVM slabs (`~34.7 GB`), fused `in_proj_qkvz [12288, 2048]`, 1-launch strided 8-expert FP8 MoE (`qFp8B128Grouped8Strided`), GPU router (`qRouterTop8Lex`), GPU Full-Attention (`qFaPrepKvGpu` + `qFaAttendGpu`), and Top-2/chunk W4 Two-Pass Exact `lm_head` (`128` BF16 rescores).
- **Full-W4 mode** (`q36-decode <dir> 24 w4`): on-GPU FP8→W4 block-32 quantization (`qFp8ToW4B32Quant`) during load (`13.3 s` total load+quantize, `~19.5 GB` VRAM resident), 4-row-per-warp zero-stall `4× LDG.E.128` W4 kernels with interleaved 4-row `qW4MacBlock` (`qW4B32Gemv4R`, `qW4B32Grouped94R`), fused SwiGLU zero-loop 4-row/half-warp 9-expert `down_proj` (`qW4B32Grouped9Dn4R`, folding `shared_expert` into slot `256`), fused `FA Q|K|V [9216, 2048]`, fused high-occupancy 33-CTA `router+sh_gate [257, 2048]` (`qBf16Gemv1R`), 2×-unrolled exact FP32 GDN state with fused `decay/beta`, and fused inter-layer `qMoeCombine9RmsFast` (`-40` RMSNorm launches).

Verified on live Spark GB10 silicon (exclusive quiet window `20261121T232155Z-317143`, `exit: 0`, quiet machine; note: still uses NVIDIA open kernel modules 580.173.02 + signed GSP firmware):
- Prompt: `<|im_start|>user\nWhat is the capital of France?<|im_end|>\n<|im_start|>assistant\n<think></think>` (`17` tokens).
- **W4 Two-Pass Exact `lm_head` parity on real 40L hidden state:** **`PARITY=EXACT` vs Full BF16 (`tok=271`)** in both Exact FP8 and Full-W4 modes.
- **Generated output (bit-for-bit identical 10-token answer in both Exact FP8 and Full-W4):** `271 760 6511 314 9338 369 2972 57590 159034 248046` → **`"\n\nThe capital of France is **Paris**.<|im_end|>"`**.

| Real-Weight 35B-A3B Zero-CUDA Milestone | Latency | Throughput | Speedup | Parity & Output |
|---|---:|---:|---:|---|
| Initial hybrid real-weight decoder (`20261121T220035Z-0f6897`) | `122.0 ms/tok` | `8.20 tok/s` | `1.00×` | `PARITY=EXACT` (`tok=271`), `**Paris**.` |
| GPU FP32 GDN + conv1d + 20-QMD MoE + spin-poll (`20261121T221800Z-5dd1ee`) | `34.0 ms/tok` | `29.41 tok/s` | `3.59×` | `PARITY=EXACT` (`tok=271`), `**Paris**.` |
| Wave 1: 100% GPU-resident `QDW_X` (`qRmsNormAddFast` + `qGdnDecayBetaFast`) | `31.0 ms/tok` | `32.26 tok/s` | `3.94×` | `PARITY=EXACT` (`tok=271`), `**Paris**.` |
| Wave 2: 1-launch strided FP8 MoE + GPU `qRouterTop8Lex` | `26.0 ms/tok` | `38.46 tok/s` | `4.69×` | `PARITY=EXACT` (`tok=271`), `**Paris**.` |
| **Wave 3–4: 1-Submit 40L Exact FP8** (`20261121T232155Z-317143`) | **`20.827 ms/tok`** | **`48.01 tok/s`** | **`5.86×`** | **`PARITY=EXACT` (`tok=271`), `**Paris**.`** |
| Wave 4 (fixed): On-GPU Full-W4 (`19.5 GB` VRAM, 1-submit) | `17.952 ms/tok` | `55.70 tok/s` | `6.80×` | `PARITY=EXACT` (`tok=271`), `**Paris**.` |
| Wave 5: 4-row/warp W4 + 9-expert MoE + fused FA `Q\|K\|V` + fused router | `16.179 ms/tok` | `61.80 tok/s` | `7.54×` | `PARITY=EXACT` (`tok=271`), `**Paris**.` |
| **Wave 6–11: Full-W4 Final + Live Arboris** (`20261122T002657Z-c1ec5b`, fused SwiGLU + `qMoeCombine9RmsFast` + 33-CTA `qBf16Gemv1R` + `LDG.E.128` SMEM + interleaved `qW4MacBlock` + `QDW_TRACE` live Arboris) | **`14.731 ms/tok`** | **`67.88 tok/s`** | **`8.28×`** | **`PARITY=EXACT` (`tok=271`), `**Paris**.`, Arboris `42–44%`** |

## High-Speed SM121 Tensor-Core Chunked Prefill + Live Arboris (`emit_prefill.om`, `decode/prefill_host.om`)

`emit_prefill.om` adds **17 pure seeded-Omega SM121 prefill kernels** (`modes 130..146`, `kids 26..42`, `B_MAX = 512` tokens/chunk in a `128 MB` UVM workspace with pre-recorded `slot 3`/`slot 4` GPFIFO packets for zero per-chunk CPU packet recording):
- **SM121 Tensor-Core W4 & BF16 GEMMs (`qPreW4GemmHmma`, `qPreBf16GemmBatch`):** `HMMA.16816.F32.BF16` (`op 16`) + `F2FP.BF16.F32.PACK_AB` (`op 61`) + `LDG.E.128` (`op 57`) with unconditional 4-tile dense path and pipelined `>=6`-cycle W4 dequantization.
- **SM121 Tensor-Core Flash-Attention-2 (`qPreFaPrepQBatch` + `qPreFaAttendHmma`):** Full `HMMA.16816` for BOTH `S = Q @ K^T` and `O = alpha * O + P @ V` (`16 Q-rows × 64 KV-tokens`, 8 warps, half-warp `SHFL.BFLY` online softmax, 8-in-flight transposed `V_tr` loads, exact causal mask + `sigmoid(gate)` epilogue).
- **Zero-Barrier Warp-Resident Chunked GDN (`qPreGdnStepBatch`):** Each 32-lane warp owns all 128 K/Q dims (`4` dims/lane via `LDG.E.128`) × 4 contiguous V-cols (`16` FP32 state floats loaded ONCE and stored ONCE per 512-token chunk); all `dot_k` and `o` reductions use pure intra-warp `SHFL.BFLY` with **zero `BAR.SYNC` and zero SMEM** (`3.53×` faster than multi-warp GDN).
- **Deduplicated Hot-First Tensor-Core 256-Expert MoE (`qPreMoeBuildGroups` + `qPreW4MoeHmma`):** Zero-atomic GPU expert bucketing with 3-pass Hot-First `EXP_ORDER[0..255]` (`cnt > 32` heavy experts launch first to eliminate tail-straggler wave bubbles, `cnt == 0` exits in 2 cycles).
- **Async Overlapped Live Arboris (Always On):** Every prompt token (`0..N-1`) emits its 40-layer top-8 routing trace into `QP_TRACE`; sparse-touch `q36ArbPredict` (`6×` faster CPU) runs asynchronously while the GPU executes the next prefill chunk (and overlaps the final prefill chunk behind decode step 1 in `q36-serve`), hiding CPU Arboris latency while warming the 40-layer co-activation graph across the entire prompt.
- **2-Byte Indexed Pure-OM-2 ByteLevel BPE Tokenizer (`serve/tokenizer.om`):** Replaces linear vocab scans with a `65,536`-bucket 2-byte prefix index (`~20,000×` faster tokenization on long prompts up to 128K).

Verified on live Spark GB10 silicon (exclusive quiet windows `20261122T025449Z-5436d0` & `20261122T025801Z-4c9b80`, `exit: 0`, `NVRM: Xid` delta `0`; still uses NVIDIA open kernel modules 580.173.02 + signed GSP firmware):

| Real-Weight 40L Full-W4 Prefill & Decode (128K Context + Live Arboris) | Wall Time | Throughput | Speedup vs Seq W4 | Live Arboris |
|---|---:|---:|---:|---|
| 17-tok prompt parity + 24-tok decode (`q36-decode ... 24 w4`) | `14.72–14.91 ms/tok` | **`67.09–67.91 tok/s`** | `PARITY=EXACT` (`tok=271`) | `37%` (cold 17-tok) |
| **`1,024`-token real-weight prefill (`q36-decode ... 1024 p`)** | **`550–559 ms`** | **`1,831–1,861 tok/s`** | **`25.1×`** | **`52%`** (`97 ms` overlapped) |
| **`4,096`-token real-weight prefill (`q36-decode ... 4096 p`)** | **`2,255–2,290 ms`** | **`1,788–1,816 tok/s`** | **`24.5×`** | **`51%`** (`433 ms` overlapped) |
| **`16,384`-token (16K) real-weight prefill (`q36-decode ... 16384 p`)** | **`14,573–14,580 ms`** | **`1,123–1,124 tok/s`** | **`15.2×`** | **`50%`** (`1,986 ms` overlapped) |
| Live HTTP `1,681`-tok 4-chunk needle recall + `32`-tok decode (`20261122T030412Z-7e0119`) | `1,918 ms` total | exact needle recall | 4 chunks (`512×3 + 145`) | **`40%`** (`218,493 / 534,056`) |

## Installed 35B Package + OpenAI HTTP Server (`om/gpu/q36/serve/` -> `q36-serve`, `q36-35b`)

`q36-serve` (`715 KB` static AArch64 ELF, `ldd: not a dynamic executable`, zero CUDA / zero `libc` / zero C / zero Python) wraps the 40-layer Full-W4 (`67.1–67.9 tok/s` decode, **`1,831–1,861 tok/s` 1K–4K prefill**, `~19.5 GB` weights + `5.37 GB` 128K KV cache + `32 MB` 128K RoPE + `128 MB` prefill workspace, default) / Exact FP8 (`48.09 tok/s`, `--fp8`) engine + **live Arboris online co-activation prefetcher (always enabled)** + **2-byte indexed pure OM-2 ByteLevel BPE tokenizer** (`tokenizer.om`, `248,044` vocab) in an OpenAI-compatible HTTP server (`GET /health`, `GET /v1/models`, `POST /v1/chat/completions`, **`131,072`-token (`128K`) context window**).

Verified on live Spark GB10 silicon (exclusive quiet window `20261122T025801Z-4c9b80`, `exit: 0`, quiet machine, `NVRM: Xid` delta `0`; still uses NVIDIA open kernel modules 580.173.02 + signed GSP firmware):
- `q36-35b --self-test` (128K context + `pos = 131,071` boundary pass + Tensor-Core prefill + Live Arboris): `Prompt 0: "\n\nThe capital of France is **Paris**."`, `Prompt 1: "\n2 + 2 = 4"`, **`Live Arboris: hits=6540 / tot=15752 (41%)`**, `PASS`.
- Live HTTP E2E (`GET /health`, `GET /v1/models`, `POST /v1/chat/completions`): reports `"context_window":131072`, `"arboris_enabled":true`, `"precision":"w4"`, returns exact completion `"\n\nThe capital of France is **Paris**."`, `1,077`-tok prompt in `728 ms` (`arboris_hit_pct: 46`), and `1,681`-tok 4-chunk needle-in-a-haystack recall (`Captain Elena Vance`, `Aurora-742`) in `1,918 ms` (`arboris_hit_pct: 40`).
- Sustained load soak (window `20261121T233252Z-375404`, `NVRM: Xid` delta `0`): Full-W4 `20/20` bit-exact turns (`1,000` gen toks) at `67.59 tok/s` (`46–49 °C`, `32 W`, `2548 MHz`); Exact FP8 `10/10` bit-exact turns (`500` gen toks) at `48.09 tok/s`; Full-W4 under concurrent 8-core CPU + 512 MB RAM burn `10/10` bit-exact turns at `64.51 tok/s`.

## Build, Install, and Run

```sh
sh seed/omega-from-seed.sh
sh om/gpu/q36/build.sh build/q36
sh om/gpu/q36/install-spark.sh .   # installs ~/.local/opt/q36/, ~/.local/bin/q36-35b, motor-revival.service (:18091)
q36-35b --self-test                # Full-W4 default + Live Arboris self-test
q36-35b --port 18091               # Start OpenAI HTTP server (Full-W4 + Live Arboris; pass --fp8 for Exact FP8)
systemctl --user start motor-revival
```
