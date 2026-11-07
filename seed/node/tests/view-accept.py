#!/usr/bin/env python3
"""DRA-291 acceptance: the operator view and commands of omnode-code, driven
only through omnode-op (seed/node/op.om) against the real workflow.

Usage: view-accept.py BUILD OMC ROUND40 OUTDIR [SCENARIO...]
BUILD holds code-main, code-test, infer, tool, op and fake-serve (all built
from .om). OMC is the compiler round40 used (its error text is part of the
prompts). ROUND40 holds repair.py and final-selected.json. The model is
replaced by fake-serve, which answers the real omnode-infer with the
recorded round40 turns (view-prep.py writes its map), so every run is
deterministic and takes seconds. Prints one PASS/FAIL line per check and
"VIEWSUM pass=P fail=F"; exits 0 when nothing failed.
"""
import json, os, signal, socket, struct, subprocess, sys, time

# the node takes absolute paths only
BUILD, OMC, R, OUT = (os.path.abspath(a) for a in sys.argv[1:5])
HERE = os.path.dirname(os.path.abspath(__file__))
os.makedirs(OUT, exist_ok=True)
NP = [0, 0]
PROCS = []


def res(ok, name, detail=''):
    NP[0 if ok else 1] += 1
    print(f"{'PASS' if ok else 'FAIL'} {name} {detail}"[:400], flush=True)
    return ok


def free_port():
    s = socket.socket()
    s.bind(('127.0.0.1', 0))
    p = s.getsockname()[1]
    s.close()
    assert p != 18091
    return p


def prep(name, ids, wrong=False):
    base = os.path.join(OUT, name)
    a = [sys.executable, os.path.join(HERE, 'view-prep.py'), R, base, ','.join(ids)]
    if wrong:
        a.append('wrong')
    subprocess.run(a, check=True, capture_output=True)
    objs = open(base + '/objs.txt').read().splitlines()
    return base, objs, json.load(open(base + '/expect.json'))


def fake(base, delay):
    port = free_port()
    log = open(base + '/fake.log', 'a')
    p = subprocess.Popen([BUILD + '/fake-serve', str(port), base + '/map', str(delay)], stdout=log, stderr=log)
    PROCS.append(p)
    wait_for(lambda: 'PORT' in open(base + '/fake.log').read(), 5)
    return p, port


def node(base, objs, fport, mode=(), prog='code-main', tag='run'):
    vport = free_port()
    out = open(f'{base}/{tag}.out', 'w')
    err = open(f'{base}/{tag}.err', 'w')
    a = [BUILD + '/' + prog, *mode, BUILD + '/infer', BUILD + '/tool', OMC, base + '/root', base + '/work',
         base + '/journal', str(fport), str(vport), *objs]
    p = subprocess.Popen(a, stdout=out, stderr=err)
    PROCS.append(p)
    ok = wait_for(lambda: f'CWV {vport}\n' in open(f'{base}/{tag}.out').read() or p.poll() is not None, 10)
    return p, vport, ok and p.poll() is None


def wait_for(f, t, step=0.02):
    end = time.time() + t
    while time.time() < end:
        if f():
            return True
        time.sleep(step)
    return f()


def op(port, *a):
    p = subprocess.run([BUILD + '/op', str(port), *map(str, a)], capture_output=True, timeout=30)
    try:
        j = json.loads(p.stdout)
    except ValueError:
        j = None
    return p.returncode, j


def view(port, since=None, inc=None):
    if since is None:
        return op(port, 'view')
    return op(port, 'view', since, inc)


def finish(p, t=60):
    try:
        return p.wait(t)
    except subprocess.TimeoutExpired:
        p.kill()
        return p.wait()


def lines(base, tag='run'):
    return open(f'{base}/{tag}.out').read().splitlines()


def cmd(port, cid, opn, tgt, snap, *args):
    return op(port, 'cmd', cid, opn, tgt, snap['incarnation'], snap['version'], *args)

def fresh(port, cid, opn, tgt, *args):
    """Post from a fresh view, again while the target moves on in between
    (a stale command is not recorded, so the same id may be posted again)."""
    for k in range(20):
        rc, s = view(port)
        rc, a = cmd(port, cid, opn, tgt, s, *args)
        if not (a and a['status'] == 'stale'):
            return rc, a
    return rc, a


KINDS = {'add': 1, 'mul': 2, 'loop': 3}


