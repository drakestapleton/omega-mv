"""Independent single-layer byte oracle. Uses the released safetensors header."""
import argparse
import hashlib
import json
import struct
import subprocess
import tempfile
from pathlib import Path

SHARD_HASH = "e1281f85d0ce4a3dfb63d41926fc4a47fa71f36ba20992e3597e702ead49d4c9"
EXPERT_BYTES = 18_800_640
IDS = (0, 383, 12, 2, 103, 4, 256, 5)
WARM, DEMAND, PREFETCH, TURN, COMMIT = range(1, 6)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def events(records):
    return b"".join(struct.pack("<II", *record) for record in records)


def read_experts(shard, ids):
    with shard.open("rb") as f:
        if hashlib.file_digest(f, "sha256").hexdigest() != SHARD_HASH:
            raise ValueError("expected pinned original shard 3")
        f.seek(0)
        hlen, = struct.unpack("<Q", f.read(8))
        header = json.loads(f.read(hlen))
        digests = {}
        for expert in ids:
            sha = hashlib.sha256()
            total = 0
            for kind in ("weight", "scale"):
                for projection in ("w1", "w2", "w3"):
                    lo, hi = header[f"layers.0.ffn.experts.{expert}.{projection}.{kind}"]["data_offsets"]
                    f.seek(8 + hlen + lo)
                    payload = f.read(hi - lo)
                    require(len(payload) == hi - lo, f"short tensor read for expert {expert}, {projection}.{kind}")
                    sha.update(payload)
                    total += len(payload)
            require(total == EXPERT_BYTES, f"unexpected payload size for expert {expert}")
            digests[expert] = sha.digest()
        return digests


def rejected(command, data=b"", code=65):
    result = subprocess.run(command, input=data, stdout=subprocess.DEVNULL, check=False)
    if result.returncode != code:
        raise AssertionError(f"expected exit {code}, got {result.returncode}")


def check_whole_layer(command, ids, digests):
    # The entire pack goes through a pipe so qualification does not require a second copy of the layer.
    with subprocess.Popen([*command, *map(str, ids)], stdout=subprocess.PIPE) as proc:
        try:
            header = proc.stdout.read(4096)
            require(struct.unpack_from("<4I", header) == (0x31505844, 1, len(ids), EXPERT_BYTES), "full-layer pack header mismatch")
            require(struct.unpack_from(f"<{len(ids)}I", header, 16) == tuple(ids), "full-layer expert order mismatch")
            for expert in ids:
                block = proc.stdout.read(EXPERT_BYTES)
                require(len(block) == EXPERT_BYTES and hashlib.sha256(block).digest() == digests[expert], f"full-layer bytes mismatch for expert {expert}")
            require(proc.stdout.read(1) == b"", "trailing full-layer pack data")
        finally:
            proc.stdout.close()
        if proc.wait() != 0:
            raise RuntimeError("native full-layer pack failed")
    print(f"PASS all {len(ids)} routed experts, {len(ids)*EXPERT_BYTES} payload bytes")


def check(shard, binaries, scratch, whole_layer):
    subprocess.run([binaries / "contract"], check=True)
    all_ids = [*IDS, *(i for i in range(384) if i not in IDS)]
    digests = read_experts(shard, all_ids if whole_layer else IDS)
    pack = scratch / "layer0.pack"
    cmd = [binaries / "pack", shard]
    if whole_layer:
        check_whole_layer(cmd, all_ids, digests)
    with pack.open("xb") as f:
        subprocess.run([*cmd, *map(str, IDS)], stdout=f, check=True)
    with pack.open("rb") as f:
        header = f.read(4096)
        require(struct.unpack_from("<4I", header) == (0x31505844, 1, len(IDS), EXPERT_BYTES), "fixture pack header mismatch")
        require(struct.unpack_from(f"<{len(IDS)}I", header, 16) == IDS, "fixture expert order mismatch")
        for expert in IDS:
            require(hashlib.sha256(f.read(EXPERT_BYTES)).digest() == digests[expert], f"fixture bytes mismatch for expert {expert}")
        require(f.read(1) == b"", "trailing fixture pack data")
    rejected([*cmd, "383", "383"], code=64)
    rejected([*cmd, "384"], code=64)
    replay = [binaries / "replay", pack]
    route = [(WARM, 0), (WARM, 383), (DEMAND, 0), (TURN, 7), (PREFETCH, 33), (PREFETCH, 12), (PREFETCH, 2),
             (DEMAND, 12), (DEMAND, 2), (DEMAND, 103), (DEMAND, 4), (DEMAND, 256), (DEMAND, 5),
             (TURN, 0), (DEMAND, 0), (DEMAND, 383), (TURN, 7), (TURN, 7), (TURN, 7),
             (COMMIT, 7), (WARM, 12), (WARM, 2), (DEMAND, 12), (DEMAND, 0)]
    keys = [key for op, key in route if op == DEMAND]
    result = scratch / "demands.bin"
    with result.open("xb") as out:
        subprocess.run(replay, input=events(route), stdout=out, check=True)
    with result.open("rb") as f:
        observations = []
        for expert in keys:
            key, hit, zone, pad = struct.unpack("<IBBH", f.read(8))
            require(key == expert and pad == 0 and hit in (0, 1), f"invalid demand metadata for expert {expert}")
            require(hashlib.sha256(f.read(EXPERT_BYTES)).digest() == digests[key], f"wrong demand payload for expert {key}")
            observations.append((key, hit, zone))
        require(f.read(1) == b"", "unexpected demand output")
    require(observations[0] == (0, 1, 2), "initial protected expert missed")
    require(observations[-4:] == [(0, 1, 2), (383, 1, 2), (12, 1, 2), (0, 0, 3)], f"detour return or pack switch mismatch: {observations[-4:]}")
    require(all(zone == 3 for _, _, zone in observations[1:-4]), "detour expert entered the protected zone")
    rejected(replay, events([(TURN, 7), (COMMIT, 7)]))
    rejected(replay, events([(TURN, 7), (TURN, 7), (COMMIT, 7)]))
    rejected(replay, events([(TURN, 7), (TURN, 0), (TURN, 7), (COMMIT, 7)]))
    rejected(replay, events([(WARM, 12), (WARM, 12)]))
    rejected(replay, events([(DEMAND, 6)]))
    rejected(replay, b"\x02")
    badpack = scratch / "short.pack"
    badpack.write_bytes(header)
    rejected([binaries / "replay", badpack])
    print(f"PASS {len(IDS)} packed layer-0 experts, {len(keys)} exact demand payloads")
    print("PASS FIFO wrap, first two returning protected hits, replacement on third consecutive turn")
    print("PASS ring saturation, out-of-order retirement, stale completion, lease and short/error controls")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("shard", type=Path)
    parser.add_argument("binaries", type=Path)
    parser.add_argument("--all-experts", action="store_true", help="check all 384 layer-0 pack extents")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="dsv41-cache-") as path:
        check(args.shard.resolve(), args.binaries.resolve(), Path(path), args.all_experts)
