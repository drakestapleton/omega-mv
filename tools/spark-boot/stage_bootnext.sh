#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# tools/spark-boot/stage_bootnext.sh
#
# Stage \EFI\AIENOS\SPARK.EFI on DGX Spark ESP and configure ONE-SHOT BootNext ONLY.
#
# Safety invariants:
#   - DRY-RUN by default. Makes ZERO changes unless BOTH:
#       --apply AND --i-am-at-the-console
#     are explicitly passed.
#   - Validates local SPARK.EFI PE32+ ARM64 (0xaa64, 0x020b, EFI_APP, SizeOfImage <= 64 MiB)
#     and SHA-256 before touching Spark.
#   - NEVER overwrites Ubuntu's \EFI\ubuntu\shimaa64.efi or GRUB.
#   - NEVER modifies BootOrder or Boot0001 (ubuntu); verifies both are byte-identical
#     before and after staging so any power-cycle or PSCI reset returns to Ubuntu Linux.
#   - Refuses to proceed if any process holds /dev/nvidia* open (inspected via read-only
#     procfs symlinks — NEVER opening /dev/nvidia*) unless --force-while-gpu-busy is passed.
#   - NEVER reboots automatically. Prints the exact manual cold power-cycle command.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)

SPARK_EFI=""
SPARK_HOST="spark"
APPLY=0
AT_CONSOLE=0
FORCE_GPU_BUSY=0
SKIP_SSH=0
MIN_ESP_FREE_BYTES=67108864   # 64 MiB
MAX_IMAGE_SIZE_BYTES=67108864 # 64 MiB

usage() {
  cat <<'EOF'
Usage: tools/spark-boot/stage_bootnext.sh [OPTIONS]

Stage \EFI\AIENOS\SPARK.EFI on DGX Spark and set ONE-SHOT BootNext ONLY.
DRY-RUN by default; makes ZERO changes unless --apply --i-am-at-the-console is passed.

Options:
  --spark-efi PATH          Path to local SPARK.EFI (default: build/spark/SPARK.EFI,
                            falling back to aienux/spark/out/SPARK.EFI or SPARK.EFI)
  --spark-host HOST         SSH host alias for Spark (default: spark)
  --dry-run                 Explicit dry-run (default behavior; zero changes)
  --apply                   Apply staging + one-shot BootNext (REQUIRES --i-am-at-the-console)
  --i-am-at-the-console     Operator attestation of physical Spark console + UART access
  --force-while-gpu-busy    Override refusal when /dev/nvidia* has open processes
  --local-only              In dry-run mode, validate local SPARK.EFI only (skip SSH probe)
  -h, --help                Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --spark-efi)
      [ $# -ge 2 ] || { echo "ERROR: --spark-efi requires a path" >&2; exit 2; }
      SPARK_EFI="$2"; shift 2 ;;
    --spark-host)
      [ $# -ge 2 ] || { echo "ERROR: --spark-host requires a host" >&2; exit 2; }
      SPARK_HOST="$2"; shift 2 ;;
    --dry-run)
      APPLY=0; shift ;;
    --apply)
      APPLY=1; shift ;;
    --i-am-at-the-console)
      AT_CONSOLE=1; shift ;;
    --force-while-gpu-busy)
      FORCE_GPU_BUSY=1; shift ;;
    --local-only)
      SKIP_SSH=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2 ;;
  esac
done

# Hard safety gate: --apply MUST be accompanied by --i-am-at-the-console
if [ "$APPLY" -eq 1 ] && [ "$AT_CONSOLE" -ne 1 ]; then
  echo "REFUSED: --apply requires --i-am-at-the-console (physical console / UART access required)." >&2
  echo "         Zero changes were made to Spark ESP or NVRAM." >&2
  exit 2
fi

if [ "$APPLY" -eq 1 ] && [ "$SKIP_SSH" -eq 1 ]; then
  echo "REFUSED: --apply cannot be combined with --local-only." >&2
  exit 2
fi

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "ERROR: neither sha256sum nor shasum found" >&2
    exit 1
  fi
}

sha256_str() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  else
    echo "ERROR: neither sha256sum nor shasum found" >&2
    exit 1
  fi
}

file_size_bytes() {
  wc -c < "$1" | tr -d '[:space:]'
}

read_u16_le() {
  od -An -tu1 -j "$2" -N 2 "$1" | awk 'NF >= 2 { printf "%d\n", $2*256 + $1; exit }'
}

