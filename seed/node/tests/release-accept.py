#!/usr/bin/env python3
"""DRA-292 release acceptance of the Omega Node coding workflow.

Usage: release-accept.py MODE BUILD OLDBIN OMC ROUND40 OUT [SCENARIO...]

MODE fake: the model is fake-serve answering the recorded round40 turns (any
host, seconds). MODE live: the own model through `ollm VERB` on 127.0.0.1:PORT,
started once by release.sh serve; run the whole driver inside a private
network namespace (bwrap --unshare-net), and with VERB gserve only inside an
authorized GB10 window. Environment for live: OLLM, VERB (serve|gserve), CK,
MERGES, PORT (default 18294, never 18091).
BUILD holds the programs release.sh build makes; OLDBIN the DRA-290 build
(code-main without the operator view) for the journal compatibility checks;
OMC the compiler whose messages round40's prompts carry; ROUND40 repair.py and
final-selected.json. Prints one PASS/FAIL/NOT_RUN line per check, MEASURED lines,
and "RELSUM pass=P fail=F not_run=N mode=..."; exits 0 when nothing failed.
"""
import collections, hashlib, json, os, shutil, signal, socket, struct, subprocess, sys, threading, time

MODE = sys.argv[1]
BUILD, OLDBIN, OMC, R, OUT = (os.path.abspath(a) for a in sys.argv[2:7])
ONLY = sys.argv[7:]
HERE = os.path.dirname(os.path.abspath(__file__))
RELEASE = os.path.join(os.path.dirname(HERE), 'release.sh')
LIVE = MODE == 'live'
PORT = int(os.environ.get('PORT', '18294'))
assert MODE in ('fake', 'live') and PORT != 18091
os.makedirs(OUT, exist_ok=True)
NP = [0, 0, 0]
PROCS = []


def res(ok, name, detail=''):
    NP[0 if ok else 1] += 1
    print(f"{'PASS' if ok else 'FAIL'} {name} {detail}"[:600], flush=True)
    return ok


def notrun(name, detail):
    NP[2] += 1
    print(f'NOT_RUN {name} {detail}'[:900], flush=True)
    return None


def measured(name, detail):
    print(f'MEASURED {name} {detail}'[:600], flush=True)


def free_port():
    while True:
        s = socket.socket()
        s.bind(('127.0.0.1', 0))
        p = s.getsockname()[1]
        s.close()
        if p not in (18091, PORT):
            return p


def wait_for(f, t, step=0.02):
    end = time.time() + t
    while time.time() < end:
        if f():
            return True
        time.sleep(step)
    return f()


def sh(*a, timeout=1200):
    p = subprocess.run(['sh', RELEASE, *map(str, a)], capture_output=True, text=True, timeout=timeout)
    return p.returncode, p.stdout + p.stderr


def op(port, *a):
    p = subprocess.run([BUILD + '/op', str(port), *map(str, a)], capture_output=True, timeout=30)
    try:
        j = json.loads(p.stdout)
    except ValueError:
        j = None
    return p.returncode, j


def view(port, since=None, inc=None):
    return op(port, 'view') if since is None else op(port, 'view', since, inc)


def fresh(port, cid, opn, tgt, *args):
    """Post from a fresh view, again while the target moves on in between."""
    for _ in range(50):
        rc, s = view(port)
        if s is None:
            return rc, None
        rc, a = op(port, 'cmd', cid, opn, tgt, s['incarnation'], s['version'], *args)
        if not (a and a['status'] == 'stale'):
            return rc, a
    return rc, a


# ---- fixtures and the model
def prep(name, ids):
    base = os.path.join(OUT, name)
    subprocess.run([sys.executable, os.path.join(HERE, 'view-prep.py'), R, base, ','.join(ids)],
                   check=True, capture_output=True)
    return base, open(base + '/objs.txt').read().splitlines(), json.load(open(base + '/expect.json'))


def frames(path):
    """(kind, objective, bytes) of every CWP/CWR frame in a node's stdout."""
    raw, ev, p = open(path, 'rb').read(), [], 0
    while p < len(raw):
        e = raw.index(b'\n', p)
        w = raw[p:e].decode(errors='replace').split(' ')
        p = e + 1
        if w[0] in ('CWP', 'CWR'):
            n = int(w[3])
            ev.append((w[0], int(w[1]), raw[p:p + n].decode(errors='replace')))
            p += n + 1
    return ev


