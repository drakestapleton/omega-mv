"""Subprocess boundary for the CPU experiment. No references or final labels enter this module."""
from pathlib import Path
import subprocess


class ComponentFailure(RuntimeError):
    def __init__(self, argv, result):
        self.details = {"component": Path(argv[0]).name, "exit": result.returncode,
                        "stderr": result.stderr.decode(errors="replace")[-500:]}
        super().__init__(self.details)


def invoke(argv, permitted):
    timeout = 2400 if Path(argv[0]).name == "solve" else 240
    result = subprocess.run(argv, capture_output=True, timeout=timeout)
    if result.returncode not in permitted:
        raise ComponentFailure(argv, result)
    return result


class Engines:
    def __init__(self, kit, scratch, prompt):
        self.kit = Path(kit).resolve()
        self.scratch = Path(scratch).resolve()
        self.prompt = self.scratch / "task.prompt"
        self.prompt.write_text(prompt)
        self.header = prompt.splitlines()[1]
        self.shape = (5 if " edit " in self.header else 4 if " view " in self.header
                      else self.header.count(" ulong") - 1)
        self.cache = {}

    def baseline(self, observations):
        examples = self.scratch / "examples"
        examples.write_text("".join(" ".join(map(str, (*x, *y)))+"\n" for x,y in observations))
        r = invoke([self.kit/"solve", self.prompt, examples], (0, 1))
        if r.returncode == 1:
            if r.stdout or r.stderr.strip() != b"combined: no candidate passed the supplied examples":
                raise RuntimeError(("unexpected abstention", r.stderr))
            return None, "abstain"
        return r.stdout, r.stderr.decode().strip()

    def predict(self, body, xs):
        cache = self.cache.setdefault(body, {})
        missing = list(dict.fromkeys(tuple(x) for x in xs if tuple(x) not in cache))
        for start in range(0, len(missing), 24):
            self._predict_batch(body, missing[start:start+24], cache)
        return [cache[tuple(x)] for x in xs]

    def _predict_batch(self, body, xs, cache):
        bodyfile, inputs = self.scratch/"body", self.scratch/"arguments"
        bodyfile.write_bytes(body)
        inputs.write_text("".join(" ".join(map(str, x))+"\n" for x in xs))
        result = invoke([self.kit/"predict", self.kit, self.scratch, self.kit/"omc",
                         self.prompt, bodyfile, inputs], (0, 1, 2))
        if result.returncode == 2 and len(xs) > 1:
            middle = len(xs)//2
            self._predict_batch(body, xs[:middle], cache)
            self._predict_batch(body, xs[middle:], cache)
        elif result.returncode:
            cache.update((x, None) for x in xs)
        else:
            lines = (self.scratch/"bench-out").read_text().splitlines()
            values = [tuple(map(int, line.split())) for line in lines]
            if len(values) != len(xs) or any(len(y) != (8 if self.shape == 5 else 1) for y in values):
                raise RuntimeError("incomplete sandbox predictions")
            cache.update(zip(xs, values))

    def examples_spec(self, observations, constants=(0, 1, 2, 3)):
        spec = [f"arity {self.shape}", "depth 2", "consts " + " ".join(map(str, constants))]
        for x, y in observations:
            if self.shape == 4:
                row = ("fold", x[0], *x[1:1+x[0]], *y)
            else:
                row = ("rew" if self.shape == 5 else "case", *x, *y)
            spec.append(" ".join(map(str, row)))
        return ("\n".join(spec)+"\n").encode()

    def formal_spec(self):
        path = self.scratch / "english.spec"
        r = invoke([self.kit/"om_formalize", "formalize", self.prompt, path], (0, 1))
        if r.returncode:
            if not r.stdout.startswith(b"FORMALIZE_ABSTAIN"):
                raise RuntimeError(("formalizer", r.stdout, r.stderr))
            return None
        return path.read_bytes()

    def symbolic(self, generator, spec):
        path = self.scratch / "examples.spec"
        path.write_bytes(spec)
        target = self.scratch / "function.om"
        r = invoke([self.kit/generator, "solve", path, target], (0, 1))
        if r.returncode:
            expected = b"SKETCH_FAIL" if generator == "om_sketch" else b"SYNTH_FAIL"
            if not r.stdout.startswith(expected):
                raise RuntimeError((generator, r.stdout, r.stderr))
            return None
        header, body = target.read_bytes().split(b"\n", 1)
        if header != self.header.encode():
            return None
        return body
