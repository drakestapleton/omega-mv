#!/usr/bin/env python3
"""Fail if a tracked path cannot be checked out on Windows.

Python 3.8+ stdlib. Reserved device names (CON, PRN, AUX, NUL, COM1-9,
LPT1-9, any extension), the characters <>:"|?*, ASCII controls, a trailing
dot or space, and paths that collide under case-folding are findings.
evidence/ is reported the same way and is not rewritten.
"""
from __future__ import annotations

import subprocess
import sys
from collections import defaultdict
from pathlib import Path

RESERVED = {"CON", "PRN", "AUX", "NUL"}
for _n in range(1, 10):
    RESERVED.add("COM%d" % _n)
    RESERVED.add("LPT%d" % _n)

FORBIDDEN = set('<>:"|?*')


def tracked_paths(root):
    try:
        out = subprocess.run(
            ["git", "ls-files", "-z"],
            cwd=str(root),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )
    except (OSError, subprocess.CalledProcessError):
        paths = []
        for path in root.rglob("*"):
            if ".git" in path.parts:
                continue
            if path.is_file() or path.is_dir():
                rel = path.relative_to(root).as_posix()
                if rel and not rel.startswith(".git"):
                    paths.append(rel)
        return paths
    paths = []
    for raw in out.stdout.split(b"\0"):
        if raw:
            paths.append(raw.decode("utf-8", "surrogateescape"))
    return paths


def component_findings(path):
    found = []
    for part in path.split("/"):
        if part in ("", ".", ".."):
            continue
        if part.endswith(" ") or part.endswith("."):
            found.append("trailing-dot-or-space")
        if any(ord(ch) < 32 for ch in part) or any(ch in FORBIDDEN for ch in part):
            found.append("forbidden-character")
        stem = part.split(".", 1)[0].upper()
        if stem in RESERVED:
            found.append("reserved-name")
    return found


def scan(paths):
    findings = []
    folded = defaultdict(list)
    for path in paths:
        reasons = component_findings(path)
        for reason in sorted(set(reasons)):
            findings.append((reason, path))
        folded[path.casefold()].append(path)
    for group in folded.values():
        unique = sorted(set(group))
        if len(unique) > 1:
            findings.append(("case-collision", " | ".join(unique)))
    return findings


def main(argv):
    root = Path(argv[1]).resolve() if len(argv) > 1 else Path(__file__).resolve().parents[2]
    paths = tracked_paths(root)
    findings = scan(paths)
    if not findings:
        print("windows-paths: 0 findings (%d paths)" % len(paths))
        return 0
    for reason, path in findings:
        note = ""
        if path.startswith("evidence/") or path.split(" | ")[0].startswith("evidence/"):
            note = " evidence path left unchanged"
        print("windows-paths: FINDING %s %s%s" % (reason, path, note))
    print("windows-paths: %d findings (%d paths)" % (len(findings), len(paths)))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
