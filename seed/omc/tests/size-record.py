#!/usr/bin/env python3
"""External oracle for the seed-born source/binary size record."""
import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
tool = Path(sys.argv[1]).resolve()
binary = (root.parent / "out" / "omc").read_bytes()
source = (root / "omc.om").read_bytes()
passed = 0

with tempfile.TemporaryDirectory(prefix="omega-size-record-") as tmp:
    tmp = Path(tmp)
    src, exe = tmp / "source.om", tmp / "compiler"
    def run(s, b):
        src.write_bytes(s)
        exe.write_bytes(b)
        return subprocess.run([str(tool), str(src), str(exe)],
                              capture_output=True, timeout=20)

    for name, s, b in [
        ("current", source, binary),
        ("source-lines", b"fn a\n note fn ignored\nfn b\nfn c", binary),
        ("binary-content", source, binary[:-1] + bytes([binary[-1] ^ 1])),
    ]:
        p = run(s, b)
        digest = hashlib.sha256(b).hexdigest()
        expected = "\t".join([
            "seeded-" + digest[:12], "Generated from seeded source and executable",
            str(s.count(b"\n")),
            str(sum(line.startswith(b"fn ") for line in s.split(b"\n"))),
            str((len(b) - 176) // 4), digest,
        ]).encode() + b"\n"
        assert p.returncode == 0 and p.stdout == expected, (name, p.returncode, p.stdout, expected)
        passed += 1

    for name, b in [
        ("empty", b""), ("short", binary[:175]),
        ("unaligned", binary[:-1]), ("magic", b"BAD!" + binary[4:]),
    ]:
        p = run(source, b)
        assert p.returncode == 67 and not p.stdout, (name, p.returncode, p.stdout)
        passed += 1
    p = subprocess.run([str(tool)], capture_output=True, timeout=20)
    assert p.returncode == 60 and not p.stdout
    passed += 1

print(f"SIZE_RECORD PASS cases={passed}")
