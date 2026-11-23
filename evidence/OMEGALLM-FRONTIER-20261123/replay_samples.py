"""Replay the separate 36-task diagnostic using its recorded inputs and both native engines."""
import argparse
from collections import Counter
from pathlib import Path
import hashlib
import json
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "train/omega-llm/tools/combined/experiment"))
from engines import Engines


def check_binary(binary, expected):
    with binary.open("rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != expected:
            raise ValueError(f"{binary.name} digest differs")


def replay(samples, previous, kit):
    check_binary(kit / "omc", samples["meta"]["omc"])
    for label, binary in (("prev", previous), ("corr", kit / "om_synth")):
        check_binary(binary, samples["meta"][label])
        counts = Counter()
        for task, versions in zip(samples["tasks"], samples["results"], strict=True):
            expected = versions[label]
            with tempfile.TemporaryDirectory() as tmp:
                directory = Path(tmp)
                spec, output = directory / "spec", directory / "function"
                lines = [f"arity {task['arity']}", f"depth {samples['depth']}"]
                for args, value in task["sup"]:
                    lines.append("case " + " ".join(map(str, [*args, value])))
                spec.write_text("\n".join(lines) + "\n")
                run = subprocess.run([binary, "solve", spec, output], capture_output=True, timeout=240)
                if run.returncode != expected["rc"] or run.stdout.decode().strip() != expected["stdout"]:
                    raise ValueError((task["id"], label, "solver result"))
                counts[run.returncode] += 1
                if run.returncode:
                    if output.exists() or expected["prog"] is not None:
                        raise ValueError((task["id"], label, "unexpected program"))
                    continue
                program = output.read_text()
                if program != expected["prog"]:
                    raise ValueError((task["id"], label, "program"))
                header, body = program.split("\n", 1)
                engine = Engines(kit, directory, "note evaluate the expression\n" + header + "\n")
                for field, grade in (("sup", "sup_ok"), ("hold", "hold_ok")):
                    xs, ys = zip(*task[field], strict=True)
                    answers = engine.predict(body.encode(), xs)
                    matches = sum(value == (want,) for value, want in zip(answers, ys, strict=True))
                    if matches != expected[grade]:
                        raise ValueError((task["id"], label, field, "grade"))
                counts["correct"] += expected["hold_ok"] == len(task["hold"])
        print(label, dict(counts))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt", type=Path)
    parser.add_argument("previous_synth", type=Path)
    parser.add_argument("kit", type=Path)
    args = parser.parse_args()
    replay(json.loads(args.receipt.read_text())["independent_samples"], args.previous_synth.resolve(), args.kit.resolve())
