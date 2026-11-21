# Native single-stream decoder

The offline tensor index and text ingress target DeepSeek-V4.1-Flash revision `314113f8a7dadb388215396ba5fbee2c610a04d6`. The index verifies each shard's exact length and SHA-256 of its JSON header before reading its tensor descriptors. Full payload qualification also requires the verified weight digests. The ingress accepts little-endian u32 text IDs and emits four BF16 embedding rows followed by the FP32 identity pre-mix.

Build from the clean repository root on AArch64 Linux with the seeded compiler. Keep build outputs outside the checkout.

```sh
out=$(mktemp -d)
d=om/gpu/dsv41/decoder
(echo om2 && cat seed/json/json.om seed/ng/sha256.om "$d/checkpoint.om" "$d/io.om" "$d/index.om") |
    seed/out/omc > "$out/index"
(echo om2 && cat seed/json/json.om om/gpu/dsv41/head/weights.om "$d/embed.om" "$d/embed-cli.om") |
    seed/out/omc > "$out/embed"
chmod +x "$out/index" "$out/embed"
"$out/index" "$checkpoint"/model-?????-of-00048.safetensors > "$out/tensors.bin"
```

Each 160-byte tensor descriptor contains the one-based shard ID at byte 0, rank at byte 2, absolute u64 offset and length at bytes 8 and 16, up to four u32 dimensions at byte 24, a zero-terminated dtype at byte 40 and a zero-terminated tensor name at byte 56. Integers are little-endian. Discard partial output on any nonzero exit.

Checkpoint configuration activates Engram at zero-based layers 1 and 14. Layer 0 has a sliding window and no Engram contribution. Its real-weight parity check must preserve that behavior. The first integrated Engram parity check belongs at layer 1.

## Expert and Engram payload index

Build the shard worker and the real-weight resolver control on the same head.

```sh
(echo om2
 sed '/^om2$/d;s/^export fn /fn /' om/sha256/sha256-om2.om
 cat seed/ng/sha256.om "$d/checkpoint.om" "$d/io.om" "$d/payload-index.om") |
    seed/out/omc > "$out/payload-index"
(echo om2
 sed -n '/^layout /,/^end$/p' om/sha256/sha256-om2.om om/runtime/slab_arena.om
 sed '/^layout /,/^end$/d;/^om2$/d;s/^export fn /fn /' om/sha256/sha256-om2.om om/runtime/slab_arena.om
 cat gpu/nvidia/native/arboris/compute-lock.om "$d/io.om" "$d/lease.om" "$d/resolve.om" "$d/check-resolve.om") |
    seed/out/omc > "$out/check-resolve"
chmod +x "$out/payload-index" "$out/check-resolve"
"$out/payload-index" "$out/tensors.bin" 03 "$checkpoint/model-00003-of-00048.safetensors" > "$out/layer0.bin"
"$out/check-resolve" "$out/layer0.bin" "$checkpoint/model-00003-of-00048.safetensors"
```

Run the worker for each shard 03 through 42 and for the two Engram shards 47 and 48. The worker requires the pinned tensor-index digest. Verify the complete source shard against its published digest before starting the worker.

Expert records have 64 bytes. Bytes 0 and 1 hold shard and layer, bytes 4..7 the expert ID, bytes 8..15 the first eight bytes of SHA-256 in digest order, and six little-endian u64 offsets start at byte 16. The digest covers W1, W2 and W3 weights followed by W1, W2 and W3 scales. The resolver verifies these same bytes in Zone 4 before it claims a FIFO victim. It publishes the slot only after the entire copy completes. A checksum mismatch leaves the resident slot and FIFO cursor intact.

The decoder opens `engram1.bin` and `engram14.bin` in the expert sidecar directory. Generate them from shards 47 and 48 respectively. It checks each header against the pinned tensor index and verifies each row before uploading it. The Engram sidecar starts with a 32-byte header containing shard, layer, row count, weight base and scale base. Each row contributes an eight-byte digest prefix in row order. Row i reads 256 weight bytes at weight_base + 256i and eight scale bytes at scale_base + 8i. The hash covers the two extents in that order.

## Native build controls

The backbone catalog uses the same 28 emitter functions as the checkpoint operator export. Its QMD recorder supports three grid dimensions and keeps the six native head entries. The host catalog control emits the aligned instruction image without opening the driver.

The CPU Engram path uses the original tokenizer's fixed remap data in `engram-token-map.u32`. The table and the constants in `engram-layout.om` were exported from the pinned reference's `build_compressed_token_map`, `compute_hash_multipliers` and `EngramLayout.from_args`. The native loader verifies the remap SHA-256 before accepting a token. A verified 264-byte row comprises its original FP8 weight plane and E8M0 scales.

The trace writer takes the six IDs and original FP32 weight bits after the native gate, without issuing another GPU kernel. Each 80-byte record has u32 turn, turn-local token, layer and reserved words, six u32 IDs, six u32 weight bit patterns, and u64 gate-ready and consumer-need timestamps. The static ring retains one context page of 2,048 tokens. Drain committed entries on the CPU lease before reusing their storage, and finalize the stream SHA-256 after a complete token.

