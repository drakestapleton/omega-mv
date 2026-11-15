#!/usr/bin/env python3
"""Host gate for seed/snap/snap.om. Test harness only (Python is the oracle and the conductor, never the product).

usage: gate.py OMC REFERENCE_JSON SCRATCH PROGRAM_DIR...

OMC             the seeded compiler (its sha256 is printed; compare it with the pin)
REFERENCE_JSON  omega-mcp data/reference.json for that compiler (word arities and categories)
PROGRAM_DIR     directories searched for *.om programs; fixtures/ beside this file is always added

Checks, on every program OMC accepts:
  A  snap strip refuses nothing (bad = 0) and equals the oracle (snapref.py): strand text, item and forced counts
  B  snap expand of that strand equals the oracle, and OMC compiles it to the same binary as the original
  C  every forced position is checked against OMC: one more word where the line had to end, or one more
     statement where `end` had to come, must be refused
  D  broken machines must fail A or B on at least one program (seven mutants)
  E  alarm: every word with an optional tail (table flag 2) is used by at least one accepted program
Programs OMC refuses are fed to strip only to show it answers (exit 0 or 3), never a trap.
Exit 0 and a last line SNAPGATE PASS only when every check holds; otherwise exit 1 and SNAPGATE FAIL.
"""
import collections, glob, hashlib, json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import snapref as R


def sha(b):
    return hashlib.sha256(b).hexdigest()


