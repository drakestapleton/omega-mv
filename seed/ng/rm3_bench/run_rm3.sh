#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# seed/ng/rm3_bench/run_rm3.sh: Reproducible Omega 1.0 RM3 Paired Efficiency Benchmark Runner.
#
# Runs on Linux AArch64 (DGX Spark Grace Cortex-X925 cores 5-9) with:
#   - Pure seeded OM-2 conductor (seed/ng/rm3_bench/rm3_bench.om)
#   - 4 arms: omc (seed/out/omc), ng (@ng front-ir + @ng opt + @ng a64), gcc -O2 -static, gcc -O3 -static
#   - 11 real kernels from seed/ng/bench/kernels/:
#       arith bcopy branch chacha fib38 isort leafcall matmul sha sieve sort
#   - Exact output equality checked fail-closed BEFORE timing + planted wrong-output negative control
#   - Interleaved rotated/alternating paired timing pinned via taskset -c 5-9
#   - Exact monons compile-time measurement (median of 3 builds per kernel & arm) + binary/code sizes
#
# Usage:
#   sh seed/ng/rm3_bench/run_rm3.sh [REPO_ROOT] [OUTDIR] [WARM] [REPS] [CPUS]
# Defaults:
#   REPO_ROOT=.  OUTDIR=/tmp/om_sw_rm3_run  WARM=2  REPS=7  CPUS=5-9

set -eu

REPO="${1:-.}"
OUT="${2:-/tmp/om_sw_rm3_run}"
WARM="${3:-2}"
REPS="${4:-7}"
CPUS="${5:-5-9}"

OMC="$REPO/seed/out/omc"
KDIR="$REPO/seed/ng/bench/kernels"
KERNELS="arith bcopy branch chacha fib38 isort leafcall matmul sha sieve sort"

if [ ! -x "$OMC" ]; then
  echo "run_rm3: missing executable $OMC" >&2
  exit 2
fi

rm -rf "$OUT"
mkdir -p "$OUT/bin/omc" "$OUT/bin/ng" "$OUT/bin/gccO2" "$OUT/bin/gccO3" "$OUT/ir" "$OUT/scr" "$OUT/neg"

echo "=== [1/5] Building pure-OM-2 rm3_bench conductor and ng compiler ==="
(printf 'om2\n'; cat "$REPO/seed/ng/sha256.om" "$REPO/seed/ng/rm3_bench/rm3_bench.om") \
  | "$OMC" > "$OUT/rm3_bench"
chmod +x "$OUT/rm3_bench"

(
  while IFS=' ' read -r _sha upath; do
    cat "$REPO/$upath"
  done < "$REPO/seed/ng/ng.units"
) | "$OMC" > "$OUT/ng"
chmod +x "$OUT/ng"

echo "=== [2/5] Recording hardware, compiler, and protocol provenance ==="
{
  echo "host=$(hostname)"
  echo "uname=$(uname -a)"
  echo "cpus_pinned=$CPUS"
  echo "warm=$WARM"
  echo "reps=$REPS"
  echo "load_start=$(cat /proc/loadavg)"
  echo "omc_sha256=$(sha256sum "$OMC" | awk '{print $1}')"
  echo "ng_sha256=$(sha256sum "$OUT/ng" | awk '{print $1}')"
  echo "rm3_bench_om_sha256=$(sha256sum "$REPO/seed/ng/rm3_bench/rm3_bench.om" | awk '{print $1}')"
  echo "rm3_bench_bin_sha256=$(sha256sum "$OUT/rm3_bench" | awk '{print $1}')"
  echo "protocol_sha256=$(sha256sum "$REPO/bench/omc_efficiency/PROTOCOL.md" | awk '{print $1}')"
  echo "gcc_version=$(/usr/bin/gcc --version | head -n 1)"
  echo "gcc_sha256=$(sha256sum /usr/bin/gcc | awk '{print $1}')"
  echo "--- lscpu ---"
  lscpu | grep -E "Architecture|Model name|CPU\(s\)|Core|Vendor|BogoMIPS" || true
} > "$OUT/hwid.txt"
cat "$OUT/hwid.txt"

echo "=== [3/5] Compiling 11 kernels across 4 arms (3 timed builds each -> median compile ns) ==="
: > "$OUT/compile.tsv"
printf "kernel\tarm\tcomp_med_ns\telf_bytes\ttext_bytes\tbin_sha256\n" >> "$OUT/compile.tsv"

