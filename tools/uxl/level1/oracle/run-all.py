# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
from pathlib import Path
import hashlib,json,os,runpy,shutil,subprocess,sys,tarfile,traceback,zipfile
D=Path(__file__).resolve().parent;os.chdir(D)
import platform,datetime
job={'phase':'verify'}
environment={'captured_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'platform':platform.platform(),'nodes':{}}
for p in Path('/sys/class/kfd/kfd/topology/nodes').glob('*/properties'):
 try:environment['nodes'][p.parent.name]={'gpu_id':(p.parent/'gpu_id').read_text(),'properties':p.read_text()}
 except OSError:pass
(D/'environment.json').write_text(json.dumps(environment,indent=2))
def snapshot():
 files=[p for p in D.rglob('*') if p.is_file() and 'source' not in p.relative_to(D).parts and p.suffix in ('.py','.json','.stdout','.stderr','.txt','.mark')]
 files += [D/'omega-launch',D/'vadd-lds.hsaco',D/'vadd.hsaco']
 tmp=D.parent/'refusal-results.tmp'
 with zipfile.ZipFile(tmp,'w',zipfile.ZIP_DEFLATED) as z:
  for p in files:z.write(p,str(p.relative_to(D)))
  z.writestr('DELIVERY_SHA256.json',json.dumps({str(p.relative_to(D)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files},indent=2))
 tmp.replace(D.parent/'omega-refusal-results.zip')
def save():
 (D/'job-state.json').write_text(json.dumps(job,indent=2));print(json.dumps(job),flush=True);snapshot()
try:
 for n,h in json.loads((D/'MANIFEST.json').read_text()).items():assert hashlib.sha256((D/n).read_bytes()).hexdigest()==h,n
 S=D/'source';S.mkdir(exist_ok=True)
 with tarfile.open(D/'cap-data.tar.xz','r:xz') as z:
  for m in z.getmembers():
   assert m.isfile() and Path(m.name).name==m.name
   (S/m.name).write_bytes(z.extractfile(m).read())
 manifest=json.loads((S/'MANIFEST.json').read_text())
 for n,h in manifest.items():assert hashlib.sha256((S/n).read_bytes()).hexdigest()==h,n
 (S/'MANIFEST.original.json').write_bytes((S/'MANIFEST.json').read_bytes())
 shutil.copytree(D/'code',S/'code',dirs_exist_ok=True);shutil.copyfile(D/'omega-launch',S/'omega-launch');(S/'omega-launch').chmod(0o755)
 manifest['omega-launch']=hashlib.sha256((S/'omega-launch').read_bytes()).hexdigest();(S/'MANIFEST.json').write_text(json.dumps(manifest))
 job['phase']='checkpoint';save();runpy.run_path(str(D/'driver-real2.py'),run_name='prepare-import')['prepare']()
 job['phase']='nonzero-LDS';save()
 for name in ('vadd-lds.hsaco','vadd.hsaco'):
  p=subprocess.run([str(S/'omega-launch'),'vadd',str(D/name),'vadd','10000000000'],capture_output=True,timeout=120)
  (D/(name+'.stdout')).write_bytes(p.stdout);(D/(name+'.stderr')).write_bytes(p.stderr)
  assert p.returncode==0 and b'OMEGA vadd=PASS count=256' in p.stdout,(name,p.returncode)
 job['phase']='coding24';save()
 with (D/'coding24-check.stdout').open('w') as o,(D/'coding24-check.stderr').open('w') as e:
  p=subprocess.run([sys.executable,str(D/'coding24-check.py')],stdout=o,stderr=e,timeout=300)
 assert p.returncode==0 and json.loads((D/'coding24.json').read_text())['phase']=='complete'
 job['phase']='lighthouse-five';save()
 env=dict(os.environ,SOURCE_PLAN_DIR=str(S),HIP_ORACLE_JSON=str(D/'independent-hip-graph.json'))
 with (D/'benchmark.stdout').open('w') as o,(D/'benchmark.stderr').open('w') as e:
  p=subprocess.run([sys.executable,str(D/'benchmark-qualified.py')],stdout=o,stderr=e,env=env,timeout=900)
 assert p.returncode==0 and json.loads((D/'state.json').read_text())['phase']=='complete'
 job['phase']='complete';save()
except BaseException:
 job.update(phase='exception',detail=traceback.format_exc());save();raise
