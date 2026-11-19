#!/bin/bash
# Launch Qwen3.8-27B-FP8 on DGX Spark GB10 with maximum unified memory dedicated
# to the model (full 262,144-token native context), bound to WireGuard 100.64.0.2:18099
# so the Raspberry Pi (hub, AArch64) drives it remotely with zero agent/compiler bloat on Spark.
#
# Follows Spark rules:
# - Never touches MODEL_PORT (18091) or motor-revival.service (Harness Lock)
# - Runs inside an authorized spark-window with an EXIT trap (RULE-spark-no-idle-models.md)
# - Posts CLAIM / RELEASE to ~/handoffs/BOARD.md
set -euo pipefail

BIN_DIR="$HOME/.local/state/aien-q36/bin-cc45f45e"
MODEL_DIR="$HOME/models/specialist-transfer/qwen3.8-27b-fp8-017b9c7a"
BIND_ADDR="${PI_DRIVE_BIND:-127.0.0.1}"
PORT="${PI_DRIVE_PORT:-18099}"
MAX_CTX="${PI_DRIVE_MAX_CTX:-131072}"
MAX_TOK="${PI_DRIVE_MAX_TOK:-16384}"
LEASE_MIN="${PI_DRIVE_LEASE:-10}"
LOG_FILE="/tmp/pi-drive-27b-spark.log"
BOARD="$HOME/handoffs/BOARD.md"
SERVER_PID=""

cleanup() {
  local rc=$?
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    for _ in $(seq 1 20); do
      kill -0 "$SERVER_PID" 2>/dev/null || break
      sleep 0.5
    done
    kill -9 "$SERVER_PID" 2>/dev/null || true
  fi
  echo "$(date -u +%FT%H:%MZ) RELEASE pi-drive-27b to all: Qwen3.8-27B-FP8 max-ctx=${MAX_CTX} server stopped cleanly on ${BIND_ADDR}:${PORT}" >> "$BOARD"
  exit "$rc"
}
trap cleanup EXIT INT TERM

cd "$BIN_DIR"
sha256sum -c SHA256SUMS >/dev/null

echo "$(date -u +%FT%H:%MZ) CLAIM pi-drive-27b to all: Qwen3.8-27B-FP8 on GB10 (max-ctx=${MAX_CTX}, ${BIND_ADDR}:${PORT}) driven from Pi hub over SSH tunnel, lease ${LEASE_MIN}m" >> "$BOARD"

./aien-serve-http \
  --engine omega \
  --model-dir "$MODEL_DIR" \
  --bind "$BIND_ADDR" \
  --port "$PORT" \
  --max-context "$MAX_CTX" \
  --max-tokens-cap "$MAX_TOK" \
  --thinking off > "$LOG_FILE" 2>&1 &
SERVER_PID=$!

for _ in $(seq 1 180); do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "ERROR: aien-serve-http exited early:" >&2
    tail -n 40 "$LOG_FILE" >&2
    exit 1
  fi
  if curl -fsS "http://${BIND_ADDR}:${PORT}/health" >/dev/null 2>&1; then
    echo "READY pid=${SERVER_PID} bind=${BIND_ADDR}:${PORT} max_ctx=${MAX_CTX}"
    break
  fi
  sleep 1
done

wait "$SERVER_PID"
