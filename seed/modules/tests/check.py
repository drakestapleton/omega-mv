#!/usr/bin/env python3
"""Independent module integration and mutation oracle. No production dependency."""
import hashlib, os, pathlib, struct, subprocess, sys, tempfile
P=pathlib.Path
repo=P(__file__).resolve().parents[3]
compiler=P(sys.argv[1]).resolve()
seed=repo/'seed/out/omc'
out=P(sys.argv[2]).resolve() if len(sys.argv)>2 else P(tempfile.mkdtemp(prefix='ommodules-'))
out.mkdir(parents=True,exist_ok=True)
sha=lambda b:hashlib.sha256(b).hexdigest()
u=lambda b,p:struct.unpack_from('<Q',b,p)[0]
def put(b,p,n): struct.pack_into('<Q',b,p,n)
comp=sha(compiler.read_bytes())
source=b'om2\n'+(repo/'seed/ng/sha256.om').read_bytes()+(repo/'seed/modules/driver.om').read_bytes()
def compile_driver(src,path):
 r=subprocess.run([seed],input=src,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 assert r.returncode==0,r.stderr.decode();path.write_bytes(r.stdout);path.chmod(0o755)
compile_driver(source,out/'ommod')
driver=out/'ommod'
subprocess.run(['cc','-Wall','-Wextra','-Werror','-O2',str(repo/'seed/modules/tests/caller.c'),str(repo/'seed/modules/tests/caller.S'),'-o',str(out/'caller')],check=True)
store=out/'store';store.mkdir(exist_ok=True)
passed=[]
def ok(label):passed.append(label);print('PASS',label,flush=True)
def run(args,expected=0,exe=None):
 r=subprocess.run([exe or driver,*map(str,args)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=30)
 assert r.returncode==expected,(args,r.returncode,expected,r.stdout,r.stderr)
 return r
profile='debug'
def build(name,text):
 p=out/(name+'.om');p.write_text(text)
 h=sha(p.read_bytes());r=run(['build',compiler,comp,profile,'aarch64-linux',store,p,h])
 artifact=r.stdout.decode().strip().split()[-1]
 assert len(artifact)==64
 blob=(store/(artifact+'.mod')).read_bytes();assert sha(blob)==artifact
 assert blob[:8]==b'OMMOD001' and blob[8:72]==comp.encode() and blob[72:136]==h.encode()
 key=sha(b'OMMOD001'+comp.encode()+h.encode()+struct.pack('<QQ',int(profile=='release'),1))
 assert (store/(key+'.ref')).read_text()==artifact
 return dict(name=name,path=p,hash=h,artifact=artifact,key=key,blob=blob)
def linkargs(m,dest,kind='program',entry='answer',s=store):
 return ['link',s,comp,profile,'aarch64-linux',m['hash'],m['artifact'],kind,entry,dest]
def execute(m,want,entry='answer'):
 p=out/(m['name']+'.elf');run(linkargs(m,p,entry=entry));r=subprocess.run([p]);assert r.returncode==want,(m['name'],r.returncode,want)
 return p
leaf=build('leaf','om2\nfn helper to int\nret 40\nend\nexport fn answer to int\nret add helper 2\nend\n')
execute(leaf,42);ok('native leaf ELF')
root=build('root',f'om2\nimport dep {leaf["hash"]} answer\nfn helper to int\nret 1\nend\nexport fn answer to int\nret add dep helper\nend\n')
execute(root,43);ok('separate native modules and private name isolation')
root2=build('root2',f'om2\nimport dep {leaf["hash"]} answer\nexport fn answer to int\nret add dep 2\nend\n')
execute(root2,44);assert (store/(leaf['artifact']+'.mod')).read_bytes()==leaf['blob'];ok('same byte-identical dependency reused by two roots')
# Direct single-unit output is the independent execution oracle.
mono=b'om2\nfn helper to int\nret 40\nend\nfn dep to int\nret add helper 2\nend\nfn main to int\nret add dep 1\nend\n'
r=subprocess.run([compiler],input=mono,stdout=subprocess.PIPE,stderr=subprocess.PIPE);assert r.returncode==0,r.stderr
p=out/'monolithic';p.write_bytes(r.stdout);p.chmod(0o755);assert subprocess.run([p]).returncode==43;ok('single-unit differential oracle')
r=run(['build',compiler,comp,profile,'aarch64-linux',store,root['path'],root['hash']]);assert r.stdout==f'CACHE {root["artifact"]}\n'.encode();ok('cache identity equality')
# strace verifies there is no compiler exec on a cache hit, even though the executable is hashed.
trace=out/'cache.strace'
subprocess.run(['strace','-f','-e','trace=execve,execveat','-o',trace,str(driver),'build',str(compiler),comp,profile,'aarch64-linux',str(store),str(root['path']),root['hash']],check=True,stdout=subprocess.PIPE)
assert trace.read_text().count('execve(')==1 and 'execveat(' not in trace.read_text();ok('cache performs no compiler execution')
fp=out/'root.native';run(linkargs(root,fp,'function','-'))
r=subprocess.run([out/'caller',fp,'0'],capture_output=True);assert r.returncode==0 and r.stdout==b'43\n';ok('function-mode independent native ABI caller')
data=fp.read_bytes();assert data[-8:]==b'OMLINK01';ds=u(data,len(data)-16);dp=len(data)-16-ds
assert u(data,dp)==1 and u(data,dp+24)==8 and u(data,dp+32)==0;ok('machine-readable export/stack descriptor')
arr=build('array','om2\nexport fn sum a view ulong * to ulong\nret add get a 0 get a 3\nend\n')
aroot=build('arrayroot',f'om2\nimport dep {arr["hash"]} sum\nexport fn sum a view ulong * to ulong\nret dep a\nend\n')
ap=out/'array.native';run(linkargs(aroot,ap,'function','-'))
r=subprocess.run([out/'caller',ap,'999'],capture_output=True);assert r.returncode==0 and r.stdout==b'14\n';ok('typed unsized-view import ABI')
trap=build('trap','om2\nexport fn answer to int\nx = int 0\nret div 1 x\nend\n')
execute(trap,102);tp=out/'trap.native';run(linkargs(trap,tp,'function','-'));assert subprocess.run([out/'caller',tp,'0']).returncode==102;ok('program and host-caller trap semantics')
void=build('void','om2\nexport fn answer to void\nret\nend\n');execute(void,0);ok('void root returns zero')
# Each negative must leave the final output absent.
serial=0
def refuse(args,label,exe=None):
 global serial
 serial+=1;p=out/f'negative-{serial}'
 r=subprocess.run([exe or driver,*map(str,args(p))],capture_output=True,timeout=30)
 assert 0<r.returncode<100,(label,r.returncode,r.stderr)
 assert not p.exists(),label
 ok(label)
refuse(lambda p:['link',store,'0'*64,profile,'aarch64-linux',root['hash'],root['artifact'],'program','answer',p],'wrong compiler identity')
refuse(lambda p:['link',store,comp,'release','aarch64-linux',root['hash'],root['artifact'],'program','answer',p],'profile mismatch')
refuse(lambda p:['link',store,comp,profile,'x86linux',root['hash'],root['artifact'],'program','answer',p],'target mismatch')
refuse(lambda p:linkargs({**root,'artifact':'0'*64},p),'root artifact digest mismatch')
refuse(lambda p:linkargs(root,p,entry='helper'),'private entry refused')
refuse(lambda p:['build',compiler,'0'*64,profile,'aarch64-linux',store,root['path'],root['hash']],'build authenticates compiler bytes')
refuse(lambda p:['build',compiler,comp,profile,'aarch64-linux',store,root['path'],'0'*64],'build authenticates source snapshot')
# Corruption without changing the content address must fail both link and cache reuse.
payload=store/(root['artifact']+'.mod');bad=bytearray(root['blob']);bad[180]^=1
payload.chmod(0o644);payload.write_bytes(bad)
refuse(lambda p:linkargs(root,p),'payload corruption hash check')
refuse(lambda p:['build',compiler,comp,profile,'aarch64-linux',store,root['path'],root['hash']],'cache corruption hash check')
payload.write_bytes(root['blob']);payload.chmod(0o444)
# Reference a structurally mutated object by its recomputed digest to reach parser checks.
def objectinfo(m):
 b=m['blob'];o=176+u(b,152);n=u(b,160);obj=b[o:o+n];p=u(obj,40);funcs=[]
 for i in range(u(obj,48)):
  start=p;np=u(obj,p+24);nl=u(obj,p+40);name=obj[p+48:p+48+nl];p=(p+48+nl+7)&~7;params=p;p+=np*40
  funcs.append((start,params,name))
 return o,obj,funcs,p
def mutation(m,change,label,exe=None,count=True):
 b=bytearray(m['blob']);o,obj,fs,calls=objectinfo(m);change(b,o,obj,fs,calls)
 h=sha(b);(store/(h+'.mod')).write_bytes(b);ref=store/(m['key']+'.ref');ref.chmod(0o644);ref.write_text(h)
 mm={**m,'artifact':h};serialname=out/('mut-'+str(len(passed))+'-'+h[:8])
 try:
  r=subprocess.run([exe or driver,*map(str,linkargs(mm,serialname))],capture_output=True,timeout=30)
  assert 0<r.returncode<100,(label,r.returncode,r.stderr)
  assert not serialname.exists(),label
  if count:ok(label)
 finally:ref.write_text(m['artifact']);ref.chmod(0o444)
mutations=[
 (lambda b,o,x,f,c:put(b,o+8,2),'bad object version'),
 (lambda b,o,x,f,c:put(b,o+16,2),'bad object target'),
 (lambda b,o,x,f,c:put(b,o+24,1),'bad object profile'),
 (lambda b,o,x,f,c:put(b,o+48,2**64-1),'overflowed function count'),
 (lambda b,o,x,f,c:put(b,o+56,2**64-1),'overflowed call count'),
 (lambda b,o,x,f,c:put(b,o+72,1),'reserved header nonzero'),
 (lambda b,o,x,f,c:put(b,o+c,175),'unaligned/outside relocation'),
 (lambda b,o,x,f,c:put(b,o+c+8,2**64-1),'bad caller function index'),
 (lambda b,o,x,f,c:put(b,o+c+16,2**64-1),'bad callee function index'),
 (lambda b,o,x,f,c:put(b,o+f[0][0]+16,12),'import signature mismatch'),
 (lambda b,o,x,f,c:struct.pack_into('<I',b,o+u(x,c),0x94000001),'wrong call instruction'),
 (lambda b,o,x,f,c:put(b,o+c+24,8388608),'transitive stack overflow'),
 (lambda b,o,x,f,c:put(b,o+f[1][0]+40,2**64-1),'overflowed name length'),
]
for change,label in mutations:mutation(root,change,label)
# Local function call cycle: rewrite the call to target its own caller, keep opcode consistent.
def cycle(b,o,x,fs,c):
 ci=next(c+i*32 for i in range(u(x,56)) if u(x,c+i*32+16)!=0)
 src=u(x,ci+8);put(b,o+ci+16,src);site=u(x,ci);dest=u(x,fs[src][0]+8)
 struct.pack_into('<I',b,o+site,0x94000000|(((dest-site)//4)&0x3ffffff))
mutation(root,cycle,'local call cycle refused')
# Duplicate relocation record pointing at the first call.
def duplicate(b,o,x,fs,c): b[o+c+32:o+c+40]=b[o+c:o+c+8]
mutation(root,duplicate,'duplicate callsite refused')
# Invalid scalar parameter and fresh import must not cross the typed boundary.
mutation(aroot,lambda b,o,x,f,c:put(b,o+f[0][1],12),'void parameter refused')
mutation(aroot,lambda b,o,x,f,c:put(b,o+f[0][1]+32,1),'fresh external parameter refused')
# Truncations at header and metadata boundaries, keeping envelope lengths internally consistent.
for cut in [0,8,175,len(objectinfo(root)[1])-1]:
 def trunc(b,o,x,f,c,cut=cut):
  del b[o+cut:o+len(x)];put(b,160,cut)
 mutation(root,trunc,f'truncated object {cut}')
# Symlink protection on store, dependency and output ancestors.
linkstore=out/'storelink';linkstore.symlink_to(store,target_is_directory=True)
refuse(lambda p:linkargs(root,p,s=linkstore),'symlink store refused')
realout=out/'realout';realout.mkdir(exist_ok=True);linked=out/'linkedout';linked.symlink_to(realout,target_is_directory=True)
refuse(lambda p:linkargs(root,linked/'must-not-exist'),'symlink output ancestor refused');assert not (realout/'must-not-exist').exists()
existing=out/'existing';existing.write_bytes(b'untouched');r=subprocess.run([driver,*map(str,linkargs(root,existing))],capture_output=True);assert r.returncode==38 and existing.read_bytes()==b'untouched';ok('existing output never overwritten')
# Native bytes for a dependency are exactly the independent compiler result.
o,obj,_,_=objectinfo(leaf)
r=subprocess.run([compiler],input=b'object\n'+leaf['path'].read_bytes(),capture_output=True)
assert r.returncode==0 and obj==r.stdout;ok('stored payload equals independent separate compilation')
# A replaced transitive identity cannot be silently followed.
ref=store/(leaf['key']+'.ref');ref.chmod(0o644);ref.write_text(root2['artifact'])
refuse(lambda p:linkargs(root,p),'changed transitive identity refused')
ref.write_text(leaf['artifact']);ref.chmod(0o444)
# Missing immutable content and nonregular sources refuse promptly.
blobpath=store/(leaf['artifact']+'.mod');hidden=blobpath.with_suffix('.hidden');blobpath.rename(hidden)
refuse(lambda p:linkargs(root,p),'missing transitive payload refused');hidden.rename(blobpath)
fifo=out/'fifo';os.mkfifo(fifo)
refuse(lambda p:['build',compiler,comp,profile,'aarch64-linux',store,fifo,leaf['hash']],'FIFO source refuses without waiting')
# Recover a crash between immutable payload publication and its reference publication.
ref=store/(root2['key']+'.ref');ref.unlink()
r=run(['build',compiler,comp,profile,'aarch64-linux',store,root2['path'],root2['hash']])
assert r.stdout==f'BUILT {root2["artifact"]}\n'.encode();ok('orphan payload publication recovered')
# Missing/private imports are checked before invoking the compiler.
for name,export in [('missing','absent'),('private','helper')]:
 p=out/(name+'.om');p.write_text(f'om2\nimport dep {leaf["hash"]} {export}\nexport fn answer to int\nret dep\nend\n')
 refuse(lambda dest,p=p:['build',compiler,comp,profile,'aarch64-linux',store,p,sha(p.read_bytes())],name+' import refused')
# Independent module count beyond the legacy 64-unit builder boundary.
leaves=[]
for i in range(70):
 leaves.append(build('wide'+str(i),f'om2\nnote unique {i}\nexport fn answer to int\nret {i}\nend\n'))
wide=build('wide','om2\n'+''.join(f'import dep{i} {m["hash"]} answer\n' for i,m in enumerate(leaves))+'export fn answer to int\nret add dep0 dep69\nend\n')
execute(wide,69);ok('71 native modules without legacy count cap')
profile='release'
rleaf=build('releaseleaf','om2 release\nexport fn answer to int\nret 17\nend\n')
rroot=build('releaseroot',f'om2 release\nimport dep {rleaf["hash"]} answer\nexport fn answer to int\nret dep\nend\n')
execute(rroot,17);ok('release profile native import')
profile='debug'
# Synthetic arithmetic boundaries. The real function text is extracted from driver.om and run in a tiny
# harness; expectations come from exact Python integers. No case allocates near the boundary.
import re,itertools
MAX=2**63-1;TL=2**60-1
def extract(text,name):
 m=re.search(r'^fn %s .*?(?=^fn |\Z)'%name,text,re.S|re.M);assert m,name;return m.group(0)
HEAD='om2\nglobal mb uchar *\nglobal mt ulong *\nglobal ms ulong 8\nglobal mw uchar 4\ntext err "x\\n"\n'
def harness(text,main,names=('die','need','sizeadd','sizemul','growto','ba','ta')):
 return (HEAD+''.join(extract(text,n) for n in names)+'fn main to int\n'+main+'\nend\n').encode()
hdir=out/'arith';hdir.mkdir(exist_ok=True);hn=0
def hrun(text,main,names=None,want=0):
 global hn
 hn+=1;exe=hdir/f'h{hn}'
 r=subprocess.run([seed],input=harness(text,main,*( [names] if names else [])),stdout=subprocess.PIPE,stderr=subprocess.PIPE);assert r.returncode==0,(main,r.stderr)
 exe.write_bytes(r.stdout);exe.chmod(0o755)
 return subprocess.run([exe],capture_output=True,timeout=30).returncode
def lit(n):return f'ulong {n}'
def arith_cases():
 cases=[]
 va=[0,1,2,MAX-2,MAX-1,MAX,MAX+1,2**64-1]
 for a,b in itertools.product(va,va):
  ok=a<=MAX and b<=MAX and a+b<=MAX
  cases.append((f'a = {lit(a)}\nb = {lit(b)}\nr = sizeadd a b\nneed eq r {lit(a+b) if ok else 0} 90\nret 0',0 if ok else 20,f'sizeadd {a} {b}'))
 vm=[0,1,2,3,MAX//3,MAX//3+1,2**31,2**32,2**32+1,2**62-1,2**62,MAX,MAX+1,2**64-1]
 for a,b in itertools.product(vm,vm):
  ok=a*b<=MAX or a==0
  want=lit(a*b) if ok else '0'
  if a==0:want='ulong 0'
  cases.append((f'a = {lit(a)}\nb = {lit(b)}\nr = sizemul a b\nneed eq r {want} 90\nret 0',0 if ok else 20,f'sizemul {a} {b}'))
 for limit in [MAX,TL]:
  vn=[0,1,limit-4097,limit-1,limit,limit+1,2**64-1];ve=[0,1,512,4096,limit-1,limit,2**64-1]
  for n,e in itertools.product(vn,ve):
   if n>limit:
    cases.append((f'n = {lit(n)}\ne = {lit(e)}\nl = {lit(limit)}\nr = growto n e l\nret 0',20,f'growto refuses {n} limit {limit}'));continue
   res=n+e if e<=limit-n else n
   cases.append((f'n = {lit(n)}\ne = {lit(e)}\nl = {lit(limit)}\nr = growto n e l\nneed eq r {lit(res)} 90\nret 0',0,f'growto {n} {e} limit {limit}'))
 # Arena reservations refuse before touching memory when used+request passes the fixed-width boundary.
 pre='r = ta 1\nr = ba 1\n'
 for used,n,fn,lim in [(1,MAX,'ba',MAX),(1,2**64-1,'ba',MAX),(MAX,1,'ba',MAX),(MAX-99,100,'ba',MAX),(1,TL,'ta',TL),(1,2**64-1,'ta',TL),(TL,1,'ta',TL),(5,TL-4,'ta',TL)]:
  idx=0 if fn=='ba' else 1
  cases.append((pre+f'u = {lit(used)}\nn = {lit(n)}\nput ms {idx} u\nr = {fn} n\nret 0',20,f'{fn} refuses used {used} request {n}'))
 return cases
cases=arith_cases();bad=[]
for main,want,label in cases:
 got=hrun(source.decode(),main)
 if got!=want:bad.append((label,got,want))
assert not bad,bad[:10]
ok(f'{len(cases)} synthetic length-arithmetic boundary cases')
# Small real growth path through ba/ta (no boundary allocation).
assert hrun(source.decode(),'r = ta 1\nr = ba 1\np = ba 5000\nneed eq p 1 90\nput mb 5000 7\nq = ba 100000\nneed eq q 5001 91\nput mb 105000 9\nneed eq get mb 5000 7 92\nt = ta 100000\nneed eq t 1 93\nput mt 100000 5\nneed eq get mt 100000 5 94\nret 0')==0;ok('small arena growth path preserves data')
# SHA-256 bit-length field is a real 64-bit wire boundary, refused before any read.
shsrc=(repo/'seed/ng/sha256.om').read_text()
def hashharness(n):
 s=('om2\nglobal mb uchar *\nglobal mt ulong *\nglobal ms ulong 8\nglobal mw uchar 4\nglobal mh uchar 64\ntext err "x\\n"\n'+shsrc.replace('om2\n','',1)+''.join(extract(driver_text,x) for x in ['die','need','hash'])+f'fn main to int\nn = {lit(n)}\nhash 0 n\nret 0\nend\n')
 return s.encode()
driver_text=(repo/'seed/modules/driver.om').read_text()
for n,want in [(2**61,20),(2**64-1,20),(2**63,20)]:
 r=subprocess.run([seed],input=hashharness(n),stdout=subprocess.PIPE,stderr=subprocess.PIPE);assert r.returncode==0,r.stderr
 e=hdir/f'hash{n}';e.write_bytes(r.stdout);e.chmod(0o755)
 assert subprocess.run([e],capture_output=True).returncode==want,n
ok('SHA-256 length field boundary refused')
for old,label in [('need le b div 9223372036854775807 a 20','sizemul overflow'),('need le b sub 9223372036854775807 a 20','sizeadd overflow'),('need le n limit 20','growto limit'),('need le n sub 9223372036854775807 p 20','ba overflow'),('need le n sub 1152921504606846975 p 20','ta overflow')]:
 mtext=source.decode();assert mtext.count(old)==1,old
 mtext=mtext.replace(old,'note disabled arithmetic check')
 killed=any(hrun(mtext,m)!=w for m,w,_ in cases)
 assert killed,'surviving arithmetic mutant '+label
 ok('caught arithmetic mutant '+label)
# Independent, targeted implementation mutants must fail the corresponding negative assertion.
mutants=[(b'need eq rw site want 32',b'note disabled relocation check',mutations[10]),(b'need le cost 8388608 37',b'note disabled stack check',mutations[11])]
for idx,(old,new,(change,label)) in enumerate(mutants):
 assert source.count(old)==1
 exe=out/f'mutant-{idx}';compile_driver(source.replace(old,new),exe)
 try:mutation(root,change,label+' mutant',exe,False)
 except AssertionError:ok('caught implementation mutant '+str(idx))
 else:raise AssertionError('surviving implementation mutant '+str(idx))
print(f'MODULES PASS {len(passed)} compiler={comp} driver={sha(driver.read_bytes())} source={sha(source)}',flush=True)
