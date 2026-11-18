#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
# Byte-exact lock for the gfx942 encodings, then the CPU numeric reference.
# llvm-mc-18 -triple=amdgcn -mcpu=gfx942 -show-encoding, the assembled .text,
# hsaco.om's packing of the .isa, and the committed .golden file must be identical.
# No GPU is required. A mismatch exits 1. Exit 3 (NOT_RUN, never a pass): seed/out/omc.sha256 does not
# start with a 64-hex sha256, or seed/out/omc is not an executable file. Before that, the same refusal
# is checked on four planted trees (no pin file, an empty pin, a short pin, a good pin with no compiler)
# and a compiler whose hash differs; any of them accepted exits 1.
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../.." && pwd)
OMC=$ROOT/seed/out/omc
QEMU=/usr/bin/qemu-aarch64-static
MC=/usr/bin/llvm-mc-18
OBJCOPY=/usr/bin/llvm-objcopy-18
SUM=/usr/bin/sha256sum

# pin_refusal TREE: why TREE/seed/out/omc may not be used (exit 3 refused, 1 hash differs), or
# nothing and status 0. The pin must be checked before it is compared: an empty pin and the empty
# hash of a missing compiler would otherwise compare equal.
pin_refusal() {
  pw=$(awk 'NR == 1 {print $1}' "$1/seed/out/omc.sha256" 2>/dev/null || true)
  if ! printf '%s\n' "$pw" | grep -qxE '[0-9a-f]{64}'; then
    echo "NOT_RUN: no sha256 in seed/out/omc.sha256"; return 3
  fi
  if [ ! -f "$1/seed/out/omc" ] || [ ! -x "$1/seed/out/omc" ]; then
    echo "NOT_RUN: no executable compiler at seed/out/omc"; return 3
  fi
  pg=$($SUM "$1/seed/out/omc" | awk '{print $1}')
  if [ "$pg" != "$pw" ]; then
    echo "omc sha256 $pg does not match seed/out/omc.sha256 $pw"; return 1
  fi
  return 0
}

echo "pin controls"
ctl=$(mktemp -d)
for c in no-pin empty short no-compiler other-compiler; do
  mkdir -p "$ctl/$c/seed/out"
  case $c in
    no-pin) ;;
    empty) : > "$ctl/$c/seed/out/omc.sha256" ;;
    short) echo "abc  seed/out/omc" > "$ctl/$c/seed/out/omc.sha256" ;;
    no-compiler) printf '%064d  seed/out/omc\n' 0 > "$ctl/$c/seed/out/omc.sha256" ;;
    other-compiler) printf '%064d  seed/out/omc\n' 0 > "$ctl/$c/seed/out/omc.sha256"
      printf '#!/bin/sh\n' > "$ctl/$c/seed/out/omc"; chmod +x "$ctl/$c/seed/out/omc" ;;
  esac
  rc=0; why=$(pin_refusal "$ctl/$c") || rc=$?
  want_rc=3; [ "$c" = other-compiler ] && want_rc=1
  if [ "$rc" != "$want_rc" ] || [ -z "$why" ]; then
    echo "pin control $c: status $rc, wanted $want_rc with a reason; the pin check accepts it" >&2
    rm -rf "$ctl"; exit 1
  fi
  echo "pin control $c refused ($rc): $why"
done
rm -rf "$ctl"

echo "omc sha256"
rc=0; why=$(pin_refusal "$ROOT") || rc=$?
if [ "$rc" != 0 ]; then
  echo "$why" >&2
  exit "$rc"
fi
$SUM "$OMC" | awk '{print $1}'

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

echo "plain reference"
g++ -O2 -std=c++17 -ffp-contract=off -o "$work/plain_ref_test" "$HERE/plain_ref_test.cpp"
"$work/plain_ref_test"
echo "check.sh pass"
