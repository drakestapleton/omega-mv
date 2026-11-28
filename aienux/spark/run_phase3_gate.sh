#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# aienux/spark/run_phase3_gate.sh: Complete host + 20-core QEMU virt verification gate
# for Phase 3 Unified SPARK.EFI Wiring (spark-glue).
# Strictly host/QEMU-only; ZERO Spark GPU/ESP/SSD/live-service disruption.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/phase3-gate.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

OS=$(uname -s)
if [ "$OS" = "Darwin" ]; then
  # macOS host omc: $HOST_OMC, else a repo-local seed/out/omc-macos, else the omega-mv-macos checkout
  # at $OMEGA_MACOS_ROOT (default $HOME/workspace/omega-mv-macos). No user-specific absolute paths.
  if [ -z "${HOST_OMC:-}" ]; then
    for cand in "$ROOT/seed/out/omc-macos" \
                "${OMEGA_MACOS_ROOT:-$HOME/workspace/omega-mv-macos}/seed/out/omc-macos"; do
      if [ -x "$cand" ]; then HOST_OMC=$cand; break; fi
    done
  fi
  if [ -z "${HOST_OMC:-}" ] || [ ! -x "$HOST_OMC" ]; then
    echo "FAIL: macOS host omc not found (set HOST_OMC=/path/to/omc-macos or OMEGA_MACOS_ROOT)" >&2
    exit 1
  fi
  HOST_HDR="target a64macos"
  sign_bin() { codesign -s - "$1" >/dev/null 2>&1; }
  if [ -z "${EFI_OMC:-}" ]; then
    # Build up-to-date macOS host compiler from worktree seed/omc/omc.om (includes Slice A aefx)
    { printf 'target a64macos\n'; cat "$ROOT/seed/omc/omc.om"; } | "$HOST_OMC" > "$TMP/omc-efi"
    chmod +x "$TMP/omc-efi"
    sign_bin "$TMP/omc-efi"
    EFI_OMC="$TMP/omc-efi"
  fi
else
  HOST_OMC="${HOST_OMC:-$ROOT/seed/out/omc}"
  EFI_OMC="${EFI_OMC:-$ROOT/seed/out/omc}"
  HOST_HDR=""
  sign_bin() { :; }
fi

compile_host_om2() {
  out="$1"; shift
  if [ -n "$HOST_HDR" ]; then
    { printf '%s\nom2\n' "$HOST_HDR"; cat "$@"; } | "$HOST_OMC" > "$out"
  else
    { printf 'om2\n'; cat "$@"; } | "$HOST_OMC" > "$out"
  fi
  chmod +x "$out"
  sign_bin "$out"
}

compile_host_om1() {
  out="$1"; shift
  if [ -n "$HOST_HDR" ]; then
    { printf '%s\n' "$HOST_HDR"; cat "$@"; } | "$HOST_OMC" > "$out"
  else
    cat "$@" | "$HOST_OMC" > "$out"
  fi
  chmod +x "$out"
  sign_bin "$out"
}

echo "=== [1/13] Unified SPARK.EFI PE32+ Build (target a64efi) ==="
OMC="$EFI_OMC" sh "$ROOT/aienux/spark/build_spark_efi.sh" "$TMP/SPARK.EFI"

echo "=== [2/13] Boot Unified SPARK.EFI in 20-core 4 GiB QEMU virt EDK2 ==="
code=${A64EFI_CODE:-}
for f in /opt/homebrew/share/qemu/edk2-aarch64-code.fd \
         /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
         /usr/share/edk2/aarch64/QEMU_EFI.fd \
         /usr/share/AAVMF/QEMU_EFI.fd; do
  [ -z "$code" ] && [ -f "$f" ] && code=$f
done
[ -n "$code" ] && [ -f "$code" ] || { echo "FAIL: EDK2 firmware not found" >&2; exit 1; }
mkdir -p "$TMP/esp/EFI/BOOT"
cp "$TMP/SPARK.EFI" "$TMP/esp/EFI/BOOT/BOOTAA64.EFI"
timeout 40 qemu-system-aarch64 \
  -M virt,gic-version=3,its=on,virtualization=on -cpu max -smp 20 -m 4096 \
  -display none -bios "$code" \
  -drive if=none,id=d0,format=raw,file=fat:rw:"$TMP/esp" \
  -device virtio-blk-device,drive=d0 \
  -net none -serial file:"$TMP/qemu.log" -monitor none -no-reboot </dev/null >/dev/null 2>&1 || true
