#!/usr/bin/env python3
"""Targeted ARM64 EFI/HVF verifier. Test infrastructure only, never guest implementation."""
import argparse
import hashlib
import json
import platform
import shutil
import struct
import subprocess
import time
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--omc", required=True)
    ap.add_argument("--sha256", required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--firmware", type=Path, required=True)
    ap.add_argument("--runner", nargs=argparse.REMAINDER, default=[])
    args = ap.parse_args()
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        ap.error("HVF qualification requires an ARM64 Mac; emulation is not a fallback")
    qemu = shutil.which("qemu-system-aarch64")
    assert qemu and args.firmware.is_file()
    assert "hvf" in subprocess.check_output([qemu, "-accel", "help"], text=True).split()
    identity = subprocess.check_output(args.runner + ["sha256sum", args.omc], text=True).split()[0]
    if identity != args.sha256:
        raise SystemExit("compiler pin mismatch")
    args.out.mkdir(parents=True, exist_ok=False)
    root = Path(__file__).resolve().parents[2]
    tests = root / "tests/aarch64efi"
    floats = root / "tests/x86efi/float"
    rows = []

    def compile_unit(name, source, rc=0):
        case = args.out / name
        case.mkdir()
        (case / "source.om").write_bytes(source)
        run = subprocess.run(args.runner + [args.omc], input=source, capture_output=True, timeout=30)
        (case / "compile.err").write_bytes(run.stderr)
        assert run.returncode == rc, (name, run.returncode, run.stderr)
        if rc:
            rows.append({"case": name, "compile_exit": rc})
            return None
        image = case / "esp/EFI/BOOT/BOOTAA64.EFI"
        image.parent.mkdir(parents=True)
        image.write_bytes(run.stdout)
        assert run.stdout[:2] == b"MZ"
        pe = struct.unpack_from("<I", run.stdout, 60)[0]
        assert run.stdout[pe:pe+4] == b"PE\0\0"
        assert struct.unpack_from("<H", run.stdout, pe+4)[0] == 0xAA64
        assert struct.unpack_from("<H", run.stdout, pe+24+68)[0] == 10
        (case / "esp/TEST.TXT").write_bytes(b"hello")
        return case

    def boot(name, source, marker, mutation=None):
        case = compile_unit(name, source)
        if mutation:
            target = case / "esp/EFI/BOOT/BOOTAA64.EFI"
            raw = target.read_bytes()
            old, new = mutation
            assert raw.count(old) >= 1, "vector instruction missing"
            target.write_bytes(raw.replace(old, new, 1))
        log = case / "serial.log"
        cmd = [qemu, "-machine", "virt", "-accel", "hvf", "-cpu", "host", "-smp", "1",
               "-m", "256", "-bios", str(args.firmware), "-drive",
               f"format=raw,file=fat:ro:{case / 'esp'},readonly=on", "-display", "none",
               "-serial", f"file:{log}", "-monitor", "none", "-nic", "none", "-no-reboot"]
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 30
            while time.monotonic() < deadline:
                data = log.read_bytes() if log.exists() else b""
                if marker in data:
                    break
                assert proc.poll() is None, proc.stderr.read()
                time.sleep(0.1)
            else:
                raise AssertionError((name, "firmware marker missing", data[-2000:]))
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
        rows.append({"case": name, "result": "PASS", "acceleration": "hvf", "cpu": "host",
                     "source_sha256": hashlib.sha256(source).hexdigest(),
                     "image_sha256": hashlib.sha256((case / "esp/EFI/BOOT/BOOTAA64.EFI").read_bytes()).hexdigest()})
        print("PASS", name, flush=True)
        return data.replace(b"\r", b"")

    for name, marker in [("hello", b"ARM64 OMEGA EFI"), ("address", b"ARM ADDRESS PASS"),
                         ("file-wait", b"ARM FILE WAIT FLOAT PASS")]:
        boot(name, (tests / (name + ".om")).read_bytes(), marker)
    source = b"target aarch64efi\n" + (tests / "vector-dot.om").read_bytes().replace(b"fn main to int", b"fn vectest to int")
    source += b'''text vmark "ARM VECTOR PASS\\n"
text vfail "ARM VECTOR REJECTED\\n"
fn main to int
r = vectest
b = new uchar 64 0
if ne r 0
for i ulong len vfail
put b i get vfail i
end
s = efi 13 0 b 0 len vfail
ret r
end
for i ulong len vmark
put b i get vmark i
end
s = efi 13 0 b 0 len vmark
ret int s
end
'''
    boot("vector", source, b"ARM VECTOR PASS")
    # Change the vector multiply into an add in the executable, leaving the independent
    # scalar oracle intact. A successful compile and boot must still reject wrong code.
    boot("vector-mutant", source, b"ARM VECTOR REJECTED", (struct.pack('<I', 0x6e63dc43), struct.pack('<I', 0x4e63d443)))
    rows[-1]["result"] = "PASS wrong vector instruction rejected"
    prefix = b"target aarch64efi\nglobal d f64 4\nglobal x f64 4\nglobal w f64 16\nfn main to int\n"
    for name, operation in [
        ("vector-dst-bounds", b"i = ulong 3\nvmadd2 d i w 0 1.0f64\n"),
        ("vector-src-bounds", b"i = ulong 15\nvmadd2 d 0 w i 1.0f64\n"),
        ("dot-row-bounds", b"vdot4 d x 0 w 0 5 4\n"),
        ("dot-matrix-bounds", b"vdot4 d x 0 w 1 4 4\n"),
        ("dot-wrap-bounds", b"vdot4 d x 18446744073709551615 w 0 1 4\n"),
        ("dot-stride-bounds", b"vdot4 d x 0 w 0 1 3\n"),
    ]:
        boot(name, prefix + operation + b"ret 0\nend\n", b"00000067")
    compile_unit("vector-readonly", b"fn f d view f64 4 w view f64 4 to void\nvmadd2 d 0 w 0 1.0f64\nend\n", 20)
    compile_unit("vector-type", b"global d f32 4\nfn main to int\nvmadd2 d 0 d 0 1.0f64\nret 0\nend\n", 7)
    source = (floats / "efi-pre.om").read_bytes().replace(b"target x86efi", b"target aarch64efi")
    source += b"".join((floats / f).read_bytes() for f in ["body.om", "fexplog.om", "main-efi.om"])
    data = boot("float", source, b"==E")
    actual = data.split(b"==B\n", 1)[1].split(b"==E", 1)[0]
    expected = (floats / "expected.txt").read_bytes()
    assert actual == expected, "float bit parity failed"
    # Wrong arithmetic must fail the same byte-exact oracle. No tolerance is enlarged.
    mutant = source.replace(b"hf add a b", b"hf sub a b")
    assert mutant != source
    data = boot("float-mutant", mutant, b"==E")
    assert data.split(b"==B\n", 1)[1].split(b"==E", 1)[0] != expected
    rows[-1]["result"] = "PASS mutant rejected by parity oracle"
    boot("bounds", (tests / "bounds.om").read_bytes(), b"00000067")
    compile_unit("linux-refused", b"target aarch64efi\nfn main to int\nr = getpid\nret 0\nend\n", 25)
    compile_unit("bare-refused", b"target aarch64efi\nfn leaf to int\nret 0\nend\n", 25)
    compile_unit("invalid-target", b"target aarch64efx\nfn main to int\nret 0\nend\n", 25)
    receipt = {"compiler_sha256": identity, "firmware_sha256": hashlib.sha256(args.firmware.read_bytes()).hexdigest(),
               "qemu": subprocess.check_output([qemu, "--version"], text=True).splitlines()[0], "checks": rows,
               "limits": ["targeted HVF tests only", "no model, networking, browser, or performance qualification", "ARM scalar/vector numerical and bounds checks included"]}
    (args.out / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")


if __name__ == "__main__":
    main()
