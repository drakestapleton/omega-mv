#!/usr/bin/env python3
"""Replay the 108 recorded round40 runs through omnode-tool (DRA-290).

For every recorded action the tool is run on a real file tree and the next
recorded prompt is rebuilt from the tool's observation and returned content;
it must equal the recorded prompt byte for byte.
Usage: tool-replay.py TOOL OMC ROUND40 OUTDIR, where ROUND40 holds repair.py
and final-selected.json of the round40 tool-model run (prompt and text are
taken from repair.py; the tool itself is the system under test). OMC must be
the compiler round40 used (sha256 2c82480596bb...), since compiler error
text is part of the prompt."""
import json, os, shutil, subprocess, sys

TOOL, OMC, R, OUT = sys.argv[1:5]
sys.path.insert(0, R)
import repair
prompt = repair.prompt; text = repair.text


def tool(*a):
    p = subprocess.run([TOOL, *a], capture_output=True, timeout=120)
    if p.returncode != 0:
        return None, f'exit {p.returncode}', b''
    out = p.stdout
    nl = out.index(b'\n')
    h = out[:nl].split()
    assert h[0] == b'OMNT1', out[:80]
    st, ol, cl = int(h[1]), int(h[2]), int(h[3])
    body = out[nl + 1:]
    assert len(body) == ol + cl, (len(body), ol, cl)
    return st, body[:ol].decode(), body[ol:].decode()


kinds = {'add': 1, 'mul': 2, 'loop': 3}
runs = json.load(open(R + '/final-selected.json'))
npass = nfail = nact = 0
for r in runs:
    j = r['job']
    root = os.path.join(OUT, j['id'])
    work = os.path.join(root, '.work')
    shutil.rmtree(root, ignore_errors=True)
    os.makedirs(os.path.join(root, os.path.dirname(j['path'])))
    os.makedirs(work)
    if j['fault'] != 'missing':
        open(os.path.join(root, j['path']), 'w').write(j['broken'])
    turns = r['turns']
    ok = True
    for i, t in enumerate(turns[:-1]):
        d = json.loads(text(t['raw']))
        if d['tool'] == 'read_file':
            st, ob, c = tool('read', root, d['path'])
        elif d['tool'] == 'omega_check':
            st, ob, c = tool('check', root, d['path'], work, OMC, str(kinds[j['kind']]), str(j['k']), str(j.get('n', 0)), str(j['a']))
        else:
            st, ob, c = tool('replace', root, d['path'], d['old'], d['new'])
        nact += 1
        nxt = turns[i + 1]
        if st == 1:
            c = ''
        got = prompt(j, nxt['state'], c, ob)
        if got != nxt['prompt']:
            ok = False
            print('MISMATCH', j['id'], j['fault'], d['tool'], 'status', st, repr(ob)[:200])
            print('  want', repr(nxt['prompt'][-200:]))
            break
    if ok:
        npass += 1
    else:
        nfail += 1
print(f'TOOL-REPLAY runs={len(runs)} pass={npass} fail={nfail} actions={nact}')
sys.exit(0 if nfail == 0 else 1)
