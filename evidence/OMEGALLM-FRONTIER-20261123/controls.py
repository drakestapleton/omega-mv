"""From a post-fix repository root, run traversal controls using the repository seed."""
import json
from pathlib import Path
import subprocess
import tempfile

path = "seed/helix/ollm_factory/om_synth.om"
control = Path(path).with_name("frontier-check.om").read_text()
native = Path(path).read_text().split("fn main to int\n", 1)[0]
base = "a4aec7ed5cc8a37f3bea9f851a19f2473c9183b4"
original = subprocess.check_output(["git", "show", base + ":" + path], text=True).split("fn main to int\n", 1)[0]
cases = [
    ("fixed", native, 0),
    ("previous", original, 104),
    ("truncated", native.replace("for offset ulong sub prevE prevS",
        "span = sub prevE prevS\nif gt span 4096\nspan = ulong 4096\nend\nfor offset ulong span"), 2),
    ("missing_order", native.replace("syExpandPair i j d and ge j prevS gt i j",
                                     "syExpandPair i j d gt i j"), 3),
    ("false_solution", native.replace("if syPoolFull\nput syLvlE d get sySt 3\nret false",
                                      "if syPoolFull\nput syLvlE d get sySt 3\nret true"), 4),
]
results = {}
with tempfile.TemporaryDirectory() as folder:
    for name, program, expected in cases:
        exe = Path(folder) / name
        with exe.open("wb") as stream:
            subprocess.run(["seed/out/omc"], input=(program + control).encode(), stdout=stream, check=True)
        exe.chmod(0o700)
        results[name] = subprocess.run([exe]).returncode
        if results[name] != expected:
            raise RuntimeError((name, expected, results[name]))
print(json.dumps(results, sort_keys=True))
