# Flash-Next file-backed n-gram embeddings

`lookup.om` reads one sequence of little-endian uint32 token IDs from standard input. For each token it emits 2,560 little-endian BF16 values. The first input starts a new sequence. The checkpoint EOS token resets the n-gram history for subsequent tokens.

With `--decoder-input`, the same executable reads only the BF16 vocabulary embedding in checkpoint shard 130. Each token yields the four 2,560-value residual streams that enter the first decoder layer, in their checkpoint order. This mode reads one row per token.

The input profile is Qwen/Qwen3.8-Flash-Next-FP8 revision `7fb48d708ca6cd8eeed8f4db0433be18af96984f`. Run the binary with the verified checkpoint as its working directory. At startup it reads the safetensors headers of files 5 through 37, locates each of the 128 row tensors by name, checks the dtype, shape and byte ranges, and reads the three hash multipliers, head offsets, vocabulary sizes and scale from the checkpoint. At each token it reads 16 FP8 rows by file offset. This host component supplies the n-gram input to the model's PLE layer. GPU execution and text generation require the rest of the model and driver.

Build on AArch64 Linux from the repository root. The executable uses seeded Omega for JSON, file I/O, FP8 conversion and BF16 rounding.

```sh
out="$PWD/build/flash-next"
mkdir -p "$out"
sha256sum -c seed/out/omc.sha256
cat gpu/nvidia/om/apiviews/bf16.om seed/json/json.om \
    gpu/nvidia/native/models/fp8.om gpu/nvidia/native/models/flash-next/lookup.om \
    > "$out/lookup.full.om"
seed/out/omc < "$out/lookup.full.om" > "$out/lookup" && chmod +x "$out/lookup"
(cd "$CHECKPOINT" && "$out/lookup") < tokens.u32 > embeddings.bf16
```

The comparison uses Python, Transformers, Torch and safetensors as an independent reference. It calls the installed Transformers n-gram layer with the checkpoint buffers and replaces its dense table with sliced on-disk reads. The checks cover the arithmetic chat prompt, sequence boundaries, all table shards, invalid input and a malformed shard. Exit codes from the Omega program are 1 for arguments, 2 for checkpoint preparation, 3 for token input, 4 for a row read and 5 for output I/O. A streaming caller must check the exit status before accepting a complete sequence.

```sh
python3 gpu/nvidia/native/models/flash-next/check.py "$out/lookup" "$CHECKPOINT"
```
