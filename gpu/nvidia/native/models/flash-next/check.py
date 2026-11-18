"""Compare the seeded lookup with the installed Transformers model and real FP8 rows."""
import argparse
import bisect
import contextlib
import hashlib
import json
import random
import struct
import subprocess
import tempfile
from pathlib import Path

import torch
from safetensors import safe_open
from transformers import AutoConfig
from transformers.models.qwen4_exp.modeling_qwen4_exp import (
    Qwen4ExpTextModel, Qwen4ExpTextNGramEmbedding, Qwen4ExpTextRotaryEmbedding,
)


PREFIX = "model.language_model.layers.1.ple.ple_embedding."
INDEX_HASH = "0419e2c2dfbb925257d7409405433a793cf7ff7d96f3eba882a815ec6d9fe7a6"
CHAT = [248045, 846, 198, 20206, 440, 799, 15262, 1132, 13, 220, 17, 10,
        17, 30, 248046, 198, 248045, 74455, 198, 248068, 271, 248069, 271, 19, 248046]


class ReferenceTable(torch.nn.Module):
    def __init__(self, tables, scale):
        super().__init__()
        self.register_buffer("weight", torch.empty(0))
        self.tables = tables
        self.scale = scale
        self.ends = []
        self.used = set()
        rows = 0
        for table in tables:
            count, width = table.get_shape()
            assert width == 160
            rows += count
            self.ends.append(rows)

    def forward(self, indices):
        rows = []
        for row in indices.flatten().tolist():
            shard = bisect.bisect_right(self.ends, row)
            self.used.add(shard)
            local = row - (self.ends[shard - 1] if shard else 0)
            rows.append(self.tables[shard][local:local + 1])
        values = torch.cat(rows).float() * self.scale.float()
        return values.bfloat16().reshape(*indices.shape, 160)


def decoder_input(cfg, weight, ids):
    """Capture the real input to the first Transformers decoder block without loading later blocks."""
    class ReachedDecoder(Exception):
        pass

    def capture(_module, args):
        raise ReachedDecoder(args[0].view(torch.uint16).numpy().tobytes())

    with torch.device("meta"):
        model = Qwen4ExpTextModel(cfg)
    model.embed_tokens = torch.nn.Embedding.from_pretrained(weight)
    model.rotary_emb = Qwen4ExpTextRotaryEmbedding(cfg)
    model.layers[0].register_forward_pre_hook(capture)
    masks = {"linear_attention": None, "qwen_sparse_attention": None}
    try:
        with torch.inference_mode():
            model(torch.tensor([ids]), attention_mask=masks, use_cache=False)
    except ReachedDecoder as result:
        return result.args[0]
    raise AssertionError("Transformers did not enter the first decoder block")


