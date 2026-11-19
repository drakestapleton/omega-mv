#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# aienux/kernel/hal/run_smmu_qemu.sh [EFI_OMC]: build smmu_qemu_test.om as a target a64efi PE32+ and run it
# under qemu-system-aarch64 -M virt,iommu=smmuv3 with an edu DMA device. QEMU-only; touches no hardware.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)
OMC="${1:-${OMC:-$ROOT/seed/out/omc}}"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/smmu-qemu.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
{
  printf 'target a64efi\nom2\n'
  cat "$ROOT/seed/a64efi/efirt.om" \
      "$ROOT/aienux/kernel/arm64/fwops.om" \
      "$ROOT/aienux/kernel/arm64/uart.om" \
      "$ROOT/aienux/kernel/arm64/frames.om" \
      "$ROOT/aienux/kernel/arm64/acpi.om" \
      "$ROOT/aienux/kernel/arm64/mmu.om" \
      "$ROOT/aienux/kernel/arm64/gicv3.om" \
      "$ROOT/aienux/kernel/arm64/smp.om" \
      "$ROOT/aienux/kernel/hal/iort.om" \
      "$ROOT/aienux/kernel/hal/bar0_mmio.om" \
      "$ROOT/aienux/kernel/hal/pcie.om" \
      "$ROOT/aienux/kernel/hal/smmuv3.om" \
      "$ROOT/aienux/kernel/hal/smmu_qemu_test.om"
} > "$TMP/smmu_qemu.om"
"$OMC" < "$TMP/smmu_qemu.om" > "$TMP/SMMUQ.EFI"
code=${A64EFI_CODE:-}
for f in /opt/homebrew/share/qemu/edk2-aarch64-code.fd \
         /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
         /usr/share/edk2/aarch64/QEMU_EFI.fd \
         /usr/share/AAVMF/QEMU_EFI.fd; do
  [ -z "$code" ] && [ -f "$f" ] && code=$f
done
[ -n "$code" ] && [ -f "$code" ] || { echo "FAIL: EDK2 firmware not found" >&2; exit 1; }
mkdir -p "$TMP/esp/EFI/BOOT"
cp "$TMP/SMMUQ.EFI" "$TMP/esp/EFI/BOOT/BOOTAA64.EFI"
timeout 60 qemu-system-aarch64 \
  -M virt,gic-version=3,its=on,virtualization=on,iommu=smmuv3 -cpu max -smp 1 -m 2048 \
  -display none -bios "$code" \
  -drive if=none,id=d0,format=raw,file=fat:rw:"$TMP/esp" \
  -device virtio-blk-device,drive=d0 \
  -device edu,dma_mask=0xffffffffff \
  -net none -serial file:"$TMP/qemu.log" -monitor none -no-reboot </dev/null >/dev/null 2>&1 || true
tr -d '\r' < "$TMP/qemu.log" | grep -E 'SMMUQ|SMMU_QEMU|PANIC|EDU' || true
if grep -q 'PANIC' "$TMP/qemu.log"; then echo "FAIL: PANIC" >&2; exit 1; fi
grep -q 'SMMU_QEMU_FAIL' "$TMP/qemu.log" && { echo "FAIL: smmu_qemu_test" >&2; exit 1; }
grep -q 'SMMUQ_MAPPED_DMA_OK bytes=256' "$TMP/qemu.log"
grep -q 'SMMUQ_FAULT type=0x0000000000000010' "$TMP/qemu.log" || grep -q 'SMMUQ_FAULT type=0x10' "$TMP/qemu.log"
grep -q 'SMMUQ_WB_MOCK_CCA0_REFUSED' "$TMP/qemu.log"
grep -q 'SMMUQ_WB_DMA_OK' "$TMP/qemu.log"
grep -q 'SMMUQ_CMDQ_LIMIT_OK' "$TMP/qemu.log"
grep -q 'SMMUQ_FAILOPEN_TEARDOWN_OK' "$TMP/qemu.log"
grep -q 'SMMU_QEMU_PASS mapped_dma=ok unmapped_dma=F_TRANSLATION evtq=recorded cmd_sync=complete wb=ok cmdq_limit=ok failopen=teardown' "$TMP/qemu.log"
echo "PASS smmu_qemu_edu (mode-1 SMMUv3: mapped NC DMA ok, unmapped DMA -> EVENTQ F_TRANSLATION, CMD_SYNC complete, WB DMA on real WB RAM + mock CCA=0 refusal, CMDQ 15-pending limit, failed-open STE teardown)"
