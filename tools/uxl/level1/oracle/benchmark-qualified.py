# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""External experiment: archived Spark prompt, fixed generation length and capacity."""
from pathlib import Path
import hashlib,json,os,re,statistics,struct,subprocess,threading,time,traceback
D=Path(__file__).resolve().parent
S=Path(os.environ['SOURCE_PLAN_DIR']).resolve()
F=json.loads((D/'lighthouse256.json').read_text())
P=F['prompt_ids'];G=F['generated_ids'];N=len(P)+len(G)-1
HIP_PATH=Path(os.environ['HIP_ORACLE_JSON']).resolve()
HIP=json.loads(HIP_PATH.read_text());H=HIP['ids']
assert HIP['capacity']==F['capacity'] and len(H)==len(G)
assert HIP['fixture_sha256']==hashlib.sha256((D/'lighthouse256.json').read_bytes()).hexdigest()
state={'phase':'prepare','rows':[],'fixture':F,'hip_oracle_sha256':hashlib.sha256(HIP_PATH.read_bytes()).hexdigest(),'qualification':'all IDs equal independent AMD HIP graph; archived Spark agreement reported separately'}
source_manifest=json.loads((S/'MANIFEST.json').read_text())
state['binary_sha256']=hashlib.sha256((S/'omega-launch').read_bytes()).hexdigest()
assert state['binary_sha256']==source_manifest['omega-launch']
def save():
 (D/'state.json').write_text(json.dumps(state,indent=2))
 print(json.dumps({'phase':state['phase'],'rows':state['rows']}),flush=True)
def patch(name):
 raw=(S/name).read_bytes()
 assert hashlib.sha256(raw).hexdigest()==json.loads((S/'MANIFEST.json').read_text())[name]
 nc,nf,nb,nd,np,ng,tok=struct.unpack_from('<7Q',raw,8)
 off=64+nc*16+nb*48;end=off+((np*4+7)//8)*8
 prompt=struct.pack('<'+'I'*len(P),*P);prompt+=bytes((-len(prompt))%8)
 delta=len(prompt)-(end-off)
 so,sl,do,dl=struct.unpack_from('<4Q',raw,len(raw)-32)
 assert so>=end and so+sl==do and do+dl==len(raw)-32
 result=raw[:40]+struct.pack('<2Q',len(P),len(G))+raw[56:off]+prompt+raw[end:-32]+struct.pack('<4Q',so+delta,sl,do+delta,dl)
 path=D/name;path.write_bytes(result)
 meta=json.loads((S/(name+'.json')).read_text())
 meta.update(plan=name,bytes=len(result),sha256=hashlib.sha256(result).hexdigest(),prompt=len(P),generate=len(G),fixture_sha256=hashlib.sha256((D/'lighthouse256.json').read_bytes()).hexdigest(),parent_plan_sha256=hashlib.sha256(raw).hexdigest())
 (D/(name+'.json')).write_text(json.dumps(meta,indent=2))
 return meta
def run(label,name,meta):
 args=[str(S/'omega-launch'),'plan',str(D/name)]+[str(S/'code'/(n+'.hsaco')) for n in sorted(meta['code_objects'])]+[str(Path('/tmp/qwen3.8-27b-fp8')/n) for n in meta['files']]
 for n,v in meta['code_objects'].items():assert hashlib.sha256((S/'code'/(n+'.hsaco')).read_bytes()).hexdigest()==v['sha256']
 start=time.monotonic();marks={};peak={'rss_kib':0,'drm':{}}
 with (D/(label+'.stderr')).open('w') as err:
  proc=subprocess.Popen(args,stdout=subprocess.PIPE,stderr=err,text=True,bufsize=1)
  def deadline():
   try:proc.wait(timeout=180)
   except subprocess.TimeoutExpired:proc.kill()
  threading.Thread(target=deadline,daemon=True).start()
  def sample():
   while proc.poll() is None:
    try:
     q=Path('/proc')/str(proc.pid)
     for l in (q/'status').read_text().splitlines():
      if l.startswith('VmRSS:'):peak['rss_kib']=max(peak['rss_kib'],int(l.split()[1]))
     for f in (q/'fdinfo').glob('*'):
      for l in f.read_text().splitlines():
       if l.startswith('drm-memory-'):
        k,v=l.split(':',1);parts=v.split()
        if parts and parts[0].isdigit() and int(parts[0])>peak['drm'].get(k,{}).get('value',-1):peak['drm'][k]={'value':int(parts[0]),'unit':parts[1] if len(parts)>1 else ''}
    except (OSError,ValueError):pass
    time.sleep(.1)
  threading.Thread(target=sample,daemon=True).start()
  with (D/(label+'.stdout')).open('w') as out:
   for line in proc.stdout:
    out.write(line);out.flush()
    if line.startswith('OMEGA_PLAN ready'):marks['ready_s']=time.monotonic()-start
    if line.startswith('OMEGA_STEP '+str(len(P)-1)+' '):marks['first_generated_id_s']=time.monotonic()-start
  rc=proc.wait()
 text=(D/(label+'.stdout')).read_text()
 steps=[tuple(map(int,v)) for v in re.findall(r'^OMEGA_STEP (\d+) tok=(\d+) us=(\d+)$',text,re.M)]
 m=re.search(r'^OMEGA_PLAN ids=\[([\d, ]+)\]$',text,re.M);ids=list(map(int,m.group(1).split(','))) if m else []
 shape=rc==0 and [i for i,t,u in steps]==list(range(N)) and ids==[t for i,t,u in steps[len(P)-1:]]
 row={'label':label,'exit':rc,'shape_ok':shape,'ids_match':sum(a==b for a,b in zip(ids,G)),'expected_ids':len(G),'first_divergence':next((i for i,(a,b) in enumerate(zip(ids,G)) if a!=b),None),'all_ids_equal':ids==G,'steps':len(steps),'marks':marks,'total_s':time.monotonic()-start,'memory_peak':peak,'prefill_ms':sum(u/1000 for i,t,u in steps[:len(P)]) if shape else None,'decode_ms_median':statistics.median(u/1000 for i,t,u in steps[len(P):]) if shape else None}
 row.update(ids=ids,hip_ids_equal=ids==H,first_hip_divergence=next((i for i,(a,b) in enumerate(zip(ids,H)) if a!=b),None))
 (D/(label+'.json')).write_text(json.dumps(row,indent=2));return row
try:
 metas={n:patch(n) for n in ['real2.plan','real2-controls.plan']}
 state['plan_hashes']={n:m['sha256'] for n,m in metas.items()}
 assert all(m['capacity']==F['capacity'] for m in metas.values())
 state['phase']='control';save()
 c=run('control','real2-controls.plan',metas['real2-controls.plan']);state['control']=c;save()
 assert c['shape_ok'] and not c['hip_ids_equal'] and not c['all_ids_equal'],'control not caught'
 for label in ['warmup']+['sample'+str(i) for i in range(1,6)]:
  state['phase']=label;save();r=run(label,'real2.plan',metas['real2.plan']);state['rows'].append(r);save()
  assert r['shape_ok'] and r['hip_ids_equal'],r
 state['phase']='complete';save()
 print('RESULT PASS same archived Spark prompt and capacity, all 256 AMD HIP graph IDs exact in five accepted runs; Spark divergence reported separately',flush=True)
except BaseException:
 state.update(phase='exception',detail=traceback.format_exc());save()
 print('RESULT FAIL_OR_INCOMPLETE',flush=True)
 raise
