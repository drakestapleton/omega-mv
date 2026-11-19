#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# aienux/spark/build_spark_efi.sh [OUT_EFI]:
# Builds the unified pure-Omega bare-metal Aienux SPARK.EFI PE32+ image
# composing all 6 Phase 2 slices (A -> B -> D -> C -> E -> F) + spark_main.om.
# Zero C, zero Linux syscalls, zero 184 MiB host-sim .bss, zero firmware bytes embedded.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
OUT="${1:-$ROOT/build/spark/SPARK.EFI}"
OMC="${OMC:-$ROOT/seed/out/omc}"
# Platform profile (aienux/spark/plat_$PLAT.om): gb10 = production SPARK.EFI (default);
# qemu = gate-only QEMU virt test image (GPU stand-in, stops after stage 3). The QEMU image
# must never be written to the default production path.
PLAT="${PLAT:-gb10}"
PLAT_OM="$ROOT/aienux/spark/plat_$PLAT.om"
if [ ! -f "$PLAT_OM" ]; then
  echo "FAIL: unknown PLAT=$PLAT (no $PLAT_OM)" >&2
  exit 1
fi
if [ "$PLAT" != "gb10" ] && [ "$(basename "$OUT")" = "SPARK.EFI" ]; then
  echo "FAIL: PLAT=$PLAT is a test profile; refusing to write it as SPARK.EFI" >&2
  exit 1
fi
if [ ! -x "$OMC" ]; then
  echo "FAIL: omc compiler not executable at $OMC (set OMC=/path/to/omc)" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/build-spark-efi.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# Stream-namespace short private helper names in OM-1 sm_121 codegen/encoder units
# so they link cleanly into the single OM-2 SPARK.EFI binary without modifying the
# sha256-pinned source files under gpu/nvidia/om/.
python3 - "$ROOT" "$TMP" <<'PY'
import os, re, sys
root, tmp = sys.argv[1], sys.argv[2]

def xform(src, dst, mapping):
    pat = re.compile(r'\b(' + '|'.join(re.escape(k) for k in mapping) + r')\b')
    out = []
    for line in open(src):
        if line.lstrip().startswith("note "):
            out.append(line)
        else:
            out.append(pat.sub(lambda m: mapping[m.group(1)], line))
    open(dst, "w").writelines(out)

cge_map = {
    "rb": "cge_rb", "ctl": "cge_ctl", "imm": "cge_imm", "arg": "cge_arg",
    "av": "cge_av", "cw": "cge_cw", "nv": "cge_nv", "ob": "cge_ob",
    "at": "cge_pos",
}
xform(os.path.join(root, "gpu/nvidia/om/codegen/cg_dec_emit.om"),
      os.path.join(tmp, "cg_dec_emit_ns.om"), cge_map)
xform(os.path.join(root, "gpu/nvidia/om/codegen/cg_dec.om"),
      os.path.join(tmp, "cg_dec_ns.om"),
      {"av": "cge_av", "cw": "cge_cw", "nv": "cge_nv", "ob": "cge_ob", "arg": "cge_arg", "rs": "cgd_rs"})
xform(os.path.join(root, "gpu/nvidia/om/encoder/bw_enc_sm121.om"),
      os.path.join(tmp, "bw_enc_sm121_ns.om"),
      {"rb": "bwe_rb", "ctl": "bwe_ctl"})
PY

