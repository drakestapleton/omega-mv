#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Host verification suite for Slice D (Piece 4: RO NVMe + GPT + ext4 + SHA-256 + RTL8127/TCP + a64efi).
# Strictly host-only (NOT_RUN on Spark silicon). Zero real firmware bytes.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
OMC="${OMC:-/Users/drakestapleton/workspace/omega-mv-macos/seed/out/omc-macos}"
if [ ! -x "$OMC" ]; then
  OMC="$ROOT/seed/out/omc"
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/slice-d-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

OS=$(uname -s)
if [ "$OS" = "Darwin" ]; then
  HOST_HDR="target a64macos"
  sign_bin() { codesign -s - "$1" >/dev/null 2>&1; }
else
  HOST_HDR=""
  sign_bin() { :; }
fi

compile_host() {
  out="$1"; shift
  if [ -n "$HOST_HDR" ]; then
    { printf '%s\n' "$HOST_HDR"; cat "$@"; } | "$OMC" > "$out"
  else
    cat "$@" | "$OMC" > "$out"
  fi
  chmod +x "$out"
  sign_bin "$out"
}

compile_linux() {
  out="$1"; shift
  cat "$@" | "$OMC" > "$out"
}

echo "=== [1/7] NVMe Read-Only Bare-Metal Simulator Test ==="
compile_host "$TMP/test_nvme_ro_bare" \
  "$ROOT/aienux/disk/nvme_ro_bare.om" \
  "$ROOT/aienux/disk/tests/test_nvme_ro_bare.om"
"$TMP/test_nvme_ro_bare"
compile_linux "$TMP/test_nvme_ro_bare.elf" \
  "$ROOT/aienux/disk/nvme_ro_bare.om" \
  "$ROOT/aienux/disk/tests/test_nvme_ro_bare.om"
echo "PASS: test_nvme_ro_bare (host run + Linux AArch64 ELF compile)"

echo "=== [2/7] Offline OMFWBND1 Bundle Packer (Synthetic Blobs Only) ==="
compile_host "$TMP/pack_bundle" \
  "$ROOT/aienux/disk/sha256_bare.om" \
  "$ROOT/aienux/disk/pack_bundle.om"
compile_linux "$TMP/pack_bundle.elf" \
  "$ROOT/aienux/disk/sha256_bare.om" \
  "$ROOT/aienux/disk/pack_bundle.om"
python3 - "$TMP" <<'PY'
import os, sys
tmp = sys.argv[1]
blobs = [
    ("gsp.bin", b"SYNTH_GSP_ELF64" * 300),
    ("bl.img", b"SYNTH_BL_IMG" * 120),
    ("fmc.img", b"SYNTH_FMC_IMG" * 120),
    ("fmc.hash", bytes(range(48))),
    ("fmc.pubkey", bytes([(i * 7) & 0xff for i in range(384)])),
    ("fmc.sig", bytes([(i * 13) & 0xff for i in range(384)])),
    ("bl_desc", bytes([(i * 3) & 0xff for i in range(84)])),
]
for name, data in blobs:
    with open(os.path.join(tmp, name), "wb") as f:
        f.write(data)
PY
"$TMP/pack_bundle" "$TMP/spark-bundle.img" 58017302 \
  1 "$TMP/gsp.bin" \
  2 "$TMP/bl.img" \
  3 "$TMP/fmc.img" \
  4 "$TMP/fmc.hash" \
  5 "$TMP/fmc.pubkey" \
  6 "$TMP/fmc.sig" \
  7 "$TMP/bl_desc"
# Regression: pack_bundle MUST reject u64 overflow (> 2^64-1) and >20-digit args with exit 2
set +e
"$TMP/pack_bundle" "$TMP/bad1.img" 18446744073709551616 1 "$TMP/gsp.bin"
rc1=$?
"$TMP/pack_bundle" "$TMP/bad2.img" 123456789012345678901 1 "$TMP/gsp.bin"
rc2=$?
set -e
if [ "$rc1" -ne 2 ] || [ "$rc2" -ne 2 ]; then
  echo "FAIL: pack_bundle bad-arg rejection (rc1=$rc1 rc2=$rc2)" >&2
  exit 1
