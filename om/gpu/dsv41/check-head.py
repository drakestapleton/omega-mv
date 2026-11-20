"""Compare every vocabulary logit against an independent CPU head using the pinned BF16 shard."""
import hashlib
import json
import struct
import sys
from urllib.request import Request, urlopen
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


def fixture(path):
    """Fetch only embedding rows 1234..1241 from the pinned public shard."""
    base = ("https://huggingface.co/deepseek-ai/DeepSeek-V4.1-Flash/resolve/"
            "314113f8a7dadb388215396ba5fbee2c610a04d6/model-00002-of-00048.safetensors")
    start = 8 + 344 + 1234 * 10240
    stop = start + 81920 - 1
    req = Request(f"{base}?omega-range={start}-{stop}", headers={"Range": f"bytes={start}-{stop}"})
    with urlopen(req, timeout=60) as resp:
        if resp.status != 206 or not resp.headers.get("Content-Range", "").startswith(f"bytes {start}-{stop}/"):
            raise ValueError("embedding server did not honor the byte range")
        rows = resp.read(81921)
    if hashlib.sha256(rows).hexdigest() != "bbbf862be017006ae7d4e4e6dfe9d6883364ef74314a7c17825bd0c8dd9cc7a6":
        raise ValueError("embedding slice SHA-256 mismatch")
    frames = (rows[:40960] + struct.pack("<4f", .1, .3, .6, 0.) +
              rows[40960:] + struct.pack("<4f", -.2, .4, 1., .25))
    cancellation = b"".join(struct.pack("<H", word) * 5120 for word in (0xbf80, 0x3f81, 0, 0))
    frames += cancellation + struct.pack("<4f", 8454145/16777216, 8388609/16777216, .5, .5)
    # BF16 2**70 is finite. Its FP32 square overflows, giving this frame zero RMS gain.
    frames += struct.pack("<H", 0x6280) * 5120 + bytes(30720) + struct.pack("<4f", 1, 0, 0, 0)
    with path.open("xb") as f:
        f.write(frames)


def verify(shard, frames, logits):
    weights, gain = load_tensors(shard)
    width = gain.size
    data = frames.read_bytes()
    record_size = 8 * width + 16
    count, tail = divmod(len(data), record_size)
    if tail or not count:
        raise ValueError("expected one or more complete residual frames")
    if logits.stat().st_size != count * weights.shape[0] * 4:
        raise ValueError("output byte length does not match complete frames")
    actual = np.fromfile(logits, "<f4").reshape(count, weights.shape[0])
    hidden = []
    for i in range(count):
        offset = i * record_size
        streams = widened(np.frombuffer(data, "<u2", 4*width, offset).reshape(4, width))
        mix = np.frombuffer(data, "<f4", 4, offset+8*width)
        state = rounded((streams * mix[:, None]).sum(axis=0, dtype=np.float32))
        with np.errstate(over="ignore"):
            var = np.mean(np.square(state), dtype=np.float32)
        rms = np.float32(1) / np.sqrt(var + np.float32(1e-20))
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
    if len(sys.argv) == 3 and sys.argv[1] == "--fixture":
        fixture(Path(sys.argv[2]))
    elif len(sys.argv) == 4:
        verify(*(Path(arg) for arg in sys.argv[1:]))
    else:
        sys.exit("usage: check-head.py --fixture FRAMES | SHARD FRAMES LOGITS")
