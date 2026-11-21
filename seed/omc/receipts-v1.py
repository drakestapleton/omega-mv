#!/usr/bin/env python3
"""Independent verifier for native omc canonical program-identity & effect receipts (OMC_RECEIPT=1)."""
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
compiler = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / 'seed/out/omc'
source = root / 'seed/omc/omc.om'
text = source.read_text()
pins = re.findall(r'^text d2pin "([0-9a-f]{64})"$', text, re.M)
assert len(pins) == 1, 'source-pin-count'
compiler_src_pin = pins[0]

def canonical_body_bytes(data: bytes) -> bytes:
    out = bytearray()
    e = len(data)
    p = 0
    ht = 0
    while p < e:
        b = data[p]
        if b in (32, 9, 13):
            p += 1
        elif b == 10:
            if ht:
                out.append(10)
                ht = 0
            p += 1
        elif ht == 0 and data[p:p+4] == b'note' and (p + 4 == e or data[p+4] <= 32 or data[p+4] in (40, 41)):
            nl = data.find(b'\n', p)
            p = e if nl == -1 else nl + 1
        else:
            if ht:
                out.append(32)
            if b == 34:
                out.append(34)
                p += 1
                while p < e:
                    sb = data[p]
                    out.append(sb)
                    p += 1
                    if sb == 92 and p < e:
                        out.append(data[p])
                        p += 1
                    elif sb in (34, 10):
                        break
            elif b in (40, 41):
                out.append(b)
                p += 1
            else:
                while p < e and data[p] > 32 and data[p] not in (40, 41, 34):
                    out.append(data[p])
                    p += 1
            ht = 1
    if ht:
        out.append(10)
    return bytes(out)

env = os.environ.copy()
env.pop('OMC_DIAGNOSTICS', None)
env.pop('OMC_MEMORY_MAX', None)
env.pop('OMC_RECEIPT', None)

def run_omc(c, data: bytes, receipt: bool = True, diag: bool = False):
    e = env.copy()
    if receipt:
        e['OMC_RECEIPT'] = '1'
    if diag:
        e['OMC_DIAGNOSTICS'] = '2'
    return subprocess.run([str(c)], input=data, capture_output=True, env=e, timeout=30)

def parse_and_verify(c, data: bytes, expect_effects: int = None, expect_sites_min: int = None):
    plain = run_omc(c, data, receipt=False)
    rich = run_omc(c, data, receipt=True)
    assert plain.returncode == 0, ('plain-fail', plain.returncode, plain.stderr)
    assert rich.returncode == 0, ('rich-fail', rich.returncode, rich.stderr)
    # stdout must be byte-identical whether OMC_RECEIPT=1 is set or not
    assert plain.stdout == rich.stdout, 'stdout-parity'
    assert plain.stderr == b'', ('plain-stderr-nonempty', plain.stderr)

    lines = [ln for ln in rich.stderr.splitlines() if ln.startswith(b'omc-receipt 1 ')]
    assert len(lines) == 1, ('receipt-line-count', rich.stderr)
    line = lines[0]
    marker = b' receipt_id='
    idx = line.rfind(marker)
    assert idx > 0, ('missing-receipt-id', line)
    payload = line[:idx]
    rid_hex = line[idx + len(marker):].decode()
    expected_rid = hashlib.sha256(b'omega.effect.receipt.v1\x00' + payload).hexdigest()
    assert rid_hex == expected_rid, ('receipt-id-mismatch', rid_hex, expected_rid)

    fields = dict(tok.split(b'=', 1) for tok in payload[len(b'omc-receipt 1 '):].split())
    assert fields[b'input_sha256'].decode() == hashlib.sha256(data).hexdigest(), 'input-sha256'
    assert int(fields[b'input_bytes']) == len(data), 'input-bytes'
    assert fields[b'output_sha256'].decode() == hashlib.sha256(rich.stdout).hexdigest(), 'output-sha256'
    assert int(fields[b'output_bytes']) == len(rich.stdout), 'output-bytes'
    assert fields[b'compiler_source_sha256'].decode() == compiler_src_pin, 'compiler-source-sha256'

    exp_body = hashlib.sha256(canonical_body_bytes(data)).digest()
    assert fields[b'body_id'].decode() == exp_body.hex(), ('body-id', fields[b'body_id'].decode(), exp_body.hex())

    sig_bytes = bytes.fromhex(fields[b'sig_id'].decode())
    con_bytes = bytes.fromhex(fields[b'contract_id'].decode())
    exp_pid = hashlib.sha256(b'omega.program.v2\x00' + exp_body + sig_bytes + con_bytes).hexdigest()
    assert fields[b'program_id'].decode() == exp_pid, ('program-id', fields[b'program_id'].decode(), exp_pid)

    eff = int(fields[b'effects'])
    sites = int(fields[b'effect_sites'])
    if expect_effects is not None:
        assert eff == expect_effects, ('effects-mask', eff, expect_effects)
    if expect_sites_min is not None:
        assert sites >= expect_sites_min, ('effect-sites', sites, expect_sites_min)
    return fields