fi
echo "PASS: pack_bundle produced $(wc -c < "$TMP/spark-bundle.img") byte synthetic OMFWBND1 bundle + overflow/length rejection"

echo "=== [3/7] Synthetic GPT + 64-bit ext4 Image & Read-Only Test ==="
python3 - "$TMP/spark-bundle.img" "$TMP/disk.img" <<'PY'
import struct, sys, zlib

bundle = open(sys.argv[1], "rb").read()
total_secs = 4096
img = bytearray(total_secs * 512)

# 1. Protective MBR (LBA 0)
img[446 + 4] = 0xEE
struct.pack_into("<II", img, 446 + 8, 1, total_secs - 1)
img[510] = 0x55
img[511] = 0xAA

# 2. GPT Partition Entries (LBA 2..33, 128 entries x 128 B = 16384 B)
ents = bytearray(128 * 128)
# Partition 1: EFI System (LBA 34..63)
efi_guid = bytes.fromhex("28732ac11ff8d211ba4b00a0c93ec93b")
struct.pack_into("<16s16sQQQ", ents, 0, efi_guid, b"\x01"*16, 34, 63, 0)
# Partition 2: Linux Filesystem (LBA 64..4062, 3999 sectors -> 499 x 4KiB blocks)
linux_guid = bytes.fromhex("af3dc60f838472478e793d69d8477de4")
part2_lba = 64
part2_last = total_secs - 34
struct.pack_into("<16s16sQQQ", ents, 128, linux_guid, b"\x02"*16, part2_lba, part2_last, 0)
ent_crc = zlib.crc32(ents) & 0xffffffff

def make_gpt_hdr(my_lba, bak_lba, ent_lba):
    hdr = bytearray(92)
    struct.pack_into("<8sIIIIQQQQ16sQIII", hdr, 0,
        b"EFI PART", 0x00010000, 92, 0, 0,
        my_lba, bak_lba, 34, total_secs - 34,
        b"\x11"*16, ent_lba, 128, 128, ent_crc)
    hcrc = zlib.crc32(hdr) & 0xffffffff
    struct.pack_into("<I", hdr, 16, hcrc)
    return hdr

img[512:512+92] = make_gpt_hdr(1, total_secs - 1, 2)
img[1024:1024+len(ents)] = ents
img[(total_secs - 1)*512:(total_secs - 1)*512+92] = make_gpt_hdr(total_secs - 1, 1, total_secs - 33)

# 3. Synthetic 64-bit ext4 inside Partition 2 (4 KiB blocks, desc_size=64, 256B inodes)
p2_off = part2_lba * 512
BS = 4096
def blk_off(b): return p2_off + b * BS

# Superblock at p2_off + 1024
sb = p2_off + 1024
n_blocks = (part2_last - part2_lba + 1) // 8
struct.pack_into("<I", img, sb + 0, 128)        # s_inodes_count
struct.pack_into("<I", img, sb + 4, n_blocks)   # s_blocks_count_lo
struct.pack_into("<I", img, sb + 24, 2)         # s_log_block_size = 2 (4096 B)
struct.pack_into("<I", img, sb + 32, 32768)     # s_blocks_per_group
struct.pack_into("<I", img, sb + 40, 128)       # s_inodes_per_group
struct.pack_into("<H", img, sb + 56, 0xEF53)    # s_magic
struct.pack_into("<H", img, sb + 88, 256)       # s_inode_size
struct.pack_into("<I", img, sb + 96, 0x40|0x80) # INCOMPAT_EXTENTS | INCOMPAT_64BIT
struct.pack_into("<H", img, sb + 254, 64)       # s_desc_size = 64
struct.pack_into("<I", img, sb + 336, 0)        # s_blocks_count_hi

