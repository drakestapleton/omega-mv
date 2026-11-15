#!/usr/bin/env python3
"""Independent native-object parser/oracle. This is a test instrument, not a linker."""
import os, struct, subprocess, sys, tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[4]
OMC = Path(sys.argv[1]).resolve() if len(sys.argv)>1 else ROOT/"seed/out/omc"
def compile_source(source, status=0):
    p = subprocess.run([OMC], input=source.encode(), capture_output=True)
    assert p.returncode == status, (status,p.returncode,p.stderr.decode())
    if status:
        assert not p.stdout, ("refusal emitted object",p.stdout[:32])
    return p.stdout
def parse(data):
    def u64(off):
        assert 0 <= off <= len(data)-8, ("truncated u64",off)
        return struct.unpack_from("<Q",data,off)[0]
    assert data[:8] == b"OMOBJ001"
    version,target,release,start,end,nf,nc,ne = [u64(x) for x in range(8,72,8)]
    assert version==1 and target==1 and release in (0,1), "object-target-contract"
    assert start==176 and start<=end<=len(data) and end%4==0
    assert data[72:176] == bytes(104)
    p=end; funcs=[]
    for f in range(nf):
        flags,addr,ret,np,stack,nlen=[u64(p+i*8) for i in range(6)]; p+=48
        assert flags in (0,1,2) and 1<=ret<=13 and np<=6
        assert stack%16==0 and nlen>0
        assert p+nlen<=len(data)
        name=data[p:p+nlen].decode("ascii");p+=nlen
        pad=(-p)%8;assert data[p:p+pad]==bytes(pad);p+=pad
        params=[]
        for j in range(np):
            t,k,n,layout,fresh=[u64(p+i*8) for i in range(5)];p+=40
            assert t in tuple(range(1,12))+(13,) and k in (0,2,3) and layout==0
            assert fresh in (0,1)
            params.append((t,k,n,layout,fresh))
        assert (addr==0 and stack==0) if flags==2 else (start<=addr<end and addr%4==0)
        funcs.append(dict(flags=flags,addr=addr,ret=ret,stack=stack,name=name,params=params))
    assert len({f["name"] for f in funcs})==nf
    calls=[]
    for c in range(nc):
        site,src,dst,cost=[u64(p+i*8) for i in range(4)];p+=32
        assert start<=site<=end-4 and site%4==0 and src<nf and dst<nf and cost%16==0
        assert funcs[src]["flags"]!=2
        word=struct.unpack_from("<I",data,site)[0]
        assert word>>26==0b100101
        if funcs[dst]["flags"]==2:
            assert word==0x94000000, ("external call must be unresolved",hex(word))
        else:
            disp=word&0x3ffffff
            if disp&(1<<25):disp-=1<<26
            assert site+4*disp==funcs[dst]["addr"]
        calls.append((site,src,dst,cost))
    assert p==len(data),("trailing bytes",p,len(data))
    exports=[f for f in funcs if f["flags"]==1]
    assert len(exports)==ne
    for i,f in enumerate(exports):
        site=start+4*i;word=struct.unpack_from("<I",data,site)[0]
        assert word>>26==0b000101
        disp=word&0x3ffffff
        if disp&(1<<25):disp-=1<<26
        assert site+disp*4==f["addr"]
    return funcs,calls,(release,start,end)
scalar="""om2
fn helper a int to int
ret add a 1
end
export fn run a int to int
ret helper a
end
"""
array="""om2
export fn readone a view uchar * to uchar
ret get a 0
end
export fn writeone a edit uchar * x uchar to void
put a 0 x
ret
end
"""
stack="""om2
fn leaf a view uchar * to uchar
ret get a 0
end
export fn run to uchar
a = new uchar 33 7
ret leaf a
end
"""
count=0
for source in [scalar,array,stack,scalar.replace("om2","om2 release")]:
    obj=compile_source("object\n"+source)
    funcs,calls,h=parse(obj)
    assert obj[h[1]:h[2]]==compile_source(source), "object payload differs from existing native compiler"
    assert obj==compile_source("object\n"+source), "nondeterministic object"
    count+=1
fs,cs,h=parse(compile_source("object\n"+stack))
# A function's record is the deepest SP its own code reaches (frame, save areas, host buffers),
# callees excluded; here that is the call: frame 48 plus the call's save area.
assert cs[0][3]>48 and fs[1]["stack"]==cs[0][3] and fs[0]["stack"]==0, "object-stack-contract"
imports="""object
om2
extern fn dep a int to int
export fn run a int to int
ret dep a
end
"""
fs,cs,h=parse(compile_source(imports))
assert [f["flags"] for f in fs]==[2,1] and fs[0]["name"]=="dep"
assert fs[0]["params"]==[(8,0,0,0,0)] and cs[0][1:3]==(1,0)
count+=1
many="object\nom2\n"+"".join("export fn entry%d to int\nret %d\nend\n"%(i,i) for i in range(80))
assert len(parse(compile_source(many))[0])==80
count+=1
# These boundaries must refuse rather than encoding untyped or effectful imports.
refusals=[
("object\nom2\nexport fn run to long\nret mapdrop 1\nend\n",9),
("object\nfn main to int\nret 0\nend\n",16),
(imports.replace("dep a","dep a b",1),16),
(imports.replace("extern fn dep a int to int","extern fn dep a int to int inline"),9),
("object\nom2\nextern fn dep a edit uchar 4 fresh to void\nexport fn run to int\nret 0\nend\n",27),
("object\nom2\nextern fn dep a int to int\nextern fn dep a int to int\n",10),
("object\nom2\nglobal g uchar 1\nexport fn run to uchar\nret get g 0\nend\n",9),
("object\nom2\ntext g \"a\"\nexport fn run to uchar\nret get g 0\nend\n",9),
("object\nom2\nexport fn run to int\nret run\nend\n",9),
("object\nom2\nextern fn dep a int to int\nexport fn run to int\nret dep ulong 3\nend\n",7),
("object\nom2\nextern fn dep a view Missing to int\n",16),
]
for source,status in refusals:
    compile_source(source,status);count+=1
# Independent parser control: bad target, trailing bytes, changed relocation, and truncation all fail.
data=compile_source(imports)
fs,cs,h=parse(data)
mutants=[]
m=bytearray(data);struct.pack_into("<Q",m,16,99);mutants.append(m)
mutants.extend([data+b"\0",data[:-1]])
m=bytearray(data);struct.pack_into("<I",m,cs[0][0],0x94000001);mutants.append(m)
for m in mutants:
    try:parse(m)
    except (AssertionError,UnicodeDecodeError):pass
    else:raise AssertionError("invalid object survived parser control")
print("OBJECT-ORACLE PASS cases=%d controls=%d"%(count,len(mutants)))
