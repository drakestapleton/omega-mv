#!/usr/bin/env python3
"""External oracle for the native daily interface; no production dependency."""
import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BIN = Path(os.environ.get('BIN', ROOT / 'build/trit/trit')).resolve()
WORK = Path(tempfile.mkdtemp(prefix='trit-daily-', dir=os.environ.get('TMPDIR')))
CB = (ROOT / 'tools/codebook/codebook.tsv').read_bytes()
CBHASH = hashlib.sha256(CB).hexdigest()
checks = []

def fresh(name):
    d = WORK / name
    (d / 'inbox').mkdir(parents=True)
    (d / 'codebook').mkdir()
    (d / 'codebook/codebook.tsv').write_bytes(CB)
    (d / 'codebook/key').write_bytes(secrets.token_bytes(32))
    (d / 'codebook/key').chmod(0o600)
    (d / 'inbox/alice.md').touch()
    (d / 'inbox/bob.md').touch()
    return d

def line(d, lane='n', ts='2026-11-16T20:00', sender='alice', to='bob', tag='stop', text='STOP task', counter=1, digits='300', signed=True):
    fields = '|'.join((ts, sender, to, tag, text, '-'))
    if signed:
        payload = f'ocb2|{CBHASH}|{counter}|{lane}|{fields}|{digits}'.encode()
        mac = hmac.new((d / 'codebook/key').read_bytes(), payload, hashlib.sha256).hexdigest()
        fields += f'|ocb2:{CBHASH}:{counter}:{digits}:{mac}'
    return (fields + '\n').encode()

def put(d, body, lane='n'):
    f = d / ('inbox/bob.emergency.md' if lane == 'e' else 'inbox/bob.md')
    f.write_bytes(body)
    return f'{lane}{len(body)}:{hashlib.sha256(body).hexdigest()}'

def run(name, d, args, rc, stdout=b'', stderr=b''):
    command = [str(BIN), str(d), *args]
    p = subprocess.run(command, capture_output=True)
    ok = (p.returncode, p.stdout, p.stderr) == (rc, stdout, stderr)
    record = {'name': name, 'command': command, 'exit': p.returncode,
              'stdout': p.stdout.decode(errors='replace'), 'stderr': p.stderr.decode(errors='replace'),
              'expected_exit': rc, 'expected_stdout': stdout.decode(), 'pass': ok,
              'inputs': {f.relative_to(d).as_posix(): hashlib.sha256(f.read_bytes()).hexdigest()
                         for f in (d / 'inbox').glob('*') if f.is_file()}}
    checks.append(record)
    print(('PASS ' if ok else 'FAIL ') + name)
    return p

for name, kw, lane in [
    ('signed-stop', {}, 'n'), ('old-unseen-stop', {'ts':'2020-01-01T00:00'}, 'n'),
    ('key-holder-claims-drake', {'sender':'drake'}, 'n'),
    ('unsigned-stop', {'signed':False}, 'n'), ('wrong-recipient', {'to':'other'}, 'n'),
    ('signed-emergency', {'lane':'e'}, 'e'),
    ('task', {'tag':'task', 'text':'Read task', 'digits':'101'}, 'n')]:
    d = fresh(name)
    body = line(d, **kw)
    token = put(d, body, lane)
    run(name, d, ['--inspect', 'bob'], 0, f'bob 1 {token}\n'.encode())
    if name in ('signed-stop', 'old-unseen-stop', 'key-holder-claims-drake', 'signed-emergency'):
        run(name+'-legacy-control', d, ['bob'], 0, f'bob 2 {token}\n'.encode())
    run(name+'-consume', d, ['--consume', 'bob', token], 0)
    run(name+'-after-consume', d, ['--inspect', 'bob'], 1)

# A changed signature must still be inspected, never treated as stop authority.
d = fresh('tamper')
body = line(d).replace(b'STOP task', b'STOP changed')
token = put(d, body)
run('tampered-stop', d, ['--inspect', 'bob'], 0, f'bob 1 {token}\n'.encode())

# Consuming one token may not emit a receipt or silently consume later work.
d = fresh('append')
first = line(d, tag='task', text='First', digits='101')
token = put(d, first)
second = line(d, tag='task', text='Second', digits='101', counter=2)
whole = first + second
later = put(d, whole)
run('consume-silent-with-next-task', d, ['--consume', 'bob', token], 0)
run('next-task-still-unread', d, ['--inspect', 'bob'], 0, f'bob 1 {later}\n'.encode())
cursor = d/'inbox/bob.md.cur'
cur = cursor.read_bytes() if cursor.exists() else None
run('bad-token', d, ['--consume', 'bob', 'n1:'+'0'*64], 3)
checks.append({'name':'bad-token-keeps-cursor', 'pass':cur is not None and cursor.exists() and cursor.read_bytes()==cur})
run('legacy-ack-still-receipt', d, ['--ack', 'bob', later], 0, b'bob 0\n')

# Empty and informational records do not wake. Multiple recipients remain independent.
d = fresh('quiet')
run('empty', d, ['--inspect', 'bob'], 1)
put(d, line(d, tag='fyi', text='Status only', signed=False))
run('informational', d, ['--inspect', 'bob'], 1)
run('inspect-no-recipient', d, ['--inspect'], 2)
run('consume-no-token', d, ['--consume', 'bob'], 2)
run('consume-extra-arg', d, ['--consume', 'bob', 'n0:'+'0'*64, 'extra'], 2)
run('invalid-recipient', d, ['--inspect', '../bob'], 2)
token = put(d, line(d, tag='task', text='Work', digits='101'))
run('multiple-recipients', d, ['--inspect', 'alice', 'bob'], 0, f'bob 1 {token}\n'.encode())

receipt = {'binary': str(BIN), 'binary_sha256':hashlib.sha256(BIN.read_bytes()).hexdigest(),
           'codebook_sha256':CBHASH, 'scope':'host fixture only; no process control, no runtime authority claimed', 'checks':checks}
(WORK/'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
failed = sum(not c['pass'] for c in checks)
print(f'DAILY checks={len(checks)} failed={failed} receipt={WORK}/receipt.json')
raise SystemExit(bool(failed))
