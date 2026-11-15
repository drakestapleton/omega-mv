"""Reference model of the forced-next-item machine. Test oracle only; the product is seed/snap/snap.om.

Items are words and NL ("\n"). forced() gives the one item that must come next, or None.
Sound by design: whenever something is not known for certain, the rest of the line is OPEN.
Raw lines (`note ...` anywhere, `text ...` at top level) are copied verbatim and never forced.
"""
import os
import re

CTRL = {'=', 'fn', 'to', 'end', 'if', 'else', 'while', 'for', 'ret', 'bound', 'note', 'global', 'text',
        'const', 'struct', 'put', 'exit', 'trap', 'break', 'continue', 'free', 'own', 'void', 'unroll',
        'inline', 'fresh', 'abstract', 'holds', 'ops', 'layout', 'field', 'at', 'little', 'big', 'out',
        'export', '(', ')'}
SKIP1 = {'sizeof': 0, 'bitcast': 1, 'seal': 1, 'enlarge': 1}   # one skipped word, then this many values
ARG1 = {'view', 'edit'}                                       # as an argument: one array name
HERE = os.path.dirname(os.path.abspath(__file__))


def snap_words(snap_src):
    """the words snap.om reads by a rule of its own: its `kwl` and `ctl` text lists (one source, the product)"""
    out = set()
    for name in ('kwl', 'ctl'):
        m = re.search(r'^text ' + name + r' "(.*)"$', snap_src, re.M)
        out |= set(m.group(1).split())
    return out


NAMED = snap_words(open(os.path.join(HERE, 'snap.om')).read())


def flags(name, entry):
    """table column 3: 1 a type word; 2 a word whose reference form has an optional tail ("[" in the form, e.g.
    kfdctl's request-dependent SUFFIX) and no rule of its own in snap.om, so the rest of its line is open"""
    if entry['category'] == 'type':
        return 1
    if '[' in entry.get('form', '') and name not in NAMED:
        return 2
    return 0


def table_text(table):
    """seed/snap/words.table: one line NAME ARITY FLAGS per reference word (gate.py --table writes it)"""
    return ''.join(f"{k} {v['arity']} {flags(k, v)}\n" for k, v in table.items())


class M:
    def __init__(s, table):
        s.ar = {k: v['arity'] for k, v in table.items()}
        s.ty = {k for k, v in table.items() if v['category'] == 'type'} | {'f32', 'f64'}
        s.tail_open = {k for k, v in table.items() if flags(k, v) == 2}
        s.om2 = False; s.struct = False; s.first = True
        s.names = []; s.fns = {}; s.blocks = []; s.infn = False; s.void = False; s.ended = False
        s.fnmark = 0
        s._nl()

    def _nl(s):
        s.i = 0; s.kind = None; s.kind0 = None; s.owed = 0; s.open = False; s.skip = 0
        s.tail = None; s.pend = None; s.hdr = None; s.newname = None; s.lhs = None; s.hs = None

    def forced(s):
        if s.i == 0:
            if s.infn and s.ended and not (s.blocks and s.blocks[-1][0] == 'if' and not s.blocks[-1][2]):
                return 'end'
            return None
        if s.open or s.skip or s.pend:
            return None
        if s.kind == 'val' and s.owed == 0 and s.tail is None:
            return '\n'
        return None

    def raw(s, first, name):
        """a verbatim line: note (invisible) or a top-level text declaration"""
        if first == 'note':
            return
        s.first = False
        if name is not None:
            s.names.append(name)

    def _val(s, w):
        if s.skip:
            s.skip -= 1; return
        if s.pend == 'new':
            s.pend = None
            if w in s.ty: s.owed += 1          # N and v take the place of one slot
            else: s.open = True
            return
        if '(' in w or ')' in w:
            s.open = True; return
        if re.match(r'-?[0-9]', w):
            s.owed -= 1; return
        if w == 'new':
            s.pend = 'new'; return
        if w in ('get', 'offsetof') and s.struct:
            s.open = True; return
        if w == 'offsetof':
            s.skip = 2; s.owed -= 1; return
        if w in SKIP1:
            s.skip = 1; s.owed += SKIP1[w] - 1; return
        if w in ARG1:
            return                               # owed + 1 - 1
        if w in s.fns:
            s.owed += s.fns[w] - 1; return
        if w in s.names:
            s.owed -= 1; return
        if w in s.ar and w not in CTRL:
            if w in s.tail_open:
                s.open = True; return            # how many words follow depends on its arguments
            s.owed += s.ar[w] - 1; return
        s.open = True

    def feed(s, w):
        if w == '\n':
            if s.i == 0:
                return
            k = s.kind0
            if k == 'fn' and s.hdr is not None:
                s.fns[s.hdr[0]] = s.hdr[1]
            if k in ('ret', 'exit', 'trap', 'break', 'continue'):
                s.ended = True
            elif k == 'if':
                s.blocks.append(['if', len(s.names), False, False]); s.ended = False
            elif k in ('while', 'for'):
                s.blocks.append([k, len(s.names), False, False]); s.ended = False
                if k == 'for' and s.newname:
                    s.names.append(s.newname)
            elif k == 'else':
                if s.blocks:
                    b = s.blocks[-1]; b[3] = s.ended; b[2] = True; del s.names[b[1]:]
                s.ended = False
            elif k == 'end':
                if s.blocks:
                    b = s.blocks.pop(); del s.names[b[1]:]
                    s.ended = b[0] == 'if' and b[2] and b[3] and s.ended
                else:
                    s.infn = False; s.ended = False; del s.names[s.fnmark:]
            elif k == 'assign' and s.newname:
                s.names.append(s.newname)
            s.first = False
            s._nl(); return
        i = s.i; s.i += 1
        if i == 0:
            s.kind0 = w
            if not s.infn:
                if w == 'om2' and s.first:
                    s.om2 = True; s.open = True; return
                if w in ('struct', 'layout', 'abstract'):
                    s.struct = True
                if w == 'fn':
                    s.kind = 'fn'; return
                s.open = True; s.kind0 = 'top'; s.kind = 'top'; s.topw = w; return
            if w in ('else', 'end', 'break', 'continue'):
                s.kind = 'val'; s.owed = 0; return
            if w == 'ret':
                s.kind = 'val'; s.owed = 0 if s.void else 1; return
            if w in ('if', 'exit', 'trap'):
                s.kind = 'val'; s.owed = 1; return
            if w == 'while':
                s.kind = 'val'; s.owed = 1; s.tail = 'while'; return
            if w == 'for':
                s.kind = 'for'; return
            if w == 'put':
                s.kind = 'val'
                if s.struct: s.open = True
                else: s.skip = 1; s.owed = 2
                return
            if w in s.fns:
                s.kind = 'val'; s.owed = s.fns[w]; s.kind0 = 'call'; return
            if w in s.ar or w in s.ty:
                s.open = True; s.kind0 = 'unknown'; return     # a reserved word we do not model here
            s.kind = 'lhs'; s.kind0 = 'assign'; s.lhs = w; return
        if s.kind == 'top':
            if i == 1 and s.topw in ('const', 'global'):
                s.names.append(w)
            return
        if s.kind == 'fn':
            return s._fnhdr(i, w)
        if s.open:
            return
        if s.kind == 'lhs':
            if w == '=':
                s.kind = 'val'; s.owed = 1
                s.newname = None if s.lhs in s.names else s.lhs
                return
            if s.lhs in s.names:
                s.kind = 'val'; s.owed = 1; return s._val(w)
            s.open = True; s.kind0 = 'unknown'; return
        if s.kind == 'for':
            if i == 1: s.newname = w; return
            s.open = True; return                # type, count and the optional tail stay open
        if s.kind == 'val':
            if s.owed == 0 and not s.skip and not s.pend:
                if s.tail == 'while' and w == 'bound':
                    s.tail = None; s.owed = 1; return
                s.open = True; return            # outside the model: never force after this
            return s._val(w)

    def _fnhdr(s, i, w):
        if i == 1:
            s.infn = True; s.fnmark = len(s.names); s.blocks = []; s.ended = False
            s.hdr = [w, 0]; s.hs = 'p'; s.void = False; return
        if s.hs == 'f':                          # after a sized array: optional `fresh`
            s.hs = 'p'
            if w == 'fresh': return
        if s.hs == 'p':
            if w == 'to': s.hs = 'r'; return
            s.names.append(w); s.hdr[1] += 1; s.hs = 't'; return
        if s.hs == 't':
            s.hs = 'a' if w in ('view', 'edit', 'out') else 'p'; return
        if s.hs == 'a':
            s.hs = 'n' if w in s.ty else 'p'; return
        if s.hs == 'n':
            s.hs = 'f'; return
        if s.hs == 'r':
            s.void = (w == 'void'); s.hs = 'x'
            if s.om2: s.open = True
            else: s.kind = 'val'; s.owed = 0
            return
        s.open = True


