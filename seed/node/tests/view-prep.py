"""Fixture for the DRA-291 view tests: objectives from the recorded round40
episodes and the map of recorded model turns that fake-serve.om answers from.

python3 view-prep.py ROUND40 BASE ID[,ID...] [WRONG]

ROUND40 holds final-selected.json and repair.py. BASE gets root/ (the broken
files), work/, objs.txt (one objective argument per line), expect.json and
map (fake-serve's format: "<klen> <vlen>\\n" key value). A key is the prompt as
a JSON string, which is how omnode-infer writes it into its request body; the
value is the completion response carrying the recorded raw model output.
With WRONG, the first objective's goal is changed to K+N+A+1 (a goal the map
has no turns for), which a redirect then corrects.
"""
import json, os, shutil, sys

R, base, want = sys.argv[1], sys.argv[2], sys.argv[3].split(',')
wrong = len(sys.argv) > 4
sys.path.insert(0, R)
import repair  # noqa: E402

d = json.load(open(R + '/final-selected.json'))
shutil.rmtree(base, ignore_errors=True)
os.makedirs(base + '/root/jobs')
os.makedirs(base + '/work')
objs, recs, mp = [], [], []
for w in want:
    r = [x for x in d if w in x['job']['path']][0]
    j = r['job']
    if j['fault'] != 'missing':
        open(base + '/root/' + j['path'], 'w').write(j['broken'])
    a = j['a']
    if wrong and not objs:
        a = j['k'] + j.get('n', 0) + j['a'] + 1
    objs.append(f"{j['kind']},{j['k']},{j.get('n', 0)},{a},{j['path']},{repair.STYLES[j['style']]}")
    recs.append(dict(path=j['path'], obj=f"{j['kind']},{j['k']},{j.get('n', 0)},{j['a']}",
                     turns=[dict(state=t['state'], prompt=t['prompt'], raw=t['raw']) for t in r['turns']],
                     pass_=r['pass'], state=r['state']))
    for t in r['turns']:
        k = json.dumps(t['prompt']).encode()
        v = json.dumps({"object": "text_completion",
                        "choices": [{"index": 0, "text": t['raw'], "finish_reason": "stop"}],
                        "usage": {"prompt_tokens": 1, "completion_tokens": 1}}).encode()
        mp.append(b'%d %d\n' % (len(k), len(v)) + k + v)
json.dump(dict(objs=objs, recs=recs), open(base + '/expect.json', 'w'), indent=1)
open(base + '/objs.txt', 'w').write('\n'.join(objs) + '\n')
open(base + '/map', 'wb').write(b''.join(mp))
print('\n'.join(objs))
