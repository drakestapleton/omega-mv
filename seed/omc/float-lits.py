#!/usr/bin/env python3
"""Float literal oracle for omc (OMEGESE 9.9, omega-mv#1024).

The oracle rounds the literal's exact rational value (fractions.Fraction) once to nearest even in
binary32 or binary64; binary64 results are also checked against Python's float(). It never reads
omc's answer to build an expectation.

  float-lits.py table             rewrite tests/float/lit_round.om and lit_round.want (fixed cases)
  float-lits.py diff OMC N SEED   compile N random literals with OMC and compare every bit pattern

diff prints FLOATDIFF PASS|FAIL total=N f64=.. f32=.. overflow=.. mismatch=.. and exits 0 only on PASS.
"""
import os
import random
import struct
import subprocess
import sys
import tempfile
from fractions import Fraction

FMT = {"f64": (53, -1022, 1023, 64), "f32": (24, -126, 127, 32)}
MAXND = 2**63 - 1


def value(lit):
    """The exact rational value of an omc float literal; None if omc must refuse its digits."""
    s = lit
    neg = s.startswith("-")
    if neg:
        s = s[1:]
    mant, _, ex = s.replace("E", "e").partition("e")
    whole, _, frac = mant.partition(".")
    digits = int(whole + frac)
    if digits > MAXND:
        return None
    p10 = (int(ex) if ex else 0) - len(frac)
    v = Fraction(digits) * Fraction(10) ** p10
    return (neg, v)


def rne(neg, x, ty):
    """IEEE bits of x rounded once to nearest even; None when it rounds to infinity."""
    p, emin, emax, w = FMT[ty]
    sign = (1 << (w - 1)) if neg else 0
    if x == 0:
        return sign
    e = x.numerator.bit_length() - x.denominator.bit_length()
    if x < Fraction(2) ** e:
        e -= 1
    e = max(e, emin)
    m = x / Fraction(2) ** (e - (p - 1))
    q = m.numerator // m.denominator
    r = m - q
    if r > Fraction(1, 2) or (r == Fraction(1, 2) and q & 1):
        q += 1
    if q == 1 << p:
        q >>= 1
        e += 1
    if e > emax:
        return None
    if q < 1 << (p - 1):
        return sign | q
    return sign | ((e + (1 << (w - p - 1)) - 1) << (p - 1)) | (q - (1 << (p - 1)))


def expect(lit, ty):
    v = value(lit)
    if v is None:
        return None
    bits = rne(v[0], v[1], ty)
    if ty == "f64":
        try:
            ref = struct.unpack("<Q", struct.pack("<d", float(lit)))[0]
        except OverflowError:
            ref = None
        if ref is not None and ref >> 52 & 2047 == 2047:
            ref = None
        assert bits == ref, (lit, bits, ref)
    return bits


def program(lits):
    """One omc program: the bits of every literal, eight bytes each, little-endian, on stdout."""
    n = len(lits)
    out = ["global g ulong %d" % n, "fn main to int"]
    for i, (lit, ty) in enumerate(lits):
        if ty == "f64":
            out.append("put g %d bitcast ulong f64 %s" % (i, lit))
        else:
            out.append("put g %d ulong bitcast uint f32 %s" % (i, lit))
    out += [
        "b = new uchar %d 0" % (8 * n),
        "for i ulong %d" % n,
        "v = get g i",
        "for j ulong 8",
        "put b add mul i 8 j uchar and shr v mul j 8 255",
        "end",
        "end",
        "n = write 1 b 0 %d" % (8 * n),
        "ret 0",
        "end",
    ]
    return "\n".join(out) + "\n"


def digits_lit(rng, nd, p10, neg):
    """A literal of nd significant digits whose value is D * 10^p10, written in a random style."""
    while True:
        d = rng.randrange(10 ** (nd - 1), 10**nd)
        if d <= MAXND:
            break
    s = str(d)
    style = rng.randrange(4)
    if style == 0:
        k = rng.randrange(1, len(s)) if len(s) > 1 else 1
        lit = s[:k] + "." + (s[k:] or "0") + "e" + str(p10 + len(s) - k)
    elif style == 1:
        lit = s + "e" + str(p10)
    elif style == 2:
        z = rng.randrange(0, 30)
        lit = "0." + "0" * z + s + "E" + str(p10 + len(s) + z)
    else:
        x = p10 + len(s) - 1
        lit = s[0] + "." + (s[1:] or "0") + "e" + ("+" if x >= 0 and rng.randrange(2) else "") + str(x)
    return ("-" if neg else "") + lit