read_u32_le() {
  od -An -tu1 -j "$2" -N 4 "$1" | awk 'NF >= 4 { printf "%.0f\n", $1 + $2*256 + $3*65536 + $4*16777216; exit }'
}

read_hex_bytes() {
  od -An -tx1 -j "$2" -N "$3" "$1" | tr -d '[:space:]'
}

# Resolve default SPARK.EFI path
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

# 1. Validate local SPARK.EFI PE32+ ARM64 header & SHA-256
if [ ! -f "$SPARK_EFI" ]; then
  echo "FAIL: SPARK.EFI not found at $SPARK_EFI" >&2
  echo "      Build it first via: sh aienux/spark/build_spark_efi.sh" >&2
  exit 1
fi

EFI_SIZE=$(file_size_bytes "$SPARK_EFI")
if [ "$EFI_SIZE" -lt 512 ]; then
  echo "FAIL: SPARK.EFI too small (${EFI_SIZE} B): $SPARK_EFI" >&2
  exit 1
fi
if [ "$EFI_SIZE" -gt "$MAX_IMAGE_SIZE_BYTES" ]; then
  echo "FAIL: SPARK.EFI raw file size (${EFI_SIZE} B) exceeds 64 MiB safety ceiling" >&2
  exit 1
fi

MZ=$(read_hex_bytes "$SPARK_EFI" 0 2)
[ "$MZ" = "4d5a" ] || { echo "FAIL: invalid DOS MZ header (got 0x$MZ)" >&2; exit 1; }

LFANEW=$(read_u32_le "$SPARK_EFI" 60)
if [ "$LFANEW" -lt 64 ] || [ $((LFANEW + 96)) -gt "$EFI_SIZE" ]; then
  echo "FAIL: invalid e_lfanew=$LFANEW for size=$EFI_SIZE" >&2
  exit 1
fi

PESIG=$(read_hex_bytes "$SPARK_EFI" "$LFANEW" 4)
[ "$PESIG" = "50450000" ] || { echo "FAIL: invalid PE signature (got 0x$PESIG)" >&2; exit 1; }

MACHINE=$(read_u16_le "$SPARK_EFI" $((LFANEW + 4)))
[ "$MACHINE" -eq 43620 ] || { echo "FAIL: COFF Machine=$MACHINE (want 43620 / 0xaa64 ARM64)" >&2; exit 1; }

OPT_MAGIC=$(read_u16_le "$SPARK_EFI" $((LFANEW + 24)))
[ "$OPT_MAGIC" -eq 523 ] || { echo "FAIL: OptionalHeader Magic=$OPT_MAGIC (want 523 / 0x020b PE32+)" >&2; exit 1; }

SIZE_OF_IMAGE=$(read_u32_le "$SPARK_EFI" $((LFANEW + 80)))
SUBSYSTEM=$(read_u16_le "$SPARK_EFI" $((LFANEW + 92)))
[ "$SUBSYSTEM" -eq 10 ] || { echo "FAIL: Subsystem=$SUBSYSTEM (want 10 EFI_APPLICATION)" >&2; exit 1; }
if [ "$SIZE_OF_IMAGE" -lt 4096 ] || [ "$SIZE_OF_IMAGE" -gt "$MAX_IMAGE_SIZE_BYTES" ]; then
  echo "FAIL: SizeOfImage=$SIZE_OF_IMAGE out of valid range [4096, $MAX_IMAGE_SIZE_BYTES]" >&2
  exit 1
fi

LOCAL_SHA=$(sha256_file "$SPARK_EFI")
if ! printf '%s\n' "$LOCAL_SHA" | grep -Eq '^[0-9a-f]{64}$'; then
  echo "FAIL: invalid local SHA-256 digest: $LOCAL_SHA" >&2
  exit 1
fi
echo "[OK] Local SPARK.EFI validated: path=$SPARK_EFI size=${EFI_SIZE}B SizeOfImage=${SIZE_OF_IMAGE}B sha256=${LOCAL_SHA}"

