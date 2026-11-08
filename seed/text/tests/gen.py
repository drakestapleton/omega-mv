#!/usr/bin/env python3
"""Cases and independent expectations for seed/text (test harness only, never part of Omega).

  gen.py OUTDIR    write OUTDIR/cases-K.bin and OUTDIR/want-K.txt, K = 0, 1, ...

Expectations come from Python itself, never from the Omega code under test: bytes ==, the ordering
of bytes objects, bytes.find, bytes.split, int() on strict [0-9]+ / [0-9a-fA-F]+ text with explicit
range limits, format(), and bytes.decode('utf-8') whose UnicodeDecodeError.start is the first byte
of the first ill-formed sequence (RFC 3629 section 4: overlong forms, surrogates D800..DFFF and values
above 10FFFF are ill-formed). UTF-8 coverage: every 1- and 2-byte string, every 3-byte string with a
lead byte E0..EF, every 4-byte string with lead F0..F4 and second byte 80..BF over a fixed sample of
third and fourth bytes, and seeded random mixes. Record layout (txdrv.om): op byte; byte strings as
u32 LE length + bytes; numbers u64 LE.
"""
import os
import random
import re
import struct
import sys

sys.set_int_max_str_digits(0)

LIMIT = 2_900_000          # bytes per cases file (txdrv reads up to 3 MiB)
U64 = (1 << 64) - 1


class Out:
    def __init__(self, d):
        self.d, self.k, self.buf, self.want = d, 0, bytearray(), []

    def add(self, rec, line):
        if len(self.buf) + len(rec) > LIMIT:
            self.flush()
        self.buf += rec
        self.want.append(line)

    def flush(self):
        if not self.buf:
            return
        with open(os.path.join(self.d, f"cases-{self.k}.bin"), "wb") as f:
            f.write(self.buf)
        with open(os.path.join(self.d, f"want-{self.k}.txt"), "w") as f:
            f.write("".join(x + "\n" for x in self.want))
        self.k, self.buf, self.want = self.k + 1, bytearray(), []


def s(b):
    return struct.pack("<I", len(b)) + b


def n(v):
    return struct.pack("<Q", v & U64)


def cmp_case(o, a, b):
    c = (a > b) - (a < b)
    o.add(b"E" + s(a) + s(b), f"E {int(a == b)} {c}")


def find_case(o, h, nd, frm):
    r = -1 if frm > len(h) else h.find(nd, frm)
    o.add(b"F" + s(h) + s(nd) + n(frm), "F n" if r < 0 else f"F {r}")


def split_case(o, t, sep):
    parts = t.split(bytes([sep]))
    o.add(b"S" + s(t) + bytes([sep]), "S " + " ".join([str(len(parts))] + [str(len(p)) for p in parts]))


def parse(t, op):
    if not t:
        return "err 1"
    if op == "D":
        ok, v, lo, hi = re.fullmatch(rb"[0-9]+", t), None, 0, U64
    elif op == "H":
        ok, lo, hi = re.fullmatch(rb"[0-9a-fA-F]+", t), 0, U64
    else:
        ok, lo, hi = re.fullmatch(rb"-?[0-9]+", t), -(1 << 63), (1 << 63) - 1
    if not ok:
        return "err 2"
    v = int(t, 16 if op == "H" else 10)
    if v < lo or v > hi:
        return "err 3"
    return f"ok {v}"


def parse_case(o, t, op):
    o.add(op.encode() + s(t), f"{op} {parse(t, op)}")


def fmt_case(o, op, v, w, cap):
    if op == "f":
        txt = str(v)
    elif op == "g":
        txt = str(v)
    else:
        txt = format(v, "x").rjust(w, "0")
    line = f"{op} E" if len(txt) > cap else f"{op} {txt}"
    o.add(op.encode() + n(v) + n(w) + n(cap), line)


def u8(b):
    try:
        b.decode("utf-8")
        return len(b)
    except UnicodeDecodeError as e:
        return e.start