med3() {
  printf '%s\n%s\n%s\n' "$1" "$2" "$3" | sort -n | sed -n '2p'
}

for k in $KERNELS; do
  # Arm 1: omc
  c1=$("$OUT/rm3_bench" time_io "$KDIR/$k.om" "$OUT/bin/omc/$k" "$OUT/scr/err" "$OMC" | awk '$1=="C"{print $2}')
  c2=$("$OUT/rm3_bench" time_io "$KDIR/$k.om" "$OUT/bin/omc/$k" "$OUT/scr/err" "$OMC" | awk '$1=="C"{print $2}')
  c3=$("$OUT/rm3_bench" time_io "$KDIR/$k.om" "$OUT/bin/omc/$k" "$OUT/scr/err" "$OMC" | awk '$1=="C"{print $2}')
  chmod +x "$OUT/bin/omc/$k"
  cm=$(med3 "$c1" "$c2" "$c3")
  sz=$(wc -c < "$OUT/bin/omc/$k")
  sh=$(sha256sum "$OUT/bin/omc/$k" | awk '{print $1}')
  printf "%s\tomc\t%s\t%s\t%s\t%s\n" "$k" "$cm" "$sz" "$sz" "$sh" >> "$OUT/compile.tsv"

  # Arm 2: ng (@ng front-ir -> @ng opt -> @ng a64)
  (printf '@ng front-ir\n'; cat "$KDIR/$k.om") > "$OUT/ir/$k.in1"
  nt1=0; nt2=0; nt3=0
  for r in 1 2 3; do
    t1=$("$OUT/rm3_bench" time_io "$OUT/ir/$k.in1" "$OUT/ir/$k.ir" "$OUT/scr/err" "$OUT/ng" | awk '$1=="C"{print $2}')
    (printf '@ng opt\n'; cat "$OUT/ir/$k.ir") > "$OUT/ir/$k.in2"
    t2=$("$OUT/rm3_bench" time_io "$OUT/ir/$k.in2" "$OUT/ir/$k.opt" "$OUT/scr/err" "$OUT/ng" | awk '$1=="C"{print $2}')
    (printf '@ng a64\n'; cat "$OUT/ir/$k.opt") > "$OUT/ir/$k.in3"
    t3=$("$OUT/rm3_bench" time_io "$OUT/ir/$k.in3" "$OUT/bin/ng/$k" "$OUT/scr/err" "$OUT/ng" | awk '$1=="C"{print $2}')
    tot=$((t1 + t2 + t3))
    eval "nt$r=$tot"
  done
  chmod +x "$OUT/bin/ng/$k"
  cm=$(med3 "$nt1" "$nt2" "$nt3")
  sz=$(wc -c < "$OUT/bin/ng/$k")
  sh=$(sha256sum "$OUT/bin/ng/$k" | awk '{print $1}')
  printf "%s\tng\t%s\t%s\t%s\t%s\n" "$k" "$cm" "$sz" "$sz" "$sh" >> "$OUT/compile.tsv"

  # Arm 3: gcc -O2 -static (also record kernel .text via gcc -O2 -c)
  c1=$("$OUT/rm3_bench" time_io /dev/null /dev/null "$OUT/scr/err" /usr/bin/gcc -B/usr/bin/ -O2 -static -o "$OUT/bin/gccO2/$k" "$KDIR/$k.c" | awk '$1=="C"{print $2}')
  c2=$("$OUT/rm3_bench" time_io /dev/null /dev/null "$OUT/scr/err" /usr/bin/gcc -B/usr/bin/ -O2 -static -o "$OUT/bin/gccO2/$k" "$KDIR/$k.c" | awk '$1=="C"{print $2}')
  c3=$("$OUT/rm3_bench" time_io /dev/null /dev/null "$OUT/scr/err" /usr/bin/gcc -B/usr/bin/ -O2 -static -o "$OUT/bin/gccO2/$k" "$KDIR/$k.c" | awk '$1=="C"{print $2}')
  /usr/bin/gcc -O2 -c -o "$OUT/scr/$k.O2.o" "$KDIR/$k.c"
  tb=$(size "$OUT/scr/$k.O2.o" | awk 'NR==2{print $1}')
  cm=$(med3 "$c1" "$c2" "$c3")
  sz=$(wc -c < "$OUT/bin/gccO2/$k")
  sh=$(sha256sum "$OUT/bin/gccO2/$k" | awk '{print $1}')
  printf "%s\tgccO2\t%s\t%s\t%s\t%s\n" "$k" "$cm" "$sz" "$tb" "$sh" >> "$OUT/compile.tsv"

  # Arm 4: gcc -O3 -static (also record kernel .text via gcc -O3 -c)
  c1=$("$OUT/rm3_bench" time_io /dev/null /dev/null "$OUT/scr/err" /usr/bin/gcc -B/usr/bin/ -O3 -static -o "$OUT/bin/gccO3/$k" "$KDIR/$k.c" | awk '$1=="C"{print $2}')
  c2=$("$OUT/rm3_bench" time_io /dev/null /dev/null "$OUT/scr/err" /usr/bin/gcc -B/usr/bin/ -O3 -static -o "$OUT/bin/gccO3/$k" "$KDIR/$k.c" | awk '$1=="C"{print $2}')
  c3=$("$OUT/rm3_bench" time_io /dev/null /dev/null "$OUT/scr/err" /usr/bin/gcc -B/usr/bin/ -O3 -static -o "$OUT/bin/gccO3/$k" "$KDIR/$k.c" | awk '$1=="C"{print $2}')
  /usr/bin/gcc -O3 -c -o "$OUT/scr/$k.O3.o" "$KDIR/$k.c"
  tb=$(size "$OUT/scr/$k.O3.o" | awk 'NR==2{print $1}')
  cm=$(med3 "$c1" "$c2" "$c3")
  sz=$(wc -c < "$OUT/bin/gccO3/$k")
  sh=$(sha256sum "$OUT/bin/gccO3/$k" | awk '{print $1}')
  printf "%s\tgccO3\t%s\t%s\t%s\t%s\n" "$k" "$cm" "$sz" "$tb" "$sh" >> "$OUT/compile.tsv"
