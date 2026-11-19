#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# aienux/spark/mk_qemu_disk.py OUT_IMG WORKDIR:
# Builds the synthetic NVMe disk for the QEMU spark_main e2e gate step (gate-only test data):
#   protective MBR + GPT (UEFI 2.10 §5.3, header + entry-array CRC32, backup header at last LBA)
#   with one Linux-filesystem partition (0FC63DAF-8483-4772-8E79-3D69D8477DE4) holding a 4K-block
#   ext4 (mke2fs -d) that contains /aienos/spark-bundle.img: an OMFWBND1 v1 bundle with kinds 1..6
#   (pseudo-random payloads, real SHA-256 per entry). No NVIDIA firmware bytes are used.
import hashlib, os, struct, subprocess, sys, uuid, zlib, random, shutil

out, work = sys.argv[1], sys.argv[2]
SEC = 512
TOTAL = 131072                  # 64 MiB disk
P_FIRST, P_SECS = 2048, 65536   # 32 MiB partition
P_LAST = P_FIRST + P_SECS - 1

def bundle():
    rng = random.Random(0x5BA4C)
    # kind -> size: gsp.bin, bl.img, fmc.img, fmc.hash, fmc.pubkey, fmc.sig
    ents = [(1, 65536), (2, 212992), (3, 212296), (4, 48), (5, 384), (6, 384)]
    off = 4096
    toc = bytearray(4096)
    toc[0:8] = b"OMFWBND1"
    struct.pack_into("<III", toc, 8, 1, 0x00030000, len(ents))
    body = []
    for i, (kind, size) in enumerate(ents):
        data = bytes(rng.getrandbits(8) for _ in range(size))
        e = 32 + i * 64
        struct.pack_into("<IIQQ", toc, e, kind, 0, off, size)
        toc[e + 32:e + 64] = hashlib.sha256(data).digest()
        body.append((off, data))
        off = (off + size + 4095) & ~4095
    img = bytearray(off)
    img[0:4096] = toc
    for o, d in body:
        img[o:o + len(d)] = d
    return bytes(img)

root = os.path.join(work, "root")
shutil.rmtree(root, ignore_errors=True)
os.makedirs(os.path.join(root, "aienos"))
open(os.path.join(root, "aienos", "spark-bundle.img"), "wb").write(bundle())
part = os.path.join(work, "part.img")
if os.path.exists(part):
    os.remove(part)
mke2fs = shutil.which("mke2fs")
for c in ("/opt/homebrew/bin/mke2fs", "/opt/homebrew/opt/e2fsprogs/sbin/mke2fs", "/sbin/mke2fs", "/usr/sbin/mke2fs"):
    if mke2fs is None and os.path.exists(c):
        mke2fs = c
if mke2fs is None:
    sys.exit("FAIL: mke2fs (e2fsprogs) not found")
env = dict(os.environ, E2FSPROGS_FAKE_TIME="1700000000")
subprocess.run([mke2fs, "-q", "-F", "-t", "ext4", "-b", "4096", "-O", "64bit,extent", "-L", "aienos",
                "-U", "5ba4c000-0000-4000-8000-000000000001", "-E", "root_owner=0:0",
                "-d", root, part, str(P_SECS * SEC // 1024) + "k"], check=True, env=env)
pdata = open(part, "rb").read()
assert len(pdata) == P_SECS * SEC

LINUX_FS = uuid.UUID("0FC63DAF-8483-4772-8E79-3D69D8477DE4").bytes_le
ent = bytearray(128 * 128)
struct.pack_into("<16s16sQQQ", ent, 0, LINUX_FS, uuid.UUID("5ba4c000-0000-4000-8000-000000000002").bytes_le,
                 P_FIRST, P_LAST, 0)
name = "aienos-root".encode("utf-16-le")
ent[56:56 + len(name)] = name
ecrc = zlib.crc32(bytes(ent)) & 0xffffffff
disk_guid = uuid.UUID("5ba4c000-0000-4000-8000-000000000003").bytes_le

def hdr(my, alt, ent_lba):
    h = bytearray(92)
    struct.pack_into("<8sIIIIQQQQ16sQIII", h, 0, b"EFI PART", 0x00010000, 92, 0, 0,
                     my, alt, 34, TOTAL - 34, disk_guid, ent_lba, 128, 128, ecrc)
    struct.pack_into("<I", h, 16, zlib.crc32(bytes(h)) & 0xffffffff)
    return bytes(h)

img = bytearray(TOTAL * SEC)
mbr = bytearray(512)
struct.pack_into("<B3sB3sII", mbr, 446, 0, b"\x00\x02\x00", 0xEE, b"\xff\xff\xff", 1, TOTAL - 1)
mbr[510:512] = b"\x55\xaa"
img[0:512] = mbr
img[SEC:SEC + 92] = hdr(1, TOTAL - 1, 2)
img[2 * SEC:2 * SEC + len(ent)] = ent
img[(TOTAL - 33) * SEC:(TOTAL - 1) * SEC] = ent
img[(TOTAL - 1) * SEC:(TOTAL - 1) * SEC + 92] = hdr(TOTAL - 1, 1, TOTAL - 33)
img[P_FIRST * SEC:P_FIRST * SEC + len(pdata)] = pdata
open(out, "wb").write(img)
print("PASS mk_qemu_disk: %s (GPT linux-fs part LBA %d+%d, ext4 4K, /aienos/spark-bundle.img %d B)"
      % (out, P_FIRST, P_SECS, os.path.getsize(os.path.join(root, "aienos", "spark-bundle.img"))))