def journal_started(base, jid):
    """True when job jid has a START whose operation has no settled DONE in
    BASE/journal/journal: none, or only DONE with outcome 0 (UNKNOWN, as
    the creator records a started job whose worker was lost). Records are 16
    little-endian words after a 64-byte header; word 0 type, 3..6 the
    operation, 7 a DONE's outcome, 8 the job id of a START."""
    b = open(base + '/journal/journal', 'rb').read()
    recs = [struct.unpack('<16Q', b[64 + i * 128:192 + i * 128]) for i in range((len(b) - 64) // 128)]
    ops = {r[3:7] for r in recs if r[0] == 3 and r[8] == jid}
    settled = {r[3:7] for r in recs if r[0] == 4 and r[7] != 0}
    return bool(ops - settled)


# ---- 1. full workflow, followed through snapshot + deltas, with a disconnect
def t_full():
    base, objs, ex = prep('full', ['76666', '83423', '82342', '85188'])
    fs, fp = fake(base, 150)
    p, vp, ok = node(base, objs, fp)
    res(ok, 'full-view-up', f'port={vp}')
    rc, s = view(vp)
    res(rc == 0 and s and s['kind'] == 'snapshot' and s['layout'] == 1 and len(s['objectives']) == 4,
        'full-snapshot', f"rc={rc} v={s and s['version']} objs={s and len(s['objectives'])}")
    # follow every event from the start of the incarnation (the ring holds it)
    inc, ver, evs, gaps, kinds = s['incarnation'], 0, [], 0, set()
    gone = 0
    t0 = time.time()
    while p.poll() is None:
        if 1.0 < time.time() - t0 < 2.5:
            gone += 1          # disconnected: no polling for 1.5 s
            time.sleep(0.05)
            continue
        rc, d = view(vp, ver, inc)
        if rc != 0 or d is None:
            break
        kinds.add(d['kind'])
        if d['kind'] == 'delta':
            for e in d['events']:
                if e[0] != ver + 1:
                    gaps += 1
                ver = e[0]
                evs.append(e)
        else:
            ver = d['version']
        time.sleep(0.03)
    rc = finish(p)
    fs.kill()
    out = lines(base)
    cwe = [list(map(int, l.split()[1:5])) for l in out if l.startswith('CWE ')]
    mine = [[e[2], e[4], e[3], e[5]] for e in evs if e[1] == 1]
    res(rc == 0 and 'CWSUM pass=4 fail=0' in out, 'full-run', f'rc={rc} {out[-1]}')
    res(gone > 0 and kinds == {'delta'} and gaps == 0 and len(mine) > 20 and cwe[:len(mine)] == mine,
        'full-delta-stream', f'gone={gone} kinds={sorted(kinds)} gaps={gaps} job-events={len(mine)}/{len(cwe)}')
    res(subprocess.run(['ss', '-ltn', f'sport = :{vp}'], capture_output=True, text=True).stdout.count('LISTEN') == 0,
        'full-view-stopped', f'port={vp}')


# ---- 2. resync: wrong incarnation and impossible since give a snapshot
def t_resync():
    base, objs, ex = prep('resync', ['76666'])
    fs, fp = fake(base, 400)
    p, vp, ok = node(base, objs, fp)
    # a delta from 0 must hold events: at version 0 an off-by-one in the event loop is invisible
    wait_for(lambda: (view(vp)[1] or {}).get('version', 0) >= 2, 10)
    rc, s = view(vp)
    rc1, d1 = view(vp, 0, s['incarnation'])
    rc2, d2 = view(vp, 0, s['incarnation'] + 7)
    rc3, d3 = view(vp, s['version'] + 1000, s['incarnation'])
    res(rc1 == 0 and d1['kind'] == 'delta' and d1['version'] >= 2 and [e[0] for e in d1['events']] == list(range(1, d1['version'] + 1)),
        'resync-delta-from-0', f"v={d1 and d1['version']} n={d1 and len(d1.get('events', []))}")
    res(rc2 == 0 and d2['kind'] == 'snapshot', 'resync-other-incarnation', f"kind={d2 and d2['kind']}")
    res(rc3 == 0 and d3['kind'] == 'snapshot', 'resync-future-since', f"kind={d3 and d3['kind']}")
    rc, h = op(vp, 'view', 'x', 1)
    res(rc == 2, 'op-usage-control', f'rc={rc}')
    finish(p)
    fs.kill()


# ---- 3. commands: stale, invalid, committed, duplicate, pause/resume
def t_commands():
    base, objs, ex = prep('cmds', ['76666'])
    fs, fp = fake(base, 1200)
    p, vp, ok = node(base, objs, fp)
    rc, s0 = view(vp)
    wait_for(lambda: view(vp)[1]['objectives'][0]['version'] > s0['version'], 10)
    rc, a = cmd(vp, 11, 4, 0, s0, 6)
    res(rc == 1 and a['status'] == 'stale', 'cmd-stale-409', f'rc={rc} {a}')
    rc, a = fresh(vp, 12, 4, 0, 9)
    res(rc == 1 and a['status'] == 'invalid', 'cmd-invalid-budget', f'rc={rc} {a}')
    rc, s1 = view(vp)
    # version 0 and op 9: only the view's incarnation check answers stale; were the command
    # passed on, the creator would answer invalid (op out of range) whatever the version is now
    rc, a = op(vp, 'cmd', 13, 9, 0, s1['incarnation'] + 1, 0, 6)
    res(rc == 1 and a['status'] == 'stale', 'cmd-other-incarnation', f'rc={rc} {a}')
    cid = 14
    rc, a = fresh(vp, cid, 4, 0, 6)
    res(rc == 0 and a['status'] == 'committed', 'cmd-budget-committed', f'id={cid} {a}')
    rc, s2 = view(vp)
    res(s2['objectives'][0]['budget'] == 6 and s2['commands']['last_id'] == cid,
        'cmd-budget-visible', f"budget={s2['objectives'][0]['budget']} last={s2['commands']['last_id']}")
    rc, a2 = cmd(vp, cid, 4, 0, s2, 6)
    res(rc == 0 and a2['status'] == 'duplicate' and a2['version'] == a['version'] and
        view(vp)[1]['commands']['committed'] == 1, 'cmd-duplicate-ack', f'{a2}')
    # pause: committed through the authority; no new grants while paused
    rc, sp = view(vp)
    rc, a = cmd(vp, 40, 1, 0, sp)
    res(rc == 0 and a['status'] == 'committed', 'cmd-pause', f'{a}')
    # a pause emits a second event before its ack, so an ack carrying the version current
    # after acting (not the one its OPER record holds) differs from the duplicate's
    rc, ad = cmd(vp, 40, 1, 0, sp)
    res(rc == 0 and ad['status'] == 'duplicate' and ad['version'] == a['version'],
        'cmd-pause-duplicate-version', f"{ad} original={a['version']}")
    rc, s3 = view(vp)
    rc, a = cmd(vp, 41, 1, 0, s3)
    res(rc == 1 and a['status'] == 'invalid', 'cmd-pause-again-invalid', f'{a}')
    time.sleep(4)
    rc, s4 = view(vp)
    if s4 is None:
        res(False, 'cmd-paused-holds', f'view gone rc={rc}')
    else:
        q = s4['queue']
        res(s4['authority']['paused'] == 1 and q['running'] == 0 and q['waiting'] + q['ready'] >= 1 and
            all(w['paused'] == 1 for w in s4['workers']),
            'cmd-paused-holds', f"auth={s4['authority']} queue={q}")
        rc, a = cmd(vp, 42, 2, 0, s4)
        res(rc == 0 and a['status'] == 'committed', 'cmd-resume', f'{a}')
    rc = finish(p, 120)
    fs.kill()
    out = lines(base)
    res(rc == 0 and 'CWSUM pass=1 fail=0' in out, 'cmd-run-completes', f'rc={rc} {out[-1]}')


# ---- 4. cancel an objective whose inference is in flight
def t_cancel():
    base, objs, ex = prep('cancel', ['76666', '83423'])
    fs, fp = fake(base, 4000)
    p, vp, ok = node(base, objs, fp)
    wait_for(lambda: view(vp)[1]['objectives'][0]['phase'] == 1, 10)
    rc, a = fresh(vp, 60, 3, 0)
    t = time.time()
    res(rc == 0 and a['status'] == 'committed', 'cancel-committed', f'{a}')
    wait_for(lambda: any(l.startswith('CWO 0 ') for l in lines(base)), 10)
    dt = time.time() - t
    rc = finish(p, 120)
    fs.kill()
    out = lines(base)
    res('CWO 0 FAIL 19 1' in out and dt < 3.5, 'cancel-objective-19', f"{[l for l in out if l.startswith('CWO')]} after {dt:.1f}s")
    res(rc == 1 and 'CWSUM pass=1 fail=1' in out, 'cancel-other-objective-passes', f'rc={rc} {out[-1]}')


# ---- 5. redirect a wrong goal while its inference is in flight
def t_redirect():
    base, objs, ex = prep('redirect', ['76666'], wrong=True)
    fs, fp = fake(base, 2000)
    p, vp, ok = node(base, objs, fp)
    wait_for(lambda: view(vp)[1]['objectives'][0]['phase'] == 1, 10)
    kn, K, N, A = ex['recs'][0]['obj'].split(',')
    k_, K, N, A = KINDS[kn], int(K), int(N), int(A)
    rc, a = fresh(vp, 80, 5, 0, k_, K, N, A)
    res(rc == 0 and a['status'] == 'committed', 'redirect-committed', f'{a}')
    rc, s = view(vp)
    o = s['objectives'][0]
    res((o['a'], o['k'], o['n']) == (A, K, N), 'redirect-visible', f'{o}')
    rc, a = fresh(vp, 99, 5, 0, 4, K, N, A)
    res(rc == 1 and a['status'] == 'invalid', 'redirect-invalid-kind', f'{a}')
    rc = finish(p, 120)
    fs.kill()
    out = lines(base)
    res(rc == 0 and 'CWSUM pass=1 fail=0' in out, 'redirect-run-passes', f'rc={rc} {out[-1]}')
    fl = open(base + '/fake.log').read().split('\n')
    res(any(l.startswith('F 404') for l in fl), 'redirect-wrong-goal-unanswered', f'{fl[1:3]}')


# ---- 6. budget: fewer turns than the objective needs
def t_budget():
    base, objs, ex = prep('budget', ['76666'])
    fs, fp = fake(base, 700)
    p, vp, ok = node(base, objs, fp)
    rc, a = fresh(vp, 120, 4, 0, 2)
    res(rc == 0 and a['status'] == 'committed', 'budget-committed', f'{a}')
    rc = finish(p, 120)
    fs.kill()
    out = lines(base)
    res('CWO 0 FAIL 12 2' in out and rc == 1, 'budget-ends-12', f"{[l for l in out if l.startswith('CWO')]}")


# ---- 7. overloaded queue: admission limit 1, refusals visible, commands still commit
# A tool job the authority refuses ends its objective with 23, so the run
# completing 3/3 also shows every refusal here was an inference (issued
# into the slot a tool job's own predecessor left); code-test unit covers a
# refused tool job.
def t_overload():
    base, objs, ex = prep('overload', ['76666', '83423', '82342'])
    fs, fp = fake(base, 300)
    p, vp, ok = node(base, objs, fp, mode=('overload', '1'), prog='code-test')
    res(ok, 'overload-view-up', f'port={vp}')
    seen, comm = 0, None
    while p.poll() is None:
        rc, s = view(vp)
        if rc != 0:
            break
        seen = max(seen, s['queue']['refused'])
        if seen > 0 and comm is None:
            rc, a = cmd(vp, 140, 4, 2, s, 7)
            if a and a['status'] != 'stale':
                comm = a
        time.sleep(0.05)
    rc = finish(p, 120)
    fs.kill()
    out = lines(base)
    res(seen > 0 and s['queue']['limit'] == 1, 'overload-refusals-visible', f"refused={seen} limit={s['queue']['limit']}")
    res(comm is not None and comm['status'] == 'committed', 'overload-command-commits', f'{comm}')
    res(rc == 0 and 'CWSUM pass=3 fail=0' in out, 'overload-run-completes', f'rc={rc} {out[-1]}')


# ---- 8. uncertain effect: the worker running a replace is killed
def t_uncertain():
    # objectives with as many turns as the one that loses its replace keep
    # the node (and its view) running after the kill
    base, objs, ex = prep('uncertain', ['76666', '82342', '85188'])
    fs, fp = fake(base, 300)
    p, vp, ok = node(base, objs, fp, mode=('uncertain',), prog='code-test')
    last, ver, inc, ev7 = None, 0, None, []
    while p.poll() is None:
        rc, s = view(vp)
        if rc != 0:
            break
        inc = s['incarnation']
        if s['uncertain']:
            last = s
        rc, d = view(vp, ver, inc)
        if rc != 0:
            break
        if d['kind'] == 'delta':
            ev7 += [e for e in d['events'] if e[1] == 7]
            ver = d['version']
        time.sleep(0.02)
    rc2 = finish(p, 60)
    fs.kill()
    out = lines(base)
    u = last and last['uncertain']
    res(u and len(u) == 1 and u[0] % 10 == 4, 'uncertain-listed', f'uncertain={u}')
    i = u[0] // 1000 - 1 if u else -1
    res(len(ev7) == 1 and ev7[0][4] == u[0] and ev7[0][2] == i, 'uncertain-event', f'{ev7}')
    res(any(l.startswith(f'CWO {i} FAIL 21') for l in out), 'uncertain-objective-21',
        f"{[l for l in out if l.startswith('CWO')]}")
    # The next incarnation's recovery settles it from the journal: a START
    # without a DONE stays UNKNOWN for good; no START proves it never ran.
    st = journal_started(base, u[0]) if u else None
    fs, fp = fake(base, 100)
    p, vp, ok = node(base, objs, fp, tag='run2')
    rc, s = view(vp)
    want = u if st else []
    res(rc == 0 and s['incarnation'] == last['incarnation'] + 1 and s['uncertain'] == want,
        'uncertain-after-restart', f"started={st} inc={s and s['incarnation']} uncertain={s and s['uncertain']}")
    finish(p, 60)
    fs.kill()


# ---- 9. creator killed: OPER replayed, duplicate acknowledged, old clients resync
def t_crash():
    base, objs, ex = prep('crash', ['76666', '83423'])
    fs, fp = fake(base, 1500)
    p, vp, ok = node(base, objs, fp)
    ids = {}
    for cid, opn, tgt, args in ((200, 3, 1, ()), (201, 4, 0, (6,))):
        rc, a = fresh(vp, cid, opn, tgt, *args)
        ids[cid] = a
    res(all(a['status'] == 'committed' for a in ids.values()), 'crash-commands-committed', f'{ids}')
    rc, old = view(vp)
    p.send_signal(signal.SIGKILL)
    p.wait()
    gone = wait_for(lambda: subprocess.run(['ss', '-ltn', f'sport = :{vp}'], capture_output=True,
                                           text=True).stdout.count('LISTEN') == 0, 3)
    res(gone, 'crash-view-exits-with-creator', f'port={vp}')
    p, vp2, ok = node(base, objs, fp, tag='run2')
    rc, s = view(vp2)
    o = s['objectives']
    res(s['incarnation'] == old['incarnation'] + 1 and s['commands']['committed'] == 2 and
        o[1]['result'] == 19 and o[0]['budget'] == 6, 'crash-oper-replayed',
        f"inc={s['incarnation']} cmds={s['commands']} r1={o[1]['result']} b0={o[0]['budget']}")
    rc, d = view(vp2, old['version'], old['incarnation'])
    res(rc == 0 and d['kind'] == 'snapshot', 'crash-old-client-resyncs', f"kind={d['kind']}")
    cid, a0 = sorted(ids.items())[0]
    rc, a = op(vp2, 'cmd', cid, 3, 1, s['incarnation'], s['version'])
    res(rc == 0 and a['status'] == 'duplicate' and a['version'] == a0['version'], 'crash-duplicate-after-restart', f'{a}')
    rc, a = cmd(vp2, cid + 1000, 3, 1, s)
    res(rc == 1 and a['status'] == 'invalid', 'crash-cancel-finished-invalid', f'{a}')
    rc = finish(p, 120)
    fs.kill()
    out = lines(base, 'run2')
    res(rc == 1 and 'CWO 1 FAIL 19 0' in out and any(l.startswith('CWO 0 PASS') for l in out),
        'crash-run2-results', f"rc={rc} {[l for l in out if l.startswith('CWO')]}")


ONLY = sys.argv[5:]
for t in (t_full, t_resync, t_commands, t_cancel, t_redirect, t_budget, t_overload, t_uncertain, t_crash):
    if ONLY and t.__name__[2:] not in ONLY:
        continue
    try:
        t()
    except Exception as e:  # a crashed check is a failed check
        res(False, t.__name__, f'{type(e).__name__}: {e}')
    for q in PROCS:
        if q.poll() is None:
            q.kill()
            q.wait()
    PROCS.clear()
print(f'VIEWSUM pass={NP[0]} fail={NP[1]}', flush=True)
sys.exit(1 if NP[1] else 0)
