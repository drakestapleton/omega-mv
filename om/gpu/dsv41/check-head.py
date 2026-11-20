"""Compare every vocabulary logit against an independent CPU head using the pinned BF16 shard."""
import hashlib
import json
import struct
import sys
from pathlib import Path

import numpy as np


def widened(words):
    return (words.astype(np.uint32) << 16).view(np.float32)


def rounded(x):
    bits = np.ascontiguousarray(x, dtype="<f4").view(np.uint32)
    return ((bits + 32767 + ((bits >> 16) & 1)) & 0xffff0000).view(np.float32)


def load_tensors(path):
    expected = "d762b688f138e00a24eac96f27b842715bb4b534ecc9ca39076bed2b8c33201e"
    with path.open("rb") as f:
        if hashlib.file_digest(f, "sha256").hexdigest() != expected:
            raise ValueError("checkpoint shard SHA-256 mismatch")
        f.seek(0)
        n, = struct.unpack("<Q", f.read(8))
        meta = json.loads(f.read(n))
    def tensor(key):
        info = meta[key]
        return np.memmap(path, mode="r", dtype="<u2", shape=tuple(info["shape"]),
                         offset=8+n+info["data_offsets"][0])
    return tensor("head.weight"), widened(tensor("norm.weight"))


def verify(shard, frames, logits):
    weights, gain = load_tensors(shard)
    width = gain.size
    data = frames.read_bytes()
    record_size = 8 * width + 16
    count, tail = divmod(len(data), record_size)
    if tail or not count:
        raise ValueError("expected one or more complete residual frames")
    actual = np.fromfile(logits, "<f4").reshape(count, weights.shape[0])
    hidden = []
    for i in range(count):
        offset = i * record_size
        streams = widened(np.frombuffer(data, "<u2", 4*width, offset).reshape(4, width))
        mix = np.frombuffer(data, "<f4", 4, offset+8*width)
        state = rounded((streams.astype(np.float64) * mix[:, None]).sum(axis=0))
        rms = np.float32(1 / np.sqrt(np.mean(state.astype(np.float64)**2) + 1e-20))
        hidden.append(rounded(state*rms*gain))
    hidden = np.stack(hidden)
    reference = np.empty_like(actual)
    for lo in range(0, weights.shape[0], 1024):
        block = widened(weights[lo:lo+1024]).astype(np.float64)
        reference[:,lo:lo+len(block)] = hidden.astype(np.float64) @ block.T
    for i, (got, want) in enumerate(zip(actual, reference)):
        if not np.isfinite(got).all():
            raise ValueError(f"frame {i} contains nonfinite logits")
        np.testing.assert_allclose(got, want, rtol=4e-5, atol=4e-5)
        if got.argmax() != want.argmax():
            raise AssertionError(f"frame {i} greedy token mismatch")
        print(f"PASS frame={i} logits={len(got)} max_abs_error={np.max(np.abs(got-want)):.8g} "
              f"greedy_token_id={got.argmax()}")


if __name__ == "__main__":
    verify(*(Path(arg) for arg in sys.argv[1:]))
