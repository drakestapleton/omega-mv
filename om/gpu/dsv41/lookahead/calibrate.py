"""Measure direct sequential reads of a verified DXP1 expert pack on Spark."""
import argparse
import csv
import hashlib
import mmap
import os
from pathlib import Path
import struct
import subprocess
import sys
import time


def measure(pack, digest, passes):
    if os.uname().machine != "aarch64":
        raise ValueError("requires AArch64 Linux")
    if subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=all"]):
        raise ValueError("dirty worktree")
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    device = subprocess.check_output(
        ["findmnt", "--noheadings", "--output", "SOURCE", "--target", str(pack)],
        text=True).strip()
    if not Path(device).resolve().name.startswith("nvme"):
        raise ValueError(f"pack is on {device}")
    with open(pack, "rb") as source:
        if hashlib.file_digest(source, "sha256").hexdigest() != digest:
            raise ValueError("pack digest mismatch")
        source.seek(0)
        header = source.read(4096)
        magic, version, count, stride = struct.unpack_from("<4I", header)
        if (magic != int.from_bytes(b"DXP1", "little") or version != 1 or
                not 1 <= count <= 384 or stride != 18800640 or
                os.fstat(source.fileno()).st_size != 4096 + count * stride):
            raise ValueError("invalid DXP1 extent")
        ids = struct.unpack_from(f"<{count}I", header, 16)
        if len(set(ids)) != count or max(ids) >= 384:
            raise ValueError("invalid DXP1 IDs")
        fd = os.open(f"/proc/self/fd/{source.fileno()}", os.O_DIRECT | os.O_RDONLY)
        try:
            with mmap.mmap(-1, stride) as buf:
                buf[:] = bytes(stride)
                writer = csv.writer(sys.stdout)
                writer.writerow(["head", "pack_sha256", "device", "pass", "expert",
                                 "offset", "bytes", "issue_ns", "complete_ns"])
                for repetition in range(passes):
                    for index, expert in enumerate(ids):
                        offset = 4096 + index * stride
                        start = time.monotonic_ns()
                        n = os.preadv(fd, [buf], offset)
                        end = time.monotonic_ns()
                        if n != stride or end <= start:
                            raise OSError("invalid direct read completion")
                        writer.writerow([head, digest, device, repetition, expert,
                                         offset, n, start, end])
        finally:
            os.close(fd)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pack", type=Path)
    parser.add_argument("sha256")
    parser.add_argument("--passes", type=int, default=3)
    args = parser.parse_args()
    if args.passes <= 0:
        parser.error("passes must be positive")
    measure(args.pack, args.sha256, args.passes)