def main():
    if len(sys.argv) < 4:
        print(__doc__); return 2
    omc, refp, scratch = sys.argv[1:4]
    dirs = sys.argv[4:] + [os.path.join(HERE, 'fixtures')]
    os.makedirs(scratch, exist_ok=True)
    T = json.load(open(refp))['words']
    table = R.table_text(T)
    print('omc sha256', sha(open(omc, 'rb').read()))

    def compile_(src, out):
        r = subprocess.run([omc], input=src.encode(), stdout=open(out, 'wb'), stderr=subprocess.PIPE)
        return r.returncode

    def build(src, name):
        out = os.path.join(scratch, name)
        if compile_(src, out) != 0:
            return None
        os.chmod(out, 0o755)
        return out

    snap_src = open(os.path.join(HERE, 'snap.om')).read()
    snap = build(snap_src, 'snap')
    if not snap:
        print('SNAPGATE FAIL snap.om does not compile'); return 1
    print('snap.om sha256', sha(snap_src.encode()), 'binary', sha(open(snap, 'rb').read()))

    def run(binary, tab, mode, prog):
        r = subprocess.run([binary], input=(tab + '%%\n' + mode + '\n' + prog).encode(), capture_output=True, timeout=120)
        m = re.match(rb'snap items (\d+) forced (\d+) bad (\d+)', r.stderr)
        return r.returncode, r.stdout.decode(errors='replace'), tuple(map(int, m.groups())) if m else None

    files = sorted({f for d in dirs for f in glob.glob(os.path.join(d, '**', '*.om'), recursive=True)})
    progs = {}
    for f in files:
        src = open(f, errors='replace').read()
        out = os.path.join(scratch, 'p.bin')
        progs[f] = (src, sha(open(out, 'rb').read()) if compile_(src, out) == 0 else None)
    acc = [f for f in files if progs[f][1]]
    ref = [f for f in files if not progs[f][1]]
    fails = []

    def check(binary, tab, f, with_compile):
        src, binsha = progs[f]
        strand, n, fo, bad = R.strip(src, T)
        if bad:
            return 'oracle refuses an accepted program'
        rc, out, st = run(binary, tab, 'strip', src)
        if rc != 0 or st is None or st != (n, fo, 0):
            return f'strip rc={rc} stats={st} want {(n, fo, 0)}'
        if out.rstrip(' ') != strand.rstrip(' '):
            return 'strand differs from the oracle'
        rc, exp, _ = run(binary, tab, 'expand', out)
        if rc != 0 or exp != R.expand(strand, T):
            return 'expand differs from the oracle'
        if with_compile:
            o = os.path.join(scratch, 'e.bin')
            if compile_(exp, o) != 0 or sha(open(o, 'rb').read()) != binsha:
                return 'expanded program does not compile to the same binary'
        return None

    items = forced = 0
    for f in acc:
        e = check(snap, table, f, True)
        if e:
            fails.append(('AB', f, e))
        _, n, fo, _ = R.strip(progs[f][0], T)
        items += n; forced += fo
    print(f'A/B accepted programs {len(acc)} items {items} forced {forced} failures {sum(1 for x in fails if x[0] == "AB")}')

    answered = 0
    for f in ref:
        rc, _, st = run(snap, table, 'strip', progs[f][0])
        if rc in (0, 3) and st is not None:
            answered += 1
        else:
            fails.append(('REFUSED-INPUT', f, f'rc={rc}'))
    print(f'refused-by-omc programs {len(ref)} answered {answered}')

    kinds = collections.Counter()
    for f in acc:
        its = R.items(progs[f][0]); m = R.M(T)

        def text(lst):
            return ''.join((x[1] + '\n') if x[0] == 'raw' else (x[1] if x[1] == '\n' else x[1] + ' ') for x in lst)
        for k, it in enumerate(its):
            if it[0] == 'raw':
                m.raw(it[2], it[3]); continue
            fo = m.forced()
            if fo is not None and fo == it[1]:
                mutant = text(its[:k]) + ('0 ' if fo == '\n' else 'trap 1\n') + text(its[k:])
                rc = compile_(mutant, os.path.join(scratch, 'm.bin'))
                kinds[('nl' if fo == '\n' else 'end', rc)] += 1
                if rc == 0:
                    fails.append(('C', f, f'item {k}: omc accepts an alternative at a forced position'))
            m.feed(it[1])
    # E (alarm): a word with an optional tail that no accepted program uses is untested here; add a fixture
    tails = sorted(k for k, v in T.items() if R.flags(k, v) == 2)
    for k in tails:
        if not any(x[0] == 'w' and x[1] == k for f in acc for x in R.items(progs[f][0])):
            fails.append(('E', k, 'optional-tail word used by no accepted program: add a fixture'))
    print('E optional-tail words', tails)
    print('C forced positions against omc:', dict(sorted((f'{a}:error{b}', c) for (a, b), c in kinds.items())),
          'accepted', sum(c for (a, b), c in kinds.items() if b == 0))

    def mut(old, new):
        assert old in snap_src, old
        return snap_src.replace(old, new, 1)
    mutants = {
        'T1 table add arity 3': (snap_src, table.replace('add 2 0\n', 'add 3 0\n')),
        'M1 while tail ignored': (mut('if ne g S_TAIL 0\nret 0\nend\nret 1\nend', 'ret 1\nend'), table),
        'M2 else ignored': (mut('if eq get bke sub nb 1 0\nret 0\nend', 'if eq get bke sub nb 1 7\nret 0\nend'), table),
        'M3 expander never closes at end of input': (mut('if eq mode 2\npushforced\nend', 'if eq mode 9\npushforced\nend'), table),
        'M4 a name takes no slot': (mut('if findname off n\nsv S_OWED sub g S_OWED 1\nret\nend\nt = findtab', 'if findname off n\nret\nend\nt = findtab'), table),
        'M5 void ret takes a value': (mut('if ne g S_VOID 0\nsv S_OWED 0\nelse', 'if ne g S_VOID 0\nsv S_OWED 1\nelse'), table),
        'M6 optional tail ignored': (mut('if ne get tty sub t 1 2\n', 'if ne get tty sub t 1 9\n'), table),
    }
    caught = 0
    for name, (src, tab) in mutants.items():
        b = build(src, 'mutant')
        bad = sum(1 for f in acc if b is None or check(b, tab, f, False)) if b else len(acc)
        print(f'D {name}: fails {bad} of {len(acc)}')
        if bad:
            caught += 1
        else:
            fails.append(('D', name, 'mutant survives'))
    print(f'D mutants caught {caught} of {len(mutants)}')
    for x in fails[:40]:
        print('FAIL', *x)
    print(f'SNAPGATE {"FAIL" if fails else "PASS"} accepted={len(acc)} items={items} forced={forced} '
          f'positions={sum(kinds.values())} mutants={caught}/{len(mutants)} fail={len(fails)}')
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
