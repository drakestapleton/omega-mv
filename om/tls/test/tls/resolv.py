#!/usr/bin/env python3
# Test instrument only: private resolver paths, descriptor/extent probes, and isolated reader twins.
import argparse
import hashlib
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import tempfile


def require(condition, detail):
    if not condition:
        raise RuntimeError(detail)

p = argparse.ArgumentParser()
p.add_argument('omc')
p.add_argument('--out')
p.add_argument('--baseline', action='store_true')
p.add_argument('--ref')
p.add_argument('--wrong-expectation', action='store_true')
a = p.parse_args()
here = Path(__file__).resolve().parent
tls = here.parent.parent
root = tls.parent.parent
out = Path(a.out).resolve() if a.out else Path(tempfile.mkdtemp(prefix='resolv-', dir=root/'build'))
out.mkdir(parents=True, exist_ok=True)
fixture = out/'private-resolv.conf'
source = subprocess.check_output(['git','-C',str(root),'show',a.ref+':om/tls/tls.om'],text=True) if a.ref else (tls/'tls.om').read_text()
old = 'text TLRESOLV "/etc/resolv.conf"'
require(source.count(old) == 1, 'private path transformation is not unique')
private = source.replace(old, 'text TLRESOLV "'+str(fixture)+'"')
units = 'sha2 hkdf drbg x25519 sha3 mlkem chacha aesgcm ec ecdh rsa x509 rev fips'.split()


def replace_once(text, old, new):
    require(text.count(old) == 1, 'transformation is not unique: '+old)
    return text.replace(old,new)


def build(name, text, driver=None):
    d = out/name
    d.mkdir(exist_ok=True)
    for u in units:
        shutil.copyfile(tls/(u+'.om'), d/(u+'.om'))
    (d/'tls.om').write_text(text)
    shutil.copyfile(tls/'build.sh', d/'build.sh')
    program = here/'resolv.om'
    if driver is not None:
        program=d/'driver.om'
        program.write_text(driver)
    cmd = ['sh', str(d/'build.sh'), str(Path(a.omc).resolve()), str(program), str(d/'bin')]
    r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (d/'build.log').write_bytes(r.stdout)
    require(r.returncode == 0, 'compile '+name+' rc='+str(r.returncode)+' '+r.stdout.decode())
    return d/'bin'

line = b'nameserver 127.0.0.12\n'
address = bytes((127,0,0,12))
def padded(n):
    require(n >= 2, 'padding too short')
    return b'#'+b'c'*(n-2)+b'\n'

# Alarms intentionally exceed the former file window and default loop bound.
cases = [
    ('at', padded(4096-len(line))+line, address, 0o600),
    ('straddle', padded(4096-len(line)+2)+line, address, 0o600),
    ('past', padded(4096)+line, address, 0o600),
    ('no-newline', padded(8192)+line[:-1], address, 0o600),
    ('long-comment', padded(1000001)+line, address, 0o600),
    ('long-blanks', b'nameserver'+b' '*1000001+b'127.0.0.12\n', address, 0o600),
    ('long-token', b'nameserver '+b'1'*1000001+b'\n'+line, address, 0o600),
    ('first-wins', line+b'nameserver 127.0.0.1\n', address, 0o600),
    ('bad-then-good', b'nameserver 999.1.1.1\n'+line, address, 0o600),
    ('ipv4-max-width', b'nameserver 255.255.255.255', bytes((255,255,255,255)), 0o600),
    ('prefix-only', b'nameserver\n', None, 0o600),
    ('truncated-ip', b'nameserver 127.0.0.\n', None, 0o600),
    ('empty', b'', None, 0o600),
    ('unreadable', line, None, 0o000),
    ('comment-edge', b'#'+b'c'*4109+b'\n'+line, address, 0o600),
    ('cr-lf-edge', padded(4096-len(line))+line[:-1]+b'\r\n', address, 0o600),
    ('nul-keyword', b'name\0server 127.0.0.1\n'+line, address, 0o600),
    ('nul-address', b'nameserver 127.0.0.1\0\n'+line, address, 0o600),
    ('nul-before-address', b'nameserver \0' + b'127.0.0.1\n'+line, address, 0o600),
    ('nul-comment', b'#ignored\0comment\n'+line, address, 0o600),
    ('nul-after-space', line[:-1]+b' \0ignored\n', address, 0o600),
    ('nul-after-cr', line[:-1]+b'\r\0\n', address, 0o600),
    ('nul-only', b'\0\0\n', None, 0o600),
]
for split in range(1,len(b'nameserver')):
    cases.append(('keyword-edge-'+str(split),padded(4096-split)+line,address,0o600))
