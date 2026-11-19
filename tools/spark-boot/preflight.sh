#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# tools/spark-boot/preflight.sh
#
# Strictly READ-ONLY preflight check for bare-metal DGX Spark (SPARK.EFI)
# and Pi 5 OMTK v1 driver (pi_drive_omtk).
#
# Safety invariants:
#   - Zero writes to Spark disk, ESP, NVRAM, or /dev/nvidia*.
#   - Never opens /dev/nvidia* or interrupts live Spark services.
#   - Fails closed on missing/invalid PE32+ ARM64 header, oversized SizeOfImage,
#     corrupted BootOrder/Boot0001, insufficient ESP space, or incompatible ext4
#     features for aienux/disk/ext4_ro.om.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)

SPARK_EFI=""
PI_DRIVE=""
BUILD_PI_DRIVE=0
CHECK_SPARK=0
SPARK_HOST="spark"
MIN_ESP_FREE_BYTES=67108864   # 64 MiB
MAX_IMAGE_SIZE_BYTES=67108864 # 64 MiB guard (prevents 184 MiB static .bss regression)
EXPECTED_GSP_BYTES=75012080   # gsp_ga10x.bin 580.173.02

FAILURES=0
WARNINGS=0

usage() {
  cat <<'EOF'
Usage: tools/spark-boot/preflight.sh [OPTIONS]

Strictly READ-ONLY preflight verification for SPARK.EFI + Pi 5 pi_drive_omtk.

Options:
  --spark-efi PATH      Path to SPARK.EFI (default: build/spark/SPARK.EFI,
                        falling back to aienux/spark/out/SPARK.EFI or SPARK.EFI)
  --pi-drive PATH       Path to existing Pi 5 AArch64 ELF pi_drive_omtk binary
                        (if absent, verifies clean build in an ephemeral temp dir)
  --build-pi-drive      Write compiled AArch64 Linux pi_drive_omtk to --pi-drive
                        (default output: build/spark/pi_drive_omtk)
  --check-spark         Run strictly read-only SSH checks against Spark
                        (Boot0001/BootOrder, ESP >= 64 MiB, nvme0n1p2 ext4,
                         gsp_ga10x.bin 580.173.02, qwen3.8-27b-fp8, RTL8127)
  --spark-host HOST     SSH host alias for Spark (default: spark)
  -h, --help            Show this help
EOF
}

pass() { printf '[PASS] %s\n' "$1"; }
warn() { printf '[WARN] %s\n' "$1"; WARNINGS=$((WARNINGS + 1)); }
fail() { printf '[FAIL] %s\n' "$1" >&2; FAILURES=$((FAILURES + 1)); }

while [ $# -gt 0 ]; do
  case "$1" in
    --spark-efi)
      [ $# -ge 2 ] || { echo "ERROR: --spark-efi requires a path" >&2; exit 2; }
      SPARK_EFI="$2"; shift 2 ;;
    --pi-drive)
      [ $# -ge 2 ] || { echo "ERROR: --pi-drive requires a path" >&2; exit 2; }
      PI_DRIVE="$2"; shift 2 ;;
    --build-pi-drive)
      BUILD_PI_DRIVE=1; shift ;;
    --check-spark)
      CHECK_SPARK=1; shift ;;
    --spark-host)
      [ $# -ge 2 ] || { echo "ERROR: --spark-host requires a host" >&2; exit 2; }
      SPARK_HOST="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2 ;;
  esac
done

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "unavailable"
  fi
}

file_size_bytes() {
  wc -c < "$1" | tr -d '[:space:]'
}

read_u16_le() {
  # $1 = file, $2 = decimal byte offset
  od -An -tu1 -j "$2" -N 2 "$1" | awk 'NF >= 2 { printf "%d\n", $2*256 + $1; exit }'
}

read_u32_le() {
  # $1 = file, $2 = decimal byte offset
  od -An -tu1 -j "$2" -N 4 "$1" | awk 'NF >= 4 { printf "%.0f\n", $1 + $2*256 + $3*65536 + $4*16777216; exit }'
}

read_hex_bytes() {
  # $1 = file, $2 = offset, $3 = count -> lowercase hex string without spaces
  od -An -tx1 -j "$2" -N "$3" "$1" | tr -d '[:space:]'
}

