#!/usr/bin/env python3
"""Independent CPU-only test instrument, not an Omega runtime dependency.
Run under the assigned CPU pool lock. Never opens an existing /dev/kfd.
C provides installed-UAPI constants; Omega provides every tested operation.
"""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
os.chdir(root)
out = root / 'build/kfd'
out.mkdir(parents=True, exist_ok=True)
omc = root / 'seed/out/omc'
rows = []

def run(cmd, data=None):
    p = subprocess.run([str(x) for x in cmd], input=data, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, timeout=90)
    return p

def record(name, actual, want, detail=''):
    rows.append(dict(name=name, actual=actual, expected=want, detail=detail))
    print(('PASS' if actual == want else 'FAIL'), name, 'exit', actual, 'expected', want, detail, flush=True)

names = ['GET_VERSION','ACQUIRE_VM','GET_PROCESS_APERTURES_NEW','CREATE_QUEUE',
         'DESTROY_QUEUE','ALLOC_MEMORY_OF_GPU','FREE_MEMORY_OF_GPU',
         'MAP_MEMORY_TO_GPU','UNMAP_MEMORY_FROM_GPU','CREATE_EVENT','DESTROY_EVENT',
         'WAIT_EVENTS','SET_SCRATCH_BACKING_VA','RUNTIME_ENABLE']
csrc = '#include <stdio.h>\n#include <linux/kfd_ioctl.h>\nint main(void){\n'
for name in names:
    csrc += f'printf("{name} %lu %lu\\n", (unsigned long)AMDKFD_IOC_{name}, (unsigned long)_IOC_SIZE(AMDKFD_IOC_{name}));\n'
csrc += 'return 0; }\n'
(out/'abi.c').write_text(csrc)
p=run(['cc','-Wall','-Werror',out/'abi.c','-o',out/'abi'])
record('C UAPI oracle compile',p.returncode,0,p.stderr.decode())
if p.returncode: sys.exit(1)
p=run([out/'abi']); record('C UAPI oracle run',p.returncode,0)
(out/'requests.txt').write_bytes(p.stdout)
abi={name:(int(q),int(n)) for name,q,n in (line.split() for line in p.stdout.decode().splitlines())}

common='global H uchar 88\nglobal P uchar 112\n'
def put(off, value, width=4, arr='H'):
    return ''.join(f'put {arr} {off+i} {b}\n' for i,b in enumerate(value.to_bytes(width,'little')))

def shape(name):
    setup=''
    suffix=''
    if name=='GET_PROCESS_APERTURES_NEW': setup=put(8,1); suffix=' P 0 56'
    if name in ('MAP_MEMORY_TO_GPU','UNMAP_MEMORY_FROM_GPU'): setup=put(16,1); suffix=' P 0 4'
    if name=='WAIT_EVENTS': setup=put(8,1); suffix=' P 0 48'
    if name in ('ALLOC_MEMORY_OF_GPU','SET_SCRATCH_BACKING_VA'):
        setup='r = kfdres 2097152\n'; suffix=' r'
        if name=='ALLOC_MEMORY_OF_GPU': setup+=put(8,4096,8)+put(36,2)
    if name=='RUNTIME_ENABLE': suffix=' long 0'
    if name=='CREATE_QUEUE':
        setup='r = mapnew neg int 1 0 4096 3 34\n'+put(32,4096)+put(40,2)
        suffix=' r r r long 0 long 0'
    return setup,suffix

def source(name, changes='', size=None, setup_override=None, suffix_override=None, request=None):
    q,n=abi[name]
    setup,suffix=shape(name)
    if setup_override is not None: setup=setup_override
    if suffix_override is not None: suffix=suffix_override
    if size is not None: n=size
    if request is not None: q=request
    return common+'fn main to int\n'+setup+changes+f'v = kfdctl neg int 1 {q} H 0 {n}{suffix}\nif ne v neg long 9\nret 80\nend\nret 0\nend\n'

def compile_case(label, src, target, want=0, compiler=omc):
    stem=out/(target+'-'+label)
    text=('target x86linux\n' if target=='x86' else '')+src
    # QEMU-user's unsupported KFD ioctl translator returns ENOTTY before fd lookup.
    # Native Linux on AArch64 reaches fd lookup and returns EBADF. This is not device evidence.
    if target=='x86' and 'v = kfdctl ' in src:
        text=text.replace('if ne v neg long 9\n','if ne v neg long 25\n')
    stem.with_suffix('.om').write_text(text)
    p=run([compiler],text.encode())
    stem.with_suffix('.err').write_bytes(p.stderr)
    record(target+' compile '+label,p.returncode,want,p.stderr.decode().strip())
    if p.returncode: return None
    stem.write_bytes(p.stdout); stem.chmod(0o755)
    return stem

qemu=shutil.which('qemu-x86_64')
objdump=shutil.which('llvm-objdump-18')
print('qemu-x86_64',qemu,'llvm-objdump-18',objdump,flush=True)

