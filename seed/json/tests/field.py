#!/usr/bin/env python3
# Test instrument only. Invoke raw function-mode Omega using its documented pointer/length slots.
# Sparse anonymous mappings supply real 4 GiB source views, touching only first/last pages. This is
# host-ABI evidence, not a claim that a seeded-Omega caller can construct/pass that source today.
import argparse
import ctypes as C
import json
import mmap
from pathlib import Path
import subprocess
import sys

MAX = 4294967295  # uint tape field width, from json.om/jsmaxn
WRAPPERS = {
'stop-copy': '''fn qb_stop s view uchar * to long
ob = new uchar 1041 0
r = js_winit ob
js_wcopy ob s 0 len s
ret js_wdone ob
end
''',
'stop-string': '''fn qb_stop s view uchar * to long
ob = new uchar 1041 0
r = js_winit ob
js_wsbuf ob s 0 len s
ret js_wdone ob
end
''',
'parse': '''fn qb_parse s view uchar * t edit uint * n ulong to long
ret js_parse s t n
end
''',
'reset': '''fn qb_reset t edit uint * n ulong to long
js_reset t n
ret long js_hg t jsherr
end
''',
'end': '''fn qb_end s view uchar * p ulong to ulong
ret js_numend s p len s
end
''',
'float': '''fn qb_float s view uchar * p ulong to ulong
fs = new long jsfs 0
x = js_f64 s p fs
if ne js_f64st fs 0
ret 0
end
ret bitcast ulong x
end
''',
'write': '''fn qb_write s view uchar * p ulong to long
ob = new uchar 1042 0
r = js_winit ob
js_wlex ob s p
r = js_wdone ob
if ne r 1
ret r
end
ret long get ob jswh
end
''',
}

def native(binary, op):
    code = Path(binary).read_bytes()
    executable = mmap.mmap(-1, len(code), prot=mmap.PROT_READ|mmap.PROT_WRITE|mmap.PROT_EXEC)
    executable.write(code)
    address = C.addressof(C.c_char.from_buffer(executable))
    cache = C.CDLL('libgcc_s.so.1').__clear_cache
    cache.argtypes = [C.c_void_p,C.c_void_p]
    cache(C.c_void_p(address),C.c_void_p(address+len(code)))
    if op.startswith('stop-'):
        # Guard-page read probe: the view spans an actual mapping, but all except its first
        # two source bytes are PROT_NONE. Exhausted output must stop before reading them.
        src = mmap.mmap(-1, 2097152, prot=mmap.PROT_READ|mmap.PROT_WRITE)
        pointer = C.addressof(C.c_char.from_buffer(src))
        page = mmap.PAGESIZE
        src[page-2:page] = b'xx'
        libc = C.CDLL(None)
        libc.mprotect.argtypes = [C.c_void_p,C.c_size_t,C.c_int]
        assert libc.mprotect(pointer+page,2097152-page,0) == 0
        f = C.CFUNCTYPE(C.c_int64,C.c_void_p,C.c_uint64)(address)
        print(f(pointer+page-2,1000001),flush=True)
        return
    if op.startswith('parse') or op.startswith('reset'):
        tape = (C.c_uint32*20)()
        tape[14],tape[8],tape[12],tape[15] = MAX,1,1,788
        # Deliberately stale successful state must be invalidated on every refusal.
        tape[0],tape[3] = 1,1
        if op.startswith('reset'):
            f = C.CFUNCTYPE(C.c_int64,C.c_void_p,C.c_uint64,C.c_uint64)(address)
            result = f(tape,20,MAX+(op=='reset-above'))
        else:
            src = mmap.mmap(-1,MAX+1,prot=mmap.PROT_READ|mmap.PROT_WRITE)
            src[0] = ord('x')
            pointer = C.addressof(C.c_char.from_buffer(src))
            f = C.CFUNCTYPE(C.c_int64,C.c_void_p,C.c_uint64,C.c_void_p,C.c_uint64,C.c_uint64)(address)
            result = f(pointer,MAX+1,tape,20,MAX+(op=='parse-above'))
        print(json.dumps([result,tape[0],tape[1],tape[3],tape[6],tape[7]]),flush=True)
        return
    src = mmap.mmap(-1,MAX,prot=mmap.PROT_READ|mmap.PROT_WRITE)
    src[MAX-1] = ord('1') if not op.endswith('bad') else ord('-')
    pointer = C.addressof(C.c_char.from_buffer(src))
    f = C.CFUNCTYPE(C.c_uint64,C.c_void_p,C.c_uint64,C.c_uint64)(address)
    print(f(pointer,MAX,MAX-1),flush=True)


def check(omc, directory, units):
    directory = Path(directory)
    directory.mkdir(parents=True,exist_ok=True)
    for name,wrapper in WRAPPERS.items():
        program = 'om2\n'+''.join(units[u] for u in ('json.om','jsonw.om','jsonf.om'))+wrapper
        (directory/(name+'.om')).write_text(program)
        r = subprocess.run([str(Path(omc).resolve())],input=program.encode(),stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        (directory/(name+'.err')).write_bytes(r.stderr)
        assert r.returncode == 0, (name,r.returncode,r.stderr)
        (directory/name).write_bytes(r.stdout)
    cases = [
      ('stop-copy','stop-copy',-21),('stop-string','stop-string',-21),
      ('parse-at','parse',[-2,0,MAX,0,2,0]),
      ('parse-above','parse',[-5,0,0,0,5,MAX]),
      ('reset-at','reset',[0,0,MAX,0,0,0]),
      ('reset-above','reset',[5,0,0,0,5,MAX]),
      ('end','end',MAX),('end-bad','end',0),
      ('float','float',4607182418800017408),('write','write',49),
    ]
    failures=[]
    for op,unit,want in cases:
        r = subprocess.run([sys.executable,__file__,'--native',str(directory/unit),op],stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=30)
        got = json.loads(r.stdout) if r.returncode == 0 else None
        ok = r.returncode == 0 and got == want
        print(('PASS' if ok else 'FAIL')+' field/'+op+' rc='+str(r.returncode)+' got='+repr(got)+' want='+repr(want),flush=True)
        if not ok:
            failures.append(op)
    return failures

if __name__ == '__main__':
    if len(sys.argv)==4 and sys.argv[1]=='--native':
        native(sys.argv[2],sys.argv[3])
    else:
        p=argparse.ArgumentParser()
        p.add_argument('omc');p.add_argument('out');p.add_argument('--ref')
        a=p.parse_args()
        j=Path(__file__).resolve().parent.parent
        if a.ref:
            units={u:subprocess.check_output(['git','-C',str(j),'show',a.ref+':seed/json/'+u],text=True) for u in ('json.om','jsonw.om','jsonf.om')}
        else:
            units={u:(j/u).read_text() for u in ('json.om','jsonw.om','jsonf.om')}
        raise SystemExit(1 if check(a.omc,a.out,units) else 0)
