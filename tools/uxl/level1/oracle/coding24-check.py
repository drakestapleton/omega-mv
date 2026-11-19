# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

from pathlib import Path
import json,subprocess,re,runpy,hashlib,traceback
D=Path(__file__).resolve().parent;S=D/'source'
g=runpy.run_path(str(D/'driver-real2.py'),run_name='gold-import')['GOLD']
r={'phase':'running','binary_sha256':hashlib.sha256((S/'omega-launch').read_bytes()).hexdigest(),'expected':g['generated_ids'],'rows':[]}
try:
 for label,name,match in [('coding24-control','real2-controls.plan',False),('coding24','real2.plan',True)]:
  m=json.loads((S/(name+'.json')).read_text())
  args=[str(S/'omega-launch'),'plan',str(S/name)]+[str(S/'code'/(n+'.hsaco')) for n in sorted(m['code_objects'])]+[str(Path('/tmp/qwen3.8-27b-fp8')/n) for n in m['files']]
  p=subprocess.run(args,capture_output=True,timeout=120)
  (D/(label+'.stdout')).write_bytes(p.stdout);(D/(label+'.stderr')).write_bytes(p.stderr)
  z=re.search(rb'^OMEGA_PLAN ids=\[([\d, ]+)\]$',p.stdout,re.M);ids=list(map(int,z.group(1).split(b','))) if z else []
  steps=re.findall(rb'^OMEGA_STEP (\d+) tok=(\d+) us=(\d+)$',p.stdout,re.M)
  row=dict(label=label,exit=p.returncode,ids=ids,all_ids_equal=ids==g['generated_ids'],steps=len(steps),plan_sha256=hashlib.sha256((S/name).read_bytes()).hexdigest());r['rows'].append(row)
  assert p.returncode==0 and len(steps)==47 and len(ids)==24 and row['all_ids_equal']==match,row
 r['phase']='complete'
except BaseException:r.update(phase='exception',detail=traceback.format_exc())
(D/'coding24.json').write_text(json.dumps(r,indent=2));print(json.dumps(r),flush=True)