# 1. Pure program: effects=0, effect_sites=0, contract_id=0..0
pure_a = b'fn main to int\nret 7\nend\n'
pure_b = b'note header comment\n\n  fn   main   to   int  \n  note inline comment\n\tret   7\n\nend\n'
pure_c = b'fn main to int\nret 8\nend\n'

fa = parse_and_verify(compiler, pure_a, expect_effects=0, expect_sites_min=0)
fb = parse_and_verify(compiler, pure_b, expect_effects=0, expect_sites_min=0)
fc = parse_and_verify(compiler, pure_c, expect_effects=0, expect_sites_min=0)

assert fa[b'input_sha256'] != fb[b'input_sha256'], 'raw-inputs-should-differ'
assert fa[b'body_id'] == fb[b'body_id'], 'whitespace-comment-invariance-body'
assert fa[b'program_id'] == fb[b'program_id'], 'whitespace-comment-invariance-program-id'
assert fa[b'program_id'] != fc[b'program_id'], 'mutation-separation'
assert fa[b'contract_id'] == b'0' * 64, 'zero-contract-id'
assert int(fa[b'effect_sites']) == 0, 'pure-zero-sites'
assert fa[b'effect_words'] == b'0' * 64, 'pure-zero-words'

# 2. Pure OM-2 function-mode unit
om2_pure = b'om2\nexport fn add1 x ulong to ulong\nret add x 1\nend\n'
f_om2 = parse_and_verify(compiler, om2_pure, expect_effects=0, expect_sites_min=0)
assert f_om2[b'om2'] == b'1' and int(f_om2[b'effect_sites']) == 0

# 3. Effectful IO program (write = keyword 54 -> cat bit 0 = 1)
io_prog = b'text hi "hi\\n"\nfn main to int\nw = write 1 hi 0 len hi\nret 0\nend\n'
f_io = parse_and_verify(compiler, io_prog, expect_effects=1, expect_sites_min=1)
ew_io = int(f_io[b'effect_words'].decode(), 16)
assert (ew_io & (1 << 54)) != 0, 'write-word-bit-set'

# 4. Effectful PROC + TIME + MEM program (monons=109 -> cat 16, enlarge=244 -> cat 64, exit=82 -> cat 4)
multi_eff = b'global pool uchar *\nfn main to int\nt = monons\nz = enlarge pool 64\nexit 0\nend\n'
f_multi = parse_and_verify(compiler, multi_eff, expect_effects=16 | 64 | 4, expect_sites_min=3)
ew_m = int(f_multi[b'effect_words'].decode(), 16)
assert (ew_m & (1 << 109)) != 0 and (ew_m & (1 << 244)) != 0 and (ew_m & (1 << 82)) != 0

# 5. Native object mode (object + om2)
obj_unit = b'object\nom2\nexport fn inc x ulong to ulong\nret add x 1\nend\n'
f_obj = parse_and_verify(compiler, obj_unit, expect_effects=0, expect_sites_min=0)
assert f_obj[b'obj'] == b'1' and f_obj[b'om2'] == b'1'

# 6. Compiler mutant control: skipping eff_rec must be caught by effect-mask check
with tempfile.TemporaryDirectory(prefix='omc-rc-mut-') as td:
    mut_src = text.replace('put rc_cat 0 or get rc_cat 0 cat\n', 'put rc_cat 0 0\n', 1)
    assert mut_src != text, 'mutant-site-missing'
    p = run_omc(compiler, mut_src.encode(), receipt=False)
    assert p.returncode == 0, ('mutant-compile-failed', p.stderr)
    mc = Path(td) / 'omc-no-eff'
    mc.write_bytes(p.stdout)
    mc.chmod(0o700)
    try:
        parse_and_verify(mc, io_prog, expect_effects=1, expect_sites_min=1)
    except AssertionError as err:
        assert 'effects-mask' in str(err), ('wrong-mutant-error', str(err))
    else:
        raise AssertionError('effect-mutant-survived')

print('RECEIPTS_V1 PASS cases=7 invariants=5 mutants=1')
