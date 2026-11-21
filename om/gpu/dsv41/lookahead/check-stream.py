"""Differential host check for ST-MoE. Inputs are controls, never track data."""
from collections import Counter, defaultdict
import io
from pathlib import Path
import random
import struct
import subprocess
import sys


def reference(rows, horizon):
    tables = defaultdict(Counter)
    history = {}
    for idx, route in enumerate(rows):
        layer = idx % 40
        history[layer] = route
        if idx >= horizon:
            src = (idx - horizon) % 40
            for expert in rows[idx - horizon]:
                tables[src, expert].update(route)
        target = (layer + horizon) % 40
        scores = Counter(history.get(target, ()))
        for expert in route:
            scores.update(tables[layer, expert])
        predicted = sorted(scores, key=lambda e: (-scores[e], e))[:6]
        yield (*predicted, *([0xffffffff] * (6 - len(predicted))))


def run(binary, rows, horizon):
    data = io.BytesIO(struct.pack("<I", horizon))
    data.seek(0, 2)
    for row in rows:
        data.write(struct.pack("<6I", *row))
    return subprocess.run([binary], input=data.getvalue(), capture_output=True)


def check(binary):
    rng = random.Random(314113)
    rows = [rng.sample(range((i % 40) * 7, (i % 40) * 7 + 15), 6)
            for i in range(400)]
    for h in [1, 2, 3, 4, 40, 80]:
        result = run(binary, rows, h)
        assert result.returncode == 0, result.returncode
        assert list(struct.iter_unpack("<6I", result.stdout)) == list(reference(rows, h))
        prefix = run(binary, rows[:80], h)
        assert prefix.returncode == 0 and prefix.stdout == result.stdout[:80 * 24]
        for bad_rows in ([], rows[:39], [[1] * 6] + rows[1:]):
            assert run(binary, bad_rows, h).returncode == 65
    assert run(binary, rows, 5).returncode == 65
    print("PASS independent ST-MoE scores at six horizons and malformed stream controls")


if __name__ == "__main__":
    check(Path(sys.argv[1]).resolve())
