# Inkling-2-Mini Seeded Omega SM121 Kernels for GB10

These **43 SM121 cubins** (`22` baseline reference kernels in `emit.om` + `21` high-speed pipelined/fused kernels in `emit_fast.om`) plus the **zero-CUDA native GB10 runner (`native_run.om` → `inkling2-native`)** implement the complete operator set and end-to-end 48-logical-layer execution path for Thinking Machines Lab's **Inkling-2-Mini** (`thinkingmachines/Inkling-2-Mini`, architecture `Inkling2LoopForConditionalGeneration`) in pure seeded Omega (`.om`) with no C, no Python, no `libc`, and no CUDA (`libcuda.so.1` / `nvcc` / `ptxas`) anywhere on the native path.

The seeded compiler (`seed/out/omc`) compiles `emit.om`, `emit_fast.om`, and `native_run.om` with the repository's SM121 encoder (`om/encoder/bw_enc_sm121.om`) and native NVRM/UVM/GPFIFO/QMD units (`gpu/nvidia/native/`). `seed/kflow/kpack.om` packs each SASS image into an SM121 `.cubin`. `lookup.om` generates the shared 272-entry FP32 decode table (`256` E4M3FN + `16` E2M1).

## Zero-CUDA native GB10 runner (`native_run.om` → `inkling2-native`)

`native_run.om` compiles with `seed/out/omc` directly to a **statically linked AArch64 ELF executable** (`ldd`: `not a dynamic executable` — zero `libcuda.so.1`, zero `libc`, zero Python, zero C). It embeds all 21 fast SM121 SASS kernels from `emit_fast.om`, opens `/dev/nvidiactl`, `/dev/nvidia0`, and `/dev/nvidia-uvm` directly through Omega's native Blackwell stack (`gpu/nvidia/native/nvrm/context.om`, `gpu/nvidia/native/blackwell/{vector,launch,batch}.om`), runs a 14-kernel live-silicon numerical parity self-test, and replays pre-recorded native GPFIFO QMD command buffers for all 48 logical Inkling-2-Mini layers (both with and without the full 201,024-row BF16 unembed + `logit_softcap`).

## High-speed SM121 suite (`emit_fast.om`, `kernels_fast.list`, `check_fast.py`)

`emit_fast.om` targets GB10's LPDDR5X memory bandwidth ceiling (`236.9 GB/s` measured STREAM / `273 GB/s` nominal) with pipelined SM121 scoreboards, `BSSY`/`BSYNC` reconvergence, `LDG.E.128`/`LDG.E.64`, SMEM activation & LUT staging, warp `SHFL.DOWN`/`SHFL.BFLY`, Split-K `bar0`/`bar2` overlapped Flash-Decoding, and pre-recorded native GPFIFO QMD replay (or single-submit CUDA Graph in the legacy `check_fast.py` comparison harness):

- **Packed BF16 streaming GEMV:** `bf16_gemv_fast` (`LDG.E.128`, SMEM `x`, 8 warps × 4 rows = 32 rows/CTA; hits `239.8–249.1 GB/s` on cold 926 MB `unembed [201024, 2304]`).
- **Grouped 8-expert NVFP4 & MXFP8 GEMV:** `nvfp4_gemv_grouped8_fast` (`LDG.E.64` 128B full-cacheline coalescing, 16 weights = 1 scale block per lane, batched 8-`LDS` LUT lookup, 1-launch all 8 experts) and `mxfp8_gemv_grouped8_fast` (`LDG.E.64`, batched 8-`LDS` LUT lookup, register `UE8M0` decode; `239.3 GB/s` on `8×2304×2304`).
- **Split-K Flash-Decoding + fused `attn_gate`:** `inkling_attn_flash_bf16` (1-launch BF16 KV), `inkling_attn_flash_split_bf16` (Split-K `Grid=(H,S,B)` with `bar 0` K + `bar 2` V async overlap; `271.5 GB/s` at `T=8192, S=8`), and `inkling_attn_reduce_bf16` (1-warp log-sum-exp combine + learned sink + optional fused `attn_gate`).
- **Parallel routing & fused glue:** `router_top8_fast` (pair with 4-CTA `bf16_gemv_fast` for `0.0125 ms` total vs `0.313 ms` baseline), `router_fast` (1-launch BF16 router), `attn_res_fast` (`LDG.E.128` 256-thread warp-parallel, `0.0104 ms` vs `1.784 ms` baseline), `rms_norm_fast`, `l2_clip_fast` (1-warp/head), `nvfp4_quant_fast`, `mxfp8_quant_fast`, `softcap_swiglu8_fast`, `glue_sconv_fast`, `sconv_dynamic_fast`, `msg_gate_fast`, `logit_softcap_fast`, `moe_combine8_sconv_fast` (fused 8-expert sum + static `sconv` + state), `sconv_rmsnorm_fast` (fused static `sconv` + state + register-resident `D=2304` RMSNorm), and `swiglu8_nvfp4_quant_fast` (fused 8-expert softcapped SwiGLU + SMEM-staged `fouroversix_mae` NVFP4 quantizer).