{
  printf 'target a64efi\nom2\n'
  # Piece 1 (Slice A): UEFI Boot -> EL2->EL1h -> MMU -> GICv3+ITS -> 20-core SMP
  cat "$ROOT/seed/a64efi/efirt.om" \
      "$ROOT/aienux/kernel/arm64/fwops.om" \
      "$ROOT/aienux/kernel/arm64/uart.om" \
      "$ROOT/aienux/kernel/arm64/frames.om" \
      "$ROOT/aienux/kernel/arm64/acpi.om" \
      "$ROOT/aienux/kernel/arm64/mmu.om" \
      "$ROOT/aienux/kernel/arm64/gicv3.om" \
      "$ROOT/aienux/kernel/arm64/smp.om"
  # Piece 2 (Slice B): Multi-Segment PCIe + ARM SMMUv3 A/B/C + BAR0 MMIO + GB20B IRQ iqmode=2
  cat "$ROOT/aienux/kernel/hal/iort.om" \
      "$ROOT/aienux/kernel/hal/bar0_mmio.om" \
      "$ROOT/aienux/kernel/hal/pcie.om" \
      "$ROOT/aienux/kernel/hal/smmuv3.om" \
      "$ROOT/gpu/driver/gsp/irqbm.om" \
      "$ROOT/gpu/driver/gsp/irq.om"
  # Piece 4 (Slice D): Strictly RO NVMe + GPT + 64-bit ext4 + SHA-256 + RTL8127/TCP
  cat "$ROOT/aienux/disk/nvme_ro_bare.om" \
      "$ROOT/aienux/disk/nvme_bare_a64efi.om" \
      "$ROOT/aienux/disk/sha256_bare.om" \
      "$ROOT/aienux/disk/gpt_ro.om" \
      "$ROOT/aienux/disk/ext4_ro.om" \
      "$ROOT/aienux/net/rtl8127/om/rtl8127/rtl8127.om" \
      "$ROOT/aienux/net/rtl8127/om/rtl8127/bare_a64efi.om" \
      "$ROOT/aienux/net/tcp/tcp.om"
  # Piece 3 (Slice C): GB20B GSP Bring-Up + GMMU + 0xca6f/0xcec0 Compute Channel
  cat "$ROOT/gpu/driver/gsp/bm_hal.om" \
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
      "$ROOT/gpu/driver/chan/rmchan.om"
  # Piece 5 (Slice E): compute.om + sm_121 SASS codegen + q38_run.om
  cat "$ROOT/gpu/driver/gsp/compute.om" \
      "$ROOT/gpu/driver/gsp/q38_run.om" \
      "$TMP/cg_dec_emit_ns.om" \
      "$TMP/cg_dec_ns.om" \
      "$ROOT/gpu/nvidia/om/components/bw_alloc.om" \
      "$TMP/bw_enc_sm121_ns.om"
  # Piece 6 (Slice F): OMTK v1 codec + bare-metal wire_loop.om
  cat "$ROOT/aienux/net/wire/omtk.om" \
      "$ROOT/aienux/net/wire/wire_loop.om"
  # Phase 3 Unified Entry & Cross-Slice Wiring
  cat "$PLAT_OM" "$ROOT/aienux/spark/spark_main.om"
} > "$TMP/spark_unified.om"

"$OMC" < "$TMP/spark_unified.om" > "$OUT"

# Verify PE32+ header & compact SizeOfImage
python3 - "$OUT" "$PLAT" <<'PY'
import hashlib, struct, sys

path = sys.argv[1]
data = open(path, "rb").read()
assert len(data) >= 512, f"PE image too small: {len(data)}"
assert data[0:2] == b"MZ", "missing MZ magic"
pe_off = struct.unpack_from("<I", data, 0x3C)[0]
assert data[pe_off:pe_off+4] == b"PE\x00\x00", "missing PE signature"
machine = struct.unpack_from("<H", data, pe_off + 4)[0]
assert machine == 0xAA64, f"unexpected machine 0x{machine:04x} (want 0xAA64)"
opt_off = pe_off + 24
opt_magic = struct.unpack_from("<H", data, opt_off)[0]
assert opt_magic == 0x020B, f"unexpected PE32+ magic 0x{opt_magic:04x}"
size_of_image = struct.unpack_from("<I", data, opt_off + 56)[0]
subsys = struct.unpack_from("<H", data, opt_off + 68)[0]
assert subsys == 10, f"unexpected subsystem {subsys} (want 10 EFI_APPLICATION)"
assert size_of_image < 16 * 1024 * 1024, f"SizeOfImage bloated: {size_of_image} B"
sha = hashlib.sha256(data).hexdigest()
print(f"PASS build_spark_efi: {path} (PLAT={sys.argv[2]})")
print(f"  PE32+ Machine=0x{machine:04x} Subsystem=EFI_APP FileSize={len(data)} B SizeOfImage={size_of_image} B ({size_of_image/1048576:.2f} MiB)")
print(f"  sha256={sha}")
PY
