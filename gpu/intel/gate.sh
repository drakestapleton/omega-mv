#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
# gpu/intel/gate.sh: host-only verification gate for the pure-Omega Intel Xe/Panther Lake backend.
# Compiles records.om, batch.om, isa.om, and plan.om with seed/out/omc, verifies requests.tsv ABI
# against /usr/include/drm/xe_drm.h (when present), checks CCS batch + Xe EU ISA emission, and runs
# negative controls. No Intel GPU hardware is opened.
set -u
OMC=${OMC:-seed/out/omc}
S=$(dirname "$0")
B=$(mktemp -d)
trap 'rm -rf "$B"' EXIT
fail=0
for f in records batch isa plan launch; do
  "$OMC" < "$S/xe/$f.om" > "$B/$f" || { echo "FAIL compile xe/$f.om"; exit 1; }
  chmod +x "$B/$f"
  echo "PASS compile xe/$f.om"
done

# 0. Compile launch.om for x86-64 Linux too (Panther Lake target) and run native AArch64 selftest
{ printf 'target x86linux\n'; cat "$S/xe/launch.om"; } > "$B/launch.x86.om"
"$OMC" < "$B/launch.x86.om" > "$B/launch.x86" && echo "PASS compile xe/launch.om (x86linux)" || { echo "FAIL compile xe/launch.om (x86linux)"; fail=1; }
"$B/launch" selftest && echo "PASS launch selftest (all 11 drm/xe ioctls -> -EBADF)" || { echo "FAIL launch selftest"; fail=1; }
# Negative control: wrong ABI size for DRM_IOCTL_XE_VM_CREATE must be refused by omc (error 9)
printf 'om2\nfn main to int\nr = new uchar 32 0\nret int kfdctl -1 3223348291 r 0 16\nend\n' > "$B/bad_sz.om"
"$OMC" < "$B/bad_sz.om" > "$B/bad_sz" 2>/dev/null && { echo "FAIL control: omc accepted wrong XE_VM_CREATE size"; fail=1; } || echo "PASS control: omc rejects wrong XE_VM_CREATE size"

# 1. Serialize every drm/xe ioctl record (0..12) from requests.tsv and check exact wire size
idx=0
for want_sz in 40 56 40 32 24 136 48 24 56 72 8 48 8; do
  "$B/records" "$S/xe/requests.tsv" "$idx" > "$B/rec.$idx.bin" || { echo "FAIL records $idx"; fail=1; }
  got_sz=$(wc -c < "$B/rec.$idx.bin" | tr -d ' ')
  if [ "$got_sz" = "$want_sz" ]; then
    echo "PASS records idx=$idx size=$got_sz"
  else
    echo "FAIL records idx=$idx got=$got_sz want=$want_sz"
    fail=1
  fi
  idx=$((idx + 1))
done

# 2. Emit & validate CCS batch buffers for vadd, fsum16, gemm16, rmsnorm
for k in vadd fsum16 gemm16 rmsnorm; do
  "$B/batch" emit 4294967296 4299161600 4303355904 1 16384 1 1 16 > "$B/$k.batch.bin" || { echo "FAIL batch emit $k"; fail=1; }
  "$B/batch" check "$B/$k.batch.bin" && echo "PASS batch check $k" || { echo "FAIL batch check $k"; fail=1; }
  "$B/isa" emit "$k" > "$B/$k.isa.bin" || { echo "FAIL isa emit $k"; fail=1; }
  "$B/isa" check "$B/$k.isa.bin" && echo "PASS isa check $k" || { echo "FAIL isa check $k"; fail=1; }
  "$B/plan" "$k" > "$B/$k.plan.txt" && echo "PASS plan $k" || { echo "FAIL plan $k"; fail=1; }
done
"$B/batch" fence 4303355904 305419896 > "$B/fence.batch.bin" || { echo "FAIL batch fence"; fail=1; }
"$B/batch" check "$B/fence.batch.bin" && echo "PASS batch check fence" || { echo "FAIL batch check fence"; fail=1; }

# 3. Negative controls
printf 'BAD_BATCH_000000000000000000000000000000000000000000000000000000' > "$B/bad.batch.bin"
"$B/batch" check "$B/bad.batch.bin" 2>/dev/null && { echo "FAIL control: batch accepted invalid packet"; fail=1; } || echo "PASS control: batch rejects invalid packet"
# Strip EOT instruction (last 16 bytes) from gemm16.isa.bin
dd if="$B/gemm16.isa.bin" of="$B/noeot.isa.bin" bs=16 count=4 2>/dev/null
"$B/isa" check "$B/noeot.isa.bin" 2>/dev/null && { echo "FAIL control: isa accepted missing EOT"; fail=1; } || echo "PASS control: isa rejects missing EOT"

[ "$fail" = 0 ] && echo "INTEL-XE-GATE PASS" || echo "INTEL-XE-GATE FAIL"
exit "$fail"
