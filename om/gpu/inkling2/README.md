# Inkling-2-Mini Seeded Omega SM121 Kernels for GB10

These 22 SM121 cubins implement the complete operator set for Thinking Machines Lab's **Inkling-2-Mini** (`thinkingmachines/Inkling-2-Mini`, architecture `Inkling2LoopForConditionalGeneration`) in pure seeded Omega (`.om`) with no C and no CUDA toolkit on the build path.

The seeded compiler (`seed/out/omc`) compiles `emit.om` with the repository's SM121 encoder (`om/encoder/bw_enc_sm121.om`), and `seed/kflow/kpack.om` packs each SASS image into an SM121 `.cubin`. `lookup.om` generates the shared 272-entry FP32 decode table (`256` E4M3FN + `16` E2M1).

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
spark-window run python3 om/gpu/inkling2/check.py build/inkling2
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
