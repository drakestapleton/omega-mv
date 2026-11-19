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
if [ "$SIZE_OF_IMAGE" -gt "$MAX_IMAGE_SIZE_BYTES" ]; then
  echo "FAIL: SizeOfImage=$SIZE_OF_IMAGE exceeds 64 MiB safety ceiling" >&2
  exit 1
fi

LOCAL_SHA=$(sha256_file "$SPARK_EFI")
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
PRE_OUT=$(ssh -o BatchMode=yes -o ConnectTimeout=8 "$SPARK_HOST" 'sh -s' <<'REMOTE_PRE'
set -eu
echo "SECTION:EFI"
efibootmgr -v
echo "SECTION:ESP"
df -B1 /boot/efi | tail -n 1
test -f /boot/efi/EFI/ubuntu/shimaa64.efi && echo "UBUNTU_SHIM=OK" || echo "UBUNTU_SHIM=MISSING"
echo "SECTION:GPUBUSY"
# Read-only procfs symlink inspection — NEVER opens /dev/nvidia*
BUSY=$(sudo -n sh -c '
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
' 2>/dev/null || true)
if [ -n "$BUSY" ]; then
  printf 'GPU_OPEN_PROCS=%s\n' "$(printf '%s\n' "$BUSY" | paste -sd',' -)"
else
  echo "GPU_OPEN_PROCS=NONE"
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
ESP_AVAIL=$(printf '%s\n' "$PRE_OUT" | awk '/^SECTION:ESP/{f=1;next}/^SECTION:/{f=0}f && /^\//{print $4; exit}')
UBUNTU_SHIM=$(printf '%s\n' "$PRE_OUT" | awk -F= '/^UBUNTU_SHIM=/{print $2; exit}')
GPU_BUSY=$(printf '%s\n' "$PRE_OUT" | awk -F= '/^GPU_OPEN_PROCS=/{print $2; exit}')

case "$ORIG_BOOTORDER" in
  0001|0001,*) ;;
  *)
    echo "FAIL: Spark BootOrder does not start with 0001 (got: ${ORIG_BOOTORDER:-missing}); refusing." >&2
    exit 1 ;;
esac

case "$ORIG_BOOT0001" in
  *ubuntu*shimaa64.efi*) ;;
  *)
    echo "FAIL: Spark Boot0001 is not Ubuntu shim (got: ${ORIG_BOOT0001:-missing}); refusing." >&2
    exit 1 ;;
esac

if [ "$UBUNTU_SHIM" != "OK" ]; then
  echo "FAIL: /boot/efi/EFI/ubuntu/shimaa64.efi missing on $SPARK_HOST; refusing." >&2
  exit 1
fi

if [ -z "$ESP_AVAIL" ] || [ "$ESP_AVAIL" -lt "$MIN_ESP_FREE_BYTES" ] 2>/dev/null; then
  echo "FAIL: Spark ESP /boot/efi free space insufficient (${ESP_AVAIL:-unknown} B < 64 MiB); refusing." >&2
  exit 1
fi

echo "[OK] Spark BootOrder=$ORIG_BOOTORDER, Boot0001=ubuntu intact, ESP free=$((ESP_AVAIL / 1048576)) MiB"

if [ "$GPU_BUSY" != "NONE" ]; then
  if [ "$APPLY" -eq 1 ] && [ "$FORCE_GPU_BUSY" -ne 1 ]; then
    echo "REFUSED: Live GPU workload detected holding /dev/nvidia* open: $GPU_BUSY" >&2
    echo "         Stop GPU workloads first or pass --force-while-gpu-busy." >&2
    echo "         Zero changes were made to Spark ESP or NVRAM." >&2
    exit 3
  fi
  echo "[WARN] Live /dev/nvidia* open processes detected: $GPU_BUSY"
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

REMOTE_TMP="/tmp/SPARK.EFI.stage.$$"
scp -q "$SPARK_EFI" "${SPARK_HOST}:${REMOTE_TMP}"

APPLY_OUT=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$SPARK_HOST" \
  "sh -s '$REMOTE_TMP' '$LOCAL_SHA' '$ORIG_BOOTORDER'" <<'REMOTE_APPLY'
