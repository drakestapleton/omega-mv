#!/usr/bin/env python3
"""Independent diagnostic-v2 oracle; never part of the compiler."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
compiler = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / 'seed/out/omc'
source = root / 'seed/omc/omc.om'
text = source.read_text()
pins = re.findall(r'^text d2pin "([0-9a-f]{64})"$', text, re.M)
assert len(pins) == 1, 'source-pin-count'
normalized = re.sub(r'^text d2pin "[0-9a-f]{64}"$', 'text d2pin "' + '0' * 64 + '"', text, flags=re.M)
assert hashlib.sha256(normalized.encode()).hexdigest() == pins[0], 'source-pin-stale'
sites = dict(re.findall(r'^note d2site (\d+)\|([^\n]+)$', text, re.M))
assert len(sites) == len(re.findall(r'^note d2site ', text, re.M)), 'site-id-duplicate'
lines = text.splitlines()
function = ''
for i, line in enumerate(lines):
    if line.startswith('fn '):
        function = line.split()[1]
    if re.match(r'^(fail|nfail|unkfail) ', line):
        if line == 'fail code' and function in ('nfail', 'unkfail'):
            continue
        assert re.fullmatch(r'put d2site 0 \d+', lines[i-1]), ('site-missing', i+1)
        site = lines[i-1].split()[-1]
        assert lines[i-2].startswith('note d2site ' + site + '|'), ('site-comment-mismatch', i+1)
        assert site in sites, ('site-unregistered', site)

env = os.environ.copy()
env.pop('OMC_DIAGNOSTICS', None)
env.pop('OMC_MEMORY_MAX', None)
seen = set()
rows = []
def invoke(c, data, enabled=True, extra=None):
    e = env.copy()
    if enabled:
        e['OMC_DIAGNOSTICS'] = '2'
    e.update(extra or {})
    return subprocess.run([str(c)], input=data, capture_output=True, env=e, timeout=30)
def record(p, data):
    found = re.findall(rb'^omc-diag 2 (.*)$', p.stderr, re.M)
    assert len(found) == 1, 'record-count'
    fields = dict(x.split(b'=', 1) for x in found[0].split())
    assert int(fields[b'code']) == p.returncode, 'record-code'
    n = int(fields[b'input_bytes'])
    assert 0 <= n <= len(data), 'input-size'
    assert fields[b'input_sha256'].decode() == hashlib.sha256(data[:n]).hexdigest(), 'input-hash'
    assert fields[b'compiler_source_sha256'].decode() == pins[0], 'compiler-source-hash'
    if fields[b'input_complete'] == b'1':
        assert n == len(data), 'complete-size'
    site = fields[b'site'].decode()
    assert site.startswith('D') and site[1:] in sites, 'record-site'
    seen.add(site[1:])
    return fields
def case(name, data, extra=None):
    plain = invoke(compiler, data, False, extra)
    rich = invoke(compiler, data, True, extra)
    assert plain.returncode == rich.returncode, ('exit-parity', name)
    assert plain.stdout == rich.stdout, ('stdout-parity', name)
    if rich.returncode:
        assert rich.returncode < 100, ('compiler-trap', name, rich.stderr)
        fields = record(rich, data)
        assert b'; ' in rich.stderr.splitlines()[0], ('human-reason', name)
    else:
        assert plain.stderr == rich.stderr, ('success-stderr-parity', name)
    rows.append({'case': name, 'exit': rich.returncode})

bad = b'fn main to int\nret missing\nend\n'
good = b'fn main to int\nret 0\nend\n'
for mode in (b'', b'om2\n', b'om2 diag\n', b'check\n', b'check span\n', b'usage\n', b'ir\n',
             b'target x86linux\n', b'object\nom2\n'):
    case('profile-' + repr(mode), mode + bad)
case('good', good)
for n in (0, 1, 55, 56, 63, 64, 65, 4096, 65535, 65536, 65537, 131072):
    case('sha-boundary-' + str(n), bad + b'note ' + b'x' * n + b'\n')
case('environment-refusal', bad, {'OMC_MEMORY_MAX': 'bad'})
case('partial-input', bad + b'note ' + b'x' * 300000 + b'\n', {'OMC_MEMORY_MAX': '1'})
for fixture in sorted((root / 'seed/omc/sites').glob('*.om')):
    case(str(fixture.relative_to(root)), fixture.read_bytes())

with tempfile.TemporaryDirectory(prefix='omc-d2-') as temp:
    d = Path(temp)
    # An actual broken compiler must be detected by the independent SHA oracle.
    assert text.count('d2feed c\n') == 1, 'hash-mutant-site'
    mutant = text.replace('d2feed c\n', 'd2feed 0\n')
    p = invoke(compiler, mutant.encode(), False)
    assert p.returncode == 0, ('mutant-build', p.stderr)
    c = d / 'omc-no-hash'
    c.write_bytes(p.stdout)
    c.chmod(0o700)
    p = invoke(c, bad)
    try:
        record(p, bad)
    except AssertionError as error:
        assert str(error) in ('complete-size', 'input-hash'), ('wrong-mutant-failure', str(error))
    else:
        raise AssertionError('hash-mutant-survived')
report = {'schema': 1, 'verdict': 'PASS', 'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
          'compiler_source_sha256': pins[0], 'cases': rows, 'sites_registered': len(sites),
          'sites_exercised': sorted(seen, key=int), 'sites_not_exercised': sorted(set(sites)-seen, key=int),
          'limits': 'Unexercised sites are not claimed covered; output is an explicit coverage inventory.'}
out = root / 'build/seed/diagnostics-v2.json'
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(report, indent=2) + '\n')
print('DIAGNOSTICS_V2 PASS cases=' + str(len(rows)) + ' sites=' + str(len(seen)) + '/' + str(len(sites)) + ' mutants=1')