# Block 1: 64-bit Group Descriptor Table (inode table at block 2)
gdt = blk_off(1)
struct.pack_into("<I", img, gdt + 8, 2)         # bg_inode_table_lo = 2
struct.pack_into("<I", img, gdt + 40, 0)        # bg_inode_table_hi = 0

# Block 2..9: Inode table (128 inodes * 256 B = 32 KiB = 8 blocks)
def write_inode(ino, mode, size, flags, ext_bytes):
    ioff = blk_off(2) + (ino - 1) * 256
    struct.pack_into("<H", img, ioff + 0, mode)
    struct.pack_into("<I", img, ioff + 4, size & 0xffffffff)
    struct.pack_into("<I", img, ioff + 32, flags)
    struct.pack_into("<I", img, ioff + 108, (size >> 32) & 0xffffffff)
    img[ioff + 40 : ioff + 40 + len(ext_bytes)] = ext_bytes

def ext_hdr(entries, max_e, depth, magic=0xF30A):
    return struct.pack("<HHHHI", magic, entries, max_e, depth, 0)

def ext_leaf(ee_blk, ee_len, pblk):
    return struct.pack("<IHHI", ee_blk, ee_len, (pblk >> 32) & 0xffff, pblk & 0xffffffff)

def ext_idx(ei_blk, leaf_blk):
    return struct.pack("<IIHH", ei_blk, leaf_blk & 0xffffffff, (leaf_blk >> 32) & 0xffff, 0)

def make_dir_block(entries):
    buf = bytearray(BS)
    pos = 0
    for idx, (ino, name, ftype) in enumerate(entries):
        nb = name.encode("ascii")
        raw = 8 + len(nb)
        rlen = (raw + 3) & ~3
        if idx == len(entries) - 1:
            rlen = BS - pos
        struct.pack_into("<IHBB", buf, pos, ino, rlen, len(nb), ftype)
        buf[pos + 8 : pos + 8 + len(nb)] = nb
        pos += rlen
    return buf

# Directories: root (ino 2 -> blk 10), /aienos (ino 12 -> blk 11), /bad (ino 13 -> blk 12)
img[blk_off(10):blk_off(11)] = make_dir_block([(2, ".", 2), (2, "..", 2), (12, "aienos", 2), (13, "bad", 2)])
write_inode(2, 0x41ED, BS, 0x80000, ext_hdr(1, 4, 0) + ext_leaf(0, 1, 10))

img[blk_off(11):blk_off(12)] = make_dir_block([(12, ".", 2), (2, "..", 2), (14, "sparse.bin", 1), (15, "spark-bundle.img", 1)])
write_inode(12, 0x41ED, BS, 0x80000, ext_hdr(1, 4, 0) + ext_leaf(0, 1, 11))

img[blk_off(12):blk_off(13)] = make_dir_block([
    (13, ".", 2), (2, "..", 2),
    (16, "inline", 1), (17, "encrypt", 1), (18, "noext", 1), (19, "badmagic", 1)
])
write_inode(13, 0x41ED, BS, 0x80000, ext_hdr(1, 4, 0) + ext_leaf(0, 1, 12))

# /aienos/sparse.bin (ino 14, 16384 B, DEPTH-1 extent tree! index -> leaf block 13):
#   lblock 0 -> blk 14 (0xA5)
#   lblock 1 -> blk 15 (unwritten ee_len = 32768 + 1, disk has 0xEE garbage -> MUST read as 0x00!)
#   lblock 2 -> sparse hole (no extent -> MUST read as 0x00!)
#   lblock 3 -> blk 16 (0x5A)
img[blk_off(14):blk_off(15)] = bytes([0xA5]) * BS
img[blk_off(15):blk_off(16)] = bytes([0xEE]) * BS
img[blk_off(16):blk_off(17)] = bytes([0x5A]) * BS
leaf13 = ext_hdr(3, 340, 0) + ext_leaf(0, 1, 14) + ext_leaf(1, 32769, 15) + ext_leaf(3, 1, 16)
img[blk_off(13):blk_off(13)+len(leaf13)] = leaf13
write_inode(14, 0x81A4, 16384, 0x80000, ext_hdr(1, 4, 1) + ext_idx(0, 13))

