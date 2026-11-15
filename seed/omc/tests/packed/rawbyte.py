#!/usr/bin/env python3
"""Raw memory image of FR-2 packed structs.

Compiles each program with the given omc, runs it, and reads the stack.
The program parks in a loop after the stores. A magic byte string that
endian does not touch marks the image. The bytes after that magic are
compared to the hand-computed image.

Doc: docs/one_layer/FR2-PACKED-STRUCTS.md
  little: bit 0 of the image is the LSB of byte 0; the LSB of the value
  is stored at the first allocated bit.
  big: bit 0 of the image is the MSB of byte 0; the MSB of the value is
  stored at the first allocated bit.
  A multi-byte field is little-endian or big-endian as a whole.
  An 8-bit field on a byte boundary matches a uchar of either endian.
  A 16-bit field on a byte boundary matches a ushort of that endian.
"""
import ctypes, os, sys, time, signal, subprocess, pathlib

libc = ctypes.CDLL("libc.so.6", use_errno=True)
libc.ptrace.restype = ctypes.c_long
libc.ptrace.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p]
PTRACE_TRACEME = 0
PTRACE_SINGLESTEP = 9
PTRACE_DETACH = 17

OMC = sys.argv[1]
ROOT = pathlib.Path(sys.argv[2])
SRC = ROOT / "src"
BIN = ROOT / "bin"
SRC.mkdir(parents=True, exist_ok=True)
BIN.mkdir(parents=True, exist_ok=True)

# magic is eight uchar fields, so endian cannot reorder it
MAG = [0xF2, 0xA1, 0x6E, 0x3C, 0x90, 0xD7, 0x14, 0x58]


def mag_fields():
    return " ".join("m%d uchar" % i for i in range(8))


def mag_vals():
    return " ".join(str(b) for b in MAG)


def program(decl, body):
    return decl + "\nfn main to int\n" + body + "\ni = ulong 0\nwhile eq i 0\ni = ulong 0\nend\nret 0\nend\n"


CASES = []


def add(name, decl, body, payload, wrong=None):
    CASES.append((name, program(decl, body), bytes(payload), None if wrong is None else bytes(wrong)))