find_omc() {
  for cand in \
    "${OMC:-}" \
    "$HOME/.local/bin/omc" \
    "$REPO_ROOT/seed/out/omc" \
    "/Users/drakestapleton/workspace/omega-mv-macos/seed/out/omc-macos"; do
    if [ -n "$cand" ] && [ -x "$cand" ]; then
      # Ensure the compiler binary can execute on this host architecture
      if "$cand" </dev/null >/dev/null 2>&1 || [ $? -ne 126 ]; then
        printf '%s\n' "$cand"
        return 0
      fi
    fi
  done
  return 1
}

verify_pe32plus_arm64() {
  f="$1"
  if [ ! -f "$f" ]; then
    fail "SPARK.EFI not found at $f (build via: sh aienux/spark/build_spark_efi.sh)"
    return 1
  fi
  sz=$(file_size_bytes "$f")
  if [ "$sz" -lt 512 ]; then
    fail "SPARK.EFI too small ($sz bytes): $f"
    return 1
  fi
  if [ "$sz" -gt "$MAX_IMAGE_SIZE_BYTES" ]; then
    fail "SPARK.EFI raw file size=${sz}B exceeds 64 MiB safety ceiling: $f"
    return 1
  fi
  mz=$(read_hex_bytes "$f" 0 2)
  if [ "$mz" != "4d5a" ]; then
    fail "SPARK.EFI invalid DOS magic (got 0x$mz, want 0x4d5a 'MZ'): $f"
    return 1
  fi
  lfanew=$(read_u32_le "$f" 60)
  if [ "$lfanew" -lt 64 ] || [ $((lfanew + 96)) -gt "$sz" ]; then
    fail "SPARK.EFI invalid e_lfanew=$lfanew for size=$sz: $f"
    return 1
  fi
  pesig=$(read_hex_bytes "$f" "$lfanew" 4)
  if [ "$pesig" != "50450000" ]; then
    fail "SPARK.EFI invalid PE signature at +$lfanew (got 0x$pesig, want 0x50450000)"
    return 1
  fi
  machine=$(read_u16_le "$f" $((lfanew + 4)))
  if [ "$machine" -ne 43620 ]; then # 0xaa64
    fail "SPARK.EFI COFF Machine mismatch (got $machine, want 43620 / 0xaa64 ARM64)"
    return 1
  fi
  opt_magic=$(read_u16_le "$f" $((lfanew + 24)))
  if [ "$opt_magic" -ne 523 ]; then # 0x020b PE32+
    fail "SPARK.EFI OptionalHeader Magic mismatch (got $opt_magic, want 523 / 0x020b PE32+)"
    return 1
  fi
  size_of_image=$(read_u32_le "$f" $((lfanew + 80)))
  subsystem=$(read_u16_le "$f" $((lfanew + 92)))
  if [ "$subsystem" -ne 10 ]; then
    fail "SPARK.EFI Subsystem mismatch (got $subsystem, want 10 EFI_APPLICATION)"
    return 1
  fi
  if [ "$size_of_image" -lt 4096 ] || [ "$size_of_image" -gt "$MAX_IMAGE_SIZE_BYTES" ]; then
    fail "SPARK.EFI SizeOfImage=$size_of_image out of valid range [4096, $MAX_IMAGE_SIZE_BYTES]"
    return 1
  fi
  sha=$(sha256_file "$f")
  pass "SPARK.EFI valid PE32+ ARM64 (0xaa64, EFI_APP): path=$f size=${sz}B SizeOfImage=${size_of_image}B sha256=${sha}"
  return 0
}

verify_aarch64_elf64() {
  f="$1"
  label="$2"
  if [ ! -f "$f" ]; then
    fail "$label not found at $f"
    return 1
  fi
  sz=$(file_size_bytes "$f")
  if [ "$sz" -lt 64 ]; then
    fail "$label too small ($sz bytes): $f"
    return 1
  fi
  magic=$(read_hex_bytes "$f" 0 4)
  cls=$(read_hex_bytes "$f" 4 1)
  data=$(read_hex_bytes "$f" 5 1)
  mach=$(read_u16_le "$f" 18)
  if [ "$magic" != "7f454c46" ] || [ "$cls" != "02" ] || [ "$data" != "01" ] || [ "$mach" -ne 183 ]; then
    fail "$label is not an AArch64 little-endian ELF64 (magic=$magic class=$cls data=$data e_machine=$mach)"
    return 1
  fi
  sha=$(sha256_file "$f")
  pass "$label valid AArch64 ELF64 (EM_AARCH64=0xb7): size=${sz}B sha256=${sha}"
  return 0
}

