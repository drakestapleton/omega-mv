#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# tests/landgate/receipts.py: TEST INSTRUMENT (Python, never on a product path). Landing receipt DRAFT for one head.
# First line "RECEIPT PASS head=<sha>" only when ALL of these hold, checked before any verdict is written:
#  - the gate summary is for this head and says "failed records: none" and "LANDGATE PASS rc=0";
#  - every summary row parses, and every row's log (passing rows and control rows alike) exists now and its sha256
#    equals the one the row recorded: an absent or changed log refuses, it is never silently left out;
#  - the readiness record is for this exact head, says "Verdict: READY", and names this summary and this contract
#    with their current sha256.
# Otherwise "RECEIPT NOT_READY head=<sha>" with each reason. Exit 0 PASS, 1 NOT_READY. Controls: tests/landgate/instruments.sh.
# usage: receipts.py --head H --base B --logdir D --core N --contract C --readiness F --out F [--repo-note TEXT] [--note TEXT ...]
import argparse, hashlib, re, sys
from pathlib import Path
ap = argparse.ArgumentParser()
for k in ('head', 'base', 'logdir', 'core', 'contract', 'readiness', 'out'): ap.add_argument('--' + k, required=True)
ap.add_argument('--repo-note', default=''); ap.add_argument('--note', action='append', default=[])
a = ap.parse_args()
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
S = Path(a.logdir) / 'SUMMARY.log'; why = []
lines = S.read_text().splitlines() if S.is_file() else []
if not ('LANDGATE PASS rc=0' in lines and 'failed records: none' in lines): why.append('gate summary not LANDGATE PASS')
if not (lines and lines[0].startswith(f'head {a.head} ')): why.append('summary is not for this head')
ROW = re.compile(r'^(\S+) (?:rc=(\d+)|control_exit=(\d+) expected_exit=(\d+)) log=(\S+) sha256=([0-9a-f]{64})( start=\S+)?( text=\w+)?$')
ev = []
for ln in lines[1:]:
    m = ROW.match(ln)
    if m:
        p = Path(m[5]); now = sha(p) if p.is_file() else None
        if now != m[6]: why.append(f'row {m[1]}: log {"missing" if now is None else "changed"} ({p})')  # receipt log predicate
        if m[2] is not None: ev.append(f'evidence {m[1]} {m[5]} sha256 {m[6]}' + (m[7] or '') + (m[8] or ''))
        else: ev.append(f'control {m[1]} expected_exit={m[4]} observed_exit={m[3]} evidence {m[5]} sha256 {m[6]}' + (m[7] or '') + (m[8] or ''))
    elif ' NOT_APPLICABLE: ' in ln: ev.append('note ' + ln)
    elif ln not in ('failed records: none', 'LANDGATE PASS rc=0'): why.append(f'unparsed summary row: {ln[:80]}')
rt = Path(a.readiness).read_text() if Path(a.readiness).is_file() else ''
if not rt: why.append('readiness record missing')
elif not (rt.startswith('# Readiness record: omega-mv ') and a.head in rt.splitlines()[0]): why.append('readiness record is not for this head')
if rt and not re.search(r'^Verdict: READY ', rt, re.M): why.append('readiness verdict is not READY')
if rt and S.is_file() and f'summary {S} sha256 {sha(S)}' not in rt: why.append('readiness names another summary or digest')
if rt and Path(a.contract).is_file() and f'contract {a.contract} sha256 {sha(a.contract)}' not in rt: why.append('readiness names another contract or digest')
ok = not why
b = [f'RECEIPT PASS head={a.head}' if ok else f'RECEIPT NOT_READY head={a.head}']
if not ok: b.append('not ready: ' + '; '.join(why))
b += [f'base {a.base}'] + ([a.repo_note] if a.repo_note else []) + [
      'DRAFT: not landed and not published. Acceptance needs independent review of this exact head by a Claude model and an OpenAI model.',
      f'gates pinned to core {a.core}',
      f'contract {a.contract} sha256 {sha(a.contract)}' if Path(a.contract).is_file() else f'contract {a.contract} MISSING',
      f'readiness {a.readiness} sha256 {sha(a.readiness)}' if rt else f'readiness {a.readiness} MISSING',
      f'log {S} sha256 {sha(S)}' if S.is_file() else f'log {S} MISSING'] + ev + ['note ' + n for n in a.note]
b.append('failed records: none' if 'failed records: none' in lines else 'failed records: ' + next((l.split(': ', 1)[1] for l in lines if l.startswith('failed records:')), 'unknown'))
b.append(f'instrument {Path(__file__).resolve()} sha256 {sha(__file__)}')
Path(a.out).write_text('\n'.join(b) + '\n'); print(a.out, sha(a.out), 'PASS' if ok else 'NOT_READY: ' + '; '.join(why)); sys.exit(0 if ok else 1)