# big u32 0x11223344 -> 11 22 33 44
add(
    "big_u32",
    "struct packed big B %s x uint end" % mag_fields(),
    "p = new B %s 287454020\n" % mag_vals(),
    [0x11, 0x22, 0x33, 0x44],
    [0x44, 0x33, 0x22, 0x11],
)
# little u32, the other order
add(
    "little_u32",
    "struct packed little B %s x uint end" % mag_fields(),
    "p = new B %s 287454020\nif ne get p x 287454020\nret 2\nend" % mag_vals(),
    [0x44, 0x33, 0x22, 0x11],
    [0x11, 0x22, 0x33, 0x44],
)
# default endian is little
add(
    "default_u32",
    "struct packed B %s x uint end" % mag_fields(),
    "p = new B %s 287454020\nif ne get p x 287454020\nret 2\nend" % mag_vals(),
    [0x44, 0x33, 0x22, 0x11],
    [0x11, 0x22, 0x33, 0x44],
)
# ushort 0x1122 = 4386
add(
    "big_u16",
    "struct packed big B %s x ushort end" % mag_fields(),
    "p = new B %s 4386\nif ne get p x 4386\nret 2\nend" % mag_vals(),
    [0x11, 0x22],
    [0x22, 0x11],
)
add(
    "little_u16",
    "struct packed B %s x ushort end" % mag_fields(),
    "p = new B %s 4386\n" % mag_vals(),
    [0x22, 0x11],
    [0x11, 0x22],
)
# 16-bit bitfield on a byte boundary matches ushort of that endian
add(
    "big_bits16",
    "struct packed big B %s x uint bits 16 end" % mag_fields(),
    "p = new B %s 4386\nif ne get p x 4386\nret 2\nend" % mag_vals(),
    [0x11, 0x22],
    [0x22, 0x11],
)
add(
    "little_bits16",
    "struct packed B %s x uint bits 16 end" % mag_fields(),
    "p = new B %s 4386\n" % mag_vals(),
    [0x22, 0x11],
    [0x11, 0x22],
)
# 8-bit field on a byte boundary, both endians, value 0xAB
add(
    "bits8",
    "struct packed big B %s x uint bits 8 end" % mag_fields(),
    "p = new B %s 171\nif ne get p x 171\nret 2\nend" % mag_vals(),
    [0xAB],
)
add(
    "bits8_little",
    "struct packed B %s x uint bits 8 end" % mag_fields(),
    "p = new B %s 171\n" % mag_vals(),
    [0xAB],
)
# signed byte -3 is FD
add(
    "signed_byte",
    "struct packed B %s x byte end" % mag_fields(),
    "p = new B %s -3\nif ne get p x -3\nret 2\nend" % mag_vals(),
    [0xFD],
)
# big signed short -128 is FF 80
add(
    "big_short",
    "struct packed big B %s x short end" % mag_fields(),
    "p = new B %s -128\nif ne get p x -128\nret 2\nend" % mag_vals(),
    [0xFF, 0x80],
    [0x80, 0xFF],
)
add(
    "unaligned_after_magic",
    "struct packed U %s a uchar b ushort end" % mag_fields(),
    "p = new U %s 17 8755\nif ne get p a 17\nret 2\nend\nif ne get p b 8755\nret 3\nend" % mag_vals(),
    [0x11, 0x33, 0x22],
    [0x11, 0x22, 0x33],
)
add(
    "unaligned_big",
    "struct packed big U %s a uchar b ushort end" % mag_fields(),
    "p = new U %s 17 8755\nif ne get p b 8755\nret 3\nend" % mag_vals(),
    [0x11, 0x22, 0x33],
    [0x11, 0x33, 0x22],
)
# documented nibbles
add(
    "nibble_little",
    "struct packed F %s a uint bits 4 b uint bits 4 end" % mag_fields(),
    "p = new F %s 1 2\nif ne get p a 1\nret 2\nend\nif ne get p b 2\nret 3\nend" % mag_vals(),
    [0x21],
    [0x12],
)
add(
    "nibble_big",
    "struct packed big F %s a uint bits 4 b uint bits 4 end" % mag_fields(),
    "p = new F %s 1 2\nif ne get p a 1\nret 2\nend\nif ne get p b 2\nret 3\nend" % mag_vals(),
    [0x12],
    [0x21],
)
# 12+4 little: 0xABC=2748, 0xD=13 -> BC DA
add(
    "bits12_little",
    "struct packed G %s a uint bits 12 b uint bits 4 end" % mag_fields(),
    "p = new G %s 2748 13\nif ne get p a 2748\nret 2\nend\nif ne get p b 13\nret 3\nend" % mag_vals(),
    [0xBC, 0xDA],
    [0xAB, 0xCD],
)
# 12+4 big -> AB CD
add(
    "bits12_big",
    "struct packed big G %s a uint bits 12 b uint bits 4 end" % mag_fields(),
    "p = new G %s 2748 13\nif ne get p a 2748\nret 2\nend\nif ne get p b 13\nret 3\nend" % mag_vals(),
    [0xAB, 0xCD],
    [0xBC, 0xDA],
)
# big bit cursor not on a nibble boundary:
# a bits 1 = 0, b bits 3 = 5 (101), c bits 4 = 10 (1010) -> 0x5A
add(
    "big_cursor",
    "struct packed big F %s a uint bits 1 b uint bits 3 c uint bits 4 end" % mag_fields(),
    "p = new F %s 0 5 10\nif ne get p b 5\nret 2\nend\nif ne get p c 10\nret 3\nend" % mag_vals(),
    [0x5A],
)
# signed nibble -3 -> low nibble 0xD, load -3
add(
    "sign_nibble",
    "struct packed S %s a int bits 4 end" % mag_fields(),
    "p = new S %s -3\nif ne get p a -3\nret 2\nend" % mag_vals(),
    [0x0D],
)
# short bits 4 value 15 sign-extends to -1; raw nibble is F
add(
    "sign_short4",
    "struct packed S %s a short bits 4 end" % mag_fields(),
    "p = new S %s 15\nif ne get p a -1\nret 2\nend" % mag_vals(),
    [0x0F],
)
# uint bits 4 value 15 stays 15
add(
    "uns_nibble",
    "struct packed S %s a uint bits 4 end" % mag_fields(),
    "p = new S %s 15\nif ne get p a 15\nret 2\nend" % mag_vals(),
    [0x0F],
)
# 1-bit signed value 1 is -1; raw bit 0 set
add(
    "sign_one",
    "struct packed S %s a short bits 1 end" % mag_fields(),
    "p = new S %s 1\nif ne get p a -1\nret 2\nend" % mag_vals(),
    [0x01],
)
# 20-bit signed, only bit 19 set: raw 00 00 08, load -524288
add(
    "sign_20",
    "struct packed S %s a int bits 20 end" % mag_fields(),
    "p = new S %s 524288\nif ne get p a -524288\nret 2\nend" % mag_vals(),
    [0x00, 0x00, 0x08],
)
# store keeps the low N bits: 0x21 in 4 bits -> 0x01, neighbour nibble stays 2
add(
    "overflow",
    "struct packed S %s a uint bits 4 b uint bits 4 end" % mag_fields(),
    "p = new S %s 33 2\nif ne get p a 1\nret 2\nend\nif ne get p b 2\nret 3\nend" % mag_vals(),
    [0x21],
)
# signed store of 13 in 4 bits loads as -3
add(
    "overflow_sign",
    "struct packed S %s a int bits 4 end" % mag_fields(),
    "p = new S %s 13\nif ne get p a -3\nret 2\nend" % mag_vals(),
    [0x0D],
)
# window: bit then a 64-bit field. little byte0=01, then the ulong
add(
    "window_little",
    "struct packed H %s a uint bits 1 b ulong bits 64 end" % mag_fields(),
    "p = new H %s 1 1234605616436508552\nif ne sizeof H 17\nret 2\nend\nif ne offsetof H b 9\nret 3\nend\nif ne get p a 1\nret 4\nend\nif ne get p b 1234605616436508552\nret 5\nend" % mag_vals(),
    [0x01, 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11],
)
# The magic is 8 bytes, so b is at offset 9 of the image, and sizeof is 17.
# Documented form without the magic is 9. Checked in the edges program.
add(
    "window_big",
    "struct packed big H %s a uint bits 1 b ulong bits 64 end" % mag_fields(),
    "p = new H %s 1 1234605616436508552\nif ne get p a 1\nret 4\nend\nif ne get p b 1234605616436508552\nret 5\nend" % mag_vals(),
    [0x80, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88],
)
# documented window without a magic, scanned as a unique 9-byte image
# f32 1.0
add(
    "f32_little",
    "struct packed P %s a f32 end" % mag_fields(),
    "p = new P %s 1.0\nif ne bitcast uint get p a 1065353216\nret 2\nend" % mag_vals(),
    [0x00, 0x00, 0x80, 0x3F],
    [0x3F, 0x80, 0x00, 0x00],
)
add(
    "f32_big",
    "struct packed big P %s a f32 end" % mag_fields(),
    "p = new P %s 1.0\nif ne bitcast uint get p a 1065353216\nret 2\nend" % mag_vals(),
    [0x3F, 0x80, 0x00, 0x00],
    [0x00, 0x00, 0x80, 0x3F],
)
# f64 1.0 = 0x3FF0000000000000
add(
    "f64_big",
    "struct packed big P %s a f64 end" % mag_fields(),
    "p = new P %s 1.0\n" % mag_vals(),
    [0x3F, 0xF0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
    [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF0, 0x3F],
)
# bool true is the byte 1
add(
    "bool",
    "struct packed B %s a bool end" % mag_fields(),
    "p = new B %s true\nif ne get p a true\nret 2\nend" % mag_vals(),
    [0x01],
)
# padding bits are zero, next byte is a full uchar
add(
    "afterbits",
    "struct packed P %s a uint bits 3 b uchar end" % mag_fields(),
    "p = new P %s 5 127\nif ne get p a 5\nret 2\nend\nif ne get p b 127\nret 3\nend" % mag_vals(),
    [0x05, 0x7F],
)
# array of ushort, big
add(
    "array_big",
    "struct packed big A %s v ushort 2 end" % mag_fields(),
    "p = new A %s 4386\nput p v 1 13124\nif ne get p v 0 4386\nret 2\nend\nif ne get p v 1 13124\nret 3\nend" % mag_vals(),
    [0x11, 0x22, 0x33, 0x44],
)
# 13124 = 0x3344
# ulong at offset 9 crosses a 16-byte line when the base is 16-aligned
# magic 8 + one uchar = offset 9
add(
    "cross16",
    "struct packed K %s a uchar b ulong end" % mag_fields(),
    "p = new K %s 238 72623859790382856\nif ne offsetof K b 9\nret 2\nend\nif ne get p b 72623859790382856\nret 3\nend" % mag_vals(),
    [0xEE, 0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01],
)
# 0x0102030405060708 little is 08 07 06 05 04 03 02 01
# 15 uchars then a ushort sitting on the 16-byte boundary (offset 15 of the
# image is not the slot boundary because of the 8-byte magic). Put the
# ushort at image offset 15: magic 8 + uchar 7 = 15.
add(
    "boundary",
    "struct packed C %s a uchar 7 b ushort end" % mag_fields(),
    "p = new C %s 165 43981\nif ne offsetof C b 15\nret 2\nend\nif ne get p b 43981\nret 3\nend" % mag_vals(),
    [0xA5, 0xA5, 0xA5, 0xA5, 0xA5, 0xA5, 0xA5, 0xCD, 0xAB],
)

# bare images with no magic: the payload is unique enough and is the whole
# struct. Runner searches the stack for the payload itself and requires the
# wrong image to be absent.
BARE = []


def bare(name, decl, body, payload, wrong=None):
    BARE.append((name, program(decl, body), bytes(payload), None if wrong is None else bytes(wrong)))


bare(
    "bare_window",
    "struct packed H a uint bits 1 b ulong bits 64 end",
    "p = new H 1 1234605616436508552\nif ne sizeof H 9\nret 2\nend\nif ne offsetof H b 1\nret 3\nend",
    [0x01, 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11],
)
bare(
    "bare_big_u32",
    "struct packed big B x uint end",
    "p = new B 287454020\n",
    [0x11, 0x22, 0x33, 0x44],
    [0x44, 0x33, 0x22, 0x11],
)
bare(
    "bare_nibble",
    "struct packed F a uint bits 4 b uint bits 4 end",
    "p = new F 1 2",
    [0x21],
    [0x12],
)


def data_maps(pid):
    spans = []
    with open("/proc/%d/maps" % pid) as f:
        for line in f:
            parts = line.split()
            lo, hi = (int(x, 16) for x in parts[0].split("-"))
            perms = parts[1]
            if "r" not in perms or "w" not in perms:
                continue
            # Omega puts the frame in the 8 MiB pool at 0x10000000, not the
            # kernel stack. The kernel stack is not the image.
            if lo == 0x10000000:
                spans.append((lo, hi))
    return spans


def read_stack(pid):
    blob = b""
    mem = os.open("/proc/%d/mem" % pid, os.O_RDONLY)
    try:
        spans = data_maps(pid)
        if not spans:
            return b""
        for lo, hi in spans:
            os.lseek(mem, lo, os.SEEK_SET)
            n = hi - lo
            chunk = b""
            while len(chunk) < n:
                part = os.read(mem, min(1 << 20, n - len(chunk)))
                if not part:
                    break
                chunk += part
            blob += chunk
    finally:
        os.close(mem)
    return blob


def run_case(name, src, payload, wrong, magic):
    sp = SRC / (name + ".om")
    bp = BIN / name
    sp.write_text(src)
    c = subprocess.run([OMC], stdin=open(sp), stdout=open(bp, "wb"), stderr=subprocess.PIPE)
    if c.returncode != 0:
        return "COMPILE %d %s" % (c.returncode, c.stderr[:160])
    os.chmod(bp, 0o755)
    pid = os.fork()
    if pid == 0:
        if libc.ptrace(PTRACE_TRACEME, 0, None, None) != 0:
            os._exit(120)
        os.execv(str(bp), [str(bp)])
        os._exit(121)
    alive = True
    try:
        wpid, status = os.waitpid(pid, 0)
        if os.WIFEXITED(status):
            alive = False
            return "EXIT %d before stop" % os.WEXITSTATUS(status)
        for _ in range(8000):
            if libc.ptrace(PTRACE_SINGLESTEP, pid, None, None) != 0:
                return "STEP errno %d" % ctypes.get_errno()
            wpid, status = os.waitpid(pid, 0)
            if os.WIFEXITED(status):
                alive = False
                return "EXIT %d during step" % os.WEXITSTATUS(status)
            if os.WIFSIGNALED(status):
                alive = False
                return "SIGNAL %d during step" % os.WTERMSIG(status)
        blob = read_stack(pid)
    finally:
        if alive:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            try:
                os.waitpid(pid, 0)
            except ChildProcessError:
                pass
    if magic:
        key = bytes(MAG) + payload
        bad = bytes(MAG) + wrong if wrong is not None else None
        n = blob.count(key)
        nb = blob.count(bad) if bad is not None else 0
        if n < 1:
            if bad is not None and blob.count(bad):
                return "WRONG got %s" % bad.hex()
            return "MISSING image %s" % payload.hex()
        if nb:
            return "WRONG image also present %s" % bad.hex()
        return "OK copies=%d" % n
    n = blob.count(payload)
    if n < 1:
        if wrong is not None and len(wrong) >= 4 and blob.count(wrong):
            return "WRONG bare %s" % wrong.hex()
        return "MISSING bare %s" % payload.hex()
    if wrong is not None and len(wrong) >= 4 and blob.count(wrong):
        return "WRONG bare also %s" % wrong.hex()
    return "OK copies=%d" % n


fails = 0
for name, src, payload, wrong in CASES:
    msg = run_case(name, src, payload, wrong, True)
    print("%s %s" % (name, msg))
    if not msg.startswith("OK"):
        fails += 1
for name, src, payload, wrong in BARE:
    msg = run_case(name, src, payload, wrong, False)
    print("%s %s" % (name, msg))
    if not msg.startswith("OK"):
        fails += 1
print("RAWFAIL %d" % fails)
sys.exit(1 if fails else 0)