### Verified GB10 silicon performance (synthetic checkpoint-shaped weights, 3.3 GB across 4 banks > 135× L2, all 128 routed experts)

Native zero-CUDA receipt: `/home/drakestapleton/yardsticks/receipts/2026-11-21-inkling2-native-zero-cuda-final.json` (exclusive quiet Spark window `20261121T145813Z-cbce03`, `exit: 0`, `nvrm_errors_delta: 0`, static AArch64 ELF `ldd: not a dynamic executable`).
Legacy `libcuda.so.1` CUDA Graph comparison receipt: `/home/drakestapleton/yardsticks/receipts/2026-11-21-inkling2-fast-final.json` (exclusive quiet Spark window `20261121T144332Z-3ba45b`, `nvrm_errors_delta: 0`).

| Configuration (48 logical layers, `T_swa=1024`, `T_full=4096`) | Median latency | Throughput | Effective DRAM BW | Speedup vs baseline |
|---|---:|---:|---:|---:|
| Baseline seeded Omega (`bench_stress.py`, `2026-11-21-inkling2-speed-stress.json`) | `384.55 ms/tok` | `2.60 tok/s` | `12.3 GB/s` | `1.0×` |
| **Pure-Omega Native GPFIFO — ZERO CUDA (`inkling2-native`, 48L, no unembed, `4.72 GB/tok`)** | **`25.84 ms/tok`** | **`38.69 tok/s`** | **`182.6 GB/s`** (`77.1%` of `236.9`) | **`14.9×`** |
| **Pure-Omega Native GPFIFO — ZERO CUDA (`inkling2-native`, 48L + full 201k BF16 `unembed`, `5.65 GB/tok`)** | **`29.76 ms/tok`** | **`33.60 tok/s`** | **`189.9 GB/s`** (`80.1%` of `236.9`) | — |
| Fast suite — Eager via `libcuda.so.1` (48L, no unembed, `4.72 GB/tok`) | `26.59 ms/tok` | `37.61 tok/s` | `177.5 GB/s` (`74.9%` of `236.9`) | `14.5×` |
| Fast suite — Single-Submit CUDA Graph via `libcuda.so.1` (48L, no unembed, `4.72 GB/tok`) | `24.30 ms/tok` (`p95 25.34 ms`) | `41.16 tok/s` | `194.2 GB/s` (`82.0%` of `236.9`) | `15.8×` |
| Fast suite — Single-Submit CUDA Graph via `libcuda.so.1` (48L + full 201k BF16 `unembed`, `5.65 GB/tok`) | `28.21 ms/tok` (`p95 28.73 ms`) | `35.45 tok/s` | `200.3 GB/s` (`84.5%` of `236.9`) | — |

*(Physical zero-overhead GB10 DRAM roofline at `236.9 GB/s`: `19.92 ms/tok` / `50.2 tok/s` without unembed, `23.85 ms/tok` / `41.9 tok/s` with full 201k BF16 unembed. Measurements used synthetic checkpoint-shaped weights; real `Inkling-2-Mini` weights were not present on Spark.)*

