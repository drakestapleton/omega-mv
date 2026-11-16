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

def line(d, lane='n', ts='2026-11-16T20:00', sender='alice', to='bob', tag='stop', text='STOP task', ref='-', counter=1, digits='300', signed=True):
    fields = '|'.join((ts, sender, to, tag, text, ref))
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
              'inputs': {str(f.relative_to(d)): hashlib.sha256(f.read_bytes()).hexdigest()
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

# Current help wire: explicit signed help task, with a reason and task reference.
# The existing task code 101 binds the record; receipt 100 never becomes help.
help_fields = dict(tag='help', text='Need a second checker; still working', ref='task-42', digits='101')
for name, change, expected in [
    ('help', {}, 0), ('unsigned-help', {'signed':False}, 1),
    ('wrong-recipient-help', {'to':'carol'}, 1),
    ('receipt-tagged-help', {'digits':'100'}, 1),
    ('mixed-receipt-help', {'digits':'101100'}, 1),
    ('emergency-tagged-help', {'digits':'300'}, 1),
    ('help-without-reason', {'text':''}, 1),
    ('help-blank-reason', {'text':' \t '}, 1),
    ('help-without-task', {'ref':''}, 1), ('help-dash-task', {'ref':'-'}, 1),
    ('help-blank-task', {'ref':' \t '}, 1), ('task-is-not-help', {'tag':'task'}, 1),
    ('help-tag-case', {'tag':'HELP'}, 1),
    ('key-holder-claims-sender', {'sender':'drake'}, 0),
]:
    d = fresh(name)
    token = put(d, line(d, **dict(help_fields, **change)))
    before = {str(f.relative_to(d)):f.read_bytes() for f in d.rglob('*') if f.is_file()}
    run(name+'-signal', d, ['--signal', 'bob'], 0, f'bob {expected} {token}\n'.encode())
    after = {str(f.relative_to(d)):f.read_bytes() for f in d.rglob('*') if f.is_file()}
    checks.append({'name':name+'-read-only', 'pass':before == after})
    run(name+'-inspect', d, ['--inspect', 'bob'], 0, f'bob 1 {token}\n'.encode())
    if name == 'help':
        run('help-legacy-stays-task', d, ['bob'], 0, f'bob 1 {token}\n'.encode())
    run(name+'-silent-consume', d, ['--consume', 'bob', token], 0)
    run(name+'-quiet', d, ['--signal', 'bob'], 1)

d = fresh('help-replay')
body = line(d, **help_fields)
token = put(d, body)
run('help-first', d, ['--signal', 'bob'], 0, f'bob 0 {token}\n'.encode())
run('help-consumed', d, ['--consume', 'bob', token], 0)
again = put(d, body + body)
run('help-replay-inspection', d, ['--signal', 'bob'], 0, f'bob 1 {again}\n'.encode())

d = fresh('help-tamper')
token = put(d, line(d, **help_fields).replace(b'Need a second', b'Need a forged'))
run('help-bad-mac', d, ['--signal', 'bob'], 0, f'bob 1 {token}\n'.encode())
d = fresh('help-no-key')
token = put(d, line(d, **help_fields))
(d/'codebook/key').unlink()
run('help-key-missing', d, ['--signal', 'bob'], 0, f'bob 1 {token}\n'.encode())

d = fresh('help-pending-task')
first = line(d, **help_fields)
token = put(d, first)
later = put(d, first + line(d, tag='task', text='Later task', digits='101', counter=2))
run('help-mixed-window', d, ['--signal', 'bob'], 0, f'bob 0 {later}\n'.encode())
run('help-consume-prefix-silent', d, ['--consume', 'bob', token], 0)
run('help-later-task-unread', d, ['--signal', 'bob'], 0, f'bob 1 {later}\n'.encode())

d = fresh('help-and-stop')
token = put(d, line(d, **help_fields) + line(d, counter=2))
run('stop-dominates-help-inspection-only', d, ['--signal', 'bob'], 0, f'bob 1 {token}\n'.encode())
d = fresh('emergency-help')
token = put(d, line(d, lane='e', **help_fields), 'e')
run('help-emergency-when-normal-quiet', d, ['--signal', 'bob'], 0, f'bob 0 {token}\n'.encode())
normal = put(d, line(d, tag='task', text='Normal task', digits='101', counter=2))
run('normal-selection-kept', d, ['--signal', 'bob'], 0, f'bob 1 {normal}\n'.encode())
d = fresh('help-normal-stop-emergency')
normal = put(d, line(d, **help_fields))
emergency = put(d, line(d, lane='e', counter=2), 'e')
run('emergency-stop-selected', d, ['--signal', 'bob'], 0, f'bob 1 {emergency}\n'.encode())

d = fresh('help-quiet')
run('signal-empty', d, ['--signal', 'bob'], 1)
put(d, line(d, tag='fyi', text='Completed task', digits='100'))
run('signal-fyi', d, ['--signal', 'bob'], 1)
run('signal-no-recipient', d, ['--signal'], 2)
run('signal-invalid-recipient', d, ['--signal', '../bob'], 2)
run('signal-cannot-ack', d, ['--signal', '--ack', 'bob'], 2)
d = fresh('help-multiple')
token = put(d, line(d, **help_fields))
(d/'inbox/alice.md').write_bytes(line(d, to='alice', tag='task', text='Other task', digits='101'))
alice_body = (d/'inbox/alice.md').read_bytes()
alice_token = f'n{len(alice_body)}:{hashlib.sha256(alice_body).hexdigest()}'
run('help-state-not-shared-across-recipients', d, ['--signal', 'bob', 'alice'], 0,
    f'bob 0 {token}\nalice 1 {alice_token}\n'.encode())

receipt = {'binary': str(BIN), 'binary_sha256':hashlib.sha256(BIN.read_bytes()).hexdigest(),
           'codebook_sha256':CBHASH, 'scope':'host fixture only; no process control, no runtime authority claimed', 'checks':checks}
(WORK/'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
failed = sum(not c['pass'] for c in checks)
print(f'DAILY checks={len(checks)} failed={failed} receipt={WORK}/receipt.json')
raise SystemExit(bool(failed))
