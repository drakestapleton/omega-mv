#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
# Correctness first. Then, only when /dev/kfd exists, time two things at the
# same shapes, each in a hot mode and a cold mode:
#   hipblaslt-bench, FP8 x FP8 into f32 (the library has no FP8 x FP32 GEMM)
#   fp8gemv_stream, FP8 weights x FP32 activations plus a per-row scale,
#   with the row-remap bit clear and with it set
# Cold, on both, reads a 512 MiB device buffer (larger than 256 MB) between
# samples via `time_fp8gemv --flush`. Hot does not. hipblaslt-bench --flush
# is an instruction-cache flush and is not passed.
# The kernel's y is compared to the CPU plain reference before any sample.
# A mismatch prints FAIL and exits non-zero. No device: exit non-zero.
# 5.3 TB/s is the published MI300X HBM peak, not a measurement.
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../.." && pwd)
OMC=$ROOT/seed/out/omc
QEMU=/usr/bin/qemu-aarch64-static
WARMUP=10
RUNS=21
PEAK=5300

"$HERE/check.sh"

echo "shapes M in 4096 8192 14336 28672, K in 4096 8192, batch 1"
echo "kernel flags: bit0 row remap, bit1 residual+rmsnorm scale, bit2 bf16 store"
echo "peak denominator 5.3 TB/s (published MI300X HBM peak, not a measurement)"
echo "hipBLASLt is f8_fnuz_r x f8_fnuz_r into f32 (compute f32, D f32, scalar scales 1)."
echo "That is HIP_R_8F_E4M3_FNUZ. The type table has no FP8 x FP32 matmul."
echo "The kernel is FP8 weights x FP32 activations plus a per-row scale."
echo "kernel bytes are M*K+4*K+8*M. library bytes are M*K+K+4*M. Each GB/s uses its own count."
echo "Non-weight bytes are at most 0.293% of the kernel weight bytes and 0.122% of the library weight bytes at these shapes (both maxima at M=K=4096)."
echo "bench_GB/s is the hipblaslt-GB/s column, not the figure from the library byte count."
echo "kernel_swizzle is flags bit 0. Same byte count either way. It is not --swizzleA."
echo "5.3 TB/s is the published peak, not a measurement."
echo "mode hot: no extra read between samples. mode cold: time_fp8gemv --flush reads 512 MiB on the device between samples, on both arms."

if [ ! -e /dev/kfd ]; then
  echo "BLOCKED_HARDWARE no /dev/kfd"
  exit 1
fi

if ! command -v hipblaslt-bench >/dev/null 2>&1; then
  echo "BLOCKED_HARDWARE /dev/kfd is present but hipblaslt-bench is not on PATH" >&2
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
"$HIPCC" -O2 -std=c++17 -ffp-contract=off -o "$work/time_fp8gemv" "$HERE/time_fp8gemv.cpp"
"$work/time_fp8gemv" "$work/fp8gemv_stream.hsaco"

echo "profiler commands this script does not run:"
echo "rocprof --stats --kernel fp8gemv_stream $work/time_fp8gemv $work/fp8gemv_stream.hsaco"
echo "omniperf profile -n fp8gemv -- $work/time_fp8gemv $work/fp8gemv_stream.hsaco"