for split in range(1,len(b'127.0.0.12')):
    cases.append(('address-edge-'+str(split),padded(4096-len(b'nameserver ')-split)+line,address,0o600))
require(os.geteuid() != 0, 'unreadable fixture requires an unprivileged user')
if a.wrong_expectation:
    name,data,expected,mode=cases[0]
    cases[0]=(name,data,bytes((127,0,0,13)),mode)


def remove_fixture():
    if fixture.is_dir():
        fixture.rmdir()
    elif fixture.exists() or fixture.is_symlink():
        fixture.chmod(0o600)
        fixture.unlink()


def execute(binary, name, expected, label, input=None):
    try:
        r=subprocess.run([str(binary)], input=input, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=2)
        rc,got=r.returncode,r.stdout
    except subprocess.TimeoutExpired:
        rc,got=124,b''
    want=1 if expected is None else 0
    ok=rc==want and got==(expected or b'')
    print(('PASS' if ok else 'FAIL')+' '+label+'/'+name+' status='+str(rc)+' output='+got.hex(),flush=True)
    return ok


specials=('absent','directory','fifo-no-writer','fifo-writer-held')
extent_cases=('growing-file','descriptor-path-swap','truncate-after-address')

def run(binary,label):
    failures=[]
    for name,data,expected,mode in cases:
        remove_fixture()
        fixture.write_bytes(data)
        fixture.chmod(mode)
        if not execute(binary,name,expected,label):
            failures.append(name)
    remove_fixture()
    # All are decided from the opened descriptor, with no blocking open on either FIFO shape.
    for name in specials:
        held=None
        remove_fixture()
        if name=='directory':
            fixture.mkdir()
        elif name.startswith('fifo'):
            os.mkfifo(fixture,0o600)
            if name=='fifo-writer-held':
                held=os.open(fixture,os.O_RDWR|os.O_NONBLOCK)
                os.write(held,line)
        try:
            if not execute(binary,name,None,label):
                failures.append(name)
        finally:
            if held is not None:
                os.close(held)
    remove_fixture()
    return failures

head = subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'], text=True).strip()
print('SOURCE '+head+(' source-ref='+a.ref if a.ref else ''),flush=True)
print('COMPILER '+hashlib.sha256(Path(a.omc).read_bytes()).hexdigest(),flush=True)
real=build('real',private)
failures=run(real,'real')
if a.baseline:
    print('RESOLV BASELINE mismatches='+','.join(failures),flush=True)
    raise SystemExit(1 if failures else 0)
require(not failures,'resolver cases failed: '+','.join(failures))

# Fault instrument: close only after a first chunk selected an address, so the next real read
# fails EBADF. A previously selected address must not turn a subsequent read error into success.
readline='n = read int fd b 0 ask'
fault=replace_once(private,readline,'if eq get st 2 1\nx = fclose int fd\nend\n'+readline)
faultbin=build('read-error-after-address',fault)
fixture.write_bytes(line+b'#'+b'c'*(8192-len(line)-1))
require(execute(faultbin,'read-error-after-address',None,'fault'),'read error after address accepted')
remove_fixture()

