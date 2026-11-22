#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
# gpu/qual/gate.sh: compile and run pure-Omega x86 Linux & non-NVIDIA GPU qualification units.
# Strictly separates HOST_TESTED / EMULATED from PHYSICAL hardware qualification:
#   - On non-x86_64 hosts (e.g. AArch64 Spark), x86linux_qual MUST refuse default execution (exit 3,
#     BLOCKED_HARDWARE) under qemu-x86_64, and only pass its selftest with --allow-emulated-selftest.
#   - On NVIDIA-only or CPU-only hosts, non_nvidia_qual MUST exit 3 (BLOCKED_HARDWARE).
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
OMC=${OMC:-"$ROOT/seed/out/omc"}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/omega-gpu-qual.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

if [ ! -x "$OMC" ]; then
    echo "OMEGA-GPU-QUAL NOT_RUN: compiler missing at $OMC" >&2
    exit 3
fi

WANT=$(awk '{print $1; exit}' "$ROOT/seed/out/omc.sha256")
GOT=$(sha256sum "$OMC" | awk '{print $1}')
if [ "$GOT" != "$WANT" ]; then
    echo "OMEGA-GPU-QUAL REFUSED: omc sha256 $GOT != $WANT" >&2
    exit 69
fi

# 1. Host classification test (AArch64 or native host)
HOST_ARCH=$(uname -m)
HDR=""
if [ "$HOST_ARCH" = "x86_64" ]; then
    HDR="target x86linux\n"
fi
{ printf "${HDR}om2\n"; grep -v '^om2$' "$ROOT/gpu/qual/qual_test.om"; } | "$OMC" > "$WORK/qual_test" 2> "$WORK/qual_test.err"
[ ! -s "$WORK/qual_test.err" ] || { cat "$WORK/qual_test.err" >&2; exit 1; }
chmod 700 "$WORK/qual_test"
"$WORK/qual_test"

# 2. Build non_nvidia_qual for BOTH AArch64 and x86linux (reproducible cross-compile)
{ printf 'om2\n'; grep -v '^om2$' "$ROOT/gpu/qual/non_nvidia_qual.om"; } | "$OMC" > "$WORK/nnq_a64" 2> "$WORK/nnq_a64.err"
[ ! -s "$WORK/nnq_a64.err" ] || { cat "$WORK/nnq_a64.err" >&2; exit 1; }
{ printf 'target x86linux\nom2\n'; grep -v '^om2$' "$ROOT/gpu/qual/non_nvidia_qual.om"; } | "$OMC" > "$WORK/nnq_x86" 2> "$WORK/nnq_x86.err"
[ ! -s "$WORK/nnq_x86.err" ] || { cat "$WORK/nnq_x86.err" >&2; exit 1; }
chmod 700 "$WORK/nnq_a64" "$WORK/nnq_x86"

NNQ="$WORK/nnq_a64"
[ "$HOST_ARCH" = "x86_64" ] && NNQ="$WORK/nnq_x86"

# Synthetic fixture positive controls: AMD MI300X and Intel Panther Lake
mkdir -p "$WORK/fix-amd/sys/bus/pci/devices/0000:c1:00.0" "$WORK/fix-amd/dev"
printf '0x1002\n' > "$WORK/fix-amd/sys/bus/pci/devices/0000:c1:00.0/vendor"
printf '0x74a1\n' > "$WORK/fix-amd/sys/bus/pci/devices/0000:c1:00.0/device"
printf '0x038000\n' > "$WORK/fix-amd/sys/bus/pci/devices/0000:c1:00.0/class"
: > "$WORK/fix-amd/dev/kfd"
"$NNQ" --root "$WORK/fix-amd" > "$WORK/amd.out"
grep -q 'VERDICT=NON_NVIDIA_HARDWARE_PRESENT' "$WORK/amd.out"