def halfway_lit(rng, ty, neg):
    """A literal within one 19th digit of the midpoint between two neighbouring floats."""
    p, emin, emax, w = FMT[ty]
    e = rng.randrange(emin - p, emax)
    if e < emin:
        q = rng.randrange(1, 1 << (p - 1))
        m = Fraction(2 * q + 1) * Fraction(2) ** (emin - p)
    else:
        q = rng.randrange(1 << (p - 1), (1 << p) - 1)
        m = Fraction(2 * q + 1) * Fraction(2) ** (e - p)
    k = 0
    t = m
    while t >= 10:
        t /= 10
        k += 1
    while t < 1:
        t *= 10
        k -= 1
    nd = rng.randrange(16, 20)
    scaled = m / Fraction(10) ** (k - nd + 1)
    d = scaled.numerator // scaled.denominator + rng.choice((-1, 0, 0, 1, 2))
    if d < 1 or d > MAXND:
        d = scaled.numerator // scaled.denominator
    if d > MAXND:
        d //= 10
        k += 1
    return ("-" if neg else "") + "%de%d" % (d, k - nd + 1)


def random_lits(rng, n):
    out = []
    for _ in range(n):
        ty = "f64" if rng.randrange(3) else "f32"
        neg = rng.randrange(5) == 0
        kind = rng.randrange(10)
        if kind < 4:
            out.append((halfway_lit(rng, ty, neg), ty))
            continue
        nd = rng.randrange(1, 20)
        if ty == "f64":
            p10 = rng.randrange(-345 - nd, 310 - nd)
        else:
            p10 = rng.randrange(-47 - nd, 40 - nd)
        if kind == 9:
            p10 = rng.randrange(-30, 30)
        out.append((digits_lit(rng, nd, p10, neg), ty))
    return out


def run_omc(omc, lits, tmp):
    src = os.path.join(tmp, "p.om")
    exe = os.path.join(tmp, "p")
    with open(src, "w") as f:
        f.write(program(lits))
    with open(src) as fi, open(exe, "wb") as fo:
        r = subprocess.run([omc], stdin=fi, stdout=fo, stderr=subprocess.PIPE)
    if r.returncode != 0:
        return None, r.returncode, r.stderr.decode()
    os.chmod(exe, 0o700)
    r = subprocess.run([exe], stdout=subprocess.PIPE)
    if r.returncode != 0:
        raise SystemExit("FLOATDIFF INVALID program exit %d" % r.returncode)
    return struct.unpack("<%dQ" % len(lits), r.stdout), 0, ""


def one_refusal(omc, lit, ty, tmp):
    """The compiler status for a program holding only this literal (expected: error 8)."""
    _, rc, err = run_omc(omc, [(lit, ty)], tmp)
    return rc, err


def diff(omc, total, seed):
    rng = random.Random(seed)
    lits = random_lits(rng, total)
    cnt = {"f64": 0, "f32": 0, "overflow": 0, "mismatch": 0}
    good = []
    with tempfile.TemporaryDirectory() as tmp:
        for lit, ty in lits:
            if expect(lit, ty) is None:
                cnt["overflow"] += 1
                if cnt["overflow"] <= 200:
                    rc, err = one_refusal(omc, lit, ty, tmp)
                    if rc != 8:
                        cnt["mismatch"] += 1
                        print("MISMATCH %s %s refused rc=%d %s" % (ty, lit, rc, err.strip()))
            else:
                good.append((lit, ty))
        for i in range(0, len(good), 2000):
            batch = good[i : i + 2000]
            got, rc, err = run_omc(omc, batch, tmp)
            if got is None:
                raise SystemExit("FLOATDIFF INVALID compile rc=%d %s" % (rc, err.strip()))
            for (lit, ty), g in zip(batch, got):
                cnt[ty] += 1
                want = expect(lit, ty)
                if g != want:
                    cnt["mismatch"] += 1
                    if cnt["mismatch"] <= 40:
                        print("MISMATCH %s %s got %x want %x" % (ty, lit, g, want))
    ok = cnt["mismatch"] == 0 and cnt["f64"] + cnt["f32"] + cnt["overflow"] == total
    print(
        "FLOATDIFF %s total=%d f64=%d f32=%d overflow=%d overflow_checked=%d mismatch=%d seed=%d"
        % ("PASS" if ok else "FAIL", total, cnt["f64"], cnt["f32"], cnt["overflow"],
           min(cnt["overflow"], 200), cnt["mismatch"], seed)
    )
    return 0 if ok else 1


