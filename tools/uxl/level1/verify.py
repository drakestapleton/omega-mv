# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
# External evidence verifier, not a production dependency.
from pathlib import Path
import ast,hashlib,json,math,re,subprocess,sys,statistics
D=Path(__file__).resolve().parent
hashes=json.loads((D/'SHA256.json').read_text())
actual={f.relative_to(D).as_posix() for f in D.rglob('*') if f.is_file() and f.name!='SHA256.json'}
assert actual==set(hashes),(actual-set(hashes),set(hashes)-actual)
for name,digest in hashes.items():assert hashlib.sha256((D/name).read_bytes()).hexdigest()==digest,name
for name,entry in json.loads((D/'oracle/ORIGINAL_SCRIPTS.json').read_text()).items():
 raw=(D/name).read_bytes();prefix=entry['portable_prefix'].encode();assert raw.startswith(prefix)
 assert hashlib.sha256(raw[len(prefix):]).hexdigest()==entry['original_sha256'],name
v=json.loads((D/'native/state.json').read_text());h=json.loads((D/'numerical/graph.json').read_text());f=json.loads((D/'oracle/lighthouse256.json').read_text())
assert h['capacity']==f['capacity']==131072 and len(h['ids'])==256
assert h['fixture_sha256']==hashlib.sha256((D/'oracle/lighthouse256.json').read_bytes()).hexdigest()
assert h['first_divergence']==109
for token,top in zip(h['ids'],h['top5']):
 assert token==top[0][0] and all(math.isfinite(score) for _,score in top)
for label in ['control']+[r['label'] for r in v['rows']]:
 row=v['control'] if label=='control' else next(r for r in v['rows'] if r['label']==label)
 raw=(D/'native'/(label+'.stdout')).read_text()
 steps=[tuple(map(int,t)) for t in re.findall(r'^OMEGA_STEP (\d+) tok=(\d+) us=(\d+)$',raw,re.M)]
 ids=list(map(int,re.search(r'^OMEGA_PLAN ids=\[([\d, ]+)\]$',raw,re.M).group(1).split(',')))
 assert row['exit']==0 and [i for i,t,u in steps]==list(range(285))
 assert math.isclose(sum(u for i,t,u in steps[:30])/1000,row['prefill_ms'],rel_tol=0,abs_tol=1e-9)
 assert statistics.median(u/1000 for i,t,u in steps[30:])==row['decode_ms_median']
 assert ids==[t for i,t,u in steps[29:]]==row['ids']
 assert (ids==h['ids'])==(label!='control')
 assert (ids==f['generated_ids'])==row['all_ids_equal']
 assert next((i for i,(a,b) in enumerate(zip(ids,f['generated_ids'])) if a!=b),None)==row['first_divergence']
gold=next(ast.literal_eval(n.value) for n in ast.parse((D/'oracle/driver-real2.py').read_text()).body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='GOLD' for t in n.targets))
c=json.loads((D/'coding24/coding24.json').read_text());assert c['phase']=='complete' and c['expected']==gold['generated_ids']
assert c['binary_sha256']==v['binary_sha256']==json.loads((D/'host/qualification.json').read_text())['binary_sha256']
for row in c['rows']:
 raw=(D/'coding24'/(row['label']+'.stdout')).read_text()
 ids=list(map(int,re.search(r'^OMEGA_PLAN ids=\[([\d, ]+)\]$',raw,re.M).group(1).split(',')))
 assert ids==row['ids'] and row['exit']==0
 assert (ids==gold['generated_ids'])==(row['label']=='coding24')
for name in ('vadd.hsaco','vadd-lds.hsaco'):
 raw=(D/'native'/(name+'.stdout')).read_text()
 assert 'OMEGA vadd=PASS count=256' in raw
 if name=='vadd-lds.hsaco':assert 'OMEGA diag group_segment_size 4096' in raw
assert json.loads((D/'native/job-state.json').read_text())['phase']=='complete'
assert json.loads((D/'native/candidate.json').read_text())['binary_sha256']==v['binary_sha256']
calc=json.loads(subprocess.check_output([sys.executable,str(D/'calculate.py')]))
assert calc==json.loads((D/'calculations.json').read_text())
print('EVIDENCE PASS',len(hashes),'hashed files; raw steps/IDs; independent graph; reference coding24; calculations')
