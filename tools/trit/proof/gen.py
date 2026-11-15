#!/usr/bin/env python3
"""gen.py ROOT N SEED CODEBOOK.tsv -- write N random fixture dirs ROOT/<i>/inbox/... for difftest.sh.
ASCII only. Lines mix valid/invalid timestamps, senders, tags, STOP near-misses, 5/6-field formats,
pipes inside text, emergency floods (4-7 lines from one sender inside 30 min), codebook-signed lines
(ocb2 over lane|ts|from|to|tag|text|ref, plus leftover ocb1, retargeted `to`, edited text/tag/ref/ts,
tampered digits/sender/MAC, wrong codebook id, replayed copies, stale and malformed counter files,
unknown codes, bad counters, ts-regress against a stored last ts), headers, blank and partial lines;
cursors are absent, valid (sha256 of the whole prefix, via hashlib), wrong-hash, garbage, past EOF,
mid-line with a matching prefix hash, or offset 0. Keys are mode 0600 and live outside boards/."""
import hashlib, hmac, os, random, shutil, sys

root, n, seed = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
CBT = sys.argv[4]  # tools/codebook/codebook.tsv
CBB = open(CBT, "rb").read(); CS = hashlib.sha256(CBB).hexdigest()
KEY = None
R = random.Random(seed)

def ts():
    r = R.random()
    if r < 0.08: return R.choice(["2026-11-15T25:00", "2026-13-15T12:00", "2026-11-15T12", "garbage-line", "0000-01-01T00:00", "2026-11-15T12:7x"])
    if r < 0.12: return R.choice(["2026-12-31T23:", "2027-01-01T00:"]) + "%02d" % R.randrange(60)
    return "2026-11-15T%02d:%02d" % (R.choice([11, 12, 12, 13]), R.randrange(60))

def mac_msg(lane, fields, ctr, digs, cs):
    # fields: ts, from, to, tag, text, ref
    ts_, frm, to, tag, text, ref = fields
    return "ocb2|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % (cs, ctr, lane, ts_, frm, to, tag, text, ref, digs)

def sig(fields, lane, legacy=False):
    CT[0] += R.choice([1, 1, 1, 2, -1, 0])
    ctr = str(max(CT[0], 0)) if R.random() < 0.9 else R.choice(["0", "01", "x", "1234567890123456789"])
    digs = R.choice(["300", "300", "301", "310", "100", "101", "000001", "", "303002", "900300", "30", "400", "3a0"])
    fs = list(fields)
    if R.random() >= 0.9:
        fs[1] = R.choice(["drake", "b", "mallory"])
    cs = CS if R.random() < 0.93 else hashlib.sha256(b"other").hexdigest()
    if legacy:
        mac = hmac.new(KEY, ("%s|%s|%s|%s" % (fs[1], CS, ctr, digs)).encode(), hashlib.sha256).hexdigest()
        pref = "ocb1"
    else:
        mac = hmac.new(KEY, mac_msg(lane, fs, ctr, digs, CS).encode(), hashlib.sha256).hexdigest()
        pref = "ocb2"
    r = R.random()
    if r < 0.08: mac = mac[:5] + ("0" if mac[5] != "0" else "1") + mac[6:]
    elif r < 0.12 and digs: digs = digs[:-1] + ("1" if digs[-1] != "1" else "2")
    elif r < 0.14: mac = mac[:63]
    elif r < 0.16: mac = mac.upper()
    return "ocb%s:%s:%s:%s:%s" % (pref[3:], cs, ctr, digs, mac) + (":x" if R.random() < 0.02 else "")

def line(emerg, force=None):
    sender = R.choice(["drake", "drake", "b", "six-sigma", "mallory", "a", "Drake", "../x", "", "drake-bot"] if emerg else ["drake-bot", "x", "six-sigma"])
    tag = R.choice(["turn", "fyi", "stop", "fail", "task", "STOP", "alert", "fyi"])
    text = R.choice(["do x", "STOP", "STOP now", "STOP:x", "STOPWATCH", "stop", "", "a|b", "STOP|x", "note"])
    ref = R.choice(["-", "-", "STOP.md", "/p/q"])
    to = "a" if R.random() < 0.85 else R.choice(["b", "x", "six-sigma"])
    lane = "e" if emerg else "n"
    signed = force in ("valid", "retarget", "edit-text", "edit-tag", "edit-ref", "edit-ts", "ocb1", "lane") or R.random() < 0.45
    if signed or R.random() < 0.5 or force:
        f = [ts(), sender, to, tag, text, ref]
        if force == "valid":
            f = ["2026-11-15T12:%02d" % R.randrange(60), "drake" if emerg else "drake-bot", "a", "alert" if emerg else "task", "do x", "-"]
            CT[0] += 1
            ctr = str(max(CT[0], 1))
            digs = "300"
            mac = hmac.new(KEY, mac_msg(lane, f, ctr, digs, CS).encode(), hashlib.sha256).hexdigest()
            return "|".join(f + ["ocb2:%s:%s:%s:%s" % (CS, ctr, digs, mac)])
        if force == "ocb1":
            f = ["2026-11-15T12:00", "drake" if emerg else "drake-bot", "a", "alert", "do x", "-"]
            CT[0] += 1
            ctr = str(max(CT[0], 1))
            digs = "300"
            mac = hmac.new(KEY, ("%s|%s|%s|%s" % (f[1], CS, ctr, digs)).encode(), hashlib.sha256).hexdigest()
            return "|".join(f + ["ocb1:%s:%s:%s:%s" % (CS, ctr, digs, mac)])
        s = sig(f, lane, legacy=(force == "ocb1" or R.random() < 0.06))
        if force == "retarget" or (force is None and R.random() < 0.04):
            f[2] = "b" if f[2] != "b" else "x"
        elif force == "edit-text" or (force is None and R.random() < 0.04):
            f[4] = f[4] + "x"
        elif force == "edit-tag" or (force is None and R.random() < 0.03):
            f[3] = "fyi" if f[3] != "fyi" else "turn"
        elif force == "edit-ref" or (force is None and R.random() < 0.03):
            f[5] = "edited-ref"
        elif force == "edit-ts" or (force is None and R.random() < 0.03):
            f[0] = "2026-11-15T00:00"
        elif force == "lane":
            # sign with the other lane so the file's lane fails the MAC
            s = sig(f, "n" if lane == "e" else "e")
        return "|".join(f + [s])
    return "|".join([ts(), sender, tag, text, ref] if R.random() < 0.7 else [ts(), sender, to, tag, text, ref])

