#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
# Byte-exact lock for the gfx942 encodings, then the CPU numeric reference.
# llvm-mc-18 -triple=amdgcn -mcpu=gfx942 -show-encoding, the assembled .text,
# hsaco.om's packing of the .isa, and the committed .golden file must be identical.
# No GPU is required. A mismatch exits 1.
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../.." && pwd)
OMC=$ROOT/seed/out/omc
QEMU=/usr/bin/qemu-aarch64-static
MC=/usr/bin/llvm-mc-18
OBJCOPY=/usr/bin/llvm-objcopy-18
SUM=/usr/bin/sha256sum

echo "omc sha256"
got=$($SUM "$OMC" | awk '{print $1}')
want=$(awk '{print $1}' "$ROOT/seed/out/omc.sha256")
echo "$got"
if [ "$got" != "$want" ]; then
  echo "omc sha256 does not match seed/out/omc.sha256" >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "compile hsaco.om"
env -i "$QEMU" "$OMC" < "$ROOT/gpu/amd/gfx942/hsaco.om" > "$work/hsaco" 2>"$work/hsaco.err"
if [ -s "$work/hsaco.err" ]; then
  cat "$work/hsaco.err" >&2
  exit 1
fi
chmod +x "$work/hsaco"

cmp_one() {
  stem=$1
  echo "llvm-mc $stem"
  "$MC" -triple=amdgcn -mcpu=gfx942 -show-encoding "$HERE/$stem.s" > "$work/$stem.enc"
  "$MC" -triple=amdgcn -mcpu=gfx942 -filetype=obj -o "$work/$stem.o" "$HERE/$stem.s"
  "$OBJCOPY" -O binary --only-section=.text "$work/$stem.o" "$work/$stem.mc"
  echo "hsaco $stem"
  env -i "$QEMU" "$work/hsaco" "$HERE/$stem.isa" > "$work/$stem.hsaco" 2>"$work/$stem.herr"
  if [ -s "$work/$stem.herr" ]; then
    cat "$work/$stem.herr" >&2
    exit 1
  fi
  "$OBJCOPY" -O binary --only-section=.text "$work/$stem.hsaco" "$work/$stem.hs"
  python3 - "$work/$stem.enc" "$work/$stem.mc" "$work/$stem.hs" "$HERE/$stem.golden" << 'PY'
import re, sys
enc, mc, hs, gold = sys.argv[1:]
text = open(enc).read()
# A branch prints "A" for the 16-bit displacement. The object file has it resolved.
words = re.findall(r"encoding: \[([0-9a-fxA, ]+)\]", text)
slots = []
for w in words:
    for tok in w.split(","):
        tok = tok.strip()
        slots.append(None if tok == "A" else int(tok, 16))
obj = open(mc, "rb").read()
packed = open(hs, "rb").read()
want = bytes.fromhex("".join(
    line.split("#", 1)[0].strip()
    for line in open(gold)
    if line.split("#", 1)[0].strip()
))
show_ok = len(slots) == len(obj) and all(
    s is None or s == obj[i] for i, s in enumerate(slots)
)
wild = sum(1 for s in slots if s is None)
print(
    "bytes", len(obj),
    "show==obj", show_ok,
    "branch-bytes", wild,
    "obj==hsaco", obj == packed,
    "obj==golden", obj == want,
)
if not (show_ok and obj == packed == want):
    sys.exit(1)
PY
}

cmp_one encprobe
cmp_one fp8gemv_stream

echo "descriptor"
python3 - "$HERE/fp8gemv_stream.isa" << 'PY'
import sys
line = ""
for raw in open(sys.argv[1]):
    if raw.startswith("K "):
        line = raw
        break
p = line.split()
# K name size align group private sgprs vgprs agprs maxgroup wave rsrc3 rsrc1 rsrc2 properties
sgprs, vgprs = int(p[6]), int(p[7])
rsrc3, rsrc1 = int(p[11], 0), int(p[12], 0)
vgpr_gran = max(0, (vgprs + 7) // 8 - 1)
sgpr_used = sgprs + 2
sgpr_field = 2 * max(0, (sgpr_used + 15) // 16 - 1)
expect = 0xAF0000 | (sgpr_field << 6) | vgpr_gran
acc = (vgprs + 3) // 4 - 1
print("sgprs", sgprs, "vgprs", vgprs, "rsrc1", hex(rsrc1), "expect", hex(expect), "rsrc3", rsrc3, "expect", acc)
if rsrc1 != expect or rsrc3 != acc:
    sys.exit(1)
if "00805edc" not in open(sys.argv[1].rsplit("/", 1)[0] + "/fp8gemv_stream.golden").read():
    sys.exit(1)
PY

echo "cpu reference"
{ printf 'target x86linux\nom2\n'; cat "$ROOT/gpu/amd/gfx942/exec/fma.om" "$HERE/check.om"; } \
  | env -i "$QEMU" "$OMC" > "$work/check" 2>"$work/check.err"
if [ -s "$work/check.err" ]; then
  cat "$work/check.err" >&2
  exit 1
fi
chmod +x "$work/check"
"$work/check"
echo "check.sh pass"