tr -d '\r' < "$TMP/qemu.log" | grep -E '\[SPARK|EL1_ALIVE|free_mib=|GICV3_|ITS_|SMP_ONLINE|PANIC'
grep -q '\[SPARK 1/6\]' "$TMP/qemu.log"
grep -q 'EL1_ALIVE current_el=1 mair=0x00000000440004ff' "$TMP/qemu.log"
grep -q 'nc_pool_mib=512' "$TMP/qemu.log"
grep -q 'GICV3_OK rev=3' "$TMP/qemu.log"
grep -q 'ITS_OK cmds=12' "$TMP/qemu.log"
grep -q 'SMP_ONLINE online=20 expected=20 failed=0' "$TMP/qemu.log"
grep -q '\[SPARK 2/6\]' "$TMP/qemu.log"
grep -q '\[SPARK FAIL stage=2 code=201\]' "$TMP/qemu.log"
if grep -q 'PANIC' "$TMP/qemu.log"; then
  echo "FAIL: unexpected PANIC in QEMU boot log" >&2
  exit 1
fi
echo "PASS qemu_20core_unified_spark_efi (Stage 1 20/20 SMP + Stage 2 fail-closed on absent GB20B)"

echo "=== [3/13] Full-Stack Host E2E Simulation (test_spark_e2e.om + Linux ELF compile) ==="
E2E_UNITS="
  $ROOT/aienux/kernel/hal/iort.om
  $ROOT/aienux/kernel/hal/bar0_mmio.om
  $ROOT/aienux/kernel/hal/pcie.om
  $ROOT/aienux/kernel/hal/smmuv3.om
  $ROOT/gpu/driver/gsp/irqbm.om
  $ROOT/gpu/driver/gsp/irq.om
  $ROOT/aienux/disk/sha256_bare.om
  $ROOT/aienux/disk/ext4_ro.om
  $ROOT/aienux/net/tcp/tcp.om
  $ROOT/gpu/driver/gsp/bm_hal.om
  $ROOT/gpu/driver/gsp/profile.om
  $ROOT/gpu/driver/gsp/mmio_bm.om
  $ROOT/gpu/driver/gsp/sec2.om
  $ROOT/gpu/driver/gsp/seq.om
  $ROOT/gpu/driver/gsp/seqcore.om
  $ROOT/gpu/driver/gsp/rpc.om
  $ROOT/gpu/driver/gsp/sysinfo.om
  $ROOT/gpu/driver/chan/params.om
  $ROOT/gpu/driver/gsp/boot.om
  $ROOT/gpu/driver/gsp/dispatch.om
  $ROOT/gpu/driver/gsp/fw_bm.om
  $ROOT/gpu/driver/gsp/arena_bm.om
  $ROOT/gpu/driver/gsp/transport_bm.om
  $ROOT/gpu/driver/chan/gmmu_bm.om
  $ROOT/gpu/driver/chan/mem.om
  $ROOT/gpu/driver/chan/chan.om
  $ROOT/gpu/driver/chan/complete.om
  $ROOT/gpu/driver/chan/rmchan.om
  $ROOT/gpu/driver/gsp/compute.om
  $ROOT/gpu/driver/gsp/q38_run.om
  $ROOT/aienux/net/wire/omtk.om
  $ROOT/aienux/net/wire/wire_loop.om
  $ROOT/aienux/spark/test_spark_e2e.om
"
# shellcheck disable=SC2086
compile_host_om2 "$TMP/test_spark_e2e" $E2E_UNITS
"$TMP/test_spark_e2e"
# shellcheck disable=SC2086
{ printf 'om2\n'; cat $E2E_UNITS; } | "$EFI_OMC" > "$TMP/test_spark_e2e.elf"
echo "PASS test_spark_e2e (host run + Linux AArch64 ELF compile $(wc -c < "$TMP/test_spark_e2e.elf" | tr -d ' ') B)"