The resident checkpoint planner packs the original embedding, head, norms, routers, shared experts, attention and Engram auxiliary tensors on 256-byte boundaries. Its host control accepts the tensor directory alone to serialize the planned allocation, original payload bytes and tensor count and context-2048 KV reservation as four u64 words. Supply the 48 verified shard paths as further arguments to populate the whole mapping and measure process RSS. KV and execution workspace allocations are separate.

```sh
(echo om2
 sed '/^om2$/d;s/^export fn /fn /' om/sha256/sha256-om2.om
 cat seed/ng/sha256.om "$d/checkpoint.om" "$d/io.om" "$d/core.om" "$d/kv.om" "$d/check-core.om") |
    seed/out/omc > "$out/check-core"
(echo om2
 sed '/^om2$/d;s/^export fn /fn /' om/sha256/sha256-om2.om
 cat seed/ng/sha256.om gpu/nvidia/native/arboris/compute-lock.om "$d/io.om" "$d/engram-layout.om" "$d/engram.om" "$d/check-engram.om") |
    seed/out/omc > "$out/check-engram"
(echo om2
 sed '/^om2$/d;s/^export fn /fn /' om/sha256/sha256-om2.om
 cat gpu/nvidia/native/arboris/compute-lock.om "$d/io.om" "$d/trace.om" "$d/check-trace.om") |
    seed/out/omc > "$out/check-trace"
(echo om2
 cat gpu/nvidia/native/nvrm/context.om gpu/nvidia/native/blackwell/vector.om gpu/nvidia/native/blackwell/launch.om gpu/nvidia/native/blackwell/batch.om om/encoder/bw_enc_sm121.om om/gpu/dsv41/emit.om om/gpu/dsv41/head/launch.om "$d/native.om" "$d/check-catalog.om") |
    seed/out/omc > "$out/check-catalog"
chmod +x "$out"/check-*
"$out/check-core" "$out/tensors.bin" "$checkpoint"/model-?????-of-00048.safetensors > "$out/core.bin"
"$out/check-engram" "$d/engram-token-map.u32" > "$out/engram-control.ids"
"$out/check-trace" > "$out/trace-control.bin" 2> "$out/trace-control.sha256.raw"
"$out/check-catalog" > "$out/code.bin"
```

## Full 40-layer native decoder

`dsv41-decode` composes the seeded SM121 backbone catalog, Zone 1 resident planner, paged KV layout, `slab_arena.om` FIFO expert resolver, CPU Engram lookup, native router trace tap, and final LM head into a single static AArch64 executable with zero external libraries.

```sh
(echo om2
 sed -n '/^layout /,/^end$/p' om/sha256/sha256-om2.om om/runtime/slab_arena.om
 sed '/^layout /,/^end$/d;/^om2$/d;s/^export fn /fn /' om/sha256/sha256-om2.om om/runtime/slab_arena.om
 cat seed/ng/sha256.om gpu/nvidia/native/arboris/compute-lock.om gpu/nvidia/native/nvrm/context.om \
     gpu/nvidia/native/blackwell/vector.om gpu/nvidia/native/blackwell/launch.om gpu/nvidia/native/blackwell/batch.om \
     om/encoder/bw_enc_sm121.om om/gpu/dsv41/emit.om om/gpu/dsv41/head/launch.om \
     "$d/checkpoint.om" "$d/io.om" "$d/core.om" "$d/kv.om" "$d/lease.om" "$d/resolve.om" \
     "$d/engram-layout.om" "$d/engram.om" "$d/trace.om" "$d/native.om" \
     "$d/layer-map.om" "$d/rope.om" "$d/workspace.om" "$d/forward.om" "$d/decode-cli.om") |
    seed/out/omc > "$out/dsv41-decode"
chmod +x "$out/dsv41-decode"
```

Inside an authorized Spark GB10 window:

```sh
# Gate 2: Layer 0 real-weight parity
spark-window run "$out/dsv41-decode" layer0 "$out/tensors.bin" "$d/engram-token-map.u32" \
    "$sidecars" "$checkpoint" 1234 "$out/layer0-out.bin"
python3 "$d/check-layer0.py" "$checkpoint" 1234 "$out/layer0-out.bin"

# Gate 3: Full 40-layer deterministic greedy generation + SHA-256 router trace archive
spark-window run "$out/dsv41-decode" gen "$out/tensors.bin" "$d/engram-token-map.u32" \
    "$sidecars" "$checkpoint" "$out/trace.bin" 32 0 671 6102 294 8760 344
python3 "$d/trace-to-csv.py" "$out/trace.bin" "$out/trace.csv"
```

Conversational capture accepts little-endian u32 words. The first word gives the turn count. Each turn contains its ID, maximum generated tokens, prompt token count and prompt IDs. The decoder retains the generated conversation between turns. The payload resolver hashes all six planes before publishing a slot. On Linux it can stream them through AF_ALG SHA-256. When the algorithm is unavailable at open, it uses seeded Omega SHA-256. A read, hash or digest error rejects the miss.

The decoder keeps one unpublished physical slot. A miss fills and verifies that slot under the CPU lease. Publication swaps its physical index with the selected FIFO victim and retains the same resident capacity. Slots needed by the current six-expert gate cannot be selected as victims. To test the exchange without opening a GPU, replace the CLI in the decoder composition with `check-slot-exchange.om` and pass the layer-zero index and shard 03. The test checks refusal after a digest mismatch, FIFO and residency preservation, and successful publication under eviction pressure.
