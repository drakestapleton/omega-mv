#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# tests/landgate/bundle.py: TEST INSTRUMENT (Python, never on a product path). Review bundle for one exact head, then
# its verification. Exit 1 (refuse), never a silent skip, when any of these holds:
#  - a file cited by a record (the readiness record, the receipt, the summary, every copied record: SUMMARY.log, *.md,
#    *.provenance, *.draft, *.receipt, REUSE manifests and bindings; followed transitively; raw logs are not records)
#    is missing, or lies outside every --root (citations are every absolute path under --cite-scope);
#  - a cited file is not in the bundle (a cited file is never omitted for its size; only uncited files of the log
#    directory over BUNDLE_MAXB bytes, default 8 MiB, are listed in logs-omitted.txt instead of copied);
#  - a bundled copy differs from the sha256 a record gives for that path ("PATH sha256 HEX" or "PATH sha256=HEX"), or
#    from the source file read at copy time;
#  - the git bundle of BRANCH (= HEAD) over BASE does not verify against a clone of --base-repo, or does not give HEAD;
#  - the omega-bridge commit named by HEAD's om/omega-bridge.lock is not bundled from --bridge-repo and verified;
#  - the base or head compiler bytes differ from their seed/out/omc.sha256 records; MANIFEST.sha256 does not check.
# Controls: tests/landgate/instruments.sh.
# usage: bundle.py --name N --head H --base B --repo R --logdir D --readiness F --receipt F --out DIR --base-repo R
#        --bridge-repo R --root LABEL=DIR [--root ...] [--cite-scope DIR] [--branch REF] [--extra PATH ...]
import argparse, hashlib, os, re, shutil, subprocess, sys, tempfile
from pathlib import Path
ap = argparse.ArgumentParser()
for k in ('name', 'head', 'base', 'repo', 'logdir', 'readiness', 'receipt', 'out', 'base-repo', 'bridge-repo'): ap.add_argument('--' + k, required=True)
ap.add_argument('--root', action='append', required=True); ap.add_argument('--cite-scope', default=str(Path.home()))
ap.add_argument('--branch'); ap.add_argument('--extra', action='append', default=[])
a = ap.parse_args()
MAXB = int(os.environ.get('BUNDLE_MAXB', 8 * 1024 * 1024))
ROOTS = [(lab, Path(p).resolve()) for lab, p in (r.split('=', 1) for r in a.root)]
BR = a.branch or f'land/{a.name}'
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
git = lambda *c: subprocess.check_output(['git', '-C', a.repo, *c])
D = Path(a.out)
if D.exists(): shutil.rmtree(D)
D.mkdir(parents=True); omitted = {}; errors = []; copied = {}; cited = {}; recorded = []
def key(src):
    for lab, r in ROOTS:
        try: return Path(lab) / src.relative_to(r)
        except ValueError: pass
    return None
def put(src, is_cited=False, where='argument'):
    src = Path(src)
    if not src.exists(): errors.append(f'missing {src} (cited in {where})'); return
    src = src.resolve(); k = key(src)
    if k is None: errors.append(f'outside bundle roots: {src} (cited in {where})'); return
    if src.is_dir():
        for p in sorted(src.rglob('*')):
            if p.is_file() and not p.is_symlink(): put(p, is_cited, where)
        return
    if is_cited: cited[k] = src
    if k in copied: return
    if src.stat().st_size > MAXB and not is_cited: omitted[k] = src; return  # omission rule
    dst = D / k; dst.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(src, dst); copied[k] = sha(src)
    if sha(dst) != copied[k]: errors.append(f'copy of {src} differs from its source')
skip = re.compile(r'(^|/)(pools\.work|shallow|qualify-out|[^/]*\.scratch|controls/pools/tree|controls/host-[a-z-]+)(/|$)|(^|/)kwctl-[a-z]+/seed/omc/(omc\.om|gate18\.sh)$')
L = Path(a.logdir)
for p in sorted(L.rglob('*')):
    r = p.relative_to(L).as_posix()
    if p.is_file() and not p.is_symlink() and not skip.search(r): put(p)
for x in [a.readiness, a.receipt, *a.extra]: put(x, True)
scope = re.escape(str(Path(a.cite_scope).resolve()).rstrip('/')) + r'/[^\s`\'")\]|<>,;=]+'
CITE = re.compile(scope); DIG = re.compile('(' + scope + r')\s+sha256[= ]([0-9a-f]{64})')
def is_record(f): return f.name in ('SUMMARY.log', 'HEAD', 'REUSE-MANIFEST.txt') or f.name.endswith('.REUSE-BINDINGS.txt') or f.suffix in ('.md', '.provenance', '.draft', '.receipt')
seen = set()
while True:
    new = False
    for k in sorted(copied):
        if k in seen: continue
        seen.add(k); f = D / k
        if not is_record(f): continue
        try: text = f.read_text(errors='strict')
        except (UnicodeError, OSError): errors.append(f'record {k} is not readable text'); continue
        for m in DIG.finditer(text): recorded.append((m[1].rstrip('.:'), m[2], k))
        for m in CITE.finditer(text):
            raw = m[0].rstrip('.:'); c = Path(raw.split('@', 1)[0])  # samebytes arguments are REPO@COMMIT
            if c.is_file():
                before = len(copied); put(c, True, str(k)); new |= len(copied) != before
            elif not c.exists() and not re.search(r'\{|\*|<', raw): errors.append(f'cited path missing: {raw} (in {k})')
    if not new: break