## Architecture coverage

- **NVFP4 (`modelopt`, layers `0..19` MoE experts):** `nvfp4_quant` (block-16 `E2M1`, `E4M3FN` block scales, `fouroversix_mae` 4-vs-6 scale selection, per-row outer scale) and `nvfp4_gemm` (packed `E2M1 x E2M1`, block-16 `E4M3` scales + FP32 outer scale product).
- **MXFP8 (layers `20..23` MoE experts):** `mxfp8_quant` (group-32 `E4M3FN`, `UE8M0` scales) and `mxfp8_gemm` (`[32, 32]` `UE8M0` scales).
- **Dense BF16 / FP32 projections:** `dense` (`M x K` x `N x K` -> `M x N` FP32), `bf16_pack`, `bf16_unpack`.
- **Normalization & clipping:** `rms_stat` (`eps=1e-6`), `rms_apply`, `rms_unweighted` (`use_value_norm_no_gamma`, `attn_res`, `msg_gate`), `l2_clip` (L2 norm clip + optional per-head learned scale + optional `log_scaling` tau).
- **Short causal convolutions (`k=4`):** `sconv_static` (`(conv + x) / sqrt(5)`) and `sconv_dynamic` (`(conv + x) / 3.0`, per-head dynamic taps for full-attention layers `5, 11, 17, 23`).
- **Hybrid 3:1 GQA attention (`24 Q / 8 KV`, `hd=128`):** `inkling_attn_scores` (3:1 or arbitrary GQA, relative-position bias `rel_extent=1024`, sliding window `W=1024` or full causal mask), `inkling_attn_mix` (online softmax with per-token learned attention sink), `attn_gate` (`a * sigmoid(g)`).
- **MoE routing & activation:** `route8` (`128` experts, `top-8`, sigmoid + FP32 `e_score_correction_bias`, renormalization + `route_scale=8.0`), `softcap_swiglu` (`4*tanh(g/4) * sigmoid(g) * 25*tanh(u/25) * w`, arbitrary `I` including `1152`), `moe_combine8` (8-expert sum, arbitrary `D` including `2304`).
- **Looped core & residuals:** `attn_res` (block & cross-pass attention residual aggregation, `Q in {1, 3, 4}`, `K <= 16`, `D=2304`), `msg_gate` (`(1 - tanh(f)) * h + tanh(m) * msg`), `logit_softcap` (`cap * tanh(x / cap)`, `cap=30.0`).
- **Arboris expert prefetching (`arboris/`):** `arboris/prefetch.om` provides both the static `ARH1` settled score-plane -> cache-replay `OP3` adapter (`arboris-expert-hints`, `128` experts) and an online adaptive sum-over-paths co-activation prefetcher (`24` transitions × `128` experts × `16` Space-Saving slots: transitions `0..22` for `L -> L+1`, including `17` for `L17 -> L18` exiting the looped core on pass 2, and transition `23` for the looped core wrap `L17 -> L6` on passes 0 and 1 matching `core_start=6, core_end=18, num_passes=3`) with resident-skipping top-K selection. `arboris/check-arboris.om` is its pure OM-2 CPU self-test gate.

## Build and verify

From the repository root on AArch64 Linux after growing `seed/out/omc`:

```sh
sh seed/omega-from-seed.sh
sh om/gpu/inkling2/build.sh build/inkling2
build/inkling2/check-arboris
```

Inside an authorized Spark GB10 window:

```sh
spark-window run build/inkling2/inkling2-native                 # 100% pure seeded Omega, zero libcuda.so.1
spark-window run python3 om/gpu/inkling2/check.py build/inkling2
spark-window run python3 om/gpu/inkling2/check_fast.py build/inkling2
```

## Launch contract

Each `.cubin` exports one symbol matching its file stem. `kernels.list` defines parameter order and sizes. All floating-point buffers are contiguous row-major FP32 (widen BF16 via `bf16_unpack` and round via `bf16_pack` at checkpoint boundaries). Four-byte packed loads require allocations rounded up to a 4-byte multiple. `tiles(n)` is `ceil(n / 128)`.

