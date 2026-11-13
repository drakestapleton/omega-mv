#!/usr/bin/env python3
# TEST INSTRUMENT: read-only reference/compatibility checker, not product code.
# Python 3 standard library and git only. Run at the checked repository root:
#   python3 seed/host/matrix-check.py seed/host/EFFECT-MATRIX.md BASE
# It checks references, not syscall semantics or whether a cited test passed.
import re
import subprocess
import sys
from pathlib import Path, PurePosixPath

ROWS = (
    *(f"{word}:{number}" for number, word in enumerate(
        ("execfds", "capget", "capset", "opentree", "mntattr", "mntmove",
         "unshare", "mount", "umount", "pivroot", "sethost", "prctl",
         "sigmask", "sigwait", "fstatfs"), 201)),
    "execprog:124", "execpure:198", "execenv:233", "renames:125", "link:141",
    "symlnk:142", "device-group:166-177,228-232", "kfdctl:241", "kfdmap:242",
    "kfdres:243", "efi:178",
)
CELLS = {"T", "P", "W", "A", "S", "D", "L"}
# These inputs are the protected six words' pre-existing, non-pool corpus.
# Never substitute the new hostpool/legacy.om: it did not exist in BASE.
PROTECTED = {
    "execprog:124": (
        "seed/qualification/security673/exec-parent.om",
        "seed/qualification/security673/exec-child.om",
        "seed/qualification/security673/pkt-consumer.om",
        "seed/qualification/security673/packet-corpus.om",
    ),
    "execpure:198": tuple(
        f"seed/qualification/security673/pure-{suffix}.om"
        for suffix in ("launch", "child", "raw", "busy", "other", "output")
    ),
    "execenv:233": ("seed/host/execenv/execenv.om",),
    "renames:125": (
        "seed/qualification/security673/renames-consumer.om",
        "seed/qualification/security673/renames-corpus.om",
    ),
    "link:141": ("seed/host/tests/links.om", "seed/host/tests/links_short.om"),
    "symlnk:142": ("seed/host/tests/links.om",),
}


class MatrixError(Exception):
    pass


