#!/usr/bin/env python3
# Test instrument and independent CPython float/serializer oracle. Never a product dependency.
def gate_require(condition, detail):
    if not condition:
        raise RuntimeError(detail)

import argparse
import hashlib
from pathlib import Path
import random
import struct
import subprocess
import sys
sys.dont_write_bytecode = True
import field

p=argparse.ArgumentParser()
p.add_argument('omc');p.add_argument('out')
p.add_argument('--wrong-expectation', action='store_true')
a=p.parse_args()
j=Path(__file__).resolve().parent.parent
out=Path(a.out).resolve();out.mkdir(parents=True,exist_ok=True)
omc=str(Path(a.omc).resolve())
units={u:(j/u).read_text() for u in ('json.om','jsonw.om','jsonf.om')}
driver=(j/'tests/big.om').read_text()

def build(name,u):
    d=out/name;d.mkdir(exist_ok=True)
    source='om2\n'+''.join(u.values())+driver
    (d/'big.om').write_text(source)
    r=subprocess.run([omc],input=source.encode(),stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    (d/'big.err').write_bytes(r.stderr)
    gate_require(r.returncode==0, (name,r.returncode,r.stderr))
    binary=d/'big';binary.write_bytes(r.stdout);binary.chmod(0o700)
    return binary

def run(binary,mode,data,want,args=(),rc=0):
    r=subprocess.run([str(binary),mode,*map(str,args)],input=data,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=60)
    ok=r.returncode==rc and r.stdout==want
    if not ok:
        print('MISMATCH mode='+mode+' bytes='+str(len(data))+' rc='+str(r.returncode)+' got='+repr(r.stdout[:100])+' want='+repr(want[:100]),flush=True)
    return ok

big=build('real',units)
checks=0
# Preserve the original 4 MiB workflow-body case, not merely a whitespace-only size probe.
import json
workflow=json.dumps({'version':'v1','jobs':{'j':{'image':{'uri':'docker://alpine'},'script':'x'*(4194304-200)}}}).encode()
workflow += b' '*(4194304-len(workflow))
gate_require(len(workflow)==4194304, 'gate condition failed')
r=subprocess.run([str(big),'p'],input=workflow,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=60)
gate_require(r.returncode==0 and r.stdout.startswith(b'OK '), (r.returncode,r.stdout))
gate_require(run(big,'p',workflow+b'x',b'',rc=93), 'gate condition failed')
checks+=2
print('PASS growing/workflow 4194304 bytes; appended x=93',flush=True)
# Reader at its presently reachable caller-local boundary, and one byte past it.
body=b'0'+b' '*4194303
gate_require(run(big,'p',body,b'OK 2\n' if a.wrong_expectation else b'OK 1\n'), 'reader expectation mismatch');checks+=1
gate_require(run(big,'p',body,b'ERR 5 4194303\n',[4194303]), 'gate condition failed');checks+=1
gate_require(run(big,'p',body+b'x',b'',rc=93), 'gate condition failed');checks+=1
# The kernel read error is not an EOF and not an overflow (directory fd as stdin).
fd=__import__('os').open(str(j),__import__('os').O_RDONLY)
try:
    r=subprocess.run([str(big),'p'],stdin=fd,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=30)
    gate_require(r.returncode==90 and not r.stdout, (r.returncode,r.stdout))
finally:
    __import__('os').close(fd)
checks+=1
# EOF without input reaches the reader's EOF refusal, not the I/O error path.
gate_require(run(big,'p',b'',b'ERR 1 0\n'), 'gate condition failed');checks+=1
print('PASS growing/reader 4194304 bytes; trailing x=93; read-error=90; EOF=ERR1',flush=True)
number=b'1'+b'0'*1000000
raw=b'x'*1000001
for mode,data,want in [('n',number,number),('s',raw,b'"'+raw+b'"')]:
    gate_require(run(big,mode,data,want), 'gate condition failed');checks+=1
    gate_require(run(big,mode,data,b'WERR 21\n',[1056]), 'gate condition failed');checks+=1
# The reader+token writer path also traverses >1000000 bytes in both consumers.
for data in (number,b'"'+raw+b'"'):
    gate_require(run(big,'r',data,data), 'gate condition failed');checks+=1
    gate_require(run(big,'r',data,b'WERR 21\n',[1056]), 'gate condition failed');checks+=1
gate_require(run(big,'n',b'',b'WERR 24\n'), 'gate condition failed');checks+=1
print('PASS growing/writer number/raw/token rewrite above 983040 bytes; short outputs=21',flush=True)

balanced=b'1'+b'0'*1000000+b'e-1000000'
fractional=b'0.'+b'0'*999999+b'1e1000000'
# Deterministic independent oracle: long significant mantissas, cancellation in both directions,
# signed values, finite/subnormal/overflow, and exponent tokens with many leading zeroes.
rng=random.Random(78803)
lexemes=[balanced,fractional,b'-'+balanced,b'-'+fractional]
for i in range(32):
    n=rng.randint(10001,180000)
    digits=bytes([rng.randrange(49,58)])+bytes(rng.randrange(48,58) for _ in range(n-1))
    shift=rng.randint(-345,325)
    if i%2:
        lex=b'0.'+b'0'*n+digits+b'e'+str(n+shift).encode()
    else:
        lex=digits+b'e'+str(-n+shift).encode()
    if i%3==0:
        lex=b'-'+lex
    lexemes.append(lex)
lexemes += [b'1e'+b'0'*1000001+b'1', b'1e-'+b'0'*1000001+b'1', b'1e'+b'9'*1000001,b'1e-'+b'9'*1000001]
# Exact rounding midpoints, not rounded decimal approximations. The independent CPython oracle
# consumes balanced million-digit encodings on both sides of, and exactly at, each midpoint.
from decimal import Decimal, localcontext
threshold_labels={}
with localcontext() as ctx:
    ctx.prec=4096  # test-only exact decimal work room, above all finite decimal expansions here
    two=Decimal(2)
    epsilon=Decimal(10)**-1200
    thresholds=[('zero-minsubnormal',two**-1075),
                ('subnormal-normal',two**-1022-two**-1075),
                ('finite-overflow',two**1024-two**970)]
    for name,middle in thresholds:
        for side in (-1,0,1):
            value=middle+side*epsilon
            parts=value.as_tuple()
            digits=bytes(d+48 for d in parts.digits)
            for form in ('integer','fractional'):
                if form=='integer':
                    lex=digits+b'0'*1000000+b'e'+str(parts.exponent-1000000).encode()
                else:
                    lex=b'0.'+b'0'*1000000+digits+b'e'+str(parts.exponent+1000000+len(digits)).encode()
                for sign in (b'',b'-'):
                    threshold_labels[len(lexemes)]=name+'/'+str(side)+'/'+form+'/'+('negative' if sign else 'positive')
                    lexemes.append(sign+lex)
for index,lex in enumerate(lexemes):
    x=float(lex)
    bits=struct.pack('>d',x).hex().encode()
    inf=bits in (b'7ff0000000000000',b'fff0000000000000')
    want=b'F '+(b'1' if inf else b'0')+b' '+bits+b' '+(b'WERR 24' if inf else repr(x).encode())+b'\n'
    gate_require(run(big,'f',lex,want), (index,len(lex)))
    print('PASS growing/float case='+str(index)+' label='+threshold_labels.get(index,'corpus')+' bytes='+str(len(lex))+' sha256='+hashlib.sha256(lex).hexdigest()+' oracle='+want.decode().strip(),flush=True)
    checks+=1

gate_require(not field.check(omc,out/'field',units), 'gate condition failed')
checks+=10
# Each defect has a compiling, behaviorally killed control. Mutations are test-only source twins.
mutants=0
for label,filename,old,new,mode,data,want,args in [
    ('copy-loop','jsonw.om','for i ulong sub e p bound 9223372036854775807','for i ulong sub e p','n',number,number,()),
    ('string-loop','jsonw.om','for i ulong n bound 9223372036854775807','for i ulong n','s',raw,b'"'+raw+b'"',()),
    ('exponent-saturation','jsonf.om','lim = add lim 331','lim = long 10000','f',balanced,b'F 0 3ff0000000000000 1.0\n',()),
    ('driver-prefix','driver','k = read 0 x 0 1\nif lt k 0','k = long 0\nif lt k 0','p',body+b'x',b'',()),
]:
    twin=dict(units)
    olddriver=driver
    if filename=='driver':
        gate_require(driver.count(old)==1, 'gate condition failed');driver=driver.replace(old,new)
    else:
        gate_require(twin[filename].count(old)==1, (label,twin[filename].count(old)))
        twin[filename]=twin[filename].replace(old,new)
    mutant=build(label,twin)
    driver=olddriver
    expected_rc=93 if label=='driver-prefix' else 0
    gate_require(not run(mutant,mode,data,want,args,expected_rc), 'survived '+label)
    print('PASS growing/mutant '+label+' caught',flush=True);mutants+=1
# Exhaustion must avoid reading the PROT_NONE tail even with an admitted million-byte source view.
for label,old in [('copy-stop','if ne get ob jswerr 0\nret\nend\njs_wb ob get s add p i'),('string-stop','if ne get ob jswerr 0\nret\nend\njs_wsb ob get s add off i')]:
    twin=dict(units);gate_require(twin['jsonw.om'].count(old)==1, 'gate condition failed')
    twin['jsonw.om']=twin['jsonw.om'].replace(old,old.split('\nend\n',1)[1])
    failures=field.check(omc,out/label,twin)
    gate_require(('stop-copy' if label=='copy-stop' else 'stop-string') in failures, 'survived '+label)
    print('PASS growing/mutant '+label+' caught',flush=True);mutants+=1
for label,filename,old,new in [
    ('preflight-narrow','json.om','js_hs tape jshn 0','js_hs tape jshn n'),
    ('sentinel','jsonw.om','if eq e 0','if eq e jsnone'),
]:
    twin=dict(units);gate_require(twin[filename].count(old)==1, 'gate condition failed')
    twin[filename]=twin[filename].replace(old,new)
    if label=='sentinel':
        start=twin[filename].index('fn js_numend ');end=twin[filename].index('\nfn js_wcopy',start)
        twin[filename]=twin[filename][:start]+twin[filename][start:end].replace('ret 0','ret jsnone')+twin[filename][end:]
        twin['jsonf.om']=twin['jsonf.om'].replace('if eq js_numend src off n 0','if eq js_numend src off n jsnone')
    failures=field.check(omc,out/label,twin)
    gate_require(('parse-above' if label=='preflight-narrow' else 'float') in failures, 'survived '+label)
    print('PASS growing/mutant '+label+' caught',flush=True);mutants+=1
print('GROWING PASS checks='+str(checks)+' float-oracle='+str(len(lexemes))+' mutants='+str(mutants),flush=True)

