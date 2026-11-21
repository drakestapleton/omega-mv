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
 cat "$d/io.om" "$d/resolve.om" "$d/check-resolve.om") |
    seed/out/omc > "$out/check-resolve"
chmod +x "$out/payload-index" "$out/check-resolve"
"$out/payload-index" "$out/tensors.bin" 03 "$checkpoint/model-00003-of-00048.safetensors" > "$out/layer0.bin"
"$out/check-resolve" "$out/layer0.bin" "$checkpoint/model-00003-of-00048.safetensors"
```

Run the worker for each shard 03 through 42 and for the two Engram shards 47 and 48. The worker requires the pinned tensor-index digest. Verify the complete source shard against its published digest before starting the worker.

Expert records have 64 bytes. Bytes 0 and 1 hold shard and layer, bytes 4..7 the expert ID, bytes 8..15 the first eight bytes of SHA-256 in digest order, and six little-endian u64 offsets start at byte 16. The digest covers W1, W2 and W3 weights followed by W1, W2 and W3 scales. The resolver verifies these same bytes in Zone 4 before it claims a FIFO victim. It publishes the slot only after the entire copy completes. A checksum mismatch leaves the resident slot and FIFO cursor intact.

The Engram sidecar starts with a 32-byte header containing shard, layer, row count, weight base and scale base. Each row contributes an eight-byte digest prefix in row order. Row i reads 256 weight bytes at weight_base + 256i and eight scale bytes at scale_base + 8i. The hash covers the two extents in that order.
