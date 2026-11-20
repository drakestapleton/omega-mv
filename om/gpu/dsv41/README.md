# DeepSeek-V4.1-Flash text decode kernels for GB10

These SM121 cubins implement operator baselines for the original DeepSeek-V4.1-Flash text backbone. The architecture, formats and tensor dimensions come from revision `314113f8a7dadb388215396ba5fbee2c610a04d6`. The model uses 40 layers, a hidden width of 5120, six routed experts per token, and a learned attention sink per head. [Published inference implementation](https://huggingface.co/deepseek-ai/DeepSeek-V4.1-Flash/tree/314113f8a7dadb388215396ba5fbee2c610a04d6/inference)

The seeded compiler builds `emit.om` with the repository's SM121 encoder. The resulting program writes SASS instructions directly. The seeded Omega packer constructs each ELF image, including the linked toolkit note needed by the Spark driver. `lookup.om` generates the shared 272-entry floating-point decode table. Shell orchestrates the build. The independent numerical test runs through Python, NumPy and the installed CUDA Driver API.

## Build and run

From the repo root on AArch64 Linux, grow the compiler and build the images.

```sh
sh seed/omega-from-seed.sh
sh om/gpu/dsv41/build.sh build/dsv41
```

Inside an authorized Spark window, compare the compiled images against the numerical references.

```sh
spark-window run python3 om/gpu/dsv41/check.py build/dsv41
```

The checks include the individual operators and a synthetic routed expert at checkpoint widths. The expert check quantizes a 5120-component activation, executes two packed FP4 projections to 2304 components, evaluates weighted SwiGLU, requantizes and projects back to 5120. Full-checkpoint logits, sustained serving throughput, multimodal inference, speculative decoding, and multi-Spark integration require separate qualification.

## Launch contract

Each image exports one symbol with the same name as its file stem. `kernels.list` gives parameter order and sizes. Pointers refer to contiguous row-major device data. A scalar occupies four bytes. Dimensions and indices are unsigned or signed 32-bit integers as indicated. The rotary sign is a float32 scalar. Grid dimensions omitted from the right are one. The block has shape `(threads,1,1)`.

In the table, B counts token rows, H local heads, T cache positions, S selected positions, D vector width, M activation rows, N output rows and K projection width. `tiles(n)` is ceiling division by 128. All dimensions and K for selection are positive. The packer assigns 64 registers per thread and zero shared bytes. Inputs are finite except for index-selection masking and pinned candidate blocks. Four-byte packed loads require the last allocation word to be readable. Flattened element/word indices must fit in 32 bits. The Engram and vocabulary gathers form their shard-row addresses in 64 bits.

| Kernel | Arguments in launch order | Grid · threads |
|---|---|---|
| hc_pre | residual[B,4,5120], pre[B,4], out[B,5120] | (40,B) · 128 |
| hc_post | sublayer[B,5120], residual, post[B,4], comb[B,4,4], out[B,4,5120] | (40,B) · 128 |
| hc_sinkhorn | raw[B,24], scales[3], bias[24], pre[B,4], post[B,4], comb[B,4,4] | (B) · 1 |
| expert_act | gate[B,2304], up[B,2304], selected weight[B], out[B,2304] | (18,B) · 128 |
| fp8_gemm, fp4_gemm | packed A[M,K], packed W[N,K], scales A, scales W, decode table, out[M,N], K, N | (tiles(N),M) · 128 |
| sparse_scores | query[B,H,512], KV[B,T,512], indices[B,S], scores[B,H,S], H,T,S | (S,H,B) · 1 |
| sparse_mix | scores[B,H,S], KV[B,T,512], indices[B,S], sink[H], out[B,H,512], H,T,S | (4,H,B) · 128 |
| quant_fp8, quant_fp4, quant_kv | input, decode table, packed output, byte scales, reconstructed output | (total groups) · half the group width |
| dense | activation[M,K], weights[N,K], out[M,N], K,N | (tiles(N),M) · 128 |
| rms_stat | input[B,D], reciprocal RMS[B], D | (B) · 1 |
| rms_apply | input[B,D], gain[D], reciprocal RMS[B], out[B,D], D | (tiles(D),B) · 128 |
| rotary_tail | in/out[B,H,D], interleaved cos/sin[B,32,2], D,H,sign | (H,B) · 32 |
| compress_pair | KV[B,2,512], score[B,2,512], out[B,512] | (4,B) · 128 |
| route6 | logits[B,384], selection bias[384], expert IDs[B,6], weights[B,6] | (B) · 1 |
| engram_rows | absolute IDs[B], shard FP8 rows[R,256], shard byte scales[R,8], decode table, out[B,256], start ID,R | (B) · 256 |
| bf16_pack, bf16_unpack | source, destination, element count | (tiles(count)) · 128 |
| index_scores | query[B,H,128], key[B,T,128], prescaled BF16 head weights[B,H], lengths[B], keep mask[B,ceil(T/8)], out[B,T], H,T | (tiles(T),B) · 128 |
| candidate_blocks | index scores[B,T], reachable lengths[B], out[B,ceil(T/8)], T | (ceil(T/8),B) · 1 |
| top_positions | scores[B,T], indices[B,K], keep mask[B,T], T,K,index offset | (B) · 1 |
| engram_gate | residual[B,4,5120], keys[B,4,5120], product of query and key weights[4,5120], token mask[B], gates[B,4] | (4,B) · 1 |
| engram_add | residual[B,4,5120], value[B,5120], gates[B,4], out[B,4,5120] | (40,4,B) · 128 |
| token_embed | token IDs[B], shard BF16 table[R,5120], out[B,4,5120], start ID,R | (40,B) · 128 |
| moe_sum | six down-projections[B,6,5120], shared output[B,5120], out[B,5120] | (40,B) · 128 |
| window_step | new KV[B,512], position per row[B], in/out cache[B,128,512], indices[B,128] | (4,B) · 128 |

**Precision and layout.** Unqualified floating-point buffers in the table use FP32 storage. Supply BF16 activations widened to FP32 where the checkpoint expects BF16, and round at each checkpoint dtype boundary. The pack and unpack kernels perform those conversions. FP4 uses low nibble first, E2M1. Both GEMMs consume E4M3 activations and require K divisible by 32. Activation scale shape is [M,K/32]. FP4 weight scales are [N,K/32], and FP8 weight scales are [ceil(N/32),K/32]. Both use E8M0 bytes. Supply `decode.f32le` as 272 contiguous device float32 values. The quantizers produce both packed values and widened BF16 reconstructions. FP8 and FP4 indexer groups have width 32 and a power-of-two scale. Compressed KV groups have width 16 and an E4M3 scale. Compressed-KV scale checks cover the finite representable range.

**Attention and routing.** Pass one query per batch row to the sparse pair. Supply identical indices to both stages. Each index is a cache position or -1. The mixer follows the reference's 64-position online softmax and rounds each numerator weight to BF16. Apply the residual gates in the upstream layer order. Send the previous sublayer's pre coefficients to hc_pre. The router ranks biased scores, takes weights from the unbiased scores, normalizes them and applies the checkpoint's factor of 1.5. It resolves ties by lower expert ID. top_positions returns ascending positions, fills unreachable entries with -1, and gives a 32-bit keep mask. It also resolves score ties by lower index. Supply K at most T and an offset that fits signed int32. For two-level selection, run candidate_blocks, top_positions on the block scores, index_scores with the resulting mask, then top_positions on the filtered scores.

**Integration.** The collection operates on caller-owned buffers. A model executor must load and shard weights and Engram tables, construct hash IDs and rotary frequencies, schedule the 40 layers and BF16 boundaries, maintain cache state, and perform rank collectives. The CUDA Driver API is used for this hardware check. Use of the native Omega submission path by a serving executor remains to be exercised.