if [ "$SKIP_SSH" -eq 1 ]; then
  echo ""
  echo "DRY-RUN (--local-only): skipped SSH probe to $SPARK_HOST."
  echo "Planned actions when run with --apply --i-am-at-the-console:"
  echo "  1. Verify Boot0001 (ubuntu) + BootOrder intact, ESP free >= 64 MiB, /dev/nvidia* idle."
  echo "  2. Stage SPARK.EFI -> /boot/efi/EFI/AIENOS/SPARK.EFI (sha256=${LOCAL_SHA})."
  echo "  3. Create/reuse BootXXXX (label 'AIENOS Spark', loader '\\EFI\\AIENOS\\SPARK.EFI') via --create-only."
  echo "  4. Set one-shot BootNext ONLY (BootOrder and Boot0001 untouched)."
  echo "  5. Print manual cold power-cycle instructions (NEVER auto-reboot)."
  echo "DRY-RUN: zero changes made to Spark ESP or NVRAM."
  exit 0
fi

# 2. Strictly read-only pre-check on Spark (runs for both dry-run and apply)
PRE_OUT=$(ssh -o BatchMode=yes -o ConnectTimeout=8 "$SPARK_HOST" "sh -s -- $APPLY" <<'REMOTE_PRE'
set -eu
PRE_APPLY="${1:-0}"
echo "SECTION:EFI"
efibootmgr -v
echo "SECTION:ESP"
ESP_SRC=$(findmnt -n -o SOURCE /boot/efi 2>/dev/null || echo "UNMOUNTED")
ESP_FSTYPE=$(findmnt -n -o FSTYPE /boot/efi 2>/dev/null || echo "NONE")
printf 'ESP_SRC=%s\nESP_FSTYPE=%s\n' "$ESP_SRC" "$ESP_FSTYPE"
df -B1 /boot/efi | tail -n 1
test -f /boot/efi/EFI/ubuntu/shimaa64.efi && echo "UBUNTU_SHIM=OK" || echo "UBUNTU_SHIM=MISSING"
echo "SECTION:GPUBUSY"
# Read-only procfs symlink inspection — NEVER opens /dev/nvidia*
# Dry-run never invokes sudo (not even sudo -n): the check is reported as not run.
# Apply mode fails closed if sudo -n fails (never falsely report NONE).
if [ "$PRE_APPLY" != "1" ]; then
  echo "GPU_OPEN_PROCS=NOT_CHECKED_DRY_RUN"
elif BUSY=$(sudo -n sh -c '
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
  if [ -n "$BUSY" ]; then
    printf 'GPU_OPEN_PROCS=%s\n' "$(printf '%s\n' "$BUSY" | paste -sd',' -)"
  else
    echo "GPU_OPEN_PROCS=NONE"
  fi
else
  echo "GPU_OPEN_PROCS=UNKNOWN_SUDO_FAILED"
fi
REMOTE_PRE
) || {
  echo "FAIL: read-only SSH pre-check to $SPARK_HOST failed" >&2
  exit 1
}

ORIG_BOOTORDER=$(printf '%s\n' "$PRE_OUT" | awk '/^BootOrder:/ {print $2; exit}')
ORIG_BOOT0001=$(printf '%s\n' "$PRE_OUT" | grep -E '^Boot0001' | head -n 1 || true)
EXISTING_SPARK_BOOT=$(printf '%s\n' "$PRE_OUT" | awk '
  /^Boot[0-9A-Fa-f]{4}/ && index($0, "\\EFI\\AIENOS\\SPARK.EFI") > 0 {
    print substr($1, 5, 4); exit
  }')
ESP_SRC=$(printf '%s\n' "$PRE_OUT" | awk -F= '/^ESP_SRC=/{print $2; exit}')
ESP_FSTYPE=$(printf '%s\n' "$PRE_OUT" | awk -F= '/^ESP_FSTYPE=/{print $2; exit}')
ESP_AVAIL=$(printf '%s\n' "$PRE_OUT" | awk '/^SECTION:ESP/{f=1;next}/^SECTION:/{f=0}f && /^\//{print $4; exit}')
UBUNTU_SHIM=$(printf '%s\n' "$PRE_OUT" | awk -F= '/^UBUNTU_SHIM=/{print $2; exit}')
GPU_BUSY=$(printf '%s\n' "$PRE_OUT" | awk -F= '/^GPU_OPEN_PROCS=/{print $2; exit}')

if ! printf '%s\n' "$ORIG_BOOTORDER" | grep -Eq '^0001(,[0-9A-Fa-f]{4})*$'; then
  echo "FAIL: Spark BootOrder invalid or does not start with 0001 (got: ${ORIG_BOOTORDER:-missing}); refusing." >&2
  exit 1
fi

case "$ORIG_BOOT0001" in
  *ubuntu*shimaa64.efi*) ;;
  *)
    echo "FAIL: Spark Boot0001 is not Ubuntu shim (got: ${ORIG_BOOT0001:-missing}); refusing." >&2
    exit 1 ;;
