#!/usr/bin/env python3
# TEST INSTRUMENT: the owner named by pool declarations that used to point at a
# stand-in. It compiles each declaring unit on its own (the view-parameter
# refusal) and compiles the composition the real gate names. No GPU is opened.
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
OWNER = "seed/omc/tests/pools/compose-owner.sh"
LAUNCH = (
    "gpu/amd/kfd/launch/device.om",
    "gpu/amd/kfd/launch/dispatch.om",
    "gpu/amd/kfd/launch/plan.om",
)


def text_row(path: Path, marker: str) -> str:
    for line in path.read_text(encoding="utf-8").splitlines():
        if marker in line and '"' in line:
            return line.split('"', 1)[1].rsplit('"', 1)[0]
    raise SystemExit(f"no {marker} row in {path}")


def launch_a64() -> tuple[str, str, list[str]]:
    row = text_row(ROOT / "gpu/amd/gate.om", "launch-a64 ")
    body = row.split("launch-a64 ", 1)[1].split("|", 1)[0].split()
    parts = []
    for item in body:
        if item == "+om2":
            parts.append("om2")
        elif item.startswith("+"):
            raise SystemExit(f"launch-a64 has unexpected flag {item}")
        else:
            parts.append(item)
    return "launch-a64", "gpu/amd/gate.om", parts


def runtime_rows() -> list[tuple[str, list[str]]]:
    rows = []
    path = ROOT / "gpu/runtime/checks.tsv"
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        name, parts, *_rest = line.split("\t")
        rows.append((name, parts.split(",")))
    return rows


def nvidia_rows() -> list[tuple[str, list[str]]]:
    rows = []
    path = ROOT / "gpu/nvidia/checks/checks.tsv"
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        # NAME TABLE PART...
        rows.append((fields[0], fields[2:]))
    return rows


def cat_parts(path: Path) -> list[str] | None:
    for line in path.read_text(encoding="utf-8").splitlines():
        if "cat " not in line or ".om" not in line:
            continue
        chunk = line
        if "cat " in chunk:
            chunk = chunk.split("cat ", 1)[1]
        chunk = chunk.split("|", 1)[0].replace(";", " ")
        files = [word for word in chunk.split() if word.endswith(".om")]
        if not files:
            continue
        parts = []
        if "om2" in line:
            parts.append("om2")
        parts.extend(files)
        return parts
    return None


def recipe(unit: str) -> tuple[str, str, list[str]]:
    if unit in LAUNCH:
        return launch_a64()
    for name, parts in runtime_rows():
        if unit in parts:
            return name, "gpu/runtime/checks.tsv", parts
    for name, parts in nvidia_rows():
        if unit in parts:
            return name, "gpu/nvidia/checks/checks.tsv", parts
    found = cat_parts(ROOT / unit)
    if found:
        return "cat", unit, found
    raise SystemExit(f"no composition for {unit}")


def declaring_units() -> list[str]:
    # Tracked units only. A host-check copy under build/ repeats the note and is not a unit.
    listed = subprocess.run(
        ["git", "ls-files", "*.om"], cwd=ROOT, check=True, capture_output=True, text=True)
    found = []
    for rel in listed.stdout.splitlines():
        text = (ROOT / rel).read_text(encoding="utf-8", errors="replace")
        if f"owner={OWNER}" in text:
            found.append(rel)
    return sorted(found)


def reason(unit: str) -> str:
    name, source, parts = recipe(unit)
    shown = " ".join(parts)
    return (
        f"compile=16 refusal=standalone-view. "
        f"Composed by {name} in {source} as {shown}."
    )


def blob(parts: list[str]) -> bytes:
    chunks = []
    for part in parts:
        if part == "om2":
            chunks.append(b"om2\n")
        else:
            data = (ROOT / part).read_bytes()
            chunks.append(data)
            if not data.endswith(b"\n"):
                chunks.append(b"\n")
    return b"".join(chunks)


def compile_bytes(omc: str, data: bytes) -> tuple[int, str]:
    process = subprocess.run(
        [omc], input=data, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, check=False)
    err = process.stderr.decode(errors="replace")
    return process.returncode, err


def main() -> int:
    omc = sys.argv[1]
    args = [arg for arg in sys.argv[2:] if not arg.startswith("/")]
    mode = args[0] if args else "compile"
    units = declaring_units()
    if not units:
        print("compose-owner: no declaring units")
        return 1
    if mode == "--recipes":
        for unit in units:
            name, source, parts = recipe(unit)
            print(f"{unit}\t{name}\t{source}\t{' '.join(parts)}")
        return 0
    if mode == "--reasons":
        for unit in units:
            print(f"{unit}\t{reason(unit)}")
        return 0
    if mode != "compile":
        print(f"compose-owner: unknown mode {mode}")
        return 2
    failed = 0
    seen = {}
    for unit in units:
        code, err = compile_bytes(omc, (ROOT / unit).read_bytes())
        if code != 16:
            print(f"FAIL standalone {unit} exit={code} {err.strip()}")
            failed += 1
        else:
            print(f"ok standalone {unit} exit=16")
        name, source, parts = recipe(unit)
        key = tuple(parts)
        if key in seen:
            print(f"ok composition {unit} shares {seen[key]}")
            continue
        code, err = compile_bytes(omc, blob(parts))
        seen[key] = f"{name} in {source}"
        if code != 0:
            print(f"FAIL composition {unit} via {name} in {source} exit={code} {err.strip()[:400]}")
            failed += 1
        else:
            print(f"ok composition {unit} via {name} in {source}")
    if failed:
        print(f"compose-owner FAIL {failed}")
        return 1
    print(f"compose-owner PASS units={len(units)} compositions={len(seen)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