def items(src):
    """('w', word) | ('w', NL) | ('raw', line, first, name). Blank lines are dropped."""
    out = []
    for line in src.split('\n'):
        ws = line.split()
        if not ws:
            continue
        if ws[0] == 'note':
            out.append(('raw', line.strip(), 'note', None)); continue
        if ws[0] == 'text':
            out.append(('raw', line.strip(), 'text', ws[1] if len(ws) > 1 else None)); continue
        out += [('w', w) for w in ws] + [('w', '\n')]
    return out


def canon(src):
    return ''.join((it[1] + '\n') if it[0] == 'raw' else (it[1] if it[1] == '\n' else it[1] + ' ') for it in items(src)).replace(' \n', '\n')


def strip(src, table):
    """-> strand text, items, forced, violations. A violation is a forced item the program does not have."""
    m = M(table); out = []; n = f = 0; bad = []
    for it in items(src):
        n += 1
        if it[0] == 'raw':
            out.append(it[1] + '\n'); m.raw(it[2], it[3]); continue
        w = it[1]; fo = m.forced()
        if fo is not None:
            if fo != w:
                bad.append((n, fo, w))
            else:
                f += 1; m.feed(w)
                if w == 'end':            # a forced `end` word is followed by its own (forced) newline
                    pass
                continue
        out.append(w if w == '\n' else w + ' '); m.feed(w)
    return ''.join(out).replace(' \n', '\n'), n, f, bad


def expand(strand, table):
    m = M(table); out = []
    def emit(w):
        out.append(w if w == '\n' else w + ' '); m.feed(w)
    lines = strand.split('\n')
    for line in lines:
        ws = line.split()
        if not ws:
            continue
        k = 0
        while k < len(ws):
            w = ws[k]
            while True:                          # forced items first, always (a note never delays them)
                fo = m.forced()
                if fo is None: break
                emit(fo)
            if m.i == 0 and (w == 'note' or w == 'text'):
                out.append(' '.join([line.strip().split(None, k)[k]]) + '\n') if k else out.append(line.strip() + '\n')
                rest = ws[k:]
                m.raw(w, rest[1] if w == 'text' and len(rest) > 1 else None)
                k = len(ws); break
            emit(w); k += 1
        else:
            # the real newline of the strand line
            if m.i != 0:
                emit('\n')
    while True:
        fo = m.forced()
        if fo is None: break
        emit(fo)
    return ''.join(out).replace(' \n', '\n')