def finished(name, lines, outs, ex, detail=''):
    """Every objective of a resumed run passed. In fake mode an objective that resumed into a prompt
    the recording never held (after its edit it reads the edited file) can only end 16: that check
    is NOT_RUN there, naming the prompt; the live own model answers it."""
    if lines and all(l.split()[2] == 'PASS' for l in lines):
        return res(True, name, f'{lines} {detail}')
    rec = {t['prompt'] for r in ex['recs'] for t in r['turns']}
    miss = []
    for l in lines:
        if l.split()[2] == 'PASS':
            continue
        i = int(l.split()[1])
        last = [b for o in outs for k, j, b in frames(o) if k == 'CWP' and j == i][-1:]
        if LIVE or l.split()[3] != '16' or not last or last[0] in rec:
            return res(False, name, f'{lines} {detail}')
        st = last[0].split('\nState: ')[1].split('\n')[0]
        miss.append(f'obj{i} state={st} sha256={hashlib.sha256(last[0].encode()).hexdigest()[:16]}')
    return notrun(name, f'fake-serve holds no recorded answer for {miss}; live mode answers it. {lines} {detail}')


class Model:
    """The live server (one per session) or a fake-serve per scenario; serve.log lines `C status
    prompt completion finish ms` (live) mark each answered request."""
    live = None

    def __init__(self, base, delay=300, name='model'):
        self.base, self.name = base, name
        if LIVE:
            self.port, self.log, self.mark = PORT, Model.live, os.path.getsize(Model.live)
            self.p = None
        else:
            self.port, self.log = free_port(), f'{base}/fake-{name}.log'
            self.mark = 0
            self.p = subprocess.Popen([BUILD + '/fake-serve', str(self.port), base + '/map', str(delay)],
                                      stdout=open(self.log, 'a'), stderr=subprocess.STDOUT)
            PROCS.append(self.p)
            wait_for(lambda: 'PORT' in open(self.log).read(), 5)

    def lines(self):
        """fake-serve logs no request lines: in fake mode this is always empty."""
        with open(self.log, 'rb') as f:
            f.seek(self.mark)
            return [l for l in f.read().decode(errors='replace').splitlines() if l.startswith('C ')]

    def close(self):
        open(f'{self.base}/{self.name}.log', 'w').write('\n'.join(self.lines()) + '\n')
        if self.p:
            self.p.kill()
            self.p.wait()


# ---- the node and its event lines
class Node:
    """omnode-code (or code-test MODE...) on BASE; follows stdout, timestamping each event line
    (CWP/CWR frames carry n bytes after their line)."""

    def __init__(self, base, objs, port, prog='code-main', mode=(), tag='run', bindir=None, view=True,
                 jdir=None, pre=()):
        b = bindir or BUILD
        self.base, self.tag = base, tag
        self.vport = free_port() if view else 0
        self.out = f'{base}/{tag}.out'
        a = [*pre, b + '/' + prog, *mode, b + '/infer', b + '/tool', OMC, base + '/root', base + '/work',
             jdir or base + '/journal', str(port)]
        if bindir is None:
            a.append(str(self.vport))
        a += objs
        self.t0 = time.time()
        self.p = subprocess.Popen(a, stdout=open(self.out, 'wb'), stderr=open(f'{base}/{tag}.err', 'wb'))
        PROCS.append(self.p)
        self.ev = []
        self.t = threading.Thread(target=self.follow, daemon=True)
        self.t.start()
        self.up = (not view or bindir is not None or
                   wait_for(lambda: any(e[1] == f'CWV {self.vport}' for e in self.ev) or self.p.poll() is not None, 15))

    def follow(self):
        buf, pos, skip = b'', 0, 0
        f = open(self.out, 'rb')
        while True:
            c = f.read()
            done = self.p.poll() is not None
            if c:
                buf += c
            while True:
                if skip:
                    if len(buf) - pos < skip:
                        break
                    pos += skip
                    skip = 0
                e = buf.find(b'\n', pos)
                if e < 0:
                    break
                line = buf[pos:e].decode(errors='replace')
                pos = e + 1
                self.ev.append((time.time(), line))
                w = line.split(' ')
                if w[0] in ('CWP', 'CWR') and len(w) >= 4 and w[3].isdigit():
                    skip = int(w[3]) + 1
            if done and not c:
                return
            time.sleep(0.01)

    def wait(self, t=3600):
        try:
            rc = self.p.wait(t)
        except subprocess.TimeoutExpired:
            self.p.kill()
            rc = self.p.wait()
        self.t.join(5)
        self.wall = time.time() - self.t0
        return rc

    def until(self, f, t):
        return wait_for(lambda: any(f(l) for _, l in self.ev) or self.p.poll() is not None, t, 0.01)

    def lines(self, k='CWO'):
        return [l for _, l in self.ev if l.startswith(k)]