echo "=== [4/13] Slice A Regression (host_test.om) ==="
compile_host_om2 "$TMP/slice_a_host" \
  "$ROOT/aienux/kernel/core/scheduler.om" \
  "$ROOT/aienux/kernel/core/ipc.om" \
  "$ROOT/aienux/kernel/core/pagetable.om" \
  "$ROOT/aienux/kernel/arm64/host_test.om"
"$TMP/slice_a_host"

echo "=== [5/13] Slice B Regression (pcie_smmu_test.om) ==="
compile_host_om2 "$TMP/pcie_smmu_test" \
  "$ROOT/aienux/kernel/hal/iort.om" \
  "$ROOT/aienux/kernel/hal/bar0_mmio.om" \
  "$ROOT/aienux/kernel/hal/pcie.om" \
  "$ROOT/aienux/kernel/hal/smmuv3.om" \
  "$ROOT/gpu/driver/gsp/logdec.om" \
  "$ROOT/gpu/driver/gsp/irqbm.om" \
  "$ROOT/gpu/driver/gsp/irq.om" \
  "$ROOT/gpu/driver/gsp/irqcc.om" \
  "$ROOT/aienux/kernel/hal/pcie_smmu_test.om"
"$TMP/pcie_smmu_test"

echo "=== [6/13] Slice C Regression (slice_c_gate.om) ==="
compile_host_om1 "$TMP/slice_c_gate" \
  "$ROOT/gpu/driver/gsp/bm_hal.om" \
  "$ROOT/gpu/driver/gsp/profile.om" \
  "$ROOT/gpu/driver/gsp/mmio_bm.om" \
  "$ROOT/gpu/driver/gsp/sec2.om" \
  "$ROOT/gpu/driver/gsp/seq.om" \
  "$ROOT/gpu/driver/gsp/seqcore.om" \
  "$ROOT/gpu/driver/gsp/rpc.om" \
  "$ROOT/gpu/driver/gsp/sysinfo.om" \
  "$ROOT/gpu/driver/chan/params.om" \
  "$ROOT/gpu/driver/gsp/boot.om" \
  "$ROOT/gpu/driver/gsp/dispatch.om" \
  "$ROOT/gpu/driver/gsp/fw_bm.om" \
  "$ROOT/gpu/driver/gsp/arena_bm.om" \
  "$ROOT/gpu/driver/gsp/transport_bm.om" \
  "$ROOT/gpu/driver/chan/gmmu_bm.om" \
  "$ROOT/gpu/driver/chan/mem.om" \
  "$ROOT/gpu/driver/chan/chan.om" \
  "$ROOT/gpu/driver/chan/complete.om" \
  "$ROOT/gpu/driver/chan/rmchan.om" \
  "$ROOT/gpu/driver/tests/slice_c_gate.om"
"$TMP/slice_c_gate"

echo "=== [7/13] Slice D Regression (run_slice_d.sh 7/7) ==="
OMC="$HOST_OMC" sh "$ROOT/aienux/disk/tests/run_slice_d.sh"

echo "=== [8/13] Slice E Regression (q38_run_test.om + pure-OM2 sm_121 SASS determinism & parity) ==="
compile_host_om1 "$TMP/q38_run_test" \
  "$ROOT/gpu/driver/tests/q38_run_shim.om" \
  "$ROOT/gpu/driver/gsp/compute.om" \
  "$ROOT/gpu/driver/gsp/q38_run.om" \
  "$ROOT/gpu/driver/tests/q38_run_test.om"
"$TMP/q38_run_test"
compile_host_om1 "$TMP/q38_sass_emit_1" \
  "$ROOT/gpu/nvidia/om/codegen/cg_dec_emit.om" \
  "$ROOT/gpu/nvidia/om/codegen/cg_dec.om" \
  "$ROOT/gpu/driver/tests/q38_sass_emit.om"
compile_host_om1 "$TMP/q38_sass_emit_2" \
  "$ROOT/gpu/nvidia/om/codegen/cg_dec_emit.om" \
  "$ROOT/gpu/nvidia/om/codegen/cg_dec.om" \
  "$ROOT/gpu/driver/tests/q38_sass_emit.om"