| Kernel | Arguments in launch order | Grid · threads |
|---|---|---|
| `nvfp4_quant` | `in[N,16]`, `lut[272]`, `outer_scale[1]`, `packed[N,8]`, `scales[N]`, `recon[N,16]`, `N` | `(tiles(N)) · 128` |
| `nvfp4_gemm` | `A[M,K/2]`, `W[N,K/2]`, `sa[M,K/16]`, `sw[N,K/16]`, `alpha[1]`, `lut[272]`, `C[M,N]`, `K`, `N` | `(tiles(N),M) · 128` |
| `mxfp8_quant` | `in[G,32]`, `lut[272]`, `packed[G,32]`, `scales[G]`, `recon[G,32]` | `(G) · 16` |
| `mxfp8_gemm` | `A[M,K]`, `W[N,K]`, `sa[M,K/32]`, `sw[ceil(N/32),K/32]`, `lut[272]`, `C[M,N]`, `K`, `N` | `(tiles(N),M) · 128` |
| `dense` | `A[M,K]`, `W[N,K]`, `C[M,N]`, `K`, `N` | `(tiles(N),M) · 128` |
| `rms_stat` | `in[B,D]`, `inv_rms[B]`, `D` | `(B) · 1` |
| `rms_apply` | `in[B,D]`, `gain[D]`, `inv_rms[B]`, `out[B,D]`, `D` | `(tiles(D),B) · 128` |
| `rms_unweighted` | `in[B,D]`, `inv_rms[B]`, `out[B,D]`, `D` | `(tiles(D),B) · 128` |
| `l2_clip` | `in[B,H,D]`, `scale[H,D]`, `tau[B]`, `out[B,H,D]`, `H`, `D`, `thresh_bits`, `flags` | `(H,B) · 1` |
| `sconv_static` | `x[B,D]`, `state[B,D,3]`, `w[D,4]`, `out[B,D]`, `D` | `(tiles(D),B) · 128` |
| `sconv_dynamic` | `x[B,D]`, `state[B,D,3]`, `static_w[4,D]`, `dyn_w[B,H,4]`, `out[B,D]`, `D`, `hd_shift` | `(tiles(D),B) · 128` |
| `inkling_attn_scores` | `Q[B,H,128]`, `K[B,Hkv,T,128]`, `rel[B,H,R]`, `scores[B,H,T]`, `H`, `Hkv`, `T`, `R`, `pos_q`, `window` | `(T,H,B) · 1` |
| `inkling_attn_mix` | `scores[B,H,T]`, `V[B,Hkv,T,128]`, `sinks[B,H]`, `out[B,H,128]`, `H`, `Hkv`, `T` | `(H,B) · 128` |
| `attn_gate` | `a[N]`, `g[N]`, `out[N]`, `N` | `(tiles(N)) · 128` |
| `route8` | `logits[B,128]`, `bias[128]`, `ids[B,8]`, `weights[B,8]` | `(B) · 1` |
| `softcap_swiglu` | `gate[B,I]`, `up[B,I]`, `weight[B]`, `out[B,I]`, `I` | `(tiles(I),B) · 128` |
| `moe_combine8` | `downs[B,8,D]`, `out[B,D]`, `D` | `(tiles(D),B) · 128` |
| `attn_res` | `V[B,K,D]`, `queries[Q,D]`, `out[B,Q,D]`, `K`, `Q`, `D` | `(Q,B) · 1` |
| `msg_gate` | `h[N]`, `msg[N]`, `f_logit[N]`, `m_logit[N]`, `out[N]`, `N` | `(tiles(N)) · 128` |
| `logit_softcap` | `x[N]`, `out[N]`, `N`, `cap_bits` | `(tiles(N)) · 128` |
| `bf16_pack` | `src[N]`, `dst[N]`, `N` | `(tiles(N)) · 128` |
| `bf16_unpack` | `src[N]`, `dst[N]`, `N` | `(tiles(N)) · 128` |
