#!/usr/bin/env python3
"""Independent C export round-trip corpus (#622 C export lane, ledger L608).

Written from spec/universal/c-u64-export-v1.md and source-aware-v1.md only; the exporter, importer and
codec are exercised through their public commands (tools/adapters/c-import, python-import, c-export,
tools/source-aware/sa). The corpus (fixtures-c-export-corpus.json) is disjoint from F1, the
c_import_controls boundaries and the F2 fixtures, and every expected export text is written by hand.

Per positive case (C source, or Python source for the cross-member leg):
  form       c-export output == '#include <stdint.h>\\n' + expected line + '\\n', stderr empty, run twice equal
  semonly    the envelope with its OMSP sidecar removed exports byte-identically (output from records only)
  compile    the exported C compiles with cc -std=c17 -O2 -Wall -Wextra -Werror -pedantic
  values     compiled original (cc for C, python3 for Python) == compiled export on boundary vectors
             (all pairs for <= 2 inputs, otherwise all rotations) plus 64 seeded random vectors
  identity   C only: sa identity(c-import(export)) == sa identity(c-import(source))
  fixpoint   c-export(c-import(export)) == export
Refusals: status, empty stdout and the named stderr line for bad commands, empty, truncated, extended,
oversized and bit-flipped envelopes, a real Python unit whose C rendering is too deep, and a stale build.
Exit 0 PASS, 1 FAIL, 3 NOT_RUN (a tool is missing; nothing passes)."""
from pathlib import Path
import argparse, json, random, shutil, struct, subprocess, sys, tempfile, zlib

ROOT = Path(__file__).resolve().parents[3]
sys.dont_write_bytecode = True
MASK = (1 << 64) - 1
BOUNDARY = [0, 1, 2, (1 << 32) - 1, 1 << 32, (1 << 63) - 1, 1 << 63, MASK - 1, MASK]
# Unused parameters are part of the profile (slots are kept), so only that one -Wextra warning is waived.
CFLAGS = ['-std=c17', '-O2', '-Wall', '-Wextra', '-Wno-unused-parameter', '-Werror', '-pedantic']
HEADER = b'#include <stdint.h>\n'
PARAMS = 'abcdef'
PYMASK = '0xFFFFFFFFFFFFFFFF'
TOOLS = {'c-import': ROOT / 'tools/adapters/c-import', 'python-import': ROOT / 'tools/adapters/python-import',
         'c-export': ROOT / 'tools/adapters/c-export', 'sa': ROOT / 'tools/source-aware/sa'}


def run(cmd, data, cwd=ROOT):
    return subprocess.run(cmd, input=data, capture_output=True, timeout=60, cwd=cwd)


def export(env, args=()):
    return run([sys.executable, str(TOOLS['c-export']), *args], env)


def c_import(src):
    return run([sys.executable, str(TOOLS['c-import'])], src)


def identity(env):
    r = run(['sh', str(TOOLS['sa']), 'identity'], env)
    return r.stdout if r.returncode == 0 else None


def semonly(env):
    # source-aware-v1 envelope: 'OMSB' 0x01, u32 LE semantic length, u32 LE sidecar length, then both.
    assert env[:5] == b'OMSB\x01', 'not an OMSB v1 envelope'
    ns, np_ = struct.unpack_from('<II', env, 5)
    assert len(env) == 13 + ns + np_, 'envelope length'
    return env[:5] + struct.pack('<II', ns, 0) + env[13:13 + ns]


def term(k):
    return PARAMS[k % 6]


def iname(k):
    return 'i%d' % PARAMS.index(term(k))


def right_sub(depth, leaf, wrap_inner, wrap):
    e = wrap_inner(leaf(depth), leaf(depth + 1))
    for k in range(depth - 1, -1, -1):
        e = wrap(leaf(k), e)
    return e


