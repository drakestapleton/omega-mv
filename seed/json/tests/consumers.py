#!/usr/bin/env python3
# Test instrument: compile concrete JSON compositions documented by the repository, not runtime
# replacements. --base compares the base tree with the candidate; newer test-only applications
# absent at that base are held identical while their JSON library inputs come from each tree.
import argparse
import hashlib
import json
import re
from pathlib import Path
import subprocess
import sys
sys.dont_write_bytecode=True
import field


def require(ok, message):
    if not ok:
        raise RuntimeError(message)

p=argparse.ArgumentParser()
p.add_argument('omc');p.add_argument('out');p.add_argument('--base')
p.add_argument('--wrong-expectation',action='store_true')
a=p.parse_args()
root=Path(__file__).resolve().parents[3]
out=Path(a.out).resolve();out.mkdir(parents=True,exist_ok=True)
omc=str(Path(a.omc).resolve())
head=subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip()
base=subprocess.check_output(['git','-C',str(root),'rev-parse',a.base],text=True).strip() if a.base else None
J='seed/json/'
N='seed/node/'
D=N+'tests/'
H='seed/net/'
common=[J+'json.om',D+'drv.om']
node=common+[D+'nodedrv.om']
lib=[J+'json.om',J+'jsonw.om',J+'jsonf.om']
main='fn main to int\nret 0\nend\n'
# The input lists are acceptance cases, each linked to an actual documented build command.
# Aliased D in the Node README is expanded from that README, rather than inferred from names.
node_readme=(root/N/'README.md').read_text()
require('D="'+ ' '.join(node)+'"' in node_readme,'documented Node D composition changed')
cases=[]
def add(name, paths, citation, om2=True, suffix=''):
    document=(root/citation).read_text()
    require(all(path in document for path in paths) or citation=='seed/json/tests/field.py',
            'composition citation missing an input: '+name)
    cases.append(dict(name=name,paths=paths,citation=citation,om2=om2,suffix=suffix))

add('bench-chat',[J+'json.om',J+'jsonw.om','bench/inference_cost/chat.om'],'bench/inference_cost/chat.om')
add('bench-fake-model',[J+'json.om',J+'jsonw.om',H+'http.om',H+'notls.om','bench/inference_cost/fake_model.om'],'bench/inference_cost/fake_model.om')
add('agent',[J+'json.om',J+'jsonw.om',H+'http.om',H+'notls.om','seed/agent/path.om','seed/agent/agent.om'],'seed/agent/README.md')
for name,paths in [
 ('infer',[J+'json.om',J+'jsonw.om',H+'http.om',H+'notls.om',N+'infer.om']),
 ('tool-replay',common+[D+'tool-replay.om']),('drv-test',common+[D+'drv-test.om']),
 ('qual',['om/tls/sha2.om']+common+[D+'qual.om']),
 ('receipt',[J+'json.om',J+'jsonw.om','om/tls/sha2.om',D+'drv.om',D+'receipt.om']),
 ('live-test',[J+'json.om','om/tls/sha2.om',N+'live-test.om']),
 ('view-prep',node+[D+'view-prep.om']),('view-accept',node+[D+'view-accept.om']),
 ('release-accept',['om/tls/sha2.om']+node+[D+'release-accept.om']),
 ('release-gate',common+[D+'release-gate.om']),
]:
    add('node-'+name,paths,'seed/node/README.md')
add('node-schedrcpt',[N+'schedrcpt.om',J+'json.om'],'seed/node/README.md',om2=False)
# Gate compositions use aliases J/$1; their exact source clauses supply provenance.
for name,paths,suffix,clause in [
 ('json-lib',lib,main,'cat "$J/json.om" "$J/jsonw.om" "$J/jsonf.om"'),
 ('json-driver',lib+[J+'tests/jsdrv.om'],'','"$J/tests/jsdrv.om"'),
]:
    doc=(root/'seed/json/tests/gate-json.sh').read_text()
    require(clause in doc,'JSON gate composition changed: '+name)
    cases.append(dict(name=name,paths=paths,citation='seed/json/tests/gate-json.sh',om2=True,suffix=suffix))
