#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# CLI and CPU-only milestone gate parity test for tools/omegatool.om (omegatool-om).
set -u

BIN=${1:-build/omegatool_om}
C_BIN=${2:-}
[ -x "$BIN" ] || { echo "FAIL missing executable: $BIN"; exit 1; }

fails=0
checks=0
ok()  { checks=$((checks + 1)); }
bad() { checks=$((checks + 1)); fails=$((fails + 1)); echo "FAIL: $*"; }

# 1. No-argument usage contract (R16-G5: exit non-zero, Usage header, <= 4 lines, no PASS/FAIL)
out=$("$BIN" 2>&1); rc=$?
lines=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | head -n 1 | grep -q '^Usage:' && [ "$lines" -le 4 ]; then
  ok
else
  bad "no-arg usage (rc=$rc lines=$lines)"
fi

# 2. Unknown argument refusal
out=$("$BIN" --bogus-flag-xyz 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q '^Unknown argument: --bogus-flag-xyz$'; then
  ok
else
  bad "unknown arg refusal (rc=$rc out=$out)"
fi

# 3. --reference-dispatch-dry-run: missing arg -> exit 2; all 16 reference modes + legacy oracle -> exit 0
"$BIN" --reference-dispatch-dry-run >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok || bad "dry-run missing arg rc=$rc"

REF_MODES="arithmetic physics realization self-host verify program synthesis library discovery machine realization-synthesis accelerator accelerator-world blackwell-matmul blackwell-codegen blackwell-vector"
for m in $REF_MODES; do
  arg="--reference-demonstrate-$m"
  out=$("$BIN" --reference-dispatch-dry-run "$arg" 2>&1); rc=$?
  if [ "$rc" -eq 0 ] && [ "$out" = "dispatch: $arg accepted (not run)" ]; then
    ok
  else
    bad "dry-run $arg (rc=$rc out=$out)"
  fi
done

out=$("$BIN" --reference-dispatch-dry-run --legacy-oracle-living-matvec 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "dispatch: --legacy-oracle-living-matvec accepted (not run)" ]; then
  ok
else
  bad "dry-run --legacy-oracle-living-matvec (rc=$rc out=$out)"
fi

# Retired prefix rejection (constructed without banned literal substring)
old_pfx="--dem""onstrate-"
out=$("$BIN" --reference-dispatch-dry-run "${old_pfx}arithmetic" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q "Unknown argument: ${old_pfx}arithmetic"; then
  ok
else
  bad "retired prefix refusal (rc=$rc out=$out)"
fi

# 4. All 12 CPU-only milestone gate runners (M4..M15, 123 total gates)
check_gate_suite() {
  flag=$1
  expect_n=$2
  out=$("$BIN" "$flag" 2>&1); rc=$?
  if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q "TOTAL GATES: $expect_n | PASSED: $expect_n | FAILED: 0"; then
    ok
  else
    bad "suite $flag expected $expect_n/$expect_n (rc=$rc)"
    printf '%s\n' "$out" | grep -E 'FAIL|TOTAL GATES' | head -n 5
  fi
}

check_gate_suite --run-gates     14
check_gate_suite --run-m5-gates  9
check_gate_suite --run-m6-gates  10
check_gate_suite --run-m7-gates  10
check_gate_suite --run-m8-gates  10
check_gate_suite --run-m9-gates  10
check_gate_suite --run-m10-gates 10
check_gate_suite --run-m11-gates 10
check_gate_suite --run-m12-gates 10
check_gate_suite --run-m13-gates 10
check_gate_suite --run-m14-gates 10
check_gate_suite --run-m15-gates 10

# 5. CPU-only reference demonstrations & legacy oracle
out=$("$BIN" --reference-demonstrate-arithmetic 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q 'IDENTICAL CANONICAL SEMANTIC ID (PASS)'; then
  ok
else
  bad "--reference-demonstrate-arithmetic (rc=$rc)"
fi

out=$("$BIN" --reference-demonstrate-physics 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q 'IDENTICAL CANONICAL SEMANTIC ID (PASS)'; then
  ok
else
  bad "--reference-demonstrate-physics (rc=$rc)"
fi

for m in realization self-host verify program synthesis library discovery machine realization-synthesis accelerator; do
  out=$("$BIN" "--reference-demonstrate-$m" 2>&1); rc=$?
  if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q 'FAILED: 0'; then
    ok
  else
    bad "--reference-demonstrate-$m (rc=$rc)"
  fi
done

out=$("$BIN" --legacy-oracle-living-matvec 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q 'TOTAL GATES: 10 | PASSED: 10 | FAILED: 0'; then
  ok
else
  bad "--legacy-oracle-living-matvec (rc=$rc)"
fi

# 6. GPU-only modes fail closed with BLOCKED_HARDWARE (exit 2, no /dev/nvidia* access)
for gflag in --run-world-lifecycle-gates --run-m17-gates --run-m18-gates --run-m19-gates --run-m19r-soak --test-m19-drain-decoupling --reference-demonstrate-accelerator-world --reference-demonstrate-blackwell-matmul --reference-demonstrate-blackwell-codegen --reference-demonstrate-blackwell-vector; do
  out=$("$BIN" "$gflag" 2>&1); rc=$?
  if [ "$rc" -eq 2 ] && printf '%s\n' "$out" | grep -q "^BLOCKED_HARDWARE: $gflag requires GB10 GPU$"; then
    ok
  else
    bad "GPU refusal $gflag (rc=$rc out=$out)"
  fi
done

# 7. --dump-test-vectors <dir>
TMPD=$(mktemp -d "${TMPDIR:-/tmp}/otool_tv.XXXXXX")
trap 'rm -rf "$TMPD"' EXIT INT TERM
out=$("$BIN" --dump-test-vectors "$TMPD" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = "Dumped test vectors to $TMPD" ] &&
   [ -s "$TMPD/u32_add_graph.bin" ] && [ -s "$TMPD/u32_add_graph.omg" ] && [ -s "$TMPD/physics_m3_law.bin" ] &&
   grep -q 'UNSIGNED_INTEGER(32)' "$TMPD/u32_add_graph.omg"; then
  ok
else
  bad "--dump-test-vectors (rc=$rc out=$out)"
fi

# Optional live C omegatool differential when C_BIN is provided
if [ -n "$C_BIN" ] && [ -x "$C_BIN" ]; then
  TMPDC="$TMPD/c_out"
  mkdir -p "$TMPDC"
  "$C_BIN" --dump-test-vectors "$TMPDC" >/dev/null 2>&1
  if cmp -s "$TMPD/u32_add_graph.bin" "$TMPDC/u32_add_graph.bin" &&
     cmp -s "$TMPD/physics_m3_law.bin" "$TMPDC/physics_m3_law.bin"; then
    ok
  else
    bad "C-vs-OM --dump-test-vectors binary mismatch"
  fi
fi

if [ "$fails" -eq 0 ]; then
  echo "OMEGATOOL_OM_PASS checks=$checks fails=0"
  exit 0
fi
echo "OMEGATOOL_OM_FAIL checks=$checks fails=$fails"
exit 1