def generate(case):
    d = case['depth']
    sig6 = ', '.join('uint64_t i%d' % i for i in range(6))
    want = 'uint64_t calc(%s) { return %s; }' % (
        sig6, right_sub(d, iname, lambda x, y: '%s - %s' % (x, y), lambda x, e: '%s - (%s)' % (x, e)))
    if case['generate'] == 'c_right_sub':
        body = right_sub(d, term, lambda x, y: '%s-%s' % (x, y), lambda x, e: '%s-(%s)' % (x, e))
        src = '#include <stdint.h>\nuint64_t calc(%s) { return %s; }\n' % (
            ', '.join('uint64_t ' + p for p in PARAMS), body)
    else:
        body = right_sub(d, term, lambda x, y: '((%s - %s) & %s)' % (x, y, PYMASK),
                         lambda x, e: '((%s - %s) & %s)' % (x, e, PYMASK))
        src = 'def g(%s):\n    return %s\n' % (', '.join(PARAMS), body)
    return src.encode(), want


def vectors(n, seed):
    if n == 0:
        return [()]
    if n == 1:
        vs = [(v,) for v in BOUNDARY]
    elif n == 2:
        vs = [(a, b) for a in BOUNDARY for b in BOUNDARY]
    else:
        vs = [tuple(BOUNDARY[(i + j) % len(BOUNDARY)] for j in range(n)) for i in range(len(BOUNDARY))]
    rng = random.Random(seed)
    vs += [tuple(rng.getrandbits(64) for _ in range(n)) for _ in range(64)]
    return vs


def c_driver(name, n, vs):
    decl = 'uint64_t %s(%s);' % (name, ', '.join(['uint64_t'] * n) if n else 'void')
    rows = ',\n'.join('{%s}' % ', '.join('%dULL' % x for x in v) if n else '{0}' for v in vs)
    call = '%s(%s)' % (name, ', '.join('v[i][%d]' % j for j in range(n)))
    return ('#include <stdint.h>\n#include <stdio.h>\n#include <inttypes.h>\n%s\n'
            'static const uint64_t v[%d][%d] = {\n%s\n};\n'
            'int main(void) { (void)v; for (unsigned i = 0; i < %d; i++) printf("%%" PRIu64 "\\n", %s); return 0; }\n'
            % (decl, len(vs), max(n, 1), rows, len(vs), call))


def compile_run(work, tag, unit_c, name, n, vs, cc):
    d = work / tag
    d.mkdir()
    (d / 'unit.c').write_bytes(unit_c)
    (d / 'driver.c').write_text(c_driver(name, n, vs))
    b = subprocess.run([cc, *CFLAGS, '-o', str(d / 'run'), str(d / 'unit.c'), str(d / 'driver.c')],
                       capture_output=True, timeout=120)
    if b.returncode:
        return None, 'cc: ' + b.stderr.decode(errors='replace')[:400]
    r = subprocess.run([str(d / 'run')], capture_output=True, timeout=60)
    if r.returncode:
        return None, 'run status %d' % r.returncode
    return [int(x) for x in r.stdout.split()], None


def python_values(src, n, vs):
    ns = {}
    exec(compile(src.decode(), '<corpus>', 'exec'), ns)
    fn = next(v for k, v in ns.items() if callable(v) and not k.startswith('__'))
    return [fn(*v) for v in vs]