done

echo "=== [4/5] Negative control: planted wrong-output arm MUST fail closed (exit 1) ==="
cat > "$OUT/neg/wrong_fib.om" << 'EOF'
om2
text m "39088170\n"
fn main to int
w = write 1 m 0 len m
ret 0
end
EOF
"$OMC" < "$OUT/neg/wrong_fib.om" > "$OUT/neg/wrong_fib"
chmod +x "$OUT/neg/wrong_fib"
WANT_FIB=$(cat "$KDIR/want/fib38.sha256")
set +e
"$OUT/rm3_bench" run 1 2 "$OUT/scr" fib38 "$WANT_FIB" \
  omc "$OUT/bin/omc/fib38" mutant "$OUT/neg/wrong_fib" > "$OUT/neg/neg.out" 2>&1
NEG_RC=$?
set -e
if [ "$NEG_RC" -ne 1 ] || ! grep -q "R MISMATCH fib38 mutant" "$OUT/neg/neg.out"; then
  echo "run_rm3: NEGATIVE CONTROL FAILED (rc=$NEG_RC)" >&2
  cat "$OUT/neg/neg.out" >&2
  exit 1
fi
echo "NEG_CONTROL_OK planted_wrong_output caught (rc=$NEG_RC)"

echo "=== [5/5] Interleaved paired timing (taskset -c $CPUS, warm=$WARM, reps=$REPS) ==="
: > "$OUT/rows.txt"
for k in $KERNELS; do
  WANT=$(cat "$KDIR/want/$k.sha256")
  echo "--- kernel: $k ---"
  taskset -c "$CPUS" "$OUT/rm3_bench" run "$WARM" "$REPS" "$OUT/scr" "$k" "$WANT" \
    omc "$OUT/bin/omc/$k" \
    ng "$OUT/bin/ng/$k" \
    gccO2 "$OUT/bin/gccO2/$k" \
    gccO3 "$OUT/bin/gccO3/$k" | tee -a "$OUT/rows.txt" | grep -E '^(P |S |RM3_BENCH_)'
done
echo "load_end=$(cat /proc/loadavg)" >> "$OUT/hwid.txt"
echo "RM3_RUN_COMPLETE out=$OUT"