# One hipblaslt-bench process times a single iteration. Hot warms that
# process's own buffers (--cold_iters WARMUP) and does not read the flush
# buffer. Cold reads it first (the same 512 MiB device read the kernel uses)
# and times the iteration with no warmup. --flush is not passed: that flag
# flushes the instruction cache, which is not the L2/MALL read.
# --use_gpu_timer keeps process startup out of the us column. Library bytes
# are the FP8 matrix, the FP8 vector and the f32 result. beta is 0, so C is
# not part of that count.
lib_one() {
  mode=$1
  M=$2
  K=$3
  cold_iters=$4
  if [ "$mode" = cold ]; then
    "$work/time_fp8gemv" --flush
  fi
  hipblaslt-bench \
    --api_method c \
    --function matmul \
    -m "$M" -n 1 -k "$K" \
    --transA T --transB N \
    --a_type f8_fnuz_r --b_type f8_fnuz_r \
    --c_type f32_r --d_type f32_r \
    --compute_type f32_r --scale_type f32_r --bias_type f32_r \
    --scaleA 1 --scaleB 1 \
    --alpha 1 --beta 0 \
    --lda "$K" --ldb "$K" --ldc "$M" --ldd "$M" \
    --stride_a 0 --stride_b 0 --stride_c 0 --stride_d 0 \
    --batch_count 1 \
    --initialization hpl \
    --cold_iters "$cold_iters" --iters 1 \
    --use_gpu_timer --print_kernel_info \
    > "$work/blt.out" 2>"$work/blt.err" || {
      echo "hipblaslt-bench failed for M=$M K=$K mode=$mode" >&2
      cat "$work/blt.err" >&2
      cat "$work/blt.out" >&2
      exit 1
    }
  python3 - "$work/blt.out" "$work/samples" << 'PY'
import sys
text = open(sys.argv[1]).read().splitlines()
header = None
start = 0
for i, line in enumerate(text):
    fields = [p.strip() for p in line.split(",")]
    if "us" in fields and "hipblaslt-GB/s" in fields:
        header = fields
        start = i + 1
        break
if header is None:
    sys.stderr.write("hipblaslt-bench output has no us column\n")
    sys.stderr.write("\n".join(text) + "\n")
    sys.exit(1)
us_at = header.index("us")
gb_at = header.index("hipblaslt-GB/s")
us = None
gb = None
for line in text[start:]:
    if line.startswith("["):
        continue
    fields = [p.strip() for p in line.split(",")]
    if len(fields) <= max(us_at, gb_at):
        continue
    if not fields[us_at]:
        continue
    us = float(fields[us_at])
    gb = float(fields[gb_at])
    break
if us is None:
    sys.stderr.write("hipblaslt-bench output has no data row\n")
    sys.stderr.write("\n".join(text) + "\n")
    sys.exit(1)
with open(sys.argv[2], "a") as out:
    out.write(f"{us} {gb}\n")
PY
}

for mode in hot cold; do
  if [ "$mode" = hot ]; then
    cold_iters=$WARMUP
  else
    cold_iters=0
  fi
  for M in 4096 8192 14336 28672; do
    for K in 4096 8192; do
      : > "$work/samples"
      n=0
      while [ "$n" -lt "$RUNS" ]; do
        lib_one "$mode" "$M" "$K" "$cold_iters"
        n=$((n + 1))
      done
      python3 - "$work/samples" "$mode" "$M" "$K" "$cold_iters" "$RUNS" "$PEAK" << 'PY'
import sys
path, mode, M, K, warmup, runs, peak = sys.argv[1:]
M, K, warmup, runs = int(M), int(K), int(warmup), int(runs)
peak = float(peak)
rows = [tuple(map(float, line.split())) for line in open(path) if line.strip()]
if len(rows) != runs:
    sys.stderr.write(f"expected {runs} samples, got {len(rows)}\n")
    sys.exit(1)
us = sorted(v[0] for v in rows)
med = us[len(us) // 2]
# Library reads M*K FP8 weights and K FP8 activations, and writes M f32 results.
# bench_GB/s is the median of hipblaslt-bench's own hipblaslt-GB/s column.
lib_bytes = M * K + K + 4 * M
gbps = lib_bytes / (med * 1e-6) / 1e9
reported = [v[1] for v in rows]
reported.sort()
rep = reported[len(reported) // 2]
print(
    f"hipblaslt mode {mode} M {M} K {K} warmup {warmup} runs {runs} "
    f"min_us {us[0]:.4f} median_us {med:.4f} max_us {us[-1]:.4f} "
    f"spread_us {us[-1] - us[0]:.4f} bytes {lib_bytes} "
    f"GB/s {gbps:.4f} bench_GB/s {rep:.4f} "
    f"pct_of_5.3TBs {gbps / peak * 100:.4f}"
)
print("samples_us", " ".join(f"{v[0]:.4f}" for v in rows))
PY
    done
  done
done

echo "bench.sh pass"
