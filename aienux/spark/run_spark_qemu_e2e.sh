#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# aienux/spark/run_spark_qemu_e2e.sh [EFI_OMC]: build the REAL spark_main.om with the QEMU platform profile
# (PLAT=qemu -> SPARK-QEMU.EFI, gate-only) and run it under QEMU virt,iommu=smmuv3 with a read-only NVMe
# disk (GPT + ext4 + synthetic OMFWBND1 bundle) and an edu device standing in for the GPU endpoint.
# Real: Stage 1, Stage 2 (MCFG/ECAM probe, BAR map, quiesce, IORT, mode-1 SMMUv3 bring-up, per-device
# streams, BME enable), Stage 3 disk + bundle (NVMe RO, GPT, ext4, TOC + SHA-256). Stubbed: GB20B
# register access, RTL8127/TCP, Stages 4..6. QEMU-only; touches no hardware.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
OMC="${1:-${OMC:-$ROOT/seed/out/omc}}"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/spark-qemu-e2e.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
PLAT=qemu OMC="$OMC" sh "$ROOT/aienux/spark/build_spark_efi.sh" "$TMP/SPARK-QEMU.EFI"
python3 "$ROOT/aienux/spark/mk_qemu_disk.py" "$TMP/disk.img" "$TMP"
code=${A64EFI_CODE:-}
for f in /opt/homebrew/share/qemu/edk2-aarch64-code.fd \
         /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
         /usr/share/edk2/aarch64/QEMU_EFI.fd \
         /usr/share/AAVMF/QEMU_EFI.fd; do
  [ -z "$code" ] && [ -f "$f" ] && code=$f
done
[ -n "$code" ] && [ -f "$code" ] || { echo "FAIL: EDK2 firmware not found" >&2; exit 1; }
mkdir -p "$TMP/esp/EFI/BOOT"
cp "$TMP/SPARK-QEMU.EFI" "$TMP/esp/EFI/BOOT/BOOTAA64.EFI"
run_qemu() { # $1 = disk image, $2 = serial log, $3 = ESP dir (default $TMP/esp)
  timeout 120 qemu-system-aarch64 \
    -M virt,gic-version=3,its=on,virtualization=on,iommu=smmuv3 -cpu max -smp 20 -m 4096 \
    -display none -bios "$code" \
    -drive if=none,id=d0,format=raw,file=fat:rw:"${3:-$TMP/esp}" \
    -device virtio-blk-device,drive=d0 \
    -drive if=none,id=nv0,format=raw,readonly=on,file="$1" \
    -device nvme,serial=spk0,drive=nv0 \
    -device edu,dma_mask=0xffffffffff \
    -net none -serial file:"$2" -monitor none -no-reboot </dev/null >/dev/null 2>&1 || true
}
run_qemu "$TMP/disk.img" "$TMP/qemu.log"
tr -d '\r' < "$TMP/qemu.log" | grep -E '\[SPARK|SMP_ONLINE|SPARK_QEMU|PANIC' || true
if grep -q 'PANIC' "$TMP/qemu.log"; then echo "FAIL: PANIC" >&2; exit 1; fi
if grep -q '\[SPARK FAIL' "$TMP/qemu.log"; then echo "FAIL: spark_main stage failure under QEMU" >&2; exit 1; fi
grep -q 'SMP_ONLINE online=20 expected=20 failed=0' "$TMP/qemu.log"
grep -q '\[SPARK 2/6\]' "$TMP/qemu.log"
grep -q '\[SPARK QEMU\] stage 2 SMMUv3 streams live' "$TMP/qemu.log"
grep -q '\[SPARK 3/6\]' "$TMP/qemu.log"
grep -q '\[SPARK QEMU\] stage 3 bundle verified' "$TMP/qemu.log"
grep -q 'SPARK_QEMU_E2E_PASS real=stage1,stage2' "$TMP/qemu.log"
# Negative: flip one payload byte of bundle entry 0 -> SHA-256 mismatch must fail closed at stage 3 (304).
python3 - "$TMP/disk.img" "$TMP/disk-bad.img" <<'PY'
import sys
d = bytearray(open(sys.argv[1], "rb").read())
i = d.find(b"OMFWBND1")
assert i > 0
d[i + 4096 + 100] ^= 1
open(sys.argv[2], "wb").write(d)
PY
run_qemu "$TMP/disk-bad.img" "$TMP/qemu-bad.log"
tr -d '\r' < "$TMP/qemu-bad.log" | grep -E '\[SPARK FAIL|SPARK_QEMU_E2E_PASS' || true
grep -q '\[SPARK FAIL stage=3 code=304\]' "$TMP/qemu-bad.log"
if grep -q 'SPARK_QEMU_E2E_PASS' "$TMP/qemu-bad.log"; then echo "FAIL: tampered bundle accepted" >&2; exit 1; fi
# Negative: a platform profile whose SMMU base disagrees with the firmware IORT must fail closed at
# stage 2 with SPK_E_SMMU_BASE (208) before any SMMU is programmed.
sed 's/ret 0x09050000/ret 0x09060000/' "$ROOT/aienux/spark/plat_qemu.om" > "$TMP/plat_qemu_badbase.om"
if cmp -s "$ROOT/aienux/spark/plat_qemu.om" "$TMP/plat_qemu_badbase.om"; then
  echo "FAIL: 208 negative control could not alter the QEMU SMMU base" >&2; exit 1
fi
PLAT=qemu PLAT_OM_OVERRIDE="$TMP/plat_qemu_badbase.om" OMC="$OMC" \
  sh "$ROOT/aienux/spark/build_spark_efi.sh" "$TMP/SPARK-QEMU-BADBASE.EFI" >/dev/null
mkdir -p "$TMP/esp-badbase/EFI/BOOT"
cp "$TMP/SPARK-QEMU-BADBASE.EFI" "$TMP/esp-badbase/EFI/BOOT/BOOTAA64.EFI"
run_qemu "$TMP/disk.img" "$TMP/qemu-badbase.log" "$TMP/esp-badbase"
tr -d '\r' < "$TMP/qemu-badbase.log" | grep -E '\[SPARK FAIL|SPARK_QEMU_E2E_PASS|streams live' || true
grep -q '\[SPARK FAIL stage=2 code=208\]' "$TMP/qemu-badbase.log"
if grep -qE 'SPARK_QEMU_E2E_PASS|stage 2 SMMUv3 streams live' "$TMP/qemu-badbase.log"; then
  echo "FAIL: mismatched SMMU base accepted" >&2; exit 1
fi
echo "PASS spark_main_qemu_e2e (real spark_main Stage 1 + Stage 2 incl. SMMUv3 mode-1 + Stage 3 NVMe/GPT/ext4/bundle; GB20B regs, net, Stages 4-6 stubbed; tampered bundle -> stage 3 code 304; IORT/platform SMMU base mismatch -> stage 2 code 208)"