# Deterministic test-only barrier after the first read: append while the read loop is in flight,
# or replace the path with a FIFO. The existing opened descriptor and its initial extent win.
start=private.index('fn dns_conf ')
end=private.index('note st: keyword position',start)
section=private[start:end]
section=replace_once(section,'\nend\nx = fclose int fd\nif lt x 0','\ndr_hook ulong n\nend\nx = fclose int fd\nif lt x 0')
hooked='global dr_once ulong 1\nglobal dr_total ulong 1\n'+private[:start]+section+private[end:]+r'''
text DRREADY "READY\n"
fn dr_hook n ulong to void
put dr_total 0 add get dr_total 0 n
if ne get dr_once 0 0
ret
end
put dr_once 0 1
b = new uchar 1 0
w = write 1 DRREADY 0 len DRREADY
if ne w long len DRREADY
exit 70
end
r = read 0 b 0 1
if ne r 1
exit 71
end
end
fn dr_done to void
b = new uchar 8 0
tls_pn b 0 get dr_total 0 8
w = write 2 b 0 8
if ne w 8
exit 72
end
end
'''
driver=replace_once((here/'resolv.om').read_text(),'k = write 1 ip 0 4','dr_done\nk = write 1 ip 0 4')
hookbin=build('extent-barrier',hooked,driver)
# This barrier is after open but before fstat: a pathname type check would see the replacement FIFO.
openhook=replace_once(hooked,'size = dns_fsize int fd','dr_hook 0\nsize = dns_fsize int fd')
openhookbin=build('descriptor-barrier',openhook,driver)
for name in extent_cases:
    remove_fixture()
    initial=line+b'#'+b'c'*(8192-len(line)-1)
    fixture.write_bytes(initial)
    binary=openhookbin if name=='descriptor-path-swap' else hookbin
    child=subprocess.Popen([str(binary)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    selector=selectors.DefaultSelector()
    selector.register(child.stdout,selectors.EVENT_READ)
    try:
        ready=selector.select(timeout=2)
        require(ready,'extent barrier was not reached')
        marker=child.stdout.read(6)
        require(marker==b'READY\n',('unexpected barrier',marker))
        if name=='growing-file':
            with fixture.open('ab') as stream:
                stream.write(b'additional bytes beyond initial extent\n'*32768)
            require(fixture.stat().st_size>len(initial),'growth instrument appended nothing')
        elif name=='truncate-after-address':
            fixture.write_bytes(b'')
        else:
            fixture.rename(out/'original-opened-file')
            os.mkfifo(fixture,0o600)
        output,error=child.communicate(b'x',timeout=2)
        if name=='truncate-after-address':
            require(child.returncode==1 and not output and not error,(name,child.returncode,output,error))
            print('PASS extent/'+name+' status=1 (short EOF after address refused)',flush=True)
        else:
            require(child.returncode==0 and output==address,(name,child.returncode,output,error))
            require(error==len(initial).to_bytes(8,'big'),(name,'read beyond initial descriptor extent',error))
            print('PASS extent/'+name+' initial-bytes='+str(len(initial))+' bytes-read='+str(int.from_bytes(error,'big')),flush=True)
    finally:
        selector.close()
        if child.poll() is None:
            child.kill();child.communicate()
        remove_fixture()

# Isolate the I/O regression: retain the exact new parser, fd check, flags and error handling;
# only clamp the initial reader extent to the former 4096-byte window.
mutant=replace_once(private,'left = ulong size','left = ulong size\nif gt left 4096\nleft = 4096\nend')
bad=run(build('reader-window-mutant',mutant),'reader-window-mutant')
require({'straddle','past','no-newline','long-comment'} <= set(bad),'isolated reader-window mutant survived')
# Independently prove nonblocking open: the regular-file check cannot run if FIFO open blocks.
mutant=replace_once(private,'or int 524288 2048','int 524288')
bad=run(build('blocking-open-mutant',mutant),'blocking-open-mutant')
require('fifo-no-writer' in bad,'blocking-open mutant survived')
print('RESOLV PASS cases='+str(len(cases)+len(specials)+1+len(extent_cases))+' mutants=2/2 source='+head,flush=True)