mkdir -p "$WORK/fix-intel/sys/bus/pci/devices/0000:00:02.0" "$WORK/fix-intel/dev/dri"
printf '0x8086\n' > "$WORK/fix-intel/sys/bus/pci/devices/0000:00:02.0/vendor"
printf '0xb080\n' > "$WORK/fix-intel/sys/bus/pci/devices/0000:00:02.0/device"
printf '0x030000\n' > "$WORK/fix-intel/sys/bus/pci/devices/0000:00:02.0/class"
: > "$WORK/fix-intel/dev/dri/renderD128"
"$NNQ" --root "$WORK/fix-intel" > "$WORK/intel.out"
grep -q 'VERDICT=NON_NVIDIA_HARDWARE_PRESENT' "$WORK/intel.out"

# Synthetic fixture negative control: NVIDIA-only GB10 must exit 3 (BLOCKED_HARDWARE)
mkdir -p "$WORK/fix-nv/sys/bus/pci/devices/000f:01:00.0"
printf '0x10de\n' > "$WORK/fix-nv/sys/bus/pci/devices/000f:01:00.0/vendor"
printf '0x2e12\n' > "$WORK/fix-nv/sys/bus/pci/devices/000f:01:00.0/device"
printf '0x030000\n' > "$WORK/fix-nv/sys/bus/pci/devices/000f:01:00.0/class"
rc=0
"$NNQ" --root "$WORK/fix-nv" > "$WORK/nv.out" || rc=$?
[ "$rc" -eq 3 ] || { echo "FAIL: NVIDIA-only fixture returned $rc, expected 3" >&2; exit 1; }
grep -q 'VERDICT=BLOCKED_HARDWARE' "$WORK/nv.out"

# Live host inventory (informational; records real hardware state)
LIVE_NNQ_RC=0
"$NNQ" > "$WORK/live_nnq.out" || LIVE_NNQ_RC=$?
echo "--- live non_nvidia_qual (exit=$LIVE_NNQ_RC) ---"
cat "$WORK/live_nnq.out"

# 3. Build x86linux_qual (target x86linux + sha256)
{ printf 'target x86linux\nom2\n'; cat "$ROOT/seed/ng/sha256.om"; grep -v '^target x86linux$' "$ROOT/gpu/qual/x86linux_qual.om" | grep -v '^om2$'; } | "$OMC" > "$WORK/x86linux_qual" 2> "$WORK/x86.err"
[ ! -s "$WORK/x86.err" ] || { cat "$WORK/x86.err" >&2; exit 1; }
chmod 700 "$WORK/x86linux_qual"

X86_STATUS="NOT_RUN"
if [ "$HOST_ARCH" = "x86_64" ]; then
    "$WORK/x86linux_qual" > "$WORK/x86.out"
    cat "$WORK/x86.out"
    grep -q 'EXEC_CLASS=PHYSICAL_X86_64' "$WORK/x86.out"
    X86_STATUS="PHYSICAL_X86_64_PASS"
elif command -v qemu-x86_64 >/dev/null 2>&1; then
    # Default invocation under QEMU MUST refuse with exit 3 (BLOCKED_HARDWARE)
    rc=0
    qemu-x86_64 "$WORK/x86linux_qual" > "$WORK/x86_def.out" || rc=$?
    [ "$rc" -eq 3 ] || { echo "FAIL: x86linux_qual under QEMU returned $rc, expected 3 (BLOCKED_HARDWARE)" >&2; exit 1; }
    grep -q 'EXEC_CLASS=EMULATED' "$WORK/x86_def.out"
    grep -q 'VERDICT=BLOCKED_HARDWARE' "$WORK/x86_def.out"
    # Explicit emulated selftest verifies x86_64 codegen, floats, sha256, and traps 1/2/3/5
    qemu-x86_64 "$WORK/x86linux_qual" --allow-emulated-selftest > "$WORK/x86_emu.out"
    cat "$WORK/x86_emu.out"
    grep -q 'VERDICT=EMULATED_SELFTEST_PASS' "$WORK/x86_emu.out"
    X86_STATUS="EMULATED_SELFTEST_PASS_PHYSICAL_NOT_RUN"
fi

echo "OMEGA-GPU-QUAL PASS host_controls=all x86linux=$X86_STATUS non_nvidia_live_exit=$LIVE_NNQ_RC"
