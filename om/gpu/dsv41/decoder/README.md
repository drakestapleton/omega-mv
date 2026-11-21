# Native single-stream decoder

The offline tensor index and text ingress target DeepSeek-V4.1-Flash revision `314113f8a7dadb388215396ba5fbee2c610a04d6`. The index verifies each shard's exact length and SHA-256 of its JSON header before reading its tensor descriptors. Full payload qualification also requires the verified weight digests. The ingress accepts little-endian u32 text IDs and emits four BF16 embedding rows followed by the FP32 identity pre-mix.

Build from the clean repository root on AArch64 Linux with the seeded compiler. Keep build outputs outside the checkout.

```sh
out=$(mktemp -d)
d=om/gpu/dsv41/decoder
(echo om2 && cat seed/json/json.om seed/ng/sha256.om "$d/checkpoint.om" "$d/index.om") |
    seed/out/omc > "$out/index"
(echo om2 && cat seed/json/json.om om/gpu/dsv41/head/weights.om "$d/embed.om" "$d/embed-cli.om") |
    seed/out/omc > "$out/embed"
chmod +x "$out/index" "$out/embed"
"$out/index" "$checkpoint"/model-?????-of-00048.safetensors > "$out/tensors.bin"
```

Each 160-byte tensor descriptor contains the one-based shard ID at byte 0, rank at byte 2, absolute u64 offset and length at bytes 8 and 16, up to four u32 dimensions at byte 24, a zero-terminated dtype at byte 40 and a zero-terminated tensor name at byte 56. Integers are little-endian. Discard partial output on any nonzero exit.

Checkpoint configuration activates Engram at zero-based layers 1 and 14. Layer 0 has a sliding window and no Engram contribution. Its real-weight parity check must preserve that behavior. The first integrated Engram parity check belongs at layer 1.
