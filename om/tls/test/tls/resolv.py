#!/usr/bin/env python3
# Test instrument only: private resolver fixtures and truncation mutant, no host resolver changes.
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

p = argparse.ArgumentParser()
p.add_argument('omc')
p.add_argument('--out')
p.add_argument('--baseline', action='store_true')
a = p.parse_args()
here = Path(__file__).resolve().parent
tls = here.parent.parent
root = tls.parent.parent
out = Path(a.out).resolve() if a.out else Path(tempfile.mkdtemp(prefix='resolv-', dir=root/'build'))
out.mkdir(parents=True, exist_ok=True)
fixture = out/'private-resolv.conf'
source = (tls/'tls.om').read_text()
old = 'text TLRESOLV "/etc/resolv.conf"'
assert source.count(old) == 1
private = source.replace(old, 'text TLRESOLV "'+str(fixture)+'"')
units = 'sha2 hkdf drbg x25519 sha3 mlkem chacha aesgcm ec ecdh rsa x509 rev fips'.split()

def build(name, text):
    d = out/name
    d.mkdir(exist_ok=True)
    for u in units:
        shutil.copyfile(tls/(u+'.om'), d/(u+'.om'))
    (d/'tls.om').write_text(text)
    shutil.copyfile(tls/'build.sh', d/'build.sh')
    cmd = ['sh', str(d/'build.sh'), str(Path(a.omc).resolve()), str(here/'resolv.om'), str(d/'bin')]
    r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (d/'build.log').write_bytes(r.stdout)
    if r.returncode:
        raise RuntimeError('compile '+name+' rc='+str(r.returncode)+' '+r.stdout.decode())
    return d/'bin'

line = b'nameserver 127.0.0.12\n'
def padded(n):
    return b'#'+b'c'*(n-2)+b'\n'
# Alarms intentionally exceed the former 4096-byte file window and the default loop bound.
cases = [
    ('at', padded(4096-len(line))+line, bytes((127,0,0,12)), 0o600),
    ('straddle', padded(4096-len(line)+2)+line, bytes((127,0,0,12)), 0o600),
    ('past', padded(4096)+line, bytes((127,0,0,12)), 0o600),
    ('no-newline', padded(8192)+line[:-1], bytes((127,0,0,12)), 0o600),
    ('long-comment', padded(1000001)+line, bytes((127,0,0,12)), 0o600),
    ('long-blanks', b'nameserver'+b' '*1000001+b'127.0.0.12\n', bytes((127,0,0,12)), 0o600),
    ('long-token', b'nameserver '+b'1'*1000001+b'\n'+line, bytes((127,0,0,12)), 0o600),
    ('first-wins', line+b'nameserver 127.0.0.1\n', bytes((127,0,0,12)), 0o600),
    ('bad-then-good', b'nameserver 999.1.1.1\n'+line, bytes((127,0,0,12)), 0o600),
    ('ipv4-max-width', b'nameserver 255.255.255.255', bytes((255,255,255,255)), 0o600),
    ('prefix-only', b'nameserver\n', None, 0o600),
    ('truncated-ip', b'nameserver 127.0.0.\n', None, 0o600),
    ('empty', b'', None, 0o600),
    ('unreadable', line, None, 0o000),
]
if os.geteuid() == 0:
    raise RuntimeError('unreadable fixture requires an unprivileged user')

def run(bin, label):
    failures = []
    for name, data, address, mode in cases:
        if fixture.exists():
            fixture.chmod(0o600)
        fixture.write_bytes(data)
        fixture.chmod(mode)
        r = subprocess.run([str(bin)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
        want = 1 if address is None else 0
        ok = r.returncode == want and r.stdout == (address or b'')
        print(('PASS' if ok else 'FAIL')+' '+label+'/'+name+' bytes='+str(len(data))+' rc='+str(r.returncode)+' output='+r.stdout.hex(), flush=True)
        if not ok:
            failures.append(name)
    fixture.chmod(0o600)
    return failures

head = subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'], text=True).strip()
print('SOURCE '+head, flush=True)
print('COMPILER '+hashlib.sha256(Path(a.omc).read_bytes()).hexdigest(), flush=True)
real = build('real', private)
failures = run(real, 'real')
if a.baseline:
    print('RESOLV BASELINE mismatches='+','.join(failures), flush=True)
    raise SystemExit(1 if failures else 0)
assert not failures, 'resolver cases failed: '+','.join(failures)
# Restore the original one-read implementation, without changing any parser or fixture.
start = private.index('fn dns_conf ')
end = private.index('note try each line of b', start)
original = '''fn dns_conf ip edit uchar * to ulong
b = new uchar 4096 0
fd = fopen TLRESOLV 0 len TLRESOLV 524288 0
if lt fd 0
ret TLEDNS
end
n = read int fd b 0 4096
x = fclose int fd
if le n 0
ret TLEDNS
end
ret dns_lines part b 0 ulong n ip
end

'''
mutant = private[:start]+original+private[end:]
assert mutant != private
bad = run(build('truncation-mutant', mutant), 'truncation-mutant')
assert {'straddle','past','no-newline','long-comment'} <= set(bad), 'truncation mutant survived'
print('RESOLV PASS cases='+str(len(cases))+' mutants=1/1 source='+head, flush=True)