class Checker:
    def __init__(self, base: str) -> None:
        self.base = self.git("rev-parse", "--verify", f"{base}^{{commit}}").strip()
        self.tracked = set(self.git("ls-files", "-z").split("\0")) - {""}
        self.base_paths = set(self.git(
            "ls-tree", "-r", "--name-only", self.base).splitlines())
        # This is tools/samebytes.sh's unfiltered corpus predicate.
        self.corpus = {p for p in self.base_paths if p.endswith(".om")}
        self.texts: dict[str, str] = {}
        self.aliases: dict[str, str] = {}
        self.cases: dict[str, dict[str, list[str]]] = {}
        self.protected: dict[str, set[str]] = {}
        self.location = "matrix"

    @staticmethod
    def git(*args: str) -> str:
        process = subprocess.run(
            ["git", *args], capture_output=True, text=True, check=False)
        if process.returncode:
            raise MatrixError(f"git {' '.join(args)} exit={process.returncode}: "
                              f"{process.stderr.strip()}")
        return process.stdout

    def path(self, name: str) -> str:
        first, separator, rest = name.partition("/")
        name = self.aliases.get(first, first) + (separator + rest if separator else "")
        path = PurePosixPath(name)
        if path.is_absolute() or ".." in path.parts or str(path) != name:
            raise MatrixError(f"unsafe/noncanonical path {name!r}")
        return name

    def tracked_path(self, name: str) -> str:
        path = self.path(name)
        if path not in self.tracked:
            raise MatrixError(f"untracked file {path}")
        if not Path(path).is_file():
            raise MatrixError(f"missing tracked file {path}")
        return path

    def text(self, name: str) -> str:
        path = self.tracked_path(name)
        if path not in self.texts:
            self.texts[path] = Path(path).read_text(encoding="utf-8")
        return self.texts[path]

    def source(self, value: str) -> None:
        fields = value.split(":", 2)
        if len(fields) != 3 or not fields[1].isdecimal() or not fields[2]:
            raise MatrixError(f"malformed line reference {value!r}")
        path, number, symbol = fields
        lines = self.text(path).splitlines()
        line = int(number)
        if line < 1 or line > len(lines) or symbol not in lines[line - 1]:
            actual = lines[line - 1] if 1 <= line <= len(lines) else "<outside file>"
            raise MatrixError(f"{self.path(path)}:{line} lacks {symbol!r}; "
                              f"actual={actual!r}")

    def case(self, value: str) -> None:
        path_name, separator, name = value.rpartition(":")
        if not separator or not name:
            raise MatrixError(f"malformed case reference {value!r}")
        path = self.tracked_path(path_name)
        if not path.endswith(".cases"):
            raise MatrixError(f"not a cases file {path}")
        if path not in self.cases:
            entries = {}
            for line in self.text(path).splitlines():
                fields = line.split()
                if not fields or fields[0].startswith("#"):
                    continue
                if len(fields) >= 3 and fields[1] in ("run", "refuse", "emit"):
                    if fields[0] in entries:
                        raise MatrixError(f"duplicate case {fields[0]} in {path}")
                    entries[fields[0]] = fields
            self.cases[path] = entries
        if name not in self.cases[path]:
            raise MatrixError(f"missing case {name!r} in {path}")
        # Check the source(s), stdin, expected stdout and stderr of the cited row.
        fields = self.cases[path][name]
        for source in fields[2].split("+"):
            self.tracked_path(source)
        for field in fields[3:]:
            if field.startswith("file:"):
                self.tracked_path(field[5:])

    def legacy(self, value: str, row: str) -> None:
        path = self.tracked_path(value)
        if path not in self.base_paths:
            raise MatrixError(f"protected fixture absent from base {self.base}: {path}")
        if path.endswith(".om") and path not in self.corpus:
            raise MatrixError(f"protected fixture outside samebytes corpus: {path}")
        blob = self.git("rev-parse", f"{self.base}:{path}").strip()
        current = self.git("hash-object", "--", path).strip()
        if blob != current:
            raise MatrixError(f"protected fixture differs from base: {path}")
        self.protected.setdefault(row, set()).add(path)

    @staticmethod
    def function(text: str, name: str) -> str:
        lines = text.splitlines(keepends=True)
        starts = [i for i, line in enumerate(lines)
                  if re.match(rf"^fn {re.escape(name)}(?: |\n|$)", line)]
        if len(starts) != 1:
            raise MatrixError(f"function {name} has {len(starts)} definitions")
        start = starts[0]
        end = next((i for i in range(start + 1, len(lines))
                    if lines[i].startswith("fn ")), len(lines))
        # Comments preceding the next function are not part of this function.
        while end > start and (not lines[end - 1].strip()
                               or lines[end - 1].startswith("note ")):
            end -= 1
        return "".join(lines[start:end])

    def token(self, token: str, row: str) -> None:
        kind, separator, value = token.partition(":")
        if kind not in {"src", "test", "case", "check", "file", "mutant",
                        "legacy", "samefn"}:
            return
        if not separator or not value:
            raise MatrixError(f"malformed token {token!r}")
        if kind in ("src", "test"):
            self.source(value)
        elif kind == "case":
            self.case(value)
        elif kind == "file":
            self.tracked_path(value)
        elif kind == "mutant":
            self.tracked_path(value + ".from")
            self.tracked_path(value + ".to")
        elif kind == "legacy":
            self.legacy(value, row)
        elif kind == "samefn":
            path, colon, name = value.partition(":")
            if not colon or not name:
                raise MatrixError(f"malformed samefn token {token!r}")
            path = self.tracked_path(path)
            base_text = self.git("show", f"{self.base}:{path}")
            if self.function(self.text(path), name) != self.function(base_text, name):
                raise MatrixError(f"function {path}:{name} differs from base")
        elif kind == "check":
            path, hashmark, number = value.partition("#")
            if not hashmark or not re.fullmatch(r"[1-9]\d*(?:-[1-9]\d*)?", number):
                raise MatrixError(f"malformed check token {token!r}")
            self.tracked_path(path)

    def run(self, matrix: str) -> tuple[int, int]:
        row = "shared"
        cells: dict[str, set[str]] = {}
        not_covered = []
        tokens = 0
        active = False
        for number, line in enumerate(matrix.splitlines(), 1):
            self.location = f"row={row} matrix-line={number}"
            if line.startswith("@alias "):
                fields = line.split()
                if len(fields) != 3 or fields[1] in self.aliases:
                    raise MatrixError("malformed/duplicate alias")
                self.aliases[fields[1]] = self.tracked_directory_alias(fields[2])
                active = True
                continue
            if line.startswith("### ROW "):
                row = line[8:]
                self.location = f"row={row} matrix-line={number}"
                if row not in ROWS or row in cells:
                    raise MatrixError("unknown/duplicate row")
                cells[row] = set()
            if not active:
                continue  # The grammar examples precede the first alias.
            if line.startswith("- ") and row in cells:
                match = re.fullmatch(
                    r"- ([TPWASDL]): (.+) \|\| EVIDENCE: (.+)", line)
                if not match:
                    raise MatrixError("malformed matrix cell")
                key, claim, evidence = match.groups()
                if key in cells[row]:
                    raise MatrixError(f"duplicate cell {key}")
                cells[row].add(key)
                if not re.search(r"`src:[^`]+`", claim):
                    raise MatrixError(f"cell {key} has no source reference")
                if "NOT_COVERED:" in evidence:
                    reason = evidence.split("NOT_COVERED:", 1)[1].strip()
                    if not reason:
                        raise MatrixError(f"cell {key} has empty NOT_COVERED reason")
                    not_covered.append((row, key, reason))
                elif not ("N/A:" in evidence or re.search(
                        r"`(?:case|check|test|legacy):[^`]+`", evidence)):
                    raise MatrixError(f"cell {key} lacks case/check or coverage label")
            for token in re.findall(r"`([^`\n]+)`", line):
                self.token(token, row)
                tokens += 1
        self.location = "row=inventory"
        if set(cells) != set(ROWS):
            raise MatrixError(f"row set differs: missing={sorted(set(ROWS)-set(cells))}")
        for row in ROWS:
            self.location = f"row={row}"
            if cells[row] != CELLS:
                raise MatrixError(f"missing cells {sorted(CELLS-cells[row])}")
            for path in PROTECTED.get(row, ()):
                if path not in self.protected.get(row, set()):
                    raise MatrixError(f"missing protected-fixture citation {path}")
        for row, cell, reason in not_covered:
            print(f"NOT_COVERED row={row} cell={cell}: {reason}")
        print(f"MATRIX-CHECK REFERENCES tokens={tokens} base={self.base} "
              f"protected_om={len({p for ps in PROTECTED.values() for p in ps})}")
        return len(cells), len(not_covered)

    @staticmethod
    def tracked_directory_alias(name: str) -> str:
        path = PurePosixPath(name)
        if path.is_absolute() or ".." in path.parts or str(path) != name:
            raise MatrixError(f"unsafe alias path {name!r}")
        return name


def main() -> int:
    checker = None
    try:
        if len(sys.argv) != 3:
            raise MatrixError("usage: matrix-check.py MATRIX BASE (cwd=repository root)")
        checker = Checker(sys.argv[2])
        matrix = Path(sys.argv[1]).read_text(encoding="utf-8")
        rows, not_covered = checker.run(matrix)
        print(f"MATRIX-CHECK PASS rows={rows} not_covered={not_covered}")
        return 0
    except (MatrixError, OSError, UnicodeError, ValueError) as error:
        where = checker.location if checker is not None else "row=setup"
        print(f"MATRIX-CHECK FAIL {where}: {error}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
