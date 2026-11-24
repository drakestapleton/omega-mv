#!/usr/bin/env python3
"""Independent decode of an x86-64 omc image; an oracle, never part of the compiler or the package.

Usage: python3 seed/omc/decode-x86.py IMAGE [OBJDUMP]
IMAGE is the x86-64 compiler built by `cat si/directives/target-x86linux.om seed/omc/omc.om | seed/out/omc`.
It runs qualify-x86.py's `disassemble` (GNU or LLVM objdump over every code span, literal islands carved
out at their branch-around) and fails unless the header, the decoded instructions and the literal islands
account for every byte of IMAGE. Prints one summary line; exit 0 PASS, 1 FAIL.
"""
import hashlib
import importlib.util
import pathlib
import shutil
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / 'seed/omc'))
spec = importlib.util.spec_from_file_location('qualify_x86', root / 'seed/omc/qualify-x86.py')
q = importlib.util.module_from_spec(spec)
sys.modules['qualify_x86'] = q
spec.loader.exec_module(q)

image_path = pathlib.Path(sys.argv[1])
objdump = sys.argv[2] if len(sys.argv) > 2 else next(
    (p for n in ('x86_64-linux-gnu-objdump', 'llvm-objdump', 'objdump') if (p := shutil.which(n))), None)
if not objdump:
    print('NOT_RUN decode-x86: no objdump')
    sys.exit(1)
image = image_path.read_bytes()
source = b'target x86linux\n' + (root / 'seed/omc/omc.om').read_bytes()
llvm = 'llvm' in pathlib.Path(objdump).name or b'LLVM' in __import__('subprocess').run(
    [objdump, '--version'], capture_output=True).stdout
with tempfile.TemporaryDirectory() as d:
    _, instructions, carveouts = q.disassemble(image, source, objdump, llvm, pathlib.Path(d), 600)
code = sum(len(raw) for _, raw, _ in instructions)
literal = sum(b - a for a, b in carveouts)
header = min(offset for offset, _, _ in instructions)
covered = header + code + literal
verdict = 'PASS' if covered == len(image) else 'FAIL'
print(f'DECODE-X86 {verdict} image={image_path.name} sha256={hashlib.sha256(image).hexdigest()} bytes={len(image)} '
      f'header={header} instructions={len(instructions)} code={code} literal={literal} covered={covered}')
sys.exit(0 if verdict == 'PASS' else 1)