def journal(base):
    b = open(base + '/journal/journal', 'rb').read()
    recs = [struct.unpack('<16Q', b[64 + i * 128:192 + i * 128]) for i in range((len(b) - 64) // 128)]
    starts = collections.Counter(r[3:7] for r in recs if r[0] == 3)
    done = {r[3:7]: (r[7], r[9]) for r in recs if r[0] == 4}
    dones = collections.defaultdict(list)
    for r in recs:
        if r[0] == 4:
            dones[r[3:7]].append((r[7], r[9]))
    return dict(recs=recs, opens=sum(r[0] == 1 for r in recs), starts=starts, done=done, dones=dones,
                max_starts=max(starts.values()) if starts else 0, oper=sum(r[0] == 9 for r in recs))


def compare(node, ex):
    """The prompts and raw model texts each objective saw against the recorded round40 turns."""
    raw = open(node.out, 'rb').read()
    ev, p = [], 0
    while p < len(raw):
        e = raw.index(b'\n', p)
        w = raw[p:e].decode(errors='replace').split(' ')
        p = e + 1
        if w[0] in ('CWP', 'CWR'):
            n = int(w[3])
            ev.append((w[0], int(w[1]), raw[p:p + n].decode(errors='replace')))
            p += n + 1
    bad = []
    for i, r in enumerate(ex['recs']):
        P = [b for k, j, b in ev if k == 'CWP' and j == i]
        W = [b for k, j, b in ev if k == 'CWR' and j == i]
        rec = r['turns']
        ok = len(P) == len(rec) and P == [t['prompt'] for t in rec] and W == [t['raw'] for t in rec]
        if not ok:
            k = next((k for k in range(min(len(W), len(rec))) if W[k] != rec[k]['raw']), None)
            bad.append(f"obj{i} turns={len(P)}/{len(rec)} first_raw_diff={k}")
    return bad


def inference(node, model):
    """MEASURED: the model's answered requests in this run and the node's time outside them (one
    inference at a time, so wall minus the sum of request times is the node's own time)."""
    cs = [l.split() for l in model.lines()]
    ok = [c for c in cs if c[1] == '200']
    ms = sum(int(c[5]) for c in ok)
    toks = sum(int(c[3]) for c in ok)
    return dict(requests=len(cs), answered=len(ok), model_ms=ms, completion_tokens=toks,
                ms_per_token=round(ms / toks, 1) if toks else None,
                wall_ms=int(node.wall * 1000), node_ms=int(node.wall * 1000) - ms)


def peak(pids):
    """VmHWM (kB) of each live pid."""
    m = {}
    for p in pids:
        try:
            for l in open(f'/proc/{p}/status'):
                if l.startswith('VmHWM:'):
                    m[p] = int(l.split()[1])
        except OSError:
            pass
    return m


def tree(pid):
    """pid and its descendants (by /proc/*/stat ppid)."""
    kids = collections.defaultdict(list)
    for d in os.listdir('/proc'):
        if d.isdigit():
            try:
                s = open(f'/proc/{d}/stat').read()
                kids[int(s[s.rindex(')') + 2:].split()[1])].append(int(d))
            except (OSError, ValueError):
                pass
    out, todo = [], [pid]
    while todo:
        x = todo.pop()
        out.append(x)
        todo += kids.get(x, [])
    return out


def exe(pid):
    try:
        return os.path.basename(os.readlink(f'/proc/{pid}/exe'))
    except OSError:
        return '?'


# ---- 1. one instruction set to a reviewed result: four objectives, the operator view followed
def t_full():
    base, objs, ex = prep('full', ['76666', '83423', '82342', '85188'])
    m = Model(base, 150)
    n = Node(base, objs, m.port)
    res(n.up, 'full-view-up', f'port={n.vport}')
    hw, ver, inc, gaps, kinds = collections.defaultdict(int), 0, None, 0, set()
    while n.p.poll() is None:
        for p, k in peak(tree(n.p.pid)).items():
            nm = exe(p)
            hw[nm] = max(hw[nm], k)
        rc, d = view(n.vport, ver, inc) if inc else view(n.vport)
        if rc == 0 and d:
            if d['kind'] == 'delta' and d['since'] != ver:
                gaps += 1
            inc, ver = d['incarnation'], d['version']
            kinds.add(d['kind'])
        time.sleep(0.05)
    rc = n.wait()
    m.close()
    o = n.lines('CWSUM')
    res(rc == 0 and o == ['CWSUM pass=4 fail=0'], 'full-4-objectives', f'rc={rc} {o} {n.lines()}')
    bad = compare(n, ex)
    res(not bad, 'full-turns-equal-recorded', f'{bad or "all prompts and model texts equal round40"}')
    j = journal(base)
    res(j['max_starts'] == 1 and j['opens'] == 1, 'full-journal-once',
        f"records={len(j['recs'])} opens={j['opens']} ops={len(j['starts'])} max_starts={j['max_starts']}")
    res(gaps == 0 and 'delta' in kinds, 'full-view-stream', f'gaps={gaps} kinds={sorted(kinds)} last_version={ver}')
    ev = [l.split() for l in n.lines('CWE')]
    reviewed = {int(w[1]) for w in ev if w[2].endswith('5') and w[3] == '4'}
    checked = {int(w[1]) for w in ev if w[2].endswith('3') and w[3] == '4'}
    res(checked and checked <= reviewed, 'full-independent-review',
        f'objectives checked={sorted(checked)} reviewed={sorted(reviewed)} (a "File not found." answer has no check)')
    measured('full-latency', json.dumps(inference(n, m)))
    measured('full-peak-rss-kB', json.dumps(dict(hw)))
    # the results are durable: a rerun on the finished journal reports them and runs nothing
    m2 = Model(base, 150, 'rerun')
    n2 = Node(base, objs, m2.port, tag='rerun')
    rc2 = n2.wait()
    m2.close()
    j2 = journal(base)
    new = [r[0] for r in j2['recs'][len(j['recs']):]]
    res(rc2 == 0 and sorted(n2.lines()) == sorted(n.lines()) and not n2.lines('CWE') and not m2.lines() and
        set(new) <= {1, 5}, 'full-results-durable',
        f'rc={rc2} {n2.lines()} new_records={new} model_requests={len(m2.lines())}')


# ---- 2. release.sh lifecycle: start, health, stop with work outstanding, restore, finish
def t_lifecycle():
    base, objs, ex = prep('lifecycle', ['76666', '83423'])
    m = Model(base, 1500)
    st = base + '/state'
    os.makedirs(st)
    for d in ('root', 'objs.txt'):
        shutil.move(base + '/' + d, st + '/' + d)
    vp = free_port()
    rc, o = sh('start', st, BUILD, OMC, m.port, vp)
    res(rc == 0, 'lifecycle-start', o.strip()[-200:])
    rc, o = sh('health', st)
    want = 0 if LIVE else 1  # fake-serve has no /health: the node half alone answers
    res(rc == want and 'node 0' in o, 'lifecycle-health', o.strip()[-200:])
    pid = int(open(st + '/node.pid').read())
    wait_for(lambda: open(st + '/run.out', 'rb').read().count(b'\nCWE ') >= 6, 1800)
    rc, o = sh('stop', st)
    s = json.load(open(st + '/view-at-stop.json'))
    gone = not os.path.exists(f'/proc/{pid}')
    res(rc == 0 and gone and s['queue']['running'] == 0 and s['authority']['paused'] == 1, 'lifecycle-stop',
        f"rc={rc} gone={gone} queue={s['queue']} {o.strip()[-160:]}")
    rc, o = sh('restore', st)
    v = json.load(open(st + '/view.json'))
    res(rc == 0 and v['incarnation'] == 2 and v['authority']['paused'] == 0, 'lifecycle-restore',
        f"rc={rc} inc={v['incarnation']} paused={v['authority']['paused']}")
    pid = int(open(st + '/node.pid').read())
    wait_for(lambda: not os.path.exists(f'/proc/{pid}'), 3600, 0.2)
    out = open(st + '/run.out', 'rb').read().decode(errors='replace')
    j = journal(st)
    cwo = [l for l in out.splitlines() if l.startswith('CWO')]
    res(j['max_starts'] == 1 and j['opens'] == 2, 'lifecycle-journal-once',
        f"opens={j['opens']} max_starts={j['max_starts']}")
    finished('lifecycle-finish', cwo, [st + '/run.out'], ex,
             [l for l in out.splitlines() if l.startswith('CWSUM')])
    m.close()


# ---- 3. the creator killed after a replace finished: restart without a second effect
def t_restart():
    base, objs, ex = prep('restart', ['76666'])
    m = Model(base, 300)
    n = Node(base, objs, m.port)
    hit = n.until(lambda l: l.startswith('CWE 0 ') and l.split()[2].endswith('4') and l.split()[3] == '4', 1800)
    n.p.send_signal(signal.SIGKILL)
    n.wait()
    out1 = n.lines()
    n2 = Node(base, objs, m.port, tag='run2')
    rc = n2.wait()
    m.close()
    j = journal(base)
    rep = [o for o in j['starts'] if o[0] % 10 == 4]
    res(hit and not out1 and len(n2.lines()) == 1 and
        j['max_starts'] == 1 and j['opens'] == 2 and rep and all(j['dones'][o] == [(2, 1)] for o in rep),
        'restart-no-duplicate-effect',
        f"killed_after_replace={hit} run1={out1} run2 rc={rc} opens={j['opens']} max_starts={j['max_starts']} replace_dones={[j['dones'][o] for o in rep]}")
    finished('restart-resumed-completes', n2.lines(), [n.out, n2.out], ex)


# ---- 4. conflict: another writer changes the file after the model read it
def t_conflict():
    base, objs, ex = prep('conflict', ['76666'])
    m = Model(base, 300)
    path = base + '/root/' + ex['recs'][0]['path']
    n = Node(base, objs, m.port)
    hit = n.until(lambda l: l.startswith('CWE 0 ') and l.split()[2].endswith('2') and l.split()[3] == '4', 1800)
    mark = b'\nnote changed by another writer (DRA-292 conflict check)\n'
    with open(path, 'ab') as f:
        f.write(mark)
    rc = n.wait()
    m.close()
    j = journal(base)
    rep = [o for o in j['starts'] if o[0] % 10 == 4]
    kept = open(path, 'rb').read().endswith(mark)
    res(hit and n.lines() == ['CWO 0 FAIL 15 ' + n.lines()[0].split()[-1]] if n.lines() else False,
        'conflict-detected-15', f'read_done={hit} {n.lines()}')
    res(kept and not rep, 'conflict-other-write-kept', f'kept={kept} replace_starts={len(rep)}')


# ---- 5. a worker killed during an inference: the job runs again, nothing is lost
def t_worker():
    base, objs, ex = prep('worker', ['76666'])
    m = Model(base, 4000)
    n = Node(base, objs, m.port)
    victim = None

    def infer_parent():
        nonlocal victim
        for p in tree(n.p.pid):
            if exe(p) == 'infer':
                s = open(f'/proc/{p}/stat').read()
                victim = int(s[s.rindex(')') + 2:].split()[1])
                return victim != n.p.pid
        return False
    found = wait_for(infer_parent, 600, 0.05)
    t = time.time()
    if found:
        os.kill(victim, signal.SIGKILL)
    rc = n.wait()
    m.close()
    j = journal(base)
    lost = {o: ds for o, ds in j['dones'].items() if any(d[1] in (2, 6) for d in ds)}
    res(found and rc == 0 and n.lines() and n.lines()[0].startswith('CWO 0 PASS') and
        list(lost.values()) == [[(1, 6), (2, 1)]] and all(j['starts'][o] == 2 for o in lost),
        'worker-death-rerun', f'killed_worker={victim} rc={rc} {n.lines()} lost_ops(DONEs outcome,how)={dict(lost)} '
        f'starts={[j["starts"][o] for o in lost]}')
    res(not compare(n, ex), 'worker-death-turns-equal-recorded', f'{compare(n, ex) or "equal"}')


# ---- 6. an uncertain effect: the worker of a granted replace dies; never retried
def t_uncertain():
    base, objs, ex = prep('uncertain', ['76666', '82342', '85188'])
    m = Model(base, 300)
    n = Node(base, objs, m.port, prog='code-test', mode=('uncertain',))
    last = None
    while n.p.poll() is None:
        rc, s = view(n.vport)
        if rc == 0 and s and s['uncertain']:
            last = s
        time.sleep(0.05)
    n.wait()
    u = last and last['uncertain']
    i = u[0] // 1000 - 1 if u else -1
    res(u and len(u) == 1 and any(l.startswith(f'CWO {i} FAIL 21') for l in n.lines()), 'uncertain-objective-21',
        f'uncertain={u} {n.lines()}')
    j = journal(base)
    ops = [o for o in j['starts'] if u and o[0] == u[0]]
    res(len(ops) == 1 and j['starts'][ops[0]] == 1 and j['done'].get(ops[0], (9,))[0] == 0, 'uncertain-start-durable',
        f"op={ops} starts={[j['starts'][o] for o in ops]} done(outcome,how)={[j['done'].get(o) for o in ops]}")
    n2 = Node(base, objs, m.port, tag='run2')
    n2.wait()
    m.close()
    j2 = journal(base)
    tail = j2['recs'][len(j['recs']):]
    rel = [r[4] for r in tail if r[0] == 5 and u and r[3] == u[0]]
    res(sorted(n2.lines()) == sorted(n.lines()) and not n2.lines('CWE') and
        not [r for r in tail if r[0] in (2, 3)] and rel == [0], 'uncertain-final-after-restart',
        f"run2 {n2.lines()} new_records={[r[0] for r in tail]} released_outcome={rel}")


# ---- 7. cancellation of a running inference through the operator
def t_cancel():
    base, objs, ex = prep('cancel', ['76666', '83423'])
    m = Model(base, 6000)
    n = Node(base, objs, m.port)
    n.until(lambda l: l.startswith('CWE 0 ') and l.split()[2].endswith('1') and l.split()[3] == '1', 600)
    time.sleep(1.0)
    rc, a = fresh(n.vport, 60, 3, 0)
    t = time.time()
    n.until(lambda l: l.startswith('CWO 0 '), 120)
    dt = time.time() - t
    rc2 = n.wait()
    m.close()
    o = n.lines()
    gone = [l for l in m.lines() if l.split()[1] == '499'] if LIVE else ['n/a: fake-serve']
    res(a and a['status'] == 'committed' and any(l.startswith('CWO 0 FAIL 19') for l in o) and
        any(l.startswith('CWO 1 PASS') for l in o) and gone, 'cancel-running-inference',
        f'ack={a} ended_after_s={dt:.2f} {o} model_499={gone}')


# ---- 8. stale and coalesced operator commands during a run
def t_commands():
    base, objs, ex = prep('commands', ['76666', '83423'])
    m = Model(base, 1500)
    n = Node(base, objs, m.port)
    rc, s = view(n.vport)
    # far ahead: the run publishes versions while the command travels, so version + 1 may be current
    rc1, a = op(n.vport, 'cmd', 300, 4, 1, s['incarnation'], s['version'] + 100000, 7)
    res(rc1 == 1 and a and a['status'] == 'stale', 'commands-future-version-stale', f'{a}')
    rc, s = view(n.vport)
    burst = [subprocess.Popen([BUILD + '/op', str(n.vport), 'cmd', str(310 + k), '4', str(k % 2),
                               str(s['incarnation']), str(s['version']), str(7 - k)], stdout=subprocess.PIPE)
             for k in range(4)]
    acks = []
    for p in burst:
        out, _ = p.communicate(60)
        try:
            acks.append(json.loads(out))
        except ValueError:
            acks.append(None)
    st = collections.Counter(x and x['status'] for x in acks)
    committed = sorted(x['version'] for x in acks if x and x['status'] == 'committed')
    res(st['committed'] >= 1 and set(st) <= {'committed', 'stale', 'busy', 'pending'} and
        len(set(committed)) == len(committed), 'commands-burst-each-answered-once',
        f'statuses={dict(st)} committed_versions={committed}')
    again = [op(n.vport, 'cmd', x['id'], 4, 0, x['incarnation'], 0, 1)[1] for x in acks if x and x['status'] == 'committed']
    res(all(y and y['status'] == 'duplicate' for y in again), 'commands-repost-duplicate', f'{again}')
    rc = n.wait()
    m.close()
    j = journal(base)
    res(rc in (0, 1) and len(n.lines()) == 2 and j['oper'] == len(committed), 'commands-run-completes',
        f'rc={rc} {n.lines()} oper_records={j["oper"]}')


# ---- 9. no model server: an explicit failure, no fallback
def t_down():
    base, objs, ex = prep('down', ['76666'])
    n = Node(base, objs, free_port())
    rc = n.wait(120)
    res(rc == 1 and n.lines() == ['CWO 0 FAIL 16 1'] and
        any(l.startswith('CWE 0 1001 4 ') for l in n.lines('CWE')), 'server-down-16', f'rc={rc} {n.lines()}')


# ---- 10. one active authority: a second creator on the same journal is fenced
def t_authority():
    base, objs, ex = prep('authority', ['76666'])
    m = Model(base, 1500)
    n = Node(base, objs, m.port)
    n2 = Node(base, objs, m.port, tag='second')
    rc2 = n2.wait(60)
    alive = n.p.poll() is None
    rc = n.wait()
    m.close()
    j = journal(base)
    res(rc2 != 0 and alive and rc == 0 and j['opens'] == 1 and n.lines()[0].startswith('CWO 0 PASS'),
        'one-active-authority', f"second rc={rc2} err={open(base + '/second.err', 'rb').read()[-160:]} first {n.lines()} opens={j['opens']}")


# ---- 11. journal compatibility and reversible cutover between the DRA-290 build and this one
def t_journal():
    base, objs, ex = prep('compat', ['76666'])
    m = Model(base, 150)
    old = Node(base, objs, m.port, bindir=OLDBIN, view=False)
    hit = old.until(lambda l: l.startswith('CWE 0 ') and l.split()[2].endswith('4') and l.split()[3] == '4', 1800)
    old.p.send_signal(signal.SIGKILL)
    old.wait()
    snap = base + '/snapshot'
    for d in ('root', 'work', 'journal'):
        shutil.copytree(f'{base}/{d}', f'{snap}/{d}')
    new = Node(base, objs, m.port, tag='forward')
    rcf = new.wait()
    j = journal(base)
    nres = sum(r[0] == 10 for r in j['recs'])
    res(hit and len(new.lines()) == 1 and j['opens'] == 2 and j['max_starts'] == 1 and nres == 1,
        'journal-forward-old-to-new',
        f"old killed after its replace={hit}; new rc={rcf} opens={j['opens']} max_starts={j['max_starts']} result_records={nres}")
    finished('journal-forward-completes', new.lines(), [old.out, new.out], ex)
    again = Node(base, objs, m.port, tag='again')
    again.wait()
    tail = journal(base)['recs'][len(j['recs']):]
    res(again.lines() == new.lines() and not [r for r in tail if r[0] in (2, 3)], 'journal-result-after-upgrade',
        f'{again.lines()} new_records={[r[0] for r in tail]}')
    before = open(base + '/journal/journal', 'rb').read()
    back = Node(base, objs, m.port, bindir=OLDBIN, view=False, tag='rollback')
    rcb = back.wait(120)
    res(rcb != 0 and not back.lines() and open(base + '/journal/journal', 'rb').read() == before,
        'journal-rollback-refuses-result', f"old rc={rcb} (30 + 24 unknown record type) unchanged=True")
    # cutover reversal: the state copied before the new build ran, under the old build again
    for d in ('root', 'work', 'journal'):
        shutil.rmtree(f'{base}/{d}')
        shutil.copytree(f'{snap}/{d}', f'{base}/{d}')
    back2 = Node(base, objs, m.port, bindir=OLDBIN, view=False, tag='rollback2')
    rcb2 = back2.wait()
    j3 = journal(base)
    res(len(back2.lines()) == 1 and j3['max_starts'] == 1 and j3['opens'] == 2,
        'journal-rollback-from-snapshot', f"rc={rcb2} opens={j3['opens']} max_starts={j3['max_starts']}")
    finished('journal-rollback-completes', back2.lines(), [old.out, back2.out], ex)
    m.close()
    # a committed operator command (DRA-291 OPER): the DRA-290 reader refuses it too, changing nothing
    base2, objs2, ex2 = prep('compat-oper', ['76666', '83423'])
    m2 = Model(base2, 1500)
    n = Node(base2, objs2, m2.port)
    rc, a = fresh(n.vport, 500, 4, 1, 7)
    n.p.send_signal(signal.SIGKILL)
    n.wait()
    j4 = journal(base2)
    before = open(base2 + '/journal/journal', 'rb').read()
    back3 = Node(base2, objs2, m2.port, bindir=OLDBIN, view=False, tag='rollback')
    rcb3 = back3.wait(120)
    after = open(base2 + '/journal/journal', 'rb').read()
    res(a and a['status'] == 'committed' and j4['oper'] == 1 and rcb3 != 0 and before == after,
        'journal-rollback-refuses-oper', f"ack={a and a['status']} oper={j4['oper']} old rc={rcb3} unchanged={before == after}")
    m2.close()


# ---- 12. memory limits: address-space caps doubling from the creator's measured peak; each run ends
# with an explicit result and a consistent journal, and the smallest passing cap is reported
def t_memory():
    base, objs, ex = prep('memory', ['76666'])
    m = Model(base, 150)
    n = Node(base, objs, m.port, tag='measure')
    hw = collections.defaultdict(int)
    vm = collections.defaultdict(int)
    while n.p.poll() is None:
        for p in tree(n.p.pid):
            try:
                for l in open(f'/proc/{p}/status'):
                    if l.startswith('VmPeak:'):
                        vm[exe(p)] = max(vm[exe(p)], int(l.split()[1]))
                    if l.startswith('VmHWM:'):
                        hw[exe(p)] = max(hw[exe(p)], int(l.split()[1]))
            except OSError:
                pass
        time.sleep(0.005)
    n.wait()
    measured('memory-peak-kB', json.dumps(dict(VmHWM=dict(hw), VmPeak=dict(vm), sampled_every_ms=5)))
    unit = vm['code-main']
    tries, passed = [], None
    for k in (0, 1, 2, 3, 4, 5, 6):
        cap = unit << k >> 1
        b, o, _ = prep(f'memory-cap{k}', ['76666'])
        x = Node(b, o, m.port, pre=('prlimit', f'--as={cap * 1024}', '--'), view=False)
        rc = x.wait(600)
        jf = b + '/journal/journal'
        js = journal(b) if os.path.exists(jf) and os.path.getsize(jf) >= 64 else None
        tries.append(dict(as_kB=cap, rc=rc, out=x.lines(), journal=bool(js), max_starts=js and js['max_starts']))
        consistent = js is None or js['max_starts'] <= 1
        explicit = (not x.lines() and rc != 0 and not js) or (len(x.lines()) == 1 and rc in (0, 1))
        if not (consistent and explicit):
            res(False, 'memory-cap-explicit', json.dumps(tries[-1]))
        if x.lines() and x.lines()[0].startswith('CWO 0 PASS'):
            passed = cap
            break
    measured('memory-caps', json.dumps(tries))
    res(passed is not None and len(tries) > 1, 'memory-caps-fail-closed-then-pass',
        f'smallest passing as_kB={passed} after {len(tries) - 1} failing caps, each explicit with a consistent journal')
    m.close()


TESTS = (t_full, t_lifecycle, t_restart, t_conflict, t_worker, t_uncertain, t_cancel, t_commands, t_down,
         t_authority, t_journal, t_memory)
if LIVE:
    rc, o = sh('serve', OUT + '/model', PORT, os.environ['OLLM'], os.environ.get('VERB', 'serve'),
               os.environ['CK'], os.environ['MERGES'])
    print('SERVE', o.strip(), flush=True)
    Model.live = OUT + '/model/serve.log'
    if rc:
        res(False, 'serve', o)
        print(f'RELSUM pass={NP[0]} fail={NP[1]} not_run={NP[2]}', flush=True)
        sys.exit(1)
for t in TESTS:
    if ONLY and t.__name__[2:] not in ONLY:
        continue
    t0 = time.time()
    try:
        t()
    except Exception as e:  # a crashed check is a failed check
        res(False, t.__name__, f'{type(e).__name__}: {e}')
    for q in PROCS:
        if q.poll() is None:
            q.kill()
            q.wait()
    PROCS.clear()
    measured(t.__name__[2:] + '-seconds', f'{time.time() - t0:.1f}')
if LIVE:
    print('UNSERVE', sh('unserve', OUT + '/model')[1].strip(), flush=True)
MODEL = ('live own model ' + os.environ.get('VERB', 'serve')) if LIVE else \
    'fake (recorded answers only: host regression, not model qualification)'
print(f'RELSUM pass={NP[0]} fail={NP[1]} not_run={NP[2]} mode={MODEL}', flush=True)
sys.exit(1 if NP[1] else 0)