# /aienos/spark-bundle.img (ino 15, blocks 20..)
bnd_blks = (len(bundle) + BS - 1) // BS
img[blk_off(20):blk_off(20)+len(bundle)] = bundle
write_inode(15, 0x81A4, len(bundle), 0x80000, ext_hdr(1, 4, 0) + ext_leaf(0, bnd_blks, 20))

# Hostile inodes in /bad/
write_inode(16, 0x81A4, 16, 0x80000 | 0x10000000, ext_hdr(0, 4, 0))  # inline
write_inode(17, 0x81A4, 16, 0x80000 | 0x800, ext_hdr(0, 4, 0))       # encrypt
write_inode(18, 0x81A4, 16, 0, b"\x00"*60)                           # no extents
write_inode(19, 0x81A4, 4096, 0x80000, ext_hdr(1, 4, 0, magic=0xDEAD) + ext_leaf(0, 1, 14))

open(sys.argv[2], "wb").write(img)
PY

# Also build a META_BG (0x10) superblock copy to verify E4_E_FEATURE fail-closed refusal
python3 - "$TMP/disk.img" "$TMP/disk_metabg.img" <<'PY'
import struct, sys
img = bytearray(open(sys.argv[1], "rb").read())
sb = 64 * 512 + 1024
inc = struct.unpack_from("<I", img, sb + 96)[0]
struct.pack_into("<I", img, sb + 96, inc | 0x10)
open(sys.argv[2], "wb").write(img)
PY

compile_host "$TMP/test_gpt_ext4_ro" \
  "$ROOT/aienux/disk/sha256_bare.om" \
  "$ROOT/aienux/disk/gpt_ro.om" \
  "$ROOT/aienux/disk/ext4_ro.om" \
  "$ROOT/aienux/disk/tests/test_gpt_ext4_ro.om"
"$TMP/test_gpt_ext4_ro" "$TMP/disk.img" "$TMP/disk_metabg.img"
compile_linux "$TMP/test_gpt_ext4_ro.elf" \
  "$ROOT/aienux/disk/sha256_bare.om" \
  "$ROOT/aienux/disk/gpt_ro.om" \
  "$ROOT/aienux/disk/ext4_ro.om" \
  "$ROOT/aienux/disk/tests/test_gpt_ext4_ro.om"
echo "PASS: test_gpt_ext4_ro (GPT + 64-bit ext4 + depth-1/unwritten/sparse/extent-run + OMFWBND1 overlap/SHA-256 + META_BG/S_IFREG/hostile refusals)"

echo "=== [4/7] RTL8127 + TCP Glue End-to-End Model Test & Existing Driver Regression ==="
compile_host "$TMP/test_tcp_glue" \
  "$ROOT/aienux/net/rtl8127/om/rtl8127/rtl8127.om" \
  "$ROOT/aienux/net/rtl8127/om/rtl8127/model.om" \
  "$ROOT/aienux/net/tcp/tcp.om" \
  "$ROOT/aienux/net/rtl8127/om/rtl8127/tcp_glue.om" \
  "$ROOT/aienux/net/rtl8127/om/rtl8127/test/test_tcp_glue.om"
"$TMP/test_tcp_glue"
compile_linux "$TMP/test_tcp_glue.elf" \
  "$ROOT/aienux/net/rtl8127/om/rtl8127/rtl8127.om" \
  "$ROOT/aienux/net/rtl8127/om/rtl8127/model.om" \
  "$ROOT/aienux/net/tcp/tcp.om" \
  "$ROOT/aienux/net/rtl8127/om/rtl8127/tcp_glue.om" \
  "$ROOT/aienux/net/rtl8127/om/rtl8127/test/test_tcp_glue.om"
compile_host "$TMP/rtl8127_driver_test" \
  "$ROOT/aienux/net/rtl8127/om/rtl8127/rtl8127.om" \
  "$ROOT/aienux/net/rtl8127/om/rtl8127/model.om" \
  "$ROOT/aienux/net/rtl8127/om/rtl8127/test/driver.om"
