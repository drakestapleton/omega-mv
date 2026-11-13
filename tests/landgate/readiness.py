#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# tests/landgate/readiness.py: TEST INSTRUMENT (Python, never on a product path). Readiness record for one exact head of
# a change line. Nothing is typed: the verdict is READY only when EVERY condition below holds; otherwise NOT_READY with
# each failing condition named. Its controls are tests/landgate/instruments.sh.
#  1 gate summary: the head line names HEAD and BASE; "failed records: none" and "LANDGATE PASS rc=0" are present.
#  2 every summary row parses; each row's log exists and its sha256 equals the row's; every row named in the contract's
#    "Required gate rows (NAME):" line is present with rc=0 (a row ending "!" is a control: its control_exit equals its
#    expected_exit and text=found; a row ending "?" may be NOT_APPLICABLE).
#  3 BASE is an ancestor of HEAD in REPO; a merge-residue scan of HEAD outside evidence/ completes (git grep exit 1) and
#    finds nothing. A scan that does not complete is a failing condition, never "no residue".
#  4 RCCA: the file exists and names this line; the action record names every action heading of that RCCA (**H<n>,
#    **R<n>) with a state; READY needs each IMPLEMENTED or EXERCISED, except actions recorded "OPEN-ACCEPTED <ref>".
#  5 finding ledger: the --ledger-check command exits 0 (set equality, run by the caller's ledger instrument).
#  6 review rounds: the rounds file names this line and, when an RCCA is given, does not still say "No RCCA file exists"
#    unless a "SUPERSEDED" line follows that statement; the author-models file exists.
#  7 each --evidence label=path exists (sha256 recorded); label=none refuses.
# usage: readiness.py --name N --head H --base B --repo R --logdir D --contract C --rcca F --actions F --ledger F
#        --ledger-check 'CMD ...' --rounds F --authors F --limits F --out F [--evidence label=path ...]
# exit 0 READY, 1 NOT_READY, 2 usage.
import argparse, datetime, hashlib, re, shlex, subprocess, sys
from pathlib import Path
ap = argparse.ArgumentParser()
for k in ('name', 'head', 'base', 'repo', 'logdir', 'contract', 'rcca', 'actions', 'ledger', 'ledger-check', 'rounds', 'authors', 'limits', 'out'):
    ap.add_argument('--' + k, required=True)
ap.add_argument('--evidence', action='append', default=[])
a = ap.parse_args()
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
def run(*c): return subprocess.run(list(c), capture_output=True, text=True)
def git(*c):
    r = run('git', '-C', a.repo, *c)
    return r.stdout.strip() if r.returncode == 0 else None
why = []; ev = []
def need(ok, msg):
    if not ok: why.append(msg)  # readiness predicate
    return ok
for label in ('contract', 'rcca', 'actions', 'ledger', 'rounds', 'authors', 'limits', 'logdir'):
    p = getattr(a, label)
    need(p != 'none' and Path(p).exists(), f'required {label} missing ({p})')
if why: print('NOT_READY: ' + '; '.join(why)); sys.exit(1)
S = Path(a.logdir) / 'SUMMARY.log'; lines = S.read_text().splitlines() if S.is_file() else []
need(bool(lines) and lines[0].startswith(f'head {a.head} ') and f' base {a.base} ' in lines[0], 'summary head line does not name this head and base')
need('LANDGATE PASS rc=0' in lines and 'failed records: none' in lines, 'gate summary is not LANDGATE PASS with no failed records')
rows = {}
for l in lines[1:]:
    m = re.match(r'^(\S+) (rc=(\d+)|control_exit=(\d+) expected_exit=(\d+)) log=(\S+) sha256=([0-9a-f]{64})( start=\S+)?( text=(found|MISSING))?$', l)
    if m:
        rows[m[1]] = m
        p = Path(m[6]); need(p.is_file() and sha(p) == m[7], f'row {m[1]}: log missing or sha256 differs')
    elif ' NOT_APPLICABLE: ' in l: rows[l.split()[0]] = 'NA'
    elif l not in ('failed records: none', 'LANDGATE PASS rc=0'): need(False, f'unparsed summary row: {l[:80]}')
ctext = Path(a.contract).read_text()
req = re.search(r'^Required gate rows \(' + re.escape(a.name) + r'\): (.+)$', ctext, re.M)
if need(req is not None, f'contract has no "Required gate rows ({a.name}):" line'):
    for tok in req[1].split():
        kind = 'pass'
        if tok.endswith('!'): kind, tok = 'control', tok[:-1]
        if tok.endswith('?'): kind, tok = 'optional', tok[:-1]
        r = rows.get(tok)
        if r is None: need(False, f'required row {tok} absent'); continue
        if r == 'NA': need(kind == 'optional', f'required row {tok} is NOT_APPLICABLE'); continue
        if kind == 'control': need(r[4] is not None and r[4] == r[5] and r[10] == 'found', f'control row {tok} did not show its expected exit and text')
        else: need(r[3] == '0' and r[10] != 'MISSING', f'row {tok} not rc=0')
