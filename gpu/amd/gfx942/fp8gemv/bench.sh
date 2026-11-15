#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
# Correctness first. Then, only when /dev/kfd exists, time two things at the
# same shapes:
#   hipblaslt-bench, FP8 x FP8 (the library has no FP8 x FP32 GEMM)
#   fp8gemv_stream with the row-remap bit clear, and with it set
# Warmup, then N samples, then median and spread. The denominator is the
# published MI300X HBM peak of 5.3 TB/s. No device: exit non-zero.
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
echo "hipBLASLt baseline is f8_fnuz_r x f8_fnuz_r, compute f32, D f32, scalar scales 1."
echo "That is HIP_R_8F_E4M3_FNUZ. The type table has no FP8 x FP32 matmul."
echo "The Omega kernel is FP8 x FP32 with a per-row scale. The two GB/s figures are different ops."
echo "kernel_swizzle is flags bit 0 of fp8gemv_stream, not hipblaslt-bench --swizzleA."

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
"$HIPCC" -O2 -o "$work/time_fp8gemv" "$HERE/time_fp8gemv.cpp"
"$work/time_fp8gemv" "$work/fp8gemv_stream.hsaco"

echo "profiler commands this script does not run:"
echo "rocprof --stats --kernel fp8gemv_stream $work/time_fp8gemv $work/fp8gemv_stream.hsaco"
echo "omniperf profile -n fp8gemv -- $work/time_fp8gemv $work/fp8gemv_stream.hsaco"

# One hipblaslt-bench process times a single iteration after WARMUP cold iterations.
# RUNS of those processes are the samples. --use_gpu_timer keeps process startup
# out of the us column. Library bytes are the FP8 matrix, the FP8 vector and the
# f32 result. beta is 0, so C is not part of that count.
lib_one() {
  M=$1
  K=$2
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
    --cold_iters "$WARMUP" --iters 1 \
    --use_gpu_timer --flush --print_kernel_info \
    > "$work/blt.out" 2>"$work/blt.err" || {
      echo "hipblaslt-bench failed for M=$M K=$K" >&2
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

for M in 4096 8192 14336 28672; do
  for K in 4096 8192; do
    : > "$work/samples"
    n=0
    while [ "$n" -lt "$RUNS" ]; do
      lib_one "$M" "$K"
      n=$((n + 1))
    done
    python3 - "$work/samples" "$M" "$K" "$WARMUP" "$RUNS" "$PEAK" << 'PY'
import sys
path, M, K, warmup, runs, peak = sys.argv[1:]
M, K, warmup, runs = int(M), int(K), int(warmup), int(runs)
peak = float(peak)
rows = [tuple(map(float, line.split())) for line in open(path) if line.strip()]
if len(rows) != runs:
    sys.stderr.write(f"expected {runs} samples, got {len(rows)}\n")
    sys.exit(1)
us = sorted(v[0] for v in rows)
med = us[len(us) // 2]
# Library reads M*K FP8 weights and K FP8 activations, and writes M f32 results.
# Reported hipblaslt-GB/s is whatever the bench counted; both are printed.
lib_bytes = M * K + K + 4 * M
gbps = lib_bytes / (med * 1e-6) / 1e9
reported = [v[1] for v in rows]
reported.sort()
rep = reported[len(reported) // 2]
print(
    f"hipblaslt M {M} K {K} warmup {warmup} runs {runs} "
    f"min_us {us[0]:.4f} median_us {med:.4f} max_us {us[-1]:.4f} "
    f"spread_us {us[-1] - us[0]:.4f} bytes {lib_bytes} "
    f"GB/s {gbps:.4f} bench_GB/s {rep:.4f} "
    f"pct_of_5.3TBs {gbps / peak * 100:.4f}"
)
print("samples_us", " ".join(f"{v[0]:.4f}" for v in rows))
PY
  done
done

echo "bench.sh pass"
