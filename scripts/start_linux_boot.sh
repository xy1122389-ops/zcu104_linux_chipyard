#!/usr/bin/env bash
# start_linux_boot.sh — Run the full Linux bring-up sequence via GDB
#
# Prerequisites:
#   1. FPGA programmed + PS DDR initialized (run_ps_ddr_init.sh)
#   2. J-Link GDB Server running on Windows (port 2331)
#   3. linux-bringup/payload/fw_payload.bin exists
#
# Usage: ./scripts/start_linux_boot.sh [BOOT_TIMEOUT_SECS]
#   Default timeout: 600s (10 min). Kernel runs for this long, then klog is dumped.
#
# This script:
#   1. Ensures TCP relay is running (WSL→Windows for Hyper-V bypass)
#   2. Runs linux_boot.gdb (Phases 1-7: zero DDR, load firmware, boot kernel)
#   3. After timeout, runs linux_klog_dump.gdb to collect kernel log
set -euo pipefail

GDB=/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb
SCRIPT="$(dirname "$0")/linux_boot.gdb"
DUMP_SCRIPT="$(dirname "$0")/linux_klog_dump.gdb"
PAYLOAD_BIN="/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.bin"
CHUNK_DIR=/tmp/fw_chunks_new
CHUNK_SIZE=4194304
JLINK_HOST="${JLINK_HOST:-172.19.128.1}"
JLINK_PORT="${JLINK_PORT:-12331}"
BOOT_TIMEOUT="${1:-600}"

for f in "$GDB" "$SCRIPT" "$DUMP_SCRIPT" "$PAYLOAD_BIN"; do
  if [[ ! -f "$f" ]]; then
    echo "Error: not found: $f" >&2
    exit 1
  fi
done

mkdir -p "$CHUNK_DIR"
rm -f "$CHUNK_DIR"/chunk_*.bin
split -b "$CHUNK_SIZE" -d -a 2 --numeric-suffixes=0 --additional-suffix=.bin \
  "$PAYLOAD_BIN" "$CHUNK_DIR/chunk_"

if ! compgen -G "$CHUNK_DIR/chunk_*.bin" > /dev/null; then
  echo "Error: failed to generate fw_payload chunk files under $CHUNK_DIR" >&2
  exit 1
fi

if ! cmp -s "$PAYLOAD_BIN" <(cat "$CHUNK_DIR"/chunk_*.bin); then
  echo "Error: generated fw_payload chunks do not match $PAYLOAD_BIN" >&2
  exit 1
fi

if nc -z -w 2 "$JLINK_HOST" "$JLINK_PORT" 2>/dev/null; then
  echo "[OK] J-Link endpoint reachable at ${JLINK_HOST}:${JLINK_PORT}"
else
  if [[ "$JLINK_HOST" == "172.19.128.1" && "$JLINK_PORT" == "12331" ]]; then
    echo "[info] Starting relay..."
    powershell.exe -NoProfile -Command "Start-Process python -ArgumentList 'C:\Users\24242\jlink_relay.py' -WindowStyle Normal" 2>/dev/null
    sleep 5
    if nc -z -w 2 "$JLINK_HOST" "$JLINK_PORT" 2>/dev/null; then
      echo "[OK] Relay started"
    else
      echo "[FAIL] Cannot reach relay endpoint ${JLINK_HOST}:${JLINK_PORT}" >&2
      exit 1
    fi
  else
    echo "[FAIL] Cannot reach J-Link endpoint ${JLINK_HOST}:${JLINK_PORT}" >&2
    exit 1
  fi
fi

RUN_TAG="${RUN_TAG:-run_$(date +%Y%m%d_%H%M%S)}"
BOOT_LOG="/tmp/boot_${RUN_TAG}.log"

echo "[info] Kernel run time: ${BOOT_TIMEOUT}s"
echo "[info] Run tag: ${RUN_TAG}"
echo "[info] J-Link endpoint: ${JLINK_HOST}:${JLINK_PORT}"
echo "[info] fw payload: ${PAYLOAD_BIN} ($(stat -c %s "$PAYLOAD_BIN") bytes)"
echo "[info] fw chunks: $(find "$CHUNK_DIR" -maxdepth 1 -name 'chunk_*.bin' | wc -l)"
echo ""

# Combined boot + klog dump in single GDB session
# The GDB script uses a Python timer to interrupt after KERNEL_RUN_SECS,
# then dumps klog before exiting. No separate dump step needed.
# Timeout = kernel_run + 600s margin for DDR zeroing + restore + dump
OUTER_TIMEOUT=$((BOOT_TIMEOUT + 600))
echo "=== Running linux_boot.gdb (combined boot + dump, outer timeout ${OUTER_TIMEOUT}s) ==="
JLINK_HOST="$JLINK_HOST" JLINK_PORT="$JLINK_PORT" KERNEL_RUN_SECS="$BOOT_TIMEOUT" RUN_TAG="$RUN_TAG" \
  timeout "$OUTER_TIMEOUT" "$GDB" -batch -x "$SCRIPT" 2>&1 | tee "$BOOT_LOG" || true

echo ""
echo "=== Done ==="
echo "Log: ${BOOT_LOG}"
echo "Klog binary: /tmp/klog_${RUN_TAG}.bin"
echo "Klog strings: /tmp/boot_${RUN_TAG}.strings"