cmp -s "$TMP/q38_sass_emit_1" "$TMP/q38_sass_emit_2" || { echo "FAIL: q38_sass_emit non-deterministic" >&2; exit 1; }
compile_host_om1 "$TMP/q38_sass_enc_1" \
  "$ROOT/gpu/nvidia/om/components/bw_alloc.om" \
  "$ROOT/gpu/nvidia/om/encoder/bw_enc_sm121.om" \
  "$ROOT/gpu/driver/tests/q38_sass_encode.om"
compile_host_om1 "$TMP/q38_sass_enc_2" \
  "$ROOT/gpu/nvidia/om/components/bw_alloc.om" \
  "$ROOT/gpu/nvidia/om/encoder/bw_enc_sm121.om" \
  "$ROOT/gpu/driver/tests/q38_sass_encode.om"
cmp -s "$TMP/q38_sass_enc_1" "$TMP/q38_sass_enc_2" || { echo "FAIL: q38_sass_encode non-deterministic" >&2; exit 1; }
compile_host_om1 "$TMP/q38_sass_enc_canon" \
  "$ROOT/gpu/nvidia/om/components/bw_alloc.om" \
  "$ROOT/om/encoder/bw_enc_sm121.om" \
  "$ROOT/gpu/driver/tests/q38_sass_encode.om"
"$TMP/q38_sass_emit_1" > "$TMP/q38_ir.bin"
"$TMP/q38_sass_enc_1" < "$TMP/q38_ir.bin" > "$TMP/q38_sass_gpu.bin"
"$TMP/q38_sass_enc_canon" < "$TMP/q38_ir.bin" > "$TMP/q38_sass_canon.bin"
cmp -s "$TMP/q38_sass_gpu.bin" "$TMP/q38_sass_canon.bin" || { echo "FAIL: bw_enc_sm121 parity mismatch vs om/encoder/bw_enc_sm121.om" >&2; exit 1; }
[ "$(wc -c < "$TMP/q38_sass_gpu.bin" | tr -d ' ')" -gt 0 ] || { echo "FAIL: empty SASS output" >&2; exit 1; }
echo "PASS q38_sass_pure_om_parity (7/7 kernels, $(wc -c < "$TMP/q38_sass_gpu.bin" | tr -d ' ') B, 2x deterministic + om/encoder/bw_enc_sm121.om parity)"

echo "=== [9/13] Slice F Regression (test_loopback.om) ==="
compile_host_om2 "$TMP/test_loopback" \
  "$ROOT/aienux/net/tcp/tcp.om" \
  "$ROOT/aienux/net/wire/omtk.om" \
  "$ROOT/aienux/net/wire/wire_loop.om" \
  "$ROOT/aienux/net/wire/test_loopback.om"
"$TMP/test_loopback"

echo "=== [10/13] SMMUv3 mode-1 on QEMU virt,iommu=smmuv3 (smmu_qemu_test.om + edu DMA) ==="
sh "$ROOT/aienux/kernel/hal/run_smmu_qemu.sh" "$EFI_OMC"

echo "=== [11/13] Real spark_main.om under QEMU (PLAT=qemu: Stage 1-3 + SMMUv3 + NVMe/GPT/ext4/bundle) ==="
sh "$ROOT/aienux/spark/run_spark_qemu_e2e.sh" "$EFI_OMC"

echo "=== [12/13] Spark boot-tool safety (stage_bootnext.sh with stubbed dry-run/apply harness; offline) ==="
sh "$ROOT/tools/spark-boot/tests/test_stage_bootnext.sh"

echo "=== [13/13] Pure OM-2 Spec-Audit Gate (spec_audit.om + 84 error codes + 7 neg controls) ==="
compile_host_om2 "$TMP/spec_audit_1" "$ROOT/aienux/spark/spec_audit.om"
compile_host_om2 "$TMP/spec_audit_2" "$ROOT/aienux/spark/spec_audit.om"
cmp -s "$TMP/spec_audit_1" "$TMP/spec_audit_2" || { echo "FAIL: spec_audit non-deterministic build" >&2; exit 1; }
(cd "$ROOT" && "$TMP/spec_audit_1")

echo "PHASE_3_SPARK_GLUE_GATE_PASS 13/13"
