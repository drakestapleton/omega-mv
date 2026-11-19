#!/bin/sh
# tests/a64efi/boot_el1_smp.sh [SPARK_EFI] [NEGATIVE_EFI]:
# Boots pure-Omega bare-metal Aienux SPARK.EFI on 20-core QEMU virt (GICv3, EL2 virtualization=on, EDK2)
# and verifies EL2->EL1h, MAIR_EL1=0x440004ff, pre-carved 512 MiB Normal-NC pool, GICv3 rev=3,
# 20/20 SMP cores online via PSCI CPU_ON, and clean PSCI SYSTEM_RESET.
# Optionally boots a negative-control image that triggers trap 8 post-EBS and verifies
# panichk logs to UART and resets cleanly without calling dead UEFI Boot Services.
# Strictly emulated (QEMU virt); NOT_RUN on physical DGX Spark silicon.
set -eu

efi=${1:?usage: boot_el1_smp.sh SPARK.EFI [NEG_TRAP.EFI]}
neg=${2:-}
code=${A64EFI_CODE:-}
for f in /opt/homebrew/share/qemu/edk2-aarch64-code.fd \
         /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
         /usr/share/edk2/aarch64/QEMU_EFI.fd \
         /usr/share/AAVMF/QEMU_EFI.fd; do
  [ -z "$code" ] && [ -f "$f" ] && code=$f
done
[ -n "$code" ] && [ -f "$code" ] || { echo "FAIL: EDK2 firmware not found (set A64EFI_CODE)" >&2; exit 1; }
command -v qemu-system-aarch64 >/dev/null 2>&1 || { echo "FAIL: qemu-system-aarch64 not found" >&2; exit 1; }

work=$(mktemp -d "${TMPDIR:-/tmp}/slice_a_qemu.XXXXXX")
trap 'rm -rf "$work"' EXIT

run_qemu() {
  img=$1 mem=$2 log=$3
  rm -rf "$work/esp" && mkdir -p "$work/esp/EFI/BOOT"
  cp "$img" "$work/esp/EFI/BOOT/BOOTAA64.EFI"
  timeout 40 qemu-system-aarch64 \
    -M virt,gic-version=3,virtualization=on -cpu max -smp 20 -m "$mem" \
    -display none -bios "$code" \
    -drive if=none,id=d0,format=raw,file=fat:rw:"$work/esp" \
    -device virtio-blk-device,drive=d0 \
    -net none -serial file:"$log" -monitor none -no-reboot </dev/null >/dev/null 2>&1
}

echo "=== QEMU 20-core 4 GiB boot (512 MiB Normal-NC pool) ==="
run_qemu "$efi" 4096 "$work/boot.log"
tr -d '\r' < "$work/boot.log" | grep -E 'AIENUX_A64EFI|EL1_ALIVE|free_mib=|GICV3_|SMP_ONLINE|SLICE_A_QEMU'
grep -q 'EL1_ALIVE current_el=1 mair=0x00000000440004ff' "$work/boot.log"
grep -q 'nc_pool_mib=512' "$work/boot.log"
grep -q 'GICV3_OK rev=3' "$work/boot.log"
grep -q 'SMP_ONLINE online=20 expected=20 failed=0' "$work/boot.log"
grep -q 'SLICE_A_QEMU_BOOT_PASS' "$work/boot.log"
echo "PASS qemu_20core_el1_mmu_gicv3_smp"

if [ -n "$neg" ]; then
  echo "=== QEMU post-EBS trap negative control ==="
  run_qemu "$neg" 2048 "$work/neg.log"
  tr -d '\r' < "$work/neg.log" | grep -E 'PANIC post-EBS'
  grep -q 'PANIC post-EBS code=0x800000000000006c' "$work/neg.log"
  echo "PASS qemu_post_ebs_trap_guard"
fi
