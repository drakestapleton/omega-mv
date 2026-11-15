#!/usr/bin/env python3
# TEST INSTRUMENT: rewrite EFFECT-MATRIX source/test anchors as content windows.
# A line number is not an anchor. Each citation becomes PATH:TEXT#N:12HEX, the
# sha256 of the shortest run of lines ending on the cited line that occurs once
# in that file. Inserting a line elsewhere does not change the window bytes.
# Line-number citations are resolved against --from (the tree that numbered them)
# and then located in the working tree, including the one site this rebase
# renumbered (628|hdecb -> 631|hdecb).
import hashlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def git_show(rev: str, path: str) -> str:
    process = subprocess.run(
        ["git", "show", f"{rev}:{path}"], cwd=ROOT, capture_output=True, check=False)
    if process.returncode:
        raise SystemExit(f"git show {rev}:{path} failed")
    return process.stdout.decode()


def unique_window(lines: list[str], end: int) -> tuple[int, str] | None:
    for n in range(1, end + 2):
        window = lines[end + 1 - n:end + 1]
        count = 0
        for i in range(n - 1, len(lines)):
            if lines[i + 1 - n:i + 1] == window:
                count += 1
                if count > 1 and n < 40:
                    break
        if count == 1:
            blob = "\n".join(window).encode()
            return n, hashlib.sha256(blob).hexdigest()[:12]
    return None


def locate(old: list[str], new: list[str], line_no: int, text: str) -> tuple[int, int, str]:
    idx = line_no - 1
    if not (0 <= idx < len(old) and text in old[idx]):
        hits = [i for i, line in enumerate(old) if text in line]
        if len(hits) != 1:
            raise SystemExit(f"old line {line_no} text {text!r} hits {len(hits)}")
        idx = hits[0]
    found = unique_window(old, idx)
    if found is None:
        raise SystemExit(f"no unique window for {text!r} at old line {line_no}")
    n, _digest = found
    window = old[idx + 1 - n:idx + 1]
    candidates = [window]
    swapped = []
    for line in window:
        line = line.replace("628|hdecb", "631|hdecb")
        line = line.replace("put d2site 0 628", "put d2site 0 631")
        swapped.append(line)
    if swapped != window:
        candidates.append(swapped)
    hit = None
    for cand in candidates:
        found_at = []
        width = len(cand)
        for i in range(width - 1, len(new)):
            if new[i + 1 - width:i + 1] == cand:
                found_at.append(i)
        if len(found_at) == 1:
            hit = found_at[0]
            break
    if hit is None:
        raise SystemExit(f"window for {text!r} (old line {line_no}) is not in the working tree")
    fresh = unique_window(new, hit)
    if fresh is None:
        raise SystemExit(f"working tree has no unique window for {text!r}")
    return fresh[0], hit, fresh[1]


def main() -> None:
    rev = "fc19607784251ba002d59788fc294c5ec852c3c2"
    if len(sys.argv) == 3 and sys.argv[1] == "--from":
        rev = sys.argv[2]
    path = ROOT / "seed/host/EFFECT-MATRIX.md"
    matrix = path.read_text(encoding="utf-8")
    aliases = {}
    cache: dict[str, tuple[list[str], list[str]]] = {}
    converted = 0

    def lines_for(name: str) -> tuple[list[str], list[str]]:
        if name not in cache:
            real = aliases.get(name, name)
            old = git_show(rev, real).splitlines()
            new = (ROOT / real).read_text(encoding="utf-8").splitlines()
            cache[name] = (old, new)
        return cache[name]

    def repl_token(token: str) -> str:
        nonlocal converted
        kind, _, value = token.partition(":")
        if kind not in ("src", "test"):
            return token
        if re.search(r"#[1-9][0-9]*:[0-9a-f]{12}$", value):
            return token
        if not re.search(r":[0-9]+:", value):
            return token
        # PATH may contain slashes. The line number is the decimal field
        # immediately before the cited text.
        match = re.match(r"^(.*):([0-9]+):(.+)$", value)
        if not match:
            raise SystemExit(f"unparsed anchor {token}")
        name, number, text = match.groups()
        old, new = lines_for(name)
        n, _hit, digest = locate(old, new, int(number), text)
        converted += 1
        return f"{kind}:{name}:{text}#{n}:{digest}"

    out_lines = []
    active = False
    for line in matrix.splitlines():
        if line.startswith("@alias "):
            _tag, key, dest = line.split()
            aliases[key] = dest
            active = True
        if active and "`" in line:
            line = re.sub(r"`([^`\n]+)`", lambda m: "`" + repl_token(m.group(1)) + "`", line)
        out_lines.append(line)
    text = "\n".join(out_lines) + "\n"
    text = text.replace(
        "Status: DRAFT for `seed/host/EFFECT-MATRIX.md`. Originally inspected at "
        "`a58a31a29ed59122fc2b1d3b8462ce18fc98446a`; references refreshed for the "
        "parent-integrated\nhead `59eeee611acf990dbabba3e9198a4ab828551acb` "
        "(base: Radicle main `2ee0a70d1830581b706f288e722f3329d51f3583`).\n"
        "The compiler bytes are unchanged by that restack; the gate-pools script anchor moved.\n",
        "Status: the anchors below are content windows, regenerated from the tree by "
        "`seed/host/matrix-anchors.py`. A cited line is the text plus a hash of the "
        "shortest unique run of lines ending there.\n",
    )
    text = text.replace(
        "- `src:PATH:LINE:TEXT` the line holds TEXT at the checked tree (a claim's source).\n"
        "- `test:PATH:LINE:TEXT` the same check, used as evidence inside a gate script or fixture.\n",
        "- `src:PATH:TEXT#N:HEX` TEXT occurs on exactly one line whose N-line window hashes to HEX "
        "(a claim's source). A line number is not accepted.\n"
        "- `test:PATH:TEXT#N:HEX` the same check, used as evidence inside a gate script or fixture.\n",
    )
    path.write_text(text, encoding="utf-8")
    print(f"MATRIX-ANCHORS WROTE tokens={converted}")


if __name__ == "__main__":
    main()