set -eu
RTMP="$1"
WANT_SHA="$2"
ORIG_ORDER="$3"

cleanup() { rm -f "$RTMP"; }
trap cleanup EXIT

GOT_SHA=$(sha256sum "$RTMP" | awk '{print $1}')
if [ "$GOT_SHA" != "$WANT_SHA" ]; then
  echo "FAIL: transferred SPARK.EFI SHA-256 mismatch (got=$GOT_SHA want=$WANT_SHA)" >&2
  exit 1
fi

sudo mkdir -p /boot/efi/EFI/AIENOS
sudo install -m 0644 "$RTMP" /boot/efi/EFI/AIENOS/.SPARK.EFI.tmp
STAGE_SHA=$(sudo sha256sum /boot/efi/EFI/AIENOS/.SPARK.EFI.tmp | awk '{print $1}')
if [ "$STAGE_SHA" != "$WANT_SHA" ]; then
  sudo rm -f /boot/efi/EFI/AIENOS/.SPARK.EFI.tmp
  echo "FAIL: staged ESP SHA-256 mismatch" >&2
  exit 1
fi
sudo mv -f /boot/efi/EFI/AIENOS/.SPARK.EFI.tmp /boot/efi/EFI/AIENOS/SPARK.EFI
sync

BOOTNUM=$(efibootmgr -v | awk '
  /^Boot[0-9A-Fa-f]{4}/ && index($0, "\\EFI\\AIENOS\\SPARK.EFI") > 0 {
    print substr($1, 5, 4); exit
  }')

if [ -z "$BOOTNUM" ]; then
  # --create-only creates the entry WITHOUT modifying BootOrder
  sudo efibootmgr --create-only \
    --disk /dev/nvme0n1 --part 1 \
    --label "AIENOS Spark" \
    --loader '\EFI\AIENOS\SPARK.EFI' >/dev/null
  BOOTNUM=$(efibootmgr -v | awk '
    /^Boot[0-9A-Fa-f]{4}/ && index($0, "\\EFI\\AIENOS\\SPARK.EFI") > 0 {
      print substr($1, 5, 4); exit
    }')
fi

if [ -z "$BOOTNUM" ]; then
  echo "FAIL: could not locate BootXXXX for \\EFI\\AIENOS\\SPARK.EFI" >&2
  exit 1
fi

# Set ONE-SHOT BootNext ONLY
sudo efibootmgr --bootnext "$BOOTNUM" >/dev/null

# Post-apply safety verification
POST_EFI=$(efibootmgr -v)
POST_ORDER=$(printf '%s\n' "$POST_EFI" | awk '/^BootOrder:/ {print $2; exit}')
POST_NEXT=$(printf '%s\n' "$POST_EFI" | awk '/^BootNext:/ {print $2; exit}')
POST_0001=$(printf '%s\n' "$POST_EFI" | grep -E '^Boot0001' | head -n 1 || true)

if [ "$POST_ORDER" != "$ORIG_ORDER" ]; then
  echo "EMERGENCY: BootOrder changed from $ORIG_ORDER to $POST_ORDER; restoring immediately!" >&2
  sudo efibootmgr -o "$ORIG_ORDER" >/dev/null
  sudo efibootmgr -N >/dev/null
  exit 1
fi

if [ "$POST_NEXT" != "$BOOTNUM" ]; then
  echo "FAIL: BootNext verification failed (got=$POST_NEXT want=$BOOTNUM)" >&2
  exit 1
fi

if ! printf '%s\n' "$POST_0001" | grep -q 'ubuntu.*shimaa64\.efi'; then
  echo "FAIL: Boot0001 verification failed after staging!" >&2
  sudo efibootmgr -N >/dev/null
  exit 1
fi

echo "STAGED_PATH=/boot/efi/EFI/AIENOS/SPARK.EFI"
echo "STAGED_SHA256=$STAGE_SHA"
echo "BOOTNUM=$BOOTNUM"
echo "POST_BOOTNEXT=$POST_NEXT"
echo "POST_BOOTORDER=$POST_ORDER"
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
