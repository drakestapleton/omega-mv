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
     statement where `end` had to come, must be refused (error 5 or 17), and so must each wider alternative
     in ALT_NL / ALT_END
  D  broken machines must fail A or B on at least one program (seven mutants)
  E  alarm: every word with an optional tail (table flag 2) is used by at least one accepted program
  F  alarm: every word snap reads by its table arity is probed in OMC: exactly that many arguments compile,
     one more is refused with error 5; words no probe program fits are listed as unprobed
Before any check: REFERENCE_JSON's pin must be OMC's sha256, and words.table must equal its projection.
usage: gate.py --table REFERENCE_JSON   writes the words.table text for that reference to stdout
Programs OMC refuses are fed to strip only to show it answers (exit 0 or 3), never a trap.
Exit 0 and a last line SNAPGATE PASS only when every check holds; otherwise exit 1 and SNAPGATE FAIL.
"""
import collections, glob, hashlib, json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import snapref as R


def sha(b):
    return hashlib.sha256(b).hexdigest()


# arity probe: for each word snap reads by its table arity, a program omc accepts with exactly that many
# arguments, and the same program with one more, which omc must refuse with error 5
ALT_NL = ('1 ', 'x ', 'inline ', 'unroll ', 'bound 5 ', 'fresh ', 'else ', 'int 1 ')   # before a forced line end
ALT_END = ('ret 0\n', 'x = int 1\n', 'else\n', 'break\n')                            # before a forced end
PRE = 'global H uchar 64\nglobal E uchar *\nfn main to int\nh = long 1\n'
FORMS = ('x = {w}\nret 0', '{w}\nret 0', 'ret int {w}', 'if {w}\nret 1\nend\nret 0')
PLAIN = ('1', 'int 1', 'long 1', 'ulong 1', 'f64 1', 'f32 1', 'H', 'true', 'h')


def slot(t):
    t = t.split(':', 1)[-1].lower()
    for key, c in (('handle', 'h'), ('array', 'H'), ('uchar', 'H'), ('ulong', 'ulong 1'), ('uint', 'uint 1'), ('long', 'long 1'),
                   ('int', 'int 1'), ('f64', 'f64 1'), ('f32', 'f32 1'), ('bool', 'true')):
        if key in t:
            return c
    return '1'


def arity_probe(omc, table, skip):
    def rc(src):
        return subprocess.run([omc], input=src.encode(), capture_output=True).returncode
    probed, unprobed, bad = [], [], []
    for k, v in table.items():
        if k in skip or v['category'] == 'type' or not isinstance(v.get('arity'), int):
            continue
        a = v['arity']
        typed = [slot(t) for t in v.get('types', [])][:a]
        cands = ([typed] + [typed[:1] + [c] * (a - 1) for c in ('1', '8')] if len(typed) == a and a else []) + [[c] * a for c in PLAIN]
        hit = None
        for unit in ('', 'om2\n'):                       # OM-2 words compile only in an om2 unit
            for args in cands:
                for form in FORMS:
                    if rc(unit + PRE + form.format(w=' '.join([k] + args)) + '\nend\n') == 0:
                        hit = (unit, args, form); break
                if hit:
                    break
            if hit:
                break
        if not hit:
            unprobed.append(k); continue
        unit, args, form = hit
        e = rc(unit + PRE + form.format(w=' '.join([k] + args + [args[-1] if args else '1'])) + '\nend\n')
        probed.append(k)
        if e != 5:
            bad.append((k, e))
    return probed, unprobed, bad


def main():
    if len(sys.argv) == 3 and sys.argv[1] == '--table':
        sys.stdout.write(R.table_text(json.load(open(sys.argv[2]))['words'])); return 0
    if len(sys.argv) < 4:
        print(__doc__); return 2
    omc, refp, scratch = sys.argv[1:4]
    dirs = sys.argv[4:] + [os.path.join(HERE, 'fixtures')]
    os.makedirs(scratch, exist_ok=True)
    T = json.load(open(refp))['words']
    pin = json.load(open(refp)).get('pin', {}).get('omc_sha256')
    omc_sha = sha(open(omc, 'rb').read())
    print('omc sha256', omc_sha, 'reference pin', pin)
    if pin != omc_sha:
        print('SNAPGATE FAIL the reference is for another compiler: use the reference.json whose pin is this omc'); return 1
    table = open(os.path.join(HERE, 'words.table')).read()
    if table != R.table_text(T):
        print('SNAPGATE FAIL words.table is stale for this reference: gate.py --table REFERENCE_JSON > seed/snap/words.table')
        return 1

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

    kinds = collections.Counter(); wide = 0
    for f in acc:
        its = R.items(progs[f][0]); m = R.M(T)

        def text(lst):
            s = ''.join((x[1] + '\n') if x[0] == 'raw' else (x[1] if x[1] == '\n' else x[1] + ' ') for x in lst)
            return s.replace(' \n', '\n')                  # omc reads `om2` only alone on its line
        # control: the rebuilt program itself must compile, or the mutants below prove nothing
        if compile_(text(its), os.path.join(scratch, 'm.bin')) != 0:
            fails.append(('C', f, 'the rebuilt program does not compile (control)')); continue
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
                elif rc not in (5, 17):
                    fails.append(('C', f, f'item {k}: omc error {rc}, not 5 or 17, so the refusal proves nothing'))
                # wider alternatives (tail words, a literal, a name, a statement): each must be refused too
                for alt in (ALT_NL if fo == '\n' else ALT_END):
                    if compile_(text(its[:k]) + alt + text(its[k:]), os.path.join(scratch, 'm.bin')) == 0:
                        fails.append(('C', f, f'item {k}: omc accepts {alt!r} at a forced position'))
                    wide += 1
            m.feed(it[1])
    # E (alarm): a word with an optional tail that no accepted program uses is untested here; add a fixture
    tails = sorted(k for k, v in T.items() if R.flags(k, v) == 2)
    for k in tails:
        if not any(x[0] == 'w' and x[1] == k for f in acc for x in R.items(progs[f][0])):
            fails.append(('E', k, 'optional-tail word used by no accepted program: add a fixture'))
    print('E optional-tail words', tails)
    # the oracle's own copies of snap.om's word lists must match snap.om
    src_ctl = set(re.search(r'^text ctl "(.*)"$', snap_src, re.M).group(1).split())
    if R.CTRL - {'(', ')'} != src_ctl:
        fails.append(('LISTS', 'CTRL', f'oracle and snap.om differ: {sorted((R.CTRL - {"(", ")"}) ^ src_ctl)}'))
    own = set(R.SKIP1) | R.ARG1 | {'get', 'offsetof', 'new'}
    if not own <= R.NAMED:
        fails.append(('LISTS', 'own rules', f'not in snap.om kwl: {sorted(own - R.NAMED)}'))
    # F (alarm): every word read by its table arity refuses one more word in omc
    probed, unprobed, bad = arity_probe(omc, T, R.NAMED | R.CTRL | {k for k, v in T.items() if R.flags(k, v) == 2})
    for k, e in bad:
        fails.append(('F', k, f'omc gives {e}, not error 5, for one word more than the table arity'))
    print(f'F arity probe: probed {len(probed)} wrong {len(bad)} unprobed {len(unprobed)}:', ' '.join(unprobed))
    print('C wider alternatives refused:', wide)
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
          f'positions={sum(kinds.values())} mutants={caught}/{len(mutants)} probed={len(probed)} '
          f'unprobed={len(unprobed)} fail={len(fails)}')
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