def u8_case(o, b):
    o.add(b"U" + s(b), f"U {u8(b)}")


def dec(b):
    for k in range(1, min(4, len(b)) + 1):
        try:
            t = b[:k].decode("utf-8")
        except UnicodeDecodeError as e:
            if e.start > 0 or e.reason != "unexpected end of data":
                return None
            continue
        return ord(t), k
    return None


def dec_case(o, b):
    r = dec(b)
    o.add(b"P" + s(b), "P n" if r is None else f"P {r[0]} {r[1]}")


def enc_case(o, cp, cap):
    if cp > 0x10FFFF or 0xD800 <= cp <= 0xDFFF:
        line = "Q R"
    else:
        e = chr(cp).encode("utf-8")
        line = "Q E" if len(e) > cap else "Q " + e.hex()
    o.add(b"Q" + n(cp) + n(cap), line)


def main(d):
    rnd = random.Random(20261108)
    o = Out(d)
    # bytes: equality and order, including bytes above 127 and chunk-crossing lengths
    for _ in range(3000):
        a = bytes(rnd.choice(b"ab\x7f\x80\xff") for _ in range(rnd.randrange(0, 9)))
        b = a if rnd.random() < 0.3 else bytes(rnd.choice(b"ab\x7f\x80\xff") for _ in range(rnd.randrange(0, 9)))
        cmp_case(o, a, b)
    big = bytes(rnd.randrange(256) for _ in range(200_000))
    cmp_case(o, big, big)
    for at in (0, 65535, 65536, 65537, 131072, 199_999):
        m = bytearray(big); m[at] ^= 0x80
        cmp_case(o, big, bytes(m))
    cmp_case(o, big, big[:-1]); cmp_case(o, big[:-1], big); cmp_case(o, b"", b"")
    # search
    for _ in range(3000):
        h = bytes(rnd.choice(b"ab") for _ in range(rnd.randrange(0, 12)))
        nd = bytes(rnd.choice(b"ab") for _ in range(rnd.randrange(0, 4)))
        find_case(o, h, nd, rnd.randrange(0, 14))
    hay = bytes(rnd.choice(b"ab") for _ in range(250_000)) + b"needle" + b"a" * 10
    for frm in (0, 65536, 250_000, 250_001, len(hay) - 6, len(hay), len(hay) + 1):
        find_case(o, hay, b"needle", frm)
    find_case(o, hay, b"", len(hay)); find_case(o, b"", b"", 0); find_case(o, b"", b"", 1)
    find_case(o, hay, b"needlex", 0)
    # fields
    for _ in range(2000):
        t = bytes(rnd.choice(b"a,") for _ in range(rnd.randrange(0, 12)))
        split_case(o, t, ord(","))
    split_case(o, b"a" * 140_000 + b"," + b"b" * 3, ord(","))
    # integer text
    edges = [b"", b"0", b"00", b"1", b"18446744073709551615", b"18446744073709551616",
             b"18446744073709551619", b"18446744073709551620", b"99999999999999999999",
             b"000000000000000000000018446744073709551615", b"1x", b"x", b" 1", b"1 ", b"+1",
             b"-", b"-0", b"-1", b"9223372036854775807", b"9223372036854775808",
             b"-9223372036854775808", b"-9223372036854775809", b"--1", b"1-",
             b"ffffffffffffffff", b"FFFFFFFFFFFFFFFF", b"10000000000000000", b"0fffffffffffffffF",
             b"g", b"0x10", b"99999999999999999999x", b"0" * 100_000 + b"7"]
    for t in edges:
        for op in "DHI":
            parse_case(o, t, op)
    for _ in range(4000):
        k = rnd.randrange(1, 23)
        t = bytes(rnd.choice(b"0123456789abcdefABCDEF-+ ") if rnd.random() < 0.05 else rnd.choice(b"0123456789") for _ in range(k))
        for op in "DHI":
            parse_case(o, t, op)
    for v in [0, 1, 9, 10, 99, 100, U64, U64 - 1, 1 << 63, (1 << 63) - 1] + [rnd.randrange(1 << 64) for _ in range(2000)]:
        for cap in (0, 1, len(str(v)) - 1, len(str(v)), 20, 64):
            if 0 <= cap <= 64:
                fmt_case(o, "f", v, 0, cap)
        for w in (0, 1, 8, 16):
            for cap in (len(format(v, "x").rjust(w, "0")) - 1, 16, 64):
                if 0 <= cap <= 64:
                    fmt_case(o, "x", v, w, cap)
    for v in [0, -1, 1, -(1 << 63), (1 << 63) - 1, -(1 << 63) + 1] + [rnd.randrange(-(1 << 63), 1 << 63) for _ in range(2000)]:
        for cap in (len(str(v)) - 1, len(str(v)), 64):
            if 0 <= cap <= 64:
                fmt_case(o, "g", v, 0, cap)
    # UTF-8
    for a in range(256):
        u8_case(o, bytes([a]))
    for a in range(256):
        for b in range(256):
            u8_case(o, bytes([a, b]))
    for a in range(0xE0, 0xF0):
        for b in range(256):
            for c in range(256):
                u8_case(o, bytes([a, b, c]))
    third = [0x00, 0x7F, 0x80, 0x8F, 0x90, 0xA0, 0xBF, 0xC0, 0xFF]
    for a in range(0xF0, 0xF5):
        for b in range(0x80, 0xC0):
            for c in third:
                for e in third:
                    u8_case(o, bytes([a, b, c, e]))
    for _ in range(20000):
        cps = [rnd.choice([rnd.randrange(0x80), rnd.randrange(0x80, 0x800), rnd.randrange(0x800, 0xD800),
                           rnd.randrange(0xE000, 0x10000), rnd.randrange(0x10000, 0x110000)]) for _ in range(rnd.randrange(0, 6))]
        b = bytearray("".join(map(chr, cps)).encode())
        if b and rnd.random() < 0.5:
            b[rnd.randrange(len(b))] = rnd.randrange(256)
        if b and rnd.random() < 0.2:
            b = b[:rnd.randrange(len(b))]
        u8_case(o, bytes(b))
    u8_case(o, ("é" * 100_000).encode() + b"\xed\xa0\x80")
    # code points: decode every 1- and 2-byte string, every 3-byte string led by E0, E1, ED, EF,
    # sampled 4-byte strings and random mixes; encode edges, the surrogate band, a stride of all
    # code points, values past 10FFFF, and every room size 0..4.
    for a in range(256):
        dec_case(o, bytes([a]))
        for b2 in range(256):
            dec_case(o, bytes([a, b2]))
    for a in (0xE0, 0xE1, 0xE8, 0xED, 0xEF):
        for b2 in range(256):
            for c in range(256):
                dec_case(o, bytes([a, b2, c]))
    for a in range(0xF0, 0xF8):
        for b2 in range(0x80, 0xC0):
            for c in third:
                for e in third:
                    dec_case(o, bytes([a, b2, c, e]) + b"x")
    for _ in range(20000):
        cps = [rnd.randrange(0x110000) for _ in range(rnd.randrange(1, 3))]
        bb = "".join(chr(x) for x in cps if not 0xD800 <= x <= 0xDFFF).encode() or b"a"
        dec_case(o, bb[:rnd.randrange(1, len(bb) + 1)])
    edges = [0, 0x7F, 0x80, 0x7FF, 0x800, 0xFFFF, 0x10000, 0x10FFFF, 0x110000, 1 << 32, U64]
    for cp in edges + list(range(0xD700, 0xE100)) + list(range(0, 0x110000, 7)):
        enc_case(o, cp, 4)
    for cp in edges:
        for cap in range(5):
            enc_case(o, cp, cap)
    o.flush()
    print(f"cases files={o.k}")


if __name__ == "__main__":
    main(sys.argv[1])