need(run('git', '-C', a.repo, 'merge-base', '--is-ancestor', a.base, a.head).returncode == 0, 'base is not an ancestor of head')
mr = run('git', '-C', a.repo, 'grep', '-l', '-I', '-E', r'^(<<<<<<< |=======$|>>>>>>> )', a.head, '--', '.', ':!evidence')
if need(mr.returncode in (0, 1), f'merge-residue scan failed (git grep exit {mr.returncode})'):  # scan predicate
    need(mr.returncode == 1 and not mr.stdout.strip(), 'merge residue: ' + mr.stdout.strip().replace('\n', ' '))
rt = Path(a.rcca).read_text()
need(a.name in rt, f'RCCA {a.rcca} does not name line {a.name}')
acts = sorted(set(re.findall(r'^\*\*((?:H|R)\d+)\b', rt, re.M)))
need(bool(acts), 'RCCA names no actions')
at = Path(a.actions).read_text(); states = {}
for act in acts:
    m = re.search(r'^\| ' + act + r' [^|]*\|(?:[^|]*\|){3} *(IMPLEMENTED|EXERCISED|OPEN-ACCEPTED [^|]+?|OPEN[^|]*?|BLOCKED[^|]*?) *\|', at, re.M)
    st = m[1].strip() if m else None; states[act] = st
    need(st is not None, f'action {act} has no row/state in {a.actions}')
    if st: need(st in ('IMPLEMENTED', 'EXERCISED') or st.startswith('OPEN-ACCEPTED '), f'action {act} is {st}')
lg = run(*shlex.split(a.ledger_check))
lgl = (lg.stdout.strip().splitlines() or [''])[-1]
need(lg.returncode == 0, f'ledger check exit {lg.returncode}: {lgl}')
rd = Path(a.rounds).read_text(); need(a.name in rd, f'rounds file does not name {a.name}')
i = rd.find('No RCCA file exists')
need(i < 0 or 'SUPERSEDED' in rd[i:], 'rounds file still says "No RCCA file exists" with no SUPERSEDED line after it')
for e in a.evidence:
    k, v = e.split('=', 1)
    if v == 'none': need(False, f'required evidence {k} is none'); ev.append(f'- {k}: none'); continue
    if need(Path(v).is_file(), f'missing evidence {v}'): ev.append(f'- {k}: {v} sha256 {sha(v)}')
ok = not why
omc = (git('show', f'{a.head}:seed/out/omc.sha256') or '?').split()[0]; bomc = (git('show', f'{a.base}:seed/out/omc.sha256') or '?').split()[0]
L = [f'# Readiness record: omega-mv {a.name} {a.head}', '',
     f'Verdict: {"READY" if ok else "NOT_READY"} (derived by tests/landgate/readiness.py; nothing typed).' + ('' if ok else ' Failing: ' + '; '.join(why)), '',
     'Not landed, not published. Review needs both a Claude model and an OpenAI model: authorship is mixed by session records.', '',
     '## Identity',
     f'- head {a.head} (line {a.name}), parent {git("rev-parse", a.head + "^")}, tree {git("rev-parse", a.head + "^{tree}")}',
     f'- base {a.base}; compiler {omc} (base {bomc})',
     f'- contract {a.contract} sha256 {sha(a.contract)}',
     f'- RCCA {a.rcca} sha256 {sha(a.rcca)}; action record {a.actions} sha256 {sha(a.actions)}; action states: ' + ', '.join(f'{k}={s}' for k, s in states.items()),
     f'- finding ledger {a.ledger} sha256 {sha(a.ledger)}; ledger check exit {lg.returncode}: {lgl}',
     f'- review rounds {a.rounds} sha256 {sha(a.rounds)}; author models {a.authors} sha256 {sha(a.authors)}', '',
     '## Gate results (exact head, fresh clone)', f'- summary {S} sha256 {sha(S) if S.is_file() else "MISSING"}']
L += ['  - ' + l for l in lines]
L += ['', '## Further evidence'] + ev + ['', '## NOT_RUN and limits', Path(a.limits).read_text().rstrip(), '',
      f'Generated {datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")} by {Path(__file__).resolve()} (sha256 {sha(__file__)}).']
Path(a.out).write_text('\n'.join(L) + '\n')
print(a.out, sha(a.out), 'READY' if ok else 'NOT_READY: ' + '; '.join(why))
sys.exit(0 if ok else 1)