def execute(label, binary, target, want=0):
    if binary is None: return
    if target=='x86' and not qemu:
        print('NOT_RUN x86 '+label+' qemu-x86_64 missing'); return
    p=run(([qemu] if target=='x86' else [])+[binary])
    binary.with_suffix('.run.err').write_bytes(p.stderr)
    record(target+' run '+label,p.returncode,want,p.stderr.decode().strip())

for target in ('a64','x86'):
    for name in names:
        b=compile_case(name,source(name),target)
        execute(name,b,target,103 if name=='ACQUIRE_VM' else 0)
        if b and objdump:
            p=run([objdump,'-D','--print-imm-hex',b]); b.with_suffix('.dis').write_bytes(p.stdout)
            record(target+' disassemble '+name,p.returncode,0)
            # x86 has one literal movabs; AArch64 materializes MOVZ/MOVK halves.
            q,n=abi[name]
            dis=p.stdout.decode()
            found=(hex(q) in dis) if target=='x86' else (hex(q&65535) in dis and hex(q>>16) in dis)
            record(target+' UAPI immediate '+name,0 if found else 1,0,hex(q))
        print('NOT_RUN device '+target+' '+name+' no authorized AMD device')
    bads=[('wrong-request',source('GET_VERSION',request=0),0,9),
          ('wrong-size',source('GET_VERSION',size=7),103,0),
          ('ring-small',source('CREATE_QUEUE',put(32,512)),103,0),
          ('ring-nonpower',source('CREATE_QUEUE',put(32,3072)),103,0),
          ('wrong-drm-kind',source('ACQUIRE_VM'),103,0),
          ('span-count',source('GET_PROCESS_APERTURES_NEW',put(8,3)),103,0),
          ('event-extension',source('WAIT_EVENTS',put(32,1,8,'P')),103,0),
          ('userptr',source('ALLOC_MEMORY_OF_GPU',put(36,4)),103,0),
          ('wrong-handle-kind',source('ALLOC_MEMORY_OF_GPU',setup_override='r = mapnew neg int 1 0 4096 3 34\n'+put(8,4096,8)),103,0),
          ('stale-handle',source('ALLOC_MEMORY_OF_GPU',changes='drop = mapdrop r\n'),103,0),
          ('short-handle',source('ALLOC_MEMORY_OF_GPU',put(8,4194304,8)),103,0)]
    for name,offs in [('GET_PROCESS_APERTURES_NEW',[0]),('CREATE_QUEUE',[0,8,16,56,72]),
                      ('ALLOC_MEMORY_OF_GPU',[0]),('MAP_MEMORY_TO_GPU',[8]),
                      ('UNMAP_MEMORY_FROM_GPU',[8]),('WAIT_EVENTS',[0]),
                      ('SET_SCRATCH_BACKING_VA',[0]),('RUNTIME_ENABLE',[0])]:
        for off in offs:
            bads.append((name+'-address-'+str(off),source(name,put(off,1,8)),103,0))
    for label,src,want,ce in bads:
        b=compile_case(label,src,target,ce)
        if not ce: execute(label,b,target,want)
    for word,expr in [('kfdctl',f'kfdctl neg int 1 {abi["GET_VERSION"][0]} H 0 8'),
                      ('kfdmap','kfdmap neg int 1 0 4096'),('kfdres','kfdres 4096')]:
        compile_case('function-'+word,'fn f to long\nH = new uchar 8 0\nret '+expr+'\nend\n',target,9)
        compile_case('om2-function-'+word,'om2\nfn f to long\nH = new uchar 8 0\nret '+expr+'\nend\n',target,9)
    missing='text K "/dev/kfd"\nfn main to int\nf = fopen K 0 len K 2 0\nif ne f neg long 2\nret 81\nend\nret 0\nend\n'
    if not Path('/dev/kfd').exists(): execute('absent-kfd',compile_case('absent-kfd',missing,target),target)
    else: print('NOT_RUN absent-kfd: device exists; never open it from CPU gate')
    mapping='''text K "kfd-cpu-map.bin"
fn main to int
r = kfdres 68721573888
if le r 0
ret 82
end
if ne and mapaddr r 2097151 0
ret 83
end
if ne mapdrop r 0
ret 84
end
f = fopen K 0 len K 578 384
if lt f 0
ret 85
end
if ne ftrunc int f 4096 0
ret 86
end
r = kfdres 4096
a = mapaddr r
if ne mapbind r int f 0 3 0
ret 87
end
if ne mapaddr r a
ret 88
end
if ne mapset r 0 8 12345 0
ret 89
end
s = kfdmap int f 0 4096
if le s 0
ret 90
end
if ne mapget s 0 8 12345
ret 91
end
v = mapdrop r
v = mapdrop s
v = fclose int f
v = unlink K 0 len K
if ne kfdmap neg int 1 0 4096 neg long 9
ret 92
end
ret 0
end
'''
    execute('mapping-large-aligned',compile_case('mapping-large-aligned',mapping,target),target)
    for label,expr in [('reserve-zero','kfdres 0'),('reserve-unaligned','kfdres 4097'),('reserve-overflow','kfdres 18446744073709547520')]:
        execute(label,compile_case(label,'fn main to int\nr = '+expr+'\nret 0\nend\n',target),target,103)