CT = [1]

def flood():
    who = R.choice(["drake", "b", "six-sigma"])
    base = R.randrange(0, 40)
    out = []
    for j in range(R.randrange(4, 8)):
        f = ["2026-11-15T12:%02d" % (base + 3 * j + R.randrange(3)), who, "a", R.choice(["alert", "fyi", "stop"]), "flood %d" % j, "-"]
        l = "|".join(f)
        if R.random() < 0.7: l += "|" + sig(f, "e")
        out.append(l)
        if R.random() < 0.2: out.append(l)
    return out

def body(emerg, extras=None):
    out = []
    if R.random() < 0.2: out.append("# Inbox: a")
    if emerg and R.random() < 0.25: out += flood()
    for _ in range(R.randrange(0, 7)):
        out.append("" if R.random() < 0.05 else line(emerg))
        if out and R.random() < 0.1: out.append(R.choice(out))
    if extras:
        out.extend(extras)
    s = "".join(x + "\n" for x in out)
    if R.random() < 0.15: s += line(emerg)[: R.randrange(1, 30)]
    return s

def cursor(content):
    b = content.encode()
    ends = [i + 1 for i, c in enumerate(b) if c == 10]
    r = R.random()
    if r < 0.35 or not ends: return None
    off = R.choice(ends)
    good = hashlib.sha256(b[:off]).hexdigest()
    if r < 0.70: return "%d %s\n" % (off, good)
    if r < 0.78: return "%d %s\n" % (off, hashlib.sha256(b[:off] + b"x").hexdigest())
    if r < 0.82: return "garbage\n"
    if r < 0.86: return "%d %s\n" % (len(b) + R.randrange(1, 50), good)
    if r < 0.92 and off > 1: return "%d %s\n" % (off - 1, hashlib.sha256(b[:off - 1]).hexdigest())
    if r < 0.96: return "0 %s\n" % hashlib.sha256(b"").hexdigest()
    return "%d %s" % (off, good)[:R.randrange(10, 60)]

KINDS = ["valid", "retarget", "edit-text", "edit-tag", "edit-ref", "edit-ts", "ocb1", "lane"]

for i in range(n):
    d = os.path.join(root, str(i), "inbox"); os.makedirs(d)
    KEY = bytes(R.getrandbits(8) for _ in range(R.choice([16, 32, 64, 65, 100])))
    CT[0] = R.randrange(0, 4)
    if R.random() < 0.9:
        os.makedirs(os.path.join(root, str(i), "codebook"))
        shutil.copyfile(CBT, os.path.join(root, str(i), "codebook", "codebook.tsv"))
        if R.random() < 0.95:
            kp = os.path.join(root, str(i), "codebook", "key")
            open(kp, "wb").write(KEY)
            os.chmod(kp, 0o600)
    for snd in ["drake", "drake-bot", "x", "b", "six-sigma"]:
        r = R.random()
        if r < 0.20:
            open(os.path.join(d, "a.%s.ctr" % snd), "w").write("%d 2026-11-15T12:%02d\n" % (R.randrange(0, 5), R.randrange(60)))
        elif r < 0.25:
            open(os.path.join(d, "a.%s.ctr" % snd), "w").write("%d\n" % R.randrange(0, 5))
        elif r < 0.28:
            open(os.path.join(d, "a.%s.ctr" % snd), "w").write(R.choice(["junk\n", "", "\n", "3"]))
    for other in ["b", "six-sigma"]:
        if R.random() < 0.4: open(os.path.join(d, other + ".md"), "w").close()
    kinds = [KINDS[i % len(KINDS)], KINDS[(i * 3) % len(KINDS)]] if KEY is not None and R.random() < 0.55 else []
    for name, emerg, p in [("a.md", False, 0.85), ("a.emergency.md", True, 0.6)]:
        if R.random() < p:
            extras = [line(emerg, force=k) for k in kinds] if kinds and not emerg else None
            c = body(emerg, extras)
            open(os.path.join(d, name), "w").write(c)
            cur = cursor(c)
            if cur is not None: open(os.path.join(d, name + ".cur"), "w").write(cur)
