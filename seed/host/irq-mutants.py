#!/usr/bin/env python3
"""Read-only compiler mutation oracle. Not used by compiler or product binaries."""
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
omc, oracle, work = map(Path, sys.argv[1:])
work.mkdir(parents=True, exist_ok=True)
source = (root / 'seed/omc/omc.om').read_text()
fixture = (root / 'seed/host/tests/vfioirq.om').read_bytes()
# Each edit must build a real mutant compiler and an executable fixture. A build
# failure is INVALID, never a killed mutant. The same runtime oracle challenges it.
mutants = [
    ('device-kind', 'hload x 4 10\nfdcheck 1', 'hload x 4 10\nfdcheck 2', '1'),
    ('event-kind', 'skip = mbranch 0\nfdcheck 2', 'skip = mbranch 0\nfdcheck 1', '5'),
    ('argsz', 'e3 3942645760 31 4 3\ntrapc 1 3', 'e3 3942645760 31 4 3\nnote removed argsz refusal', '2'),
    ('count-bound', 'mimmed 4043309056 31 5 64\ntrapc 8 3', 'mimmed 4043309056 31 5 65\ntrapc 8 3', '3'),
    ('range-wrap', 'e3 3942645760 31 6 7\ntrapc 8 3', 'e3 3942645760 31 6 7\nnote removed range refusal', '8'),
    ('payload-size', 'matconst 7 4\ne3 2600500224 7 5 7', 'matconst 7 8\ne3 2600500224 7 5 7', '0'),
    ('action-allowlist', 'mimmed 4043309056 31 4 17\ntrapc 1 3', 'mimmed 4043309056 31 4 17\nnote removed action refusal', '7'),
    ('event-count-condition', 'patch19 event get oc 0\nmimmed 4043309056 31 5 0\ntrapc 0 3', 'patch19 event get oc 0\nmimmed 4043309056 31 5 0\ntrapc 1 3', '0'),
    ('disable-start', 'mimmed 4043309056 31 6 0\ntrapc 1 3\ndisdone', 'mimmed 4043309056 31 6 0\nnote removed disable start refusal\ndisdone', '<'),
    ('close-invalidation', 'if eq c 100\nhload x 0 10\nfdforget', 'if eq c 100\nhload x 0 10\nnote removed close invalidation', '6'),
    ('dup-invalidation', 'hload x 1 10\nfdforget\npatch19 baddup', 'hload x 1 10\nnote removed dup invalidation\npatch19 baddup', ';'),
    ('payload-loop', 'mimmed 3506438144 5 5 1\nmimmed 4043309056 31 5 0\nagain = mbranch 1', 'mimmed 3506438144 5 5 1\nmimmed 4043309056 31 5 0\nagain = mbranch 0', 'A'),
    ('cloexec', 'matconst 1 526336\nhsys 19', 'matconst 1 2048\nhsys 19', '0'),
]
for name, old, new, mode in mutants:
    if source.count(old) != 1:
        raise SystemExit(f'INVALID {name}: mutation site count={source.count(old)}')
    compiler = work / (name + '.omc')
    altered = source.replace(old, new)
    (work / (name + '.om')).write_text(altered)
    result = subprocess.run([str(omc)], input=altered.encode(), capture_output=True, timeout=30)
    if result.returncode:
        raise SystemExit(f'INVALID {name}: compiler build rc={result.returncode} {result.stderr!r}')
    compiler.write_bytes(result.stdout)
    compiler.chmod(0o755)
    result = subprocess.run([str(compiler)], input=fixture, capture_output=True, timeout=30)
    if result.returncode:
        raise SystemExit(f'INVALID {name}: fixture build rc={result.returncode} {result.stderr!r}')
    binary = work / (name + '.elf')
    binary.write_bytes(result.stdout)
    binary.chmod(0o755)
    expected = '0' if mode == '0' else '103'
    result = subprocess.run([str(oracle), str(binary), mode, expected, '0'], capture_output=True, timeout=10)
    (work / (name + '.log')).write_bytes(result.stdout + result.stderr)
    if result.returncode == 0:
        raise SystemExit(f'FAIL {name}: mutant survived')
    print(f'PASS killed {name} oracle_rc={result.returncode}', flush=True)
print(f'PASS IRQ compiler mutants killed={len(mutants)}')