for k, src in sorted(cited.items()):
    if k not in copied: errors.append(f'required artifact omitted: {src} ({src.stat().st_size} bytes)')  # required-artifact predicate
for p, d, where in recorded:
    k = key(Path(p).resolve()) if Path(p).exists() else None
    if k is None or k not in copied: continue  # missing or outside roots: already refused above
    if sha(D / k) != d: errors.append(f'{p} differs from its recorded sha256 {d} (in {where})')  # recorded-digest predicate
(D / 'HEAD').write_text(f'{a.head} {BR} base {a.base}\n')
(D / 'commit-message.txt').write_bytes(git('log', '-1', '--format=%B', a.head))
(D / 'diff-from-base.patch').write_bytes(git('diff', '--binary', f'{a.head}^', a.head))
(D / 'stat.txt').write_bytes(git('diff', '--stat', f'{a.head}^', a.head))
changed = git('diff', '--name-only', '--no-renames', f'{a.head}^', a.head).decode().split()
(D / 'changed-files.txt').write_text('\n'.join(changed) + '\n')
for f in changed:
    try: blob = git('show', f'{a.head}:{f}')
    except subprocess.CalledProcessError: continue
    p = D / 'files' / f; p.parent.mkdir(parents=True, exist_ok=True); p.write_bytes(blob)
(D / 'compilers').mkdir(); (D / 'compilers/base-omc').write_bytes(git('show', f'{a.base}:seed/out/omc')); (D / 'compilers/head-omc').write_bytes(git('show', f'{a.head}:seed/out/omc'))
for which, rev in (('base', a.base), ('head', a.head)):
    if sha(D / f'compilers/{which}-omc') != git('show', f'{rev}:seed/out/omc.sha256').decode().split()[0]: errors.append(f'{which} compiler bytes differ from its record')
if subprocess.run(['git', '-C', a.repo, 'rev-parse', BR], capture_output=True, text=True).stdout.strip() != a.head: errors.append(f'{BR} is not {a.head}')
gb = D / f'omega-mv-{a.name}-{a.head[:12]}.bundle'
subprocess.check_call(['git', '-C', a.repo, 'bundle', 'create', '-q', str(gb), BR, f'^{a.base}'])
with tempfile.TemporaryDirectory() as t:
    if subprocess.run(['git', 'clone', '-q', '--bare', a.base_repo, f'{t}/v'], capture_output=True).returncode != 0: subprocess.check_call(['git', 'init', '-q', '--bare', f'{t}/v'])
    v = subprocess.run(['git', '-C', f'{t}/v', 'bundle', 'verify', str(gb)], capture_output=True, text=True)
    if v.returncode != 0: errors.append('git bundle does not verify against the base repository: ' + v.stderr.strip()[:200])
    else:
        subprocess.check_call(['git', '-C', f'{t}/v', 'fetch', '-q', str(gb), f'{BR}:refs/heads/x'])
        got = subprocess.check_output(['git', '-C', f'{t}/v', 'rev-parse', 'refs/heads/x'], text=True).strip()
        if got != a.head: errors.append(f'bundle ref {BR} is {got}, not {a.head}')
lock = git('show', f'{a.head}:om/omega-bridge.lock').decode().split('\n')
lock = next(l.split()[0] for l in lock if l.strip() and not l.startswith('#'))
bb = D / f'omega-bridge-{lock[:12]}.bundle'
if subprocess.run(['git', '-C', a.bridge_repo, 'branch', '-f', 'lane-lock', lock], capture_output=True).returncode != 0 or subprocess.run(['git', '-C', a.bridge_repo, 'bundle', 'create', '-q', str(bb), 'lane-lock'], capture_output=True).returncode != 0:
    bb.write_bytes(b'')
with tempfile.TemporaryDirectory() as t:
    subprocess.check_call(['git', 'init', '-q', '--bare', f'{t}/b'])
    v = subprocess.run(['git', '-C', f'{t}/b', 'fetch', '-q', str(bb), 'lane-lock:refs/heads/x'], capture_output=True, text=True)
    got = subprocess.run(['git', '-C', f'{t}/b', 'rev-parse', 'refs/heads/x'], capture_output=True, text=True).stdout.strip()
    if v.returncode != 0 or got != lock: errors.append(f'omega-bridge lock {lock} not bundled')
om = sorted(k for k in omitted if k not in copied)
(D / 'logs-omitted.txt').write_text(''.join(f'{sha(omitted[k])}  {k}  {omitted[k].stat().st_size} bytes\n' for k in om) or 'none\n')
files = sorted(p for p in D.rglob('*') if p.is_file() and p.name != 'MANIFEST.sha256')
(D / 'MANIFEST.sha256').write_text(''.join(f'{sha(p)}  {p.relative_to(D)}\n' for p in files))
c = subprocess.run(['sha256sum', '-c', '--quiet', 'MANIFEST.sha256'], cwd=D, capture_output=True, text=True)
if c.returncode != 0: errors.append('MANIFEST.sha256 does not check')
print(f'BUNDLE {D} files={len(files)} cited={len(cited)} recorded_digests={len(recorded)} omitted={len(om)} errors={len(errors)} MANIFEST sha256 {sha(D / "MANIFEST.sha256")}')
print(f'instrument {Path(__file__).resolve()} sha256 {sha(__file__)} maxb={MAXB}')
for e in errors: print('ERROR', e)
sys.exit(1 if errors else 0)