"$TMP/rtl8127_driver_test"
echo "PASS: test_tcp_glue + existing rtl8127 driver.om regression"

echo "=== [5/7] RTL8127 Direct Normal-NC Physical DMA Regression Test ==="
compile_host "$TMP/test_rtl8127_nc_dma" \
  "$ROOT/aienux/net/rtl8127/om/rtl8127/rtl8127.om" \
  "$ROOT/aienux/net/rtl8127/om/rtl8127/test/test_rtl8127_nc_dma.om"
"$TMP/test_rtl8127_nc_dma"
compile_linux "$TMP/test_rtl8127_nc_dma.elf" \
  "$ROOT/aienux/net/rtl8127/om/rtl8127/rtl8127.om" \
  "$ROOT/aienux/net/rtl8127/om/rtl8127/test/test_rtl8127_nc_dma.om"
echo "PASS: test_rtl8127_nc_dma (direct Normal-NC RX/TX ring + payload before doorbell, .bss rdma untouched)"

echo "=== [6/7] Bare-Metal target a64efi PE32+ Compile Check (NVMe + GPT + ext4 + SHA-256) ==="
cat <<'OM' > "$TMP/efi_nvme_stub.om"
fn a64_dsb_sy to void
end
fn a64_dc_civac_range pa ulong nbytes ulong to void
end
fn gpt_read_lba lba ulong to int
ret 0
end
fn ext4_read_lba lba ulong to int
ret 0
end
fn ext4_sink off ulong b uchar to void
end
fn main to int
r = nvme_init 1645215744 268435456 1
if ne r 0
ret r
end
r2 = gpt_ro_parse 4096
if ne r2 0
ret r2
end
ret ext4_ro_mount 64 4000
end
OM
{ printf 'target a64efi\n'; \
  cat "$ROOT/aienux/disk/nvme_ro_bare.om" \
      "$ROOT/aienux/disk/nvme_bare_a64efi.om" \
      "$ROOT/aienux/disk/sha256_bare.om" \
      "$ROOT/aienux/disk/gpt_ro.om" \
      "$ROOT/aienux/disk/ext4_ro.om" \
      "$TMP/efi_nvme_stub.om"; } | "$OMC" > "$TMP/nvme_storage.efi"
echo "PASS: target a64efi NVMe+GPT+ext4+SHA256 PE32+ compiled ($(wc -c < "$TMP/nvme_storage.efi") bytes)"

echo "=== [7/7] Bare-Metal target a64efi PE32+ Compile Check (RTL8127 + TCP) ==="
cat <<'OM' > "$TMP/efi_net_stub.om"
fn a64_dsb_sy to void
end
fn a64_dc_civac_range pa ulong nbytes ulong to void
end
fn main to int
r = rtl_bare_setup RTL_SPARK_BAR2 268435456
if ne r 0
ret r
end
e = rtlinit 268435456
if ne e 0
ret int e
end
rtltcp_bind_mac
tinit
put Tcf 1 3232235884
put Tcf 2 3232235777
put Tcf 3 4294967040
put Tcf 5 12345
tlisten 9000
z = rtltcp_poll 0
ret 0
end
OM
{ printf 'target a64efi\n'; \
  cat "$ROOT/aienux/net/rtl8127/om/rtl8127/rtl8127.om" \
      "$ROOT/aienux/net/rtl8127/om/rtl8127/bare_a64efi.om" \
      "$ROOT/aienux/net/tcp/tcp.om" \
      "$ROOT/aienux/net/rtl8127/om/rtl8127/tcp_glue.om" \
      "$TMP/efi_net_stub.om"; } | "$OMC" > "$TMP/rtl8127_tcp.efi"
echo "PASS: target a64efi RTL8127+TCP PE32+ compiled ($(wc -c < "$TMP/rtl8127_tcp.efi") bytes)"

echo "SLICE D ALL 7 CHECKS PASSED"