# Native trace oracle observes the syscall boundary, independently of errno.
if os.uname().machine=='aarch64':
    p=run(['cc','-Wall','-Wextra','-Werror',root/'tests/kfd/trace.c','-o',out/'trace'])
    record('trace oracle compile',p.returncode,0,p.stderr.decode())
    if not p.returncode:
        for name,offs in [('GET_VERSION',[]),('GET_PROCESS_APERTURES_NEW',[0]),
                          ('CREATE_QUEUE',[0,8,16,56,72]),('ALLOC_MEMORY_OF_GPU',[0]),
                          ('MAP_MEMORY_TO_GPU',[8]),('UNMAP_MEMORY_FROM_GPU',[8]),
                          ('WAIT_EVENTS',[0]),('SET_SCRATCH_BACKING_VA',[0]),('RUNTIME_ENABLE',[0])]:
            kwargs={}
            if name=='CREATE_QUEUE':
                kwargs={'changes':put(64,64,8)+put(80,64),'suffix_override':' r r r r r'}
            if name=='RUNTIME_ENABLE':
                kwargs={'setup_override':'r = mapnew neg int 1 0 4096 3 34\n','suffix_override':' r'}
            s=source(name,**kwargs).replace('v = kfdctl ','w = write int 1 P 0 112\nv = kfdctl ')
            checks=''
            for off in offs:
                for i in range(8): checks+=f'if ne get H {off+i} 0\nret 95\nend\n'
            if name in ('GET_VERSION','ALLOC_MEMORY_OF_GPU'):
                off=0 if name=='GET_VERSION' else 16
                for i,b in enumerate((0x44332211).to_bytes(8,'little')):
                    checks+=f'if ne get H {off+i} {b}\nret 96\nend\n'
            s=s.replace('ret 0\nend\n',checks+'ret 0\nend\n')
            b=compile_case('trace-'+name,s,'a64')
            if b:
                p=run([out/'trace',b])
                record('trace '+name,p.returncode,0,p.stderr.decode())
else:
    print('NOT_RUN AArch64 native trace oracle: host is not aarch64')

# Faults are planted in independent compiler copies, never in the compiler under test.
# Each must compile and let precisely the formerly refused case through.
original=(root/'seed/omc/omc.om').read_text()
mutants=[
    ('request', [('ksize','fail 9\nret 0','ret 8')],
     source('GET_VERSION',request=0),False),
    ('size', [('kctl','kfdcmpv 0 n\nkfdtrap 1','kfdcmpv 0 n')],
     source('GET_VERSION',size=7),False),
    ('address', [('kfdzero','kfdtrap 1','note planted missing address refusal')],
     source('GET_PROCESS_APERTURES_NEW',put(0,1,8)),False),
    ('kind', [('kbind','kfdcmpv 0 kind\nkfdtrap 1','kfdcmpv 0 kind')],
     source('ALLOC_MEMORY_OF_GPU',setup_override='r = mapnew neg int 1 0 4096 3 34\n'+put(8,4096,8)),False),
    ('function', [(f,'if eq ok 0\nfail 9','if eq ok 0\nnote planted missing mode refusal')
                  for f in ('hostval','xhost')],
     'om2\nfn f to long\nret kfdres 4096\nend\n',True)]
for label, patches, case, function in mutants:
    changed=original
    for fn,old,new in patches:
        start=changed.index('fn '+fn+' ')
        stop=changed.find('\nfn ',start+1)
        if stop<0: stop=len(changed)
        body=changed[start:stop]
        if body.count(old)!=1: raise RuntimeError('mutation seam '+label+' '+fn)
        changed=changed[:start]+body.replace(old,new)+changed[stop:]
    m=out/('mutant-'+label)
    m.with_suffix('.om').write_text(changed)
    p=run([omc],changed.encode())
    record('build compiler mutant '+label,p.returncode,0,p.stderr.decode())
    if p.returncode: continue
    m.write_bytes(p.stdout); m.chmod(0o755)
    for target in ('a64','x86'):
        b=compile_case('killed-'+label,case,target,compiler=m)
        if not function: execute('killed-'+label,b,target)

(out/'results.json').write_text(json.dumps(rows,indent=2)+'\n')
print('compiler_sha256',hashlib.sha256(omc.read_bytes()).hexdigest())
fail=sum(r['actual']!=r['expected'] for r in rows)
print('KFD_CPU',len(rows),'checks',fail,'failures; hardware NOT_RUN')
if not fail and '--record-history' in sys.argv[1:]:
    # Measuring-instrument output, not a maintained copy of compiler facts.
    ledger=root/'seed/omc/size-history.tsv'
    digest=hashlib.sha256(omc.read_bytes()).hexdigest()
    if not ledger.read_text().splitlines()[-1].endswith('\t'+digest):
        lines=original.splitlines()
        values=['kfd-uapi','KFD checked records and aligned reservations on Linux AArch64/x86',
                len(lines),sum(s.startswith('fn ') for s in lines),
                (omc.stat().st_size-176)//4,digest]
        with ledger.open('a') as f: f.write('\t'.join(map(str,values))+'\n')
sys.exit(bool(fail))