def check(exe, model):
    index = (model / "model.safetensors.index.json").read_bytes()
    assert hashlib.sha256(index).hexdigest() == INDEX_HASH
    locations = json.loads(index)["weight_map"]
    cfg = AutoConfig.from_pretrained(model, local_files_only=True).text_config
    rng = random.Random(1331)
    ids = CHAT + [cfg.eos_token_id, 0, cfg.eos_token_id, cfg.eos_token_id,
                  cfg.vocab_size - 1] + [rng.randrange(cfg.vocab_size) for _ in range(240)]
    data = struct.pack(f"<{len(ids)}I", *ids)
    with safe_open(model / locations["model.language_model.embed_tokens.weight"], framework="pt") as shard:
        weight = shard.get_tensor("model.language_model.embed_tokens.weight")
        assert weight.shape == (cfg.vocab_size, cfg.hidden_size)
        residual = decoder_input(cfg, weight, ids)

    def input_run(payload, cwd=model, mode="--decoder-input"):
        return subprocess.run([exe, mode], input=payload, stdout=subprocess.PIPE, cwd=cwd, timeout=60)

    actual = input_run(data)
    assert actual.returncode == 0 and actual.stdout == residual
    assert len(residual) == len(ids) * 4 * 5120
    assert input_run(b"").returncode == 0
    for bad in (b"x", struct.pack("<I", cfg.vocab_size)):
        result = input_run(bad)
        assert (result.returncode, result.stdout) == (3, b"")
    assert input_run(b"", mode="--decoder-input-extra").returncode == 1
    with tempfile.TemporaryDirectory() as scratch:
        root = Path(scratch)
        assert input_run(data, root).returncode == 2
        name = locations["model.language_model.embed_tokens.weight"]
        with (model / name).open("rb") as src:
            n, = struct.unpack("<Q", src.read(8))
            header = json.loads(src.read(n))
        key = "model.language_model.embed_tokens.weight"
        for field, value in (("dtype", "F16"), ("shape", [cfg.vocab_size - 1, cfg.hidden_size]),
                             ("data_offsets", [0, 2])):
            changed = {**header, key: {**header[key], field: value}}
            raw = json.dumps(changed).encode()
            with (root / name).open("wb") as out:
                out.write(struct.pack("<Q", len(raw)) + raw)
                out.truncate((model / name).stat().st_size - n + len(raw))
            result = input_run(data, root)
            assert (result.returncode, result.stdout) == (2, b"")
    print(f"PASS decoder input: {len(ids)} tokens, {len(residual)} identical BF16 bytes, sha256 {hashlib.sha256(residual).hexdigest()}")
    with contextlib.ExitStack() as stack:
        filenames = {name for key, name in locations.items() if key.startswith(PREFIX)}
        shards = {name: stack.enter_context(safe_open(model / name, framework="pt"))
                  for name in sorted(filenames)}
        def tensor(suffix):
            key = PREFIX + suffix
            return shards[locations[key]].get_tensor(key)

        with torch.device("meta"):
            lookup = Qwen4ExpTextNGramEmbedding(cfg, cfg.ple_embed_dim, 1)
        for name in ("layer_multipliers", "ngram_heads_offsets", "ngram_heads_vocab_sizes"):
            setattr(lookup, name, tensor(name))
        tables = []
        for i in range(cfg.split_ngram_parts):
            key = PREFIX + f"ngram_embedding.shard_{i}.weight"
            tables.append(shards[locations[key]].get_slice(key))
        table = ReferenceTable(tables, tensor("ngram_embedding.weight_scale"))
        lookup.ngram_embedding = table
        with torch.inference_mode():
            expected = lookup(torch.tensor([ids]), None).view(torch.uint16).numpy().tobytes()
        assert len(table.used) == 128

    def run(payload, cwd=model):
        return subprocess.run([exe], input=payload, stdout=subprocess.PIPE, cwd=cwd, timeout=60)

    good = run(data)
    assert good.returncode == 0 and good.stdout == expected
    assert len(expected) == len(ids) * 5120
    # The real model input detects dropped history; a restart agrees only after EOS.
    restart = run(struct.pack("<I", ids[1]))
    assert restart.returncode == 0 and restart.stdout != expected[5120:10240]
    empty = run(b"")
    assert (empty.returncode, empty.stdout) == (0, b"")
    for invalid in (b"\x01", struct.pack("<I", cfg.vocab_size)):
        bad = run(invalid)
        assert (bad.returncode, bad.stdout) == (3, b"")
    with tempfile.TemporaryDirectory() as scratch:
        root = Path(scratch)
        assert run(data, root).returncode == 2
        for shard in model.glob("model-*.safetensors"):
            (root / shard.name).symlink_to(shard)
        name = "model-00006-of-00131.safetensors"
        corrupt = root / name
        corrupt.unlink()
        with (model / name).open("rb") as src:
            n, = struct.unpack("<Q", src.read(8))
            header = json.loads(src.read(n))
        key = PREFIX + "ngram_embedding.shard_2.weight"
        header[key]["shape"][1] -= 1
        raw = json.dumps(header).encode()
        with corrupt.open("wb") as out:
            out.write(struct.pack("<Q", len(raw)) + raw)
            out.truncate((model / name).stat().st_size)
        bad = run(data, root)
        assert (bad.returncode, bad.stdout) == (2, b"")
    print(f"PASS {len(ids)} tokens, {len(table.used)} shards, {len(expected)} identical BF16 bytes")
    print("vector_sha256", hashlib.sha256(expected).hexdigest())
    print("PASS history, empty input, invalid token, short input, missing and malformed shard controls")


if __name__ == "__main__":
    if not __debug__:
        raise RuntimeError("Run the comparison with assertions enabled")
    parser = argparse.ArgumentParser()
    parser.add_argument("executable", type=Path)
    parser.add_argument("checkpoint", type=Path)
    args = parser.parse_args()
    torch.set_num_threads(1)
    check(args.executable.resolve(), args.checkpoint.resolve())