echo "=== [1/3] Local SPARK.EFI PE32+ ARM64 Verification ==="
if [ -z "$SPARK_EFI" ]; then
  for cand in \
    "$REPO_ROOT/build/spark/SPARK.EFI" \
    "$REPO_ROOT/aienux/spark/out/SPARK.EFI" \
    "$REPO_ROOT/SPARK.EFI"; do
    if [ -f "$cand" ]; then
      SPARK_EFI="$cand"
      break
    fi
  done
  if [ -z "$SPARK_EFI" ]; then
    SPARK_EFI="$REPO_ROOT/build/spark/SPARK.EFI"
  fi
fi
verify_pe32plus_arm64 "$SPARK_EFI" || true

echo ""
echo "=== [2/3] Pi 5 OMTK v1 Client (pi_drive_omtk) Verification ==="
OMTK_SRC="$REPO_ROOT/aienux/net/wire/omtk.om"
PIDRV_SRC="$REPO_ROOT/tools/pi-drive-27b/pi_drive_omtk.om"

if [ ! -f "$OMTK_SRC" ] || [ ! -f "$PIDRV_SRC" ]; then
  fail "Missing OMTK client sources ($OMTK_SRC or $PIDRV_SRC)"
else
  if [ "$BUILD_PI_DRIVE" -eq 1 ]; then
    OUT_BIN="${PI_DRIVE:-$REPO_ROOT/build/spark/pi_drive_omtk}"
    OMC_BIN=$(find_omc || true)
    if [ -z "$OMC_BIN" ]; then
      fail "No executable omc found to build pi_drive_omtk (set OMC=/path/to/omc)"
    else
      mkdir -p "$(dirname "$OUT_BIN")"
      if { printf 'om2\n'; cat "$OMTK_SRC" "$PIDRV_SRC"; } | "$OMC_BIN" > "$OUT_BIN"; then
        chmod +x "$OUT_BIN"
        verify_aarch64_elf64 "$OUT_BIN" "pi_drive_omtk (built -> $OUT_BIN)" || true
      else
        rm -f "$OUT_BIN"
        fail "omc failed to compile pi_drive_omtk from $OMTK_SRC + $PIDRV_SRC"
      fi
    fi
  elif [ -n "$PI_DRIVE" ] && [ -f "$PI_DRIVE" ]; then
    verify_aarch64_elf64 "$PI_DRIVE" "pi_drive_omtk ($PI_DRIVE)" || true
  elif [ -f "$REPO_ROOT/build/spark/pi_drive_omtk" ]; then
    verify_aarch64_elf64 "$REPO_ROOT/build/spark/pi_drive_omtk" "pi_drive_omtk ($REPO_ROOT/build/spark/pi_drive_omtk)" || true
  else
    # Read-only compile verification in ephemeral temp dir (zero repo writes)
    OMC_BIN=$(find_omc || true)
    if [ -z "$OMC_BIN" ]; then
      warn "pi_drive_omtk binary not present and no host-runnable omc found; build on Pi 5 with: { printf 'om2\\n'; cat aienux/net/wire/omtk.om tools/pi-drive-27b/pi_drive_omtk.om; } | ./seed/out/omc > pi_drive_omtk"
    else
      TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/spark-preflight.XXXXXX")
      trap 'rm -rf "$TMP_DIR"' EXIT
      if { printf 'om2\n'; cat "$OMTK_SRC" "$PIDRV_SRC"; } | "$OMC_BIN" > "$TMP_DIR/pi_drive_omtk"; then
        verify_aarch64_elf64 "$TMP_DIR/pi_drive_omtk" "pi_drive_omtk (ephemeral compile-check via $OMC_BIN)" || true
      else
        fail "pi_drive_omtk compile-check failed via $OMC_BIN"
      fi
    fi
  fi
fi

