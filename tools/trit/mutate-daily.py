#!/usr/bin/env python3
"""External mutation instrument for daily-interface assertions; no runtime role."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
OMC = Path(os.environ.get('OMC', ROOT / 'seed/out/omc')).resolve()
SOURCE = Path(os.environ.get('COMPOSED', ROOT / 'build/trit/trit.full.om')).resolve()
WORK = Path(tempfile.mkdtemp(prefix='daily-mutants-', dir=os.environ.get('TMPDIR')))
source = SOURCE.read_text()
cases = [
    ('baseline', None, None),
    ('stop-promoted', 'put outb o 49', 'put outb o add uchar open t 48'),
    ('receipt-leak', 'if consume\nzap\nret 0', 'if consume\nreceipt\nzap\nret 0'),
    ('next-wake-leak', 'if consume\nzap\nret 0', 'if consume\nz = emit state\nzap\nret 0'),
    ('consume-bypassed', 'doack ulong tn\nif consume', 'note omitted consumption\nif consume'),
    ('help-suppressed', 'if and eq get helping 0 1 ne open t 2\nput outb o 48',
     'if and eq get helping 0 1 ne open t 2\nput outb o 49'),
    ('help-unverified', 'if or ne get signaling 0 1 ne get vf 0 1',
     'if ne get signaling 0 1'),
    ('receipt-becomes-help', 'text ttaskcode "101"', 'text ttaskcode "100"'),
    ('help-lane-leak', 'pbase 0\nput helping 0 0\ntn = tritmk 0',
     'pbase 0\ntn = tritmk 0'),
    ('help-hides-stop', 'if and eq get helping 0 1 ne open t 2',
     'if eq get helping 0 1'),
]
records = []
failed = False
for name, before, after in cases:
    d = WORK / name
    d.mkdir()
    if before is not None and source.count(before) != 1:
        records.append({'name':name, 'verdict':'NOT_APPLIED'})
        failed = True
        break
    text = source if before is None else source.replace(before, after)
    (d/'input.om').write_text(text)
    binary = d/'trit'
    with binary.open('wb') as output:
        p = subprocess.run([str(OMC)], input=text.encode(), stdout=output, stderr=subprocess.PIPE)
    (d/'compiler.stderr').write_bytes(p.stderr)
    item = {'name':name, 'compile_command':[str(OMC)], 'compile_exit':p.returncode,
            'input_sha256':hashlib.sha256(text.encode()).hexdigest()}
    records.append(item)
    if p.returncode:
        item['verdict'] = 'INVALID'
        failed = True
        break
    binary.chmod(0o755)
    cmd = ['python3', str(ROOT/'tools/trit/test-daily.py')]
    p = subprocess.run(cmd, env=dict(os.environ, BIN=str(binary), TMPDIR=str(d)), capture_output=True)
    (d/'test.stdout').write_bytes(p.stdout)
    (d/'test.stderr').write_bytes(p.stderr)
    totals = re.findall(rb'^DAILY checks=([0-9]+) failed=([0-9]+) receipt=.+$', p.stdout, re.M)
    good = False
    if len(totals) == 1 and int(totals[0][0]) > 0:
        failures = int(totals[0][1])
        good = (p.returncode == 0 and failures == 0) if before is None else (
            p.returncode == 1 and failures > 0 and re.search(rb'^FAIL ', p.stdout, re.M) is not None)
    item.update(test_command=cmd, test_exit=p.returncode, binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
                stdout_sha256=hashlib.sha256(p.stdout).hexdigest(), stderr_sha256=hashlib.sha256(p.stderr).hexdigest(),
                verdict=('BASELINE_PASS' if before is None else 'KILLED') if good else 'REJECTED')
    print(name, item['verdict'])
    if not good:
        failed = True
        break
(WORK/'receipt.json').write_text(json.dumps({'compiler_sha256':hashlib.sha256(OMC.read_bytes()).hexdigest(),
    'composed_input_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(), 'records':records}, indent=2)+'\n')
print(f'DAILY-MUTATIONS {"FAIL" if failed else "PASS"} receipt={WORK}/receipt.json')
raise SystemExit(bool(failed))