esac
ORIG_0001_SHA=$(sha256_str "$ORIG_BOOT0001")
if ! printf '%s\n' "$ORIG_0001_SHA" | grep -Eq '^[0-9a-f]{64}$'; then
  echo "FAIL: failed to hash ORIG_BOOT0001" >&2
  exit 1
fi

if [ "$ESP_SRC" != "/dev/nvme0n1p1" ] || [ "$ESP_FSTYPE" != "vfat" ]; then
  echo "FAIL: /boot/efi mount mismatch (source=${ESP_SRC:-missing} fstype=${ESP_FSTYPE:-missing}, want /dev/nvme0n1p1 vfat); refusing." >&2
  exit 1
fi

if [ "$UBUNTU_SHIM" != "OK" ]; then
  echo "FAIL: /boot/efi/EFI/ubuntu/shimaa64.efi missing on $SPARK_HOST; refusing." >&2
  exit 1
fi

case "$ESP_AVAIL" in
  ''|*[!0-9]*)
    echo "FAIL: Spark ESP /boot/efi free space is not a number (got: ${ESP_AVAIL:-missing}); refusing." >&2
    exit 1 ;;
esac
if [ "$ESP_AVAIL" -lt "$MIN_ESP_FREE_BYTES" ]; then
  echo "FAIL: Spark ESP /boot/efi free space insufficient (${ESP_AVAIL} B < 64 MiB); refusing." >&2
  exit 1
fi

echo "[OK] Spark BootOrder=$ORIG_BOOTORDER, Boot0001=ubuntu intact, ESP=${ESP_SRC}(${ESP_FSTYPE}) free=$((ESP_AVAIL / 1048576)) MiB"

if [ "$GPU_BUSY" != "NONE" ]; then
  if [ "$APPLY" -eq 1 ] && [ "$FORCE_GPU_BUSY" -ne 1 ]; then
    if [ "$GPU_BUSY" = "UNKNOWN_SUDO_FAILED" ] || [ -z "$GPU_BUSY" ]; then
      echo "REFUSED: Could not verify /dev/nvidia* idle state (sudo -n failed; fail-closed)." >&2
    else
      echo "REFUSED: Live GPU workload detected holding /dev/nvidia* open: $GPU_BUSY" >&2
    fi
    echo "         Stop GPU workloads / ensure sudo -n works, or pass --force-while-gpu-busy." >&2
    echo "         Zero changes were made to Spark ESP or NVRAM." >&2
    exit 3
  fi
  if [ "$APPLY" -ne 1 ] && [ "$GPU_BUSY" = "NOT_CHECKED_DRY_RUN" ]; then
    echo "[INFO] /dev/nvidia* open-process check needs sudo; not run in dry-run (apply mode runs it, fail-closed)"
  else
    echo "[WARN] /dev/nvidia* status: ${GPU_BUSY:-UNKNOWN}"
  fi
else
  echo "[OK] Spark /dev/nvidia* idle (no open processes)"
fi

if [ "$APPLY" -ne 1 ]; then
  echo ""
  echo "=== DRY-RUN PLAN (host=$SPARK_HOST) ==="
  echo "  Target ESP path : /boot/efi/EFI/AIENOS/SPARK.EFI (Ubuntu \\EFI\\ubuntu\\* untouched)"
  echo "  Local SHA-256   : $LOCAL_SHA"
  if [ -n "$EXISTING_SPARK_BOOT" ]; then
    echo "  UEFI Boot entry : reuse existing Boot${EXISTING_SPARK_BOOT} (\\EFI\\AIENOS\\SPARK.EFI)"
  else
    echo "  UEFI Boot entry : create via 'sudo efibootmgr --create-only --disk /dev/nvme0n1 --part 1 --label \"AIENOS Spark\" --loader \\EFI\\AIENOS\\SPARK.EFI'"
  fi
  echo "  BootNext        : one-shot BootNext ONLY (BootOrder=$ORIG_BOOTORDER and Boot0001 untouched)"
  echo "  Auto-reboot     : NEVER (manual cold power-cycle required after staging)"
  echo ""
  echo "To apply (at physical Spark console + UART):"
  echo "  $0 --spark-efi '$SPARK_EFI' --spark-host '$SPARK_HOST' --apply --i-am-at-the-console"
  echo "DRY-RUN: zero changes made to Spark ESP or NVRAM."
  exit 0
