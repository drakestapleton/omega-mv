#!/usr/bin/env python3
"""Independent JSON oracle for the bounded Omega Radicle adapter, not a runtime."""
import copy,json,pathlib,subprocess,tempfile,sys
exe=pathlib.Path(sys.argv[1]).resolve()
patch=json.load(open(sys.argv[2]))
rev=patch['revisions'][-1]
ctx=dict(status='active',rid='rad:z6do9WDBhuSnvopDkgFdFr1yWA62',patch=patch['id'],revision=rev['id'],candidate=rev['oid'],base=rev['base'],toolchain='cfd96b48b0460ab5557853d6856f9c741b96ac8d0d624e06198defb4cbfa0d8a',task='public-catalog-pilot',attempt='attempt-1',generation='1',policy='a'*64)
event=dict(request='trigger',version=1,event_type='patch',repository=dict(id=ctx['rid']),action='Created',patch=dict(id=ctx['patch'],state=dict(status='open'),after=ctx['candidate'],commits=[ctx['candidate']],revisions=[dict(id=ctx['revision'],oid=ctx['candidate'],base=ctx['base'])]))
count=0
with tempfile.TemporaryDirectory(prefix='radci-test-') as tmp:
    cp=pathlib.Path(tmp)/'context.json'
    def run(e=event,c=ctx,host=None,raw=None):
        cp.write_text(json.dumps(c))
        p=subprocess.run([str(exe),str(cp)]+([host] if host else []),input=(raw if raw is not None else json.dumps(e)+'\n').encode(),capture_output=True,timeout=10)
        return p
    def check(label,p,code=0):
        global count
        assert p.returncode==code,(label,p.returncode,p.stderr)
        if code: assert not p.stdout,(label,p.stdout)
        count+=1;print('PASS',label)
    p=run();check('normalized-public-patch',p);out=p.stdout
    expected={k:v for k,v in ctx.items() if k!='status'};expected['schema']='radicle-queen-ticket-v1'
    assert json.loads(out)==expected
    for label in ['duplicate','fresh-process-restart','repeated-scan']:
        p=run();check(label,p);assert p.stdout==out
    p=run(host='/usr/bin/cat');check('host-exec-stdin-ticket',p);assert p.stdout==out
    check('host-failure-not-success',run(host='/bin/false'),1)
    check('missing-host-refused',run(host='/nonexistent/radci'),27)
    for k in ['rid','patch','revision','candidate','base']:
        c=copy.deepcopy(ctx);c[k]='0'*40 if k!='rid' else 'rad:zWrong'
        check('binding-'+k,run(c=c),23)
    for k in ['toolchain','policy','candidate','base','patch','revision']:
        c=copy.deepcopy(ctx);c[k]='z'*len(c[k]);check('malformed-'+k,run(c=c),22)
    for k in ['attempt','task','generation']:
        c=copy.deepcopy(ctx);c[k]='x\nunsafe';check('unsafe-'+k,run(c=c),22)
    for val in ['0','01','-1','abc','9007199254740992','99999999999999999']:
        c=copy.deepcopy(ctx);c['generation']=val;check('generation-'+val,run(c=c),22)
    c=copy.deepcopy(ctx);c['status']='cancelled';check('cancelled-context',run(c=c),24)
    for state in ['closed','merged','archived']:
        e=copy.deepcopy(event);e['patch']['state']['status']=state;check('patch-'+state,run(e=e),24)
    e=copy.deepcopy(event);e['patch']['revisions']*=2;check('duplicate-revision',run(e=e),23)
    e=copy.deepcopy(event);e['patch']['revisions'][0]['oid']='1'*40;check('revision-head-mismatch',run(e=e),23)
    e=copy.deepcopy(event);e['patch']['revisions'][0]['base']='1'*40;check('revision-base-mismatch',run(e=e),23)
    e=copy.deepcopy(event);e['patch']['commits'][0]='1'*40;check('commit-head-mismatch',run(e=e),23)
    e=copy.deepcopy(event);e['version']=2;check('version-refused',run(e=e),24)
    e=copy.deepcopy(event);e['event_type']='push';check('unsupported-push',run(e=e),24)
    raw=json.dumps(event).replace('"request": "trigger"','"request": "trigger", "request": "trigger"')
    check('duplicate-authority-key',run(raw=raw),21)
    check('truncated-disconnect',run(raw=json.dumps(event)[:100]),21)
    check('oversize-request',run(raw=' '*65536),20)
    print('PASS checks='+str(count))