# Fixed cases: #1024's two literals, halfway and subnormal boundaries, both ends of the range,
# 19-digit significands and long fractions. Each row is (literal, type).
TABLE = [
    ("6816.702656e-27", "f64"),
    ("2.4703282292062328e-324", "f64"),
    ("2.4703282292062327e-324", "f64"),
    ("2.470328229206232720e-324", "f64"),
    ("2.470328229206232721e-324", "f64"),
    ("4.9406564584124654e-324", "f64"),
    ("7.4109846876186981e-324", "f64"),
    ("2.2250738585072011e-308", "f64"),
    ("2.2250738585072012e-308", "f64"),
    ("2.2250738585072014e-308", "f64"),
    ("1.7976931348623157e308", "f64"),
    ("1.7976931348623158e308", "f64"),
    ("9007199254740993.0", "f64"),
    ("9007199254740993.001", "f64"),
    ("9007199254740992.999", "f64"),
    ("9007199254740995.0", "f64"),
    ("4503599627370496.5", "f64"),
    ("4503599627370497.5", "f64"),
    ("1.000000000000000111e0", "f64"),
    ("1.000000000000000110e0", "f64"),
    ("0.1", "f64"),
    ("0.3", "f64"),
    ("123456789012345678e-20", "f64"),
    ("9223372036854775807e-342", "f64"),
    ("9223372036854775807e289", "f64"),
    ("8.98846567431158e307", "f64"),
    ("5.0e-324", "f64"),
    ("4.9e-324", "f64"),
    ("1e-999", "f64"),
    ("-1e-999", "f64"),
    ("0.000000000000000000000000000000000000000000000000000001e-270", "f64"),
    ("1e23", "f64"),
    ("8.533e-308", "f64"),
    ("3.4028234663852886e38", "f32"),
    ("3.4028235677973366e38", "f32"),
    ("1.1754943508222875e-38", "f32"),
    ("1.1754942807573643e-38", "f32"),
    ("1.1754942807573644e-38", "f32"),
    ("1.4012984643248171e-45", "f32"),
    ("7.0064923216240854e-46", "f32"),
    ("7.0064923216240853e-46", "f32"),
    ("16777217.0", "f32"),
    ("16777217.000000001", "f32"),
    ("16777219.0", "f32"),
    ("0.1", "f32"),
    ("1.000000059604644776", "f32"),
    ("1.000000059604644775", "f32"),
    ("-2.718281828459045235", "f32"),
    ("6816.702656e-27", "f32"),
]


def table():
    here = os.path.dirname(os.path.abspath(__file__))
    t = os.path.join(here, "tests", "float")
    rng = random.Random(1024)
    rows = list(TABLE)
    while len(rows) < 512:
        ty = "f64" if len(rows) % 3 else "f32"
        lit = halfway_lit(rng, ty, rng.randrange(4) == 0)
        if expect(lit, ty) is not None:
            rows.append((lit, ty))
    for lit, ty in rows:
        assert expect(lit, ty) is not None, lit
    with open(os.path.join(t, "lit_round.om"), "w") as f:
        f.write("note generated by seed/omc/float-lits.py table: 512 literals (omega-mv#1024); expected\n")
        f.write("note bits are in lit_round.want, computed by the script's exact rational oracle.\n")
        f.write(program(rows))
    with open(os.path.join(t, "lit_round.want"), "w") as f:
        for lit, ty in rows:
            f.write("%016x %s %s\n" % (expect(lit, ty), ty, lit))
    print("wrote %d rows" % len(rows))


if __name__ == "__main__":
    if sys.argv[1:2] == ["table"]:
        table()
    elif sys.argv[1:2] == ["diff"] and len(sys.argv) == 5:
        sys.exit(diff(sys.argv[2], int(sys.argv[3]), int(sys.argv[4])))
    else:
        sys.exit(__doc__)