def positive(ctx, case, lang):
    rec = {'id': case['id'], 'lang': lang, 'checks': {}}
    chk = rec['checks']
    if 'generate' in case:
        src, want = generate(case)
    else:
        src, want = case['source'].encode(), case['expect']
    name = case.get('name')
    args = [name] if name else []
    imp = c_import(src) if lang == 'c' else run([sys.executable, str(TOOLS['python-import'])], src)
    if imp.returncode:
        chk['import'] = 'FAIL status %d %s' % (imp.returncode, imp.stderr.decode(errors='replace')[:200])
        return rec
    env = imp.stdout
    e1, e2, e3 = export(env, args), export(env, args), export(semonly(env), args)
    expected = HEADER + (want + '\n').encode()
    chk['form'] = 'PASS' if (e1.returncode == 0 and e1.stdout == expected and e1.stderr == b''
                             and e2.stdout == e1.stdout) else \
        'FAIL status %d got %r want %r' % (e1.returncode, e1.stdout[:300], expected[:300])
    chk['semonly'] = 'PASS' if e3.returncode == 0 and e3.stdout == e1.stdout else 'FAIL'
    if e1.returncode:
        return rec
    rec['export'] = e1.stdout.decode()
    n = want.count('uint64_t i')
    fname = name or 'calc'
    vs = vectors(n, zlib.crc32(case['id'].encode()))
    got, why = compile_run(ctx.work, case['id'] + '-export', e1.stdout, fname, n, vs, ctx.cc)
    chk['compile'] = 'PASS' if got is not None else 'FAIL ' + why
    if lang == 'c':
        oname = src.split(b'uint64_t ', 2)[1].split(b'(')[0].decode()
        ref, why = compile_run(ctx.work, case['id'] + '-orig', src, oname, n, vs, ctx.cc)
    else:
        ref, why = python_values(src, n, vs), None
    if got is None or ref is None:
        chk['values'] = 'FAIL ' + (why or 'export did not run')
    else:
        bad = [i for i in range(len(vs)) if got[i] != ref[i] or not 0 <= ref[i] <= MASK]
        chk['values'] = 'PASS' if not bad else 'FAIL at %r' % [vs[i] for i in bad[:3]]
        ctx.observations += len(vs)
    re_imp = c_import(e1.stdout)
    if re_imp.returncode:
        chk['reimport'] = 'FAIL status %d' % re_imp.returncode
        return rec
    if lang == 'c':
        a, b = identity(env), identity(re_imp.stdout)
        chk['identity'] = 'PASS' if a is not None and a == b else 'FAIL'
    fx = export(re_imp.stdout, args)
    chk['fixpoint'] = 'PASS' if fx.returncode == 0 and fx.stdout == e1.stdout else 'FAIL'
    return rec


def refused(r, status, line):
    return r.returncode == status and r.stdout == b'' and (line is None or r.stderr.decode(errors='replace').startswith(line))