if [ "$CHECK_SPARK" -eq 1 ]; then
  echo ""
  echo "=== [3/3] Strictly Read-Only Spark Preflight (host=$SPARK_HOST) ==="
  REMOTE_OUT=$(ssh -o BatchMode=yes -o ConnectTimeout=8 "$SPARK_HOST" 'sh -s' <<'REMOTE_SH'
set -eu
echo "SECTION:EFI"
efibootmgr -v 2>&1 || echo "ERR_EFIBOOTMGR"

echo "SECTION:ESP"
ESP_SRC=$(findmnt -n -o SOURCE /boot/efi 2>/dev/null || echo "UNMOUNTED")
ESP_FSTYPE=$(findmnt -n -o FSTYPE /boot/efi 2>/dev/null || echo "NONE")
printf 'ESP_SRC=%s\nESP_FSTYPE=%s\n' "$ESP_SRC" "$ESP_FSTYPE"
df -B1 /boot/efi 2>&1 | tail -n 1 || echo "ERR_DF"
test -f /boot/efi/EFI/ubuntu/shimaa64.efi && echo "UBUNTU_SHIM=OK" || echo "UBUNTU_SHIM=MISSING"

echo "SECTION:EXT4"
TUNE_OUT=""
if TUNE_OUT=$(sudo -n tune2fs -l /dev/nvme0n1p2 2>/dev/null); then
  :
elif TUNE_OUT=$(tune2fs -l /dev/nvme0n1p2 2>/dev/null); then
  :
else
  TUNE_OUT="ERR_TUNE2FS"
fi
printf '%s\n' "$TUNE_OUT" | grep -E '^(Filesystem features:|Block size:|Inode size:|ERR_TUNE2FS)' || echo "ERR_TUNE2FS"

echo "SECTION:GSP"
GSP_PATH="/lib/firmware/nvidia/580.173.02/gsp_ga10x.bin"
if [ -f "$GSP_PATH" ]; then
  printf 'GSP_FILE=%s SIZE=%s\n' "$GSP_PATH" "$(wc -c < "$GSP_PATH" | tr -d '[:space:]')"
else
  echo "GSP_FILE=MISSING"
fi

echo "SECTION:MODEL"
MODEL_DIR=""
for d in "$HOME"/models/specialist-transfer/qwen3.8-27b-fp8*; do
  if [ -d "$d" ]; then
    MODEL_DIR="$d"
    break
  fi
done
if [ -n "$MODEL_DIR" ]; then
  MSZ=$(du -sb "$MODEL_DIR" 2>/dev/null | awk '{print $1}')
  printf 'MODEL_DIR=%s SIZE=%s\n' "$MODEL_DIR" "${MSZ:-0}"
else
  echo "MODEL_DIR=MISSING"
fi

echo "SECTION:NET"
FOUND_RTL=0
for d in /sys/class/net/*; do
  [ -d "$d" ] || continue
  n=$(basename "$d")
  drv=$(readlink -f "$d/device/driver" 2>/dev/null | xargs basename 2>/dev/null || echo "-")
  pci=$(readlink -f "$d/device" 2>/dev/null | xargs basename 2>/dev/null || echo "-")
  if [ "$drv" = "r8127" ] || [ "$pci" = "0007:01:00.0" ]; then
    FOUND_RTL=1
    st=$(cat "$d/operstate" 2>/dev/null || echo "unknown")
    mac=$(cat "$d/address" 2>/dev/null || echo "unknown")
    ip4=$(ip -4 -o addr show dev "$n" 2>/dev/null | awk '{print $4}' | paste -sd, - || echo "")
    printf 'RTL8127 iface=%s pci=%s drv=%s state=%s mac=%s ipv4=%s\n' "$n" "$pci" "$drv" "$st" "$mac" "${ip4:-none}"
  fi
done
if [ "$FOUND_RTL" -eq 0 ]; then
  echo "RTL8127=MISSING"
fi

echo "SECTION:GPUBUSY"
# Strictly read-only procfs symlink inspection (NEVER opens /dev/nvidia*)
# Fail closed if sudo -n fails (never falsely report NONE).
if BUSY_PROCS=$(sudo -n sh -c '
  for p in /proc/[0-9]*; do
    pid=${p#/proc/}
    for fd in "$p"/fd/*; do
      t=$(readlink "$fd" 2>/dev/null || true)
      case "$t" in
        /dev/nvidia*)
          comm=$(cat "$p/comm" 2>/dev/null || echo "?")
          echo "${pid}:${comm}:${t}"
          break ;;
      esac
    done
  done
' 2>/dev/null); then
  if [ -n "$BUSY_PROCS" ]; then
    printf 'GPU_OPEN_PROCS=%s\n' "$(printf '%s\n' "$BUSY_PROCS" | paste -sd',' -)"
  else
    echo "GPU_OPEN_PROCS=NONE"
  fi
else
  echo "GPU_OPEN_PROCS=UNKNOWN_SUDO_FAILED"
fi
REMOTE_SH
  ) || {
    fail "Read-only SSH to $SPARK_HOST failed"
    REMOTE_OUT=""
  }

  if [ -n "$REMOTE_OUT" ]; then
    # 1. Boot0001 + BootOrder
    BOOT_ORDER=$(printf '%s\n' "$REMOTE_OUT" | awk '/^BootOrder:/ {print $2; exit}')
    BOOT_0001=$(printf '%s\n' "$REMOTE_OUT" | grep -E '^Boot0001' | head -n 1 || true)
    BOOT_NEXT=$(printf '%s\n' "$REMOTE_OUT" | awk '/^BootNext:/ {print $2; exit}')

    case "$BOOT_ORDER" in
      0001|0001,*)
        pass "Spark BootOrder starts with 0001 (ubuntu): BootOrder=$BOOT_ORDER" ;;
      *)
        fail "Spark BootOrder does not start with 0001 (got: ${BOOT_ORDER:-missing})" ;;
    esac

    case "$BOOT_0001" in
      *ubuntu*shimaa64.efi*)
        pass "Spark Boot0001 intact: ubuntu (\\EFI\\ubuntu\\shimaa64.efi)" ;;
      *)
        fail "Spark Boot0001 missing or altered (got: ${BOOT_0001:-missing})" ;;
    esac

    if [ -n "$BOOT_NEXT" ]; then
      warn "Spark BootNext is already set to $BOOT_NEXT (clear with: sudo efibootmgr -N)"
    fi

    # 2. ESP mount (/dev/nvme0n1p1 vfat) + free space >= 64 MiB + Ubuntu shim
    ESP_SRC=$(printf '%s\n' "$REMOTE_OUT" | awk -F= '/^ESP_SRC=/{print $2; exit}')
    ESP_FSTYPE=$(printf '%s\n' "$REMOTE_OUT" | awk -F= '/^ESP_FSTYPE=/{print $2; exit}')
    ESP_AVAIL=$(printf '%s\n' "$REMOTE_OUT" | awk '/^SECTION:ESP/{f=1;next}/^SECTION:/{f=0}f && /^\//{print $4; exit}')
    UBUNTU_SHIM=$(printf '%s\n' "$REMOTE_OUT" | awk -F= '/^UBUNTU_SHIM=/{print $2; exit}')
    if [ "$ESP_SRC" = "/dev/nvme0n1p1" ] && [ "$ESP_FSTYPE" = "vfat" ]; then
      pass "Spark ESP /boot/efi mounted: source=$ESP_SRC fstype=$ESP_FSTYPE"
    else
      fail "Spark ESP /boot/efi mount mismatch (source=${ESP_SRC:-missing} fstype=${ESP_FSTYPE:-missing}, want /dev/nvme0n1p1 vfat)"
    fi
    if [ -n "$ESP_AVAIL" ] && [ "$ESP_AVAIL" -ge "$MIN_ESP_FREE_BYTES" ] 2>/dev/null; then
      ESP_MIB=$((ESP_AVAIL / 1048576))
      pass "Spark ESP /boot/efi free space ${ESP_MIB} MiB (${ESP_AVAIL} B) >= 64 MiB"
    else
      fail "Spark ESP /boot/efi free space insufficient (avail=${ESP_AVAIL:-unknown}, need >= ${MIN_ESP_FREE_BYTES} B)"
    fi
    if [ "$UBUNTU_SHIM" = "OK" ]; then
      pass "Spark /boot/efi/EFI/ubuntu/shimaa64.efi present"
    else
      fail "Spark /boot/efi/EFI/ubuntu/shimaa64.efi missing"
    fi

    # 3. nvme0n1p2 ext4 features (ext4_ro.om compatibility)
    EXT4_FEATS=$(printf '%s\n' "$REMOTE_OUT" | awk -F': ' '/^Filesystem features:/{print $2; exit}')
    EXT4_BLK=$(printf '%s\n' "$REMOTE_OUT" | awk '/^Block size:/{print $3; exit}')
    if [ -z "$EXT4_FEATS" ]; then
      fail "Could not read /dev/nvme0n1p2 ext4 features (need read-only tune2fs)"
    else
      EXT4_OK=1
      case " $EXT4_FEATS " in
        *" extent "*) ;;
        *) fail "nvme0n1p2 missing required 'extent' feature for ext4_ro.om"; EXT4_OK=0 ;;
      esac
      for bad in compression meta_bg inline_data encrypt; do
        case " $EXT4_FEATS " in
          *" $bad "*) fail "nvme0n1p2 has unsupported ext4_ro.om incompat feature: $bad"; EXT4_OK=0 ;;
        esac
      done
      if [ "${EXT4_BLK:-0}" != "4096" ]; then
        fail "nvme0n1p2 block size=${EXT4_BLK:-unknown} (ext4_ro.om expects 4096)"
        EXT4_OK=0
      fi
      if [ "$EXT4_OK" -eq 1 ]; then
        pass "Spark nvme0n1p2 ext4 compatible with ext4_ro.om (block_size=4096, extent present, no compression/meta_bg/inline_data/encrypt)"
      fi
    fi

    # 4. gsp_ga10x.bin (580.173.02)
    GSP_LINE=$(printf '%s\n' "$REMOTE_OUT" | grep '^GSP_FILE=' | head -n 1 || true)
    GSP_SIZE=$(printf '%s\n' "$GSP_LINE" | sed -n 's/.*SIZE=\([0-9]*\).*/\1/p')
    if [ "${GSP_SIZE:-0}" = "$EXPECTED_GSP_BYTES" ]; then
      pass "Spark gsp_ga10x.bin (580.173.02) present: ${GSP_LINE}"
    else
      fail "Spark gsp_ga10x.bin missing or unexpected size (got: ${GSP_LINE:-none}, want ${EXPECTED_GSP_BYTES} B)"
    fi

    # 5. qwen3.8-27b-fp8 model directory
    MODEL_LINE=$(printf '%s\n' "$REMOTE_OUT" | grep '^MODEL_DIR=' | head -n 1 || true)
    MODEL_SIZE=$(printf '%s\n' "$MODEL_LINE" | sed -n 's/.*SIZE=\([0-9]*\).*/\1/p')
    if [ -n "$MODEL_SIZE" ] && [ "$MODEL_SIZE" -gt 1000000000 ] 2>/dev/null; then
      MODEL_GIB=$(awk -v b="$MODEL_SIZE" 'BEGIN { printf "%.2f", b / 1073741824 }')
      pass "Spark qwen3.8-27b-fp8 present: ${MODEL_LINE} (${MODEL_GIB} GiB)"
    else
      fail "Spark qwen3.8-27b-fp8 missing or too small (got: ${MODEL_LINE:-none})"
    fi

    # 6. RTL8127 link/IP config
    RTL_LINE=$(printf '%s\n' "$REMOTE_OUT" | grep '^RTL8127 ' | head -n 1 || true)
    if [ -n "$RTL_LINE" ]; then
      pass "Spark RTL8127 NIC detected: $RTL_LINE"
    else
      fail "Spark RTL8127 NIC (0007:01:00.0 / r8127) not detected"
    fi

    # 7. GPU busy advisory (read-only procfs symlink check; fail-closed on sudo failure)
    GPU_BUSY=$(printf '%s\n' "$REMOTE_OUT" | awk -F= '/^GPU_OPEN_PROCS=/{print $2; exit}')
    if [ "$GPU_BUSY" = "NONE" ]; then
      pass "Spark /dev/nvidia* open processes: NONE (idle)"
    elif [ "$GPU_BUSY" = "UNKNOWN_SUDO_FAILED" ] || [ -z "$GPU_BUSY" ]; then
      fail "Spark /dev/nvidia* open-process check failed (sudo -n failed; refusing to assume GPU idle)"
    else
      warn "Spark /dev/nvidia* currently held open by: $GPU_BUSY (stage_bootnext.sh --apply will refuse without --force-while-gpu-busy)"
    fi
  fi
else
  echo ""
  echo "=== [3/3] Spark Remote Check Skipped (pass --check-spark for read-only SSH probe) ==="
fi

echo ""
echo "=== Preflight Summary ==="
echo "failures=$FAILURES warnings=$WARNINGS"
if [ "$FAILURES" -ne 0 ]; then
  echo "VERDICT: FAIL" >&2
  exit 1
fi
echo "VERDICT: PASS"
exit 0
