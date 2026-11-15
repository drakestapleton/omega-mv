#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
# Correctness first. Then, only when /dev/kfd exists, one process times two
# arms at the same shapes, each in a hot mode and a cold mode:
#   hipblasLtMatmul, FP8 x FP8 into f32 (the library has no FP8 x FP32 GEMM)
#   fp8gemv_stream, FP8 weights x FP32 activations plus a per-row scale,
#   with the row-remap bit clear and with it set
# Hot is 10 calls on the buffers being timed, then 21 samples, in that process.
# Cold reads a 512 MiB device buffer in that process and then times the next
# call on the same operands. hipblaslt-bench is not invoked: its --flush is
# s_icache_inv, and its --rotating copies are initialized before one averaged
# interval. The kernel's y is compared to the CPU plain reference before any
# sample. A mismatch prints FAIL and exits non-zero. No device: exit non-zero.
# 5.3 TB/s is the published MI300X HBM peak, not a measurement.
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../.." && pwd)
OMC=$ROOT/seed/out/omc
QEMU=/usr/bin/qemu-aarch64-static

"$HERE/check.sh"

echo "shapes M in 4096 8192 14336 28672, K in 4096 8192, batch 1"
echo "kernel flags: bit0 row remap, bit1 residual+rmsnorm scale, bit2 bf16 store"
echo "peak denominator 5.3 TB/s (published MI300X HBM peak, not a measurement)"
echo "hipBLASLt is f8_fnuz_r x f8_fnuz_r into f32 (compute f32, D f32, scalar scales 1)."
echo "That is HIP_R_8F_E4M3_FNUZ. The type table has no FP8 x FP32 matmul."
echo "The kernel is FP8 weights x FP32 activations plus a per-row scale."
echo "kernel bytes are M*K+4*K+8*M. library bytes are M*K+K+4*M. Each GB/s uses its own count."
echo "Non-weight bytes are at most 0.293% of the kernel weight bytes and 0.122% of the library weight bytes at these shapes (both maxima at M=K=4096)."
echo "The library GB/s is the median of this process's hipblasLtMatmul samples and M*K+K+4*M. hipblaslt-bench is not the timer, so there is no bench_GB/s column."
echo "kernel_swizzle is flags bit 0. Same byte count either way. It is not --swizzleA."
echo "5.3 TB/s is the published peak, not a measurement."
echo "mode hot: 10 warmups then 21 samples, one process, no extra read. mode cold: a 512 MiB device read, then the next call on the same operands, 21 times."

if [ ! -e /dev/kfd ]; then
  echo "BLOCKED_HARDWARE no /dev/kfd"
  exit 1
fi

HIPCC=$(command -v hipcc || true)
if [ -z "$HIPCC" ] && [ -x /opt/rocm/bin/hipcc ]; then
  HIPCC=/opt/rocm/bin/hipcc
fi
if [ -z "$HIPCC" ]; then
  echo "BLOCKED_HARDWARE /dev/kfd is present but hipcc is not on PATH" >&2
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
env -i "$QEMU" "$work/hsaco" "$HERE/fp8gemv_stream.isa" > "$work/fp8gemv_stream.hsaco" 2>"$work/herr"
if [ -s "$work/herr" ]; then
  cat "$work/herr" >&2
  exit 1
fi

echo "compile time_fp8gemv"
if ! "$HIPCC" -O2 -std=c++17 -ffp-contract=off -o "$work/time_fp8gemv" \
  "$HERE/time_fp8gemv.cpp" -lhipblaslt; then
  echo "BLOCKED_HARDWARE hipcc could not link hipblaslt" >&2
  exit 1
fi
"$work/time_fp8gemv" "$work/fp8gemv_stream.hsaco"

echo "profiler commands this script does not run:"
echo "rocprof --stats --kernel fp8gemv_stream $work/time_fp8gemv $work/fp8gemv_stream.hsaco"
echo "omniperf profile -n fp8gemv -- $work/time_fp8gemv $work/fp8gemv_stream.hsaco"

echo "bench.sh pass"