doc=(root/'seed/semhash/check.sh').read_text()
require('cat "$J/json.om" "$J/jsonw.om";' in doc,'semhash no-float composition changed')
cases.append(dict(name='json-nof',paths=lib[:2],citation='seed/semhash/check.sh',om2=True,suffix=main))
doc=(root/'seed/json/tests/growing.py').read_text()
require("units={u:(j/u).read_text() for u in ('json.om','jsonw.om','jsonf.om')}" in doc,'growth composition changed')
cases.append(dict(name='json-big',paths=lib+[J+'tests/big.om'],citation='seed/json/tests/growing.py',om2=True,suffix=''))
for name,wrapper in field.WRAPPERS.items():
    cases.append(dict(name='field-'+name,paths=lib,citation='seed/json/tests/field.py',om2=True,suffix=wrapper))

cache={}
fallbacks=[]
def text(path, ref):
    key=(path,ref)
    if key in cache:
        return cache[key]
    if ref is None:
        result=(root/path).read_text()
    else:
        r=subprocess.run(['git','-C',str(root),'show',ref+':'+path],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        if r.returncode:
            require(path in (J+'tests/big.om',),'base lacks a non-test composition input: '+path)
            result=(root/path).read_text()
            fallbacks.append(path)
        else:
            result=r.stdout.decode()
    cache[key]=result
    return result

results=[]
for case in cases:
    statuses=[]
    for label,ref in ([('base',base)] if base else [])+[('head',None)]:
        program=('om2\n' if case['om2'] else '')+''.join(text(path,ref) for path in case['paths'])+case['suffix']
        path=out/(case['name']+'-'+label)
        path.with_suffix('.om').write_text(program)
        r=subprocess.run([omc],input=program.encode(),stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=120)
        path.write_bytes(r.stdout)
        path.with_suffix('.err').write_bytes(r.stderr)
        statuses.append(r.returncode)
        results.append(dict(name=case['name'],tree=label,exit=r.returncode,input_sha256=hashlib.sha256(program.encode()).hexdigest(),citation=case['citation'],paths=case['paths']))
    expected=23 if a.wrong_expectation and case['name']=='bench-chat' else 0
    require(all(status==expected for status in statuses) and len(set(statuses))==1,
            'composition expectation mismatch: '+case['name']+' '+repr(statuses))
    print('PASS composition/'+case['name']+' statuses='+','.join(map(str,statuses)),flush=True)
# A library-sized buffer-type regression must be a compile refusal, not a passing parity record.
for case in [c for c in cases if c['name'] in ('node-view-prep','node-view-accept','node-release-accept')]:
    sources=[]
    for path in case['paths']:
        value=text(path,None)
        if path==D+'nodedrv.om':
            declaration=re.findall(r'^const ndjsz ulong [0-9]+$',value,re.M)
            require(len(declaration)==1,'Node width declaration is not unique')
            library_width=re.findall(r'^const jsmaxn ulong ([0-9]+)$',text(J+'json.om',None),re.M)
            require(len(library_width)==1,'library width declaration is not unique')
            value=value.replace(declaration[0],'const ndjsz ulong '+library_width[0])
        sources.append(value)
    r=subprocess.run([omc],input=('om2\n'+''.join(sources)).encode(),stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,timeout=120)
    require(r.returncode==23,(case['name'],'width mutant not refused',r.returncode,r.stderr))
    print('PASS composition/'+case['name']+' width-mutant=23',flush=True)
(out/'manifest.json').write_text(json.dumps(dict(head=head,base=base,cases=cases,results=results,base_application_fallbacks=sorted(set(fallbacks)),excluded_templates=["seed/json/README.md app.om is a placeholder, not a repository program","seed/net/README.md optional JSON addition is not a concrete additional program","seed/text and seed/equiv mention copied routines, not JSON composition"]),indent=2)+'\n')
print('CONSUMERS PASS compositions='+str(len(cases))+' base='+str(base)+' head='+head+' width-mutants=3',flush=True)