fi

# 3. APPLY MODE (both --apply and --i-am-at-the-console verified above)
echo ""
echo "=== APPLYING STAGING + ONE-SHOT BootNext ON $SPARK_HOST ==="

# Verify non-interactive sudo works BEFORE creating temp files or touching /boot/efi
if ! ssh -o BatchMode=yes -o ConnectTimeout=8 "$SPARK_HOST" 'sudo -n true' 2>/dev/null; then
  echo "FAIL: passwordless sudo (sudo -n) is not available on $SPARK_HOST; zero changes made." >&2
  exit 1
fi

REMOTE_DIR=$(ssh -o BatchMode=yes -o ConnectTimeout=8 "$SPARK_HOST" 'mktemp -d /tmp/spark-stage.XXXXXX')
if [ -z "$REMOTE_DIR" ]; then
  echo "FAIL: could not create 0700 staging temp dir on $SPARK_HOST" >&2
  exit 1
fi
REMOTE_TMP="${REMOTE_DIR}/SPARK.EFI"
scp -q "$SPARK_EFI" "${SPARK_HOST}:${REMOTE_TMP}"

APPLY_OUT=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$SPARK_HOST" \
  "sh -s '$REMOTE_DIR' '$LOCAL_SHA' '$ORIG_BOOTORDER' '$ORIG_0001_SHA'" <<'REMOTE_APPLY'
set -eu
RDIR="$1"
RTMP="${RDIR}/SPARK.EFI"
WANT_SHA="$2"
ORIG_ORDER="$3"
ORIG_0001_SHA="$4"

cleanup() { rm -rf "$RDIR"; }
trap cleanup EXIT

# Error-path BootNext clear: report the real outcome (never claim success that did not happen).
clear_bootnext() {
  if sudo -n efibootmgr -N >/dev/null 2>&1; then
    echo "           BootNext cleared (efibootmgr -N succeeded)." >&2
  else
    echo "           BootNext clear FAILED: a one-shot BootNext may still be armed." >&2
    echo "           At the console run: sudo efibootmgr -N   and verify with: efibootmgr -v" >&2
  fi
}

GOT_SHA=$(sha256sum "$RTMP" | awk '{print $1}')
if [ "$GOT_SHA" != "$WANT_SHA" ]; then
  echo "FAIL: transferred SPARK.EFI SHA-256 mismatch (got=$GOT_SHA want=$WANT_SHA)" >&2
  exit 1
fi

# Re-verify /boot/efi mount right before writing
ESP_SRC=$(findmnt -n -o SOURCE /boot/efi 2>/dev/null || echo "UNMOUNTED")
ESP_FSTYPE=$(findmnt -n -o FSTYPE /boot/efi 2>/dev/null || echo "NONE")
if [ "$ESP_SRC" != "/dev/nvme0n1p1" ] || [ "$ESP_FSTYPE" != "vfat" ]; then
  echo "FAIL: /boot/efi mount changed (source=$ESP_SRC fstype=$ESP_FSTYPE); aborting before write" >&2
  exit 1
fi

sudo -n mkdir -p /boot/efi/EFI/AIENOS
sudo -n install -m 0644 "$RTMP" /boot/efi/EFI/AIENOS/.SPARK.EFI.tmp
STAGE_SHA=$(sudo -n sha256sum /boot/efi/EFI/AIENOS/.SPARK.EFI.tmp | awk '{print $1}')
if [ "$STAGE_SHA" != "$WANT_SHA" ]; then
  sudo -n rm -f /boot/efi/EFI/AIENOS/.SPARK.EFI.tmp
  echo "FAIL: staged ESP SHA-256 mismatch" >&2
  exit 1
fi
sudo -n mv -f /boot/efi/EFI/AIENOS/.SPARK.EFI.tmp /boot/efi/EFI/AIENOS/SPARK.EFI
sync

