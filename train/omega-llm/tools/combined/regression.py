"""Replay both historical conditions. The input kit supplies fixed private checkpoints."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import subprocess
import time


def command(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def fixed_examples(bench, tasks, kit, out, prompts):
    values = {
        "in1": [(x,) for x in (23, 18, 22, 27, 35, 54, 81, 210)],
        "in2": [(2,11),(13,3),(11,11),(21,0),(1,19),(32,7),(13,26),(20,4)],
        "in3": [(2,11,5),(13,3,13),(11,11,11),(21,0,0),(1,19,26),(32,7,14),(13,26,4),(20,4,1)],
        "arr": [(7,0,3,11,3,2,9,13),(9,2,3,2,1,12,0,9)],
        "cnt": [(0,), (2,), (5,), (8,)],
    }
    lines = tasks.read_text().splitlines()
    headers = [f"note {k} " + " ".join(map(str, x)) for k, xs in values.items() for x in xs]
    public = out / "public.om"
    public.write_text("\n".join(headers + [line for line in lines if not line.startswith(
        tuple(f"note {k} " for k in values))]) + "\n")
    rows = command([bench, "table", public, kit/"omc", out], capture_output=True, text=True)
    for line in rows.stdout.splitlines():
        task, *ys = line.split()
        sig = (prompts / f"prompt-{task}").read_text().splitlines()[-1]
        if " view " in sig or " edit " in sig:
            xs = [n + a for a in values["arr"] for n in values["cnt"]]
        else:
            xs = values["in" + str(sig.count(" ulong") - 1)]
        stride = 8 if " edit " in sig else 1
        assert len(ys) == len(xs) * stride
        (out / f"cases-{task}").write_text("".join(" ".join(map(str, (*x, *ys[i*stride:(i+1)*stride])))+"\n"
                                                   for i, x in enumerate(xs)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kit", type=Path)
    parser.add_argument("out", type=Path)
    parser.add_argument("--jobs", type=int, default=1)
    args = parser.parse_args()
    kit, out = args.kit.resolve(), args.out.resolve()
    out.mkdir()
    src = Path(__file__).resolve().parents[1] / "bench"
    bench = out / "bench"
    with (src/"bench.om").open("rb") as inp, bench.open("wb") as exe:
        command([kit/"omc"], stdin=inp, stdout=exe)
    bench.chmod(0o700)
    prompts = out / "prompts"
    prompts.mkdir()
    tasks = src / "tasks.om"
    command([bench, "prompts", tasks, prompts])
    fixed_examples(bench, tasks, kit, out, prompts)

    def replay(prompt):
        task = prompt.name.removeprefix("prompt-")
        argv = [kit/"solve", prompt]
        if mode == "checked":
            argv.append(out / f"cases-{task}")
        start = time.monotonic()
        result = subprocess.run(argv, capture_output=True, timeout=240)
        if result.returncode == 0:
            (answers / f"answer-{task}").write_bytes(result.stdout)
        elif mode != "checked" or result.returncode != 1 or result.stdout:
            raise RuntimeError((task, result.returncode, result.stderr))
        return {"id": task, "route": result.stderr.decode().strip(), "seconds": time.monotonic()-start}

    for mode in ("checked", "plain"):
        answers = out / mode
        answers.mkdir()
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            rows = list(pool.map(replay, sorted(prompts.glob("prompt-*"))))
        score = command([bench, "score", tasks, src/"expect.txt", kit/"omc", answers], capture_output=True, text=True)
        (answers/"score-all").write_text(score.stdout)
        verdicts = {r[1]:r[3] for line in score.stdout.splitlines() if (r:=line.split()) and r[0]=="R"}
        assert len(rows) == len(verdicts) == 165
        for row in rows:
            row["verdict"] = verdicts[row["id"]]
        (answers/"results.json").write_text(json.dumps(rows, indent=2)+"\n")
        print(mode, next(line for line in score.stdout.splitlines() if line.startswith("SCORE ")), flush=True)


if __name__ == "__main__":
    main()