def refusal(ctx, case, base):
    rec = {'id': case['id'], 'kind': case['kind']}
    st, line = case.get('status'), case.get('stderr')
    k = case['kind']
    if k == 'args':
        ok = refused(export(base, case['args']), st, line)
        rec['tried'] = 1
    elif k == 'bytes':
        ok = refused(export(b''), st, line)
        rec['tried'] = 1
    elif k == 'truncate':
        rs = [export(base[:i]) for i in range(1, len(base))]
        ok = all(refused(r, st, line) for r in rs)
        rec['tried'] = len(rs)
    elif k == 'trailing':
        ok = refused(export(base + b'\x00'), st, line)
        rec['tried'] = 1
    elif k == 'oversize':
        ok = refused(export(base + b' ' * (8193 - len(base))), st, line)
        rec['tried'] = 1
    elif k == 'flip':
        # Every single-bit change (bits 0 and 7 of each byte) must agree with the reference #621 codec
        # (`sa decode`, a separate public command): refused 65 exactly when the codec rejects it with a
        # status other than 68, refused 68 only when the codec accepts it or answers 68, accepted only when
        # the codec accepts it. An accepted change inside the OMSP sidecar must export byte-identically.
        ns = struct.unpack_from('<I', base, 5)[0]
        ref = export(base).stdout
        statuses, accepted_sidecar, accepted_semantic, bad = {}, 0, 0, []
        for i in range(len(base)):
            for bit in (0, 7):
                m = bytearray(base)
                m[i] ^= 1 << bit
                m = bytes(m)
                r = export(m)
                d = run(['sh', str(TOOLS['sa']), 'decode'], m).returncode
                statuses[r.returncode] = statuses.get(r.returncode, 0) + 1
                if r.returncode == 0:
                    good = d == 0 and r.stdout != b''
                    if i >= 13 + ns:
                        good = good and r.stdout == ref
                        accepted_sidecar += 1
                    else:
                        accepted_semantic += 1
                elif r.returncode == 65:
                    good = d not in (0, 68) and r.stdout == b''
                elif r.returncode == 68:
                    good = d in (0, 68) and r.stdout == b''
                else:
                    good = False
                if not good:
                    bad.append((i, bit, r.returncode, d))
        ok = not bad
        rec['tried'] = sum(statuses.values())
        rec['statuses'] = {str(s): c for s, c in sorted(statuses.items())}
        rec['accepted_sidecar_identical'] = accepted_sidecar
        rec['accepted_semantic'] = accepted_semantic
        rec['disagreements'] = bad[:10]
    elif k == 'python':
        src, _ = generate(case)
        imp = run([sys.executable, str(TOOLS['python-import'])], src)
        rec['python_import_status'] = imp.returncode
        ok = imp.returncode == 0 and refused(export(imp.stdout), st, line)
        rec['tried'] = 1
    elif k == 'stale':
        fake = ctx.work / 'stale-root'
        (fake / 'tools/adapters').mkdir(parents=True)
        shutil.copy2(TOOLS['c-export'], fake / 'tools/adapters/c-export')
        ok = refused(run([sys.executable, str(fake / 'tools/adapters/c-export')], base, cwd=fake), st, line)
        rec['tried'] = 1
    else:
        raise SystemExit('unknown refusal kind ' + k)
    rec['result'] = 'PASS' if ok else 'FAIL'
    return rec


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', required=True)
    ap.add_argument('--cc', default='cc')
    a = ap.parse_args()
    missing = [k for k, p in TOOLS.items() if not p.is_file()] + ([] if shutil.which(a.cc) else [a.cc])
    if missing:
        print('NOT_RUN missing ' + ' '.join(missing))
        return 3
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=False)
    corpus = json.loads((Path(__file__).resolve().parent / 'fixtures-c-export-corpus.json').read_text())
    with tempfile.TemporaryDirectory(prefix='c-export-corpus-') as t:
        ctx = argparse.Namespace(work=Path(t), cc=a.cc, observations=0)
        recs = [positive(ctx, c, 'c') for c in corpus['c_positives']]
        recs += [positive(ctx, c, 'python') for c in corpus['python_positives']]
        exports = {r['id']: r.get('export') for r in recs}
        for c in corpus['c_positives']:
            if 'same_export_as' in c:
                same = exports[c['id']] is not None and exports[c['id']] == exports[c['same_export_as']]
                next(r for r in recs if r['id'] == c['id'])['checks']['same_export'] = 'PASS' if same else 'FAIL'
        base = c_import(corpus['c_positives'][3]['source'].encode()).stdout
        refs = [refusal(ctx, c, base) for c in corpus['refusals']]
        obs = ctx.observations
    failed = [r['id'] for r in recs if len(r['checks']) < 2 or any(v != 'PASS' for v in r['checks'].values())]
    failed += [r['id'] for r in refs if r['result'] != 'PASS']
    for r in recs:
        print(r['id'], 'PASS' if r['id'] not in failed else 'FAIL %s' % r['checks'])
    for r in refs:
        print(r['id'], r['result'], 'tried=%d' % r['tried'], r.get('statuses', ''))
    summary = {'schema': 'omega.c-u64-export.corpus-result.v1', 'positives': '%d/%d' % (
        sum(r['id'] not in failed for r in recs), len(recs)), 'refusals': '%d/%d' % (
        sum(r['result'] == 'PASS' for r in refs), len(refs)), 'value_observations': obs, 'failed': failed,
        'cases': recs, 'refusal_cases': refs}
    (out / 'result.json').write_text(json.dumps(summary, indent=1) + '\n')
    print(('PASS' if not failed else 'FAIL'), 'positives=%s refusals=%s value_observations=%d' % (
        summary['positives'], summary['refusals'], obs))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