BOOTNUM=$(efibootmgr -v | awk '
  /^Boot[0-9A-Fa-f]{4}/ && index($0, "\\EFI\\AIENOS\\SPARK.EFI") > 0 {
    print substr($1, 5, 4); exit
  }')

if [ -z "$BOOTNUM" ]; then
  # --create-only creates the entry WITHOUT modifying BootOrder
  sudo -n efibootmgr --create-only \
    --disk /dev/nvme0n1 --part 1 \
    --label "AIENOS Spark" \
    --loader '\EFI\AIENOS\SPARK.EFI' >/dev/null
  BOOTNUM=$(efibootmgr -v | awk '
    /^Boot[0-9A-Fa-f]{4}/ && index($0, "\\EFI\\AIENOS\\SPARK.EFI") > 0 {
      print substr($1, 5, 4); exit
    }')
fi

if [ -z "$BOOTNUM" ] || [ "$BOOTNUM" = "0001" ] || ! printf '%s\n' "$BOOTNUM" | grep -Eq '^[0-9A-Fa-f]{4}$'; then
  echo "FAIL: invalid or protected BOOTNUM='${BOOTNUM:-empty}' for \\EFI\\AIENOS\\SPARK.EFI" >&2
  exit 1
fi

# Set ONE-SHOT BootNext ONLY
sudo -n efibootmgr --bootnext "$BOOTNUM" >/dev/null

# Post-apply safety verification (byte-exact BootOrder and Boot0001)
POST_EFI=$(efibootmgr -v)
POST_ORDER=$(printf '%s\n' "$POST_EFI" | awk '/^BootOrder:/ {print $2; exit}')
POST_NEXT=$(printf '%s\n' "$POST_EFI" | awk '/^BootNext:/ {print $2; exit}')
POST_0001=$(printf '%s\n' "$POST_EFI" | grep -E '^Boot0001' | head -n 1 || true)
POST_0001_SHA=$(printf '%s' "$POST_0001" | sha256sum | awk '{print $1}')

if [ "$POST_ORDER" != "$ORIG_ORDER" ]; then
  # Never rewrite BootOrder from this tool (not even to "restore" it): clear the one-shot BootNext only
  # and hand the BootOrder decision to the operator at the console.
  echo "EMERGENCY: BootOrder changed from $ORIG_ORDER to $POST_ORDER; clearing BootNext only." >&2
  echo "           BootOrder was NOT rewritten. Inspect at the console; to restore manually:" >&2
  echo "             sudo efibootmgr -o $ORIG_ORDER" >&2
  clear_bootnext
  exit 1
fi

if [ "$POST_NEXT" != "$BOOTNUM" ]; then
  echo "FAIL: BootNext verification failed (got=$POST_NEXT want=$BOOTNUM)" >&2
  clear_bootnext
  exit 1
fi

if [ "$POST_0001_SHA" != "$ORIG_0001_SHA" ]; then
  echo "FAIL: Boot0001 changed after staging (sha got=$POST_0001_SHA want=$ORIG_0001_SHA); clearing BootNext." >&2
  clear_bootnext
  exit 1
fi

echo "STAGED_PATH=/boot/efi/EFI/AIENOS/SPARK.EFI"
echo "STAGED_SHA256=$STAGE_SHA"
echo "BOOTNUM=$BOOTNUM"
echo "POST_BOOTNEXT=$POST_NEXT"
echo "POST_BOOTORDER=$POST_ORDER"
echo "POST_BOOT0001_SHA256=$POST_0001_SHA"
REMOTE_APPLY
)

printf '%s\n' "$APPLY_OUT"
echo ""
echo "=== STAGING COMPLETE (NO REBOOT ISSUED) ==="
echo "SAFETY WARNING — GB20B COLD RESET REQUIRED:"
echo "  NEVER warm-reboot (sudo reboot) after nvidia.ko has been loaded on Spark!"
echo "  Perform a FULL COLD POWER-CYCLE instead:"
echo "    1. Attach UART console (0x16A00000, 115200 8N1) and monitor fan/thermals."
echo "    2. Cleanly power off Spark:"
echo "         ssh ${SPARK_HOST} 'sudo poweroff'"
echo "    3. Wait for power LED off, disconnect AC for 10 seconds, then power back on."
echo "       UEFI will boot \\EFI\\AIENOS\\SPARK.EFI ONCE via BootNext."
echo "  Any subsequent power-cycle or PSCI SYSTEM_RESET automatically returns to Ubuntu (Boot0001)."
echo ""
echo "To cancel BootNext before powering off:"
echo "  ssh ${SPARK_HOST} 'sudo efibootmgr -N'"
exit 0
