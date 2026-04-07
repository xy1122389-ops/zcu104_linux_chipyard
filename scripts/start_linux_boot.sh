#!/usr/bin/env bash
# start_linux_boot.sh — Run the full Linux bring-up sequence via GDB
#
# Prerequisites:
#   1. FPGA programmed + PS DDR initialized (run_ps_ddr_init.sh)
#   2. J-Link GDB Server running on Windows (port 2331)
#   3. /tmp/fw_chunks_new/chunk_*.bin exists (fw_payload split into 4MB chunks)
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
RELAY_HOST="172.19.128.1"
RELAY_PORT=12331
BOOT_TIMEOUT="${1:-600}"

for f in "$GDB" "$SCRIPT" "$DUMP_SCRIPT"; do
  if [[ ! -f "$f" ]]; then
    echo "Error: not found: $f" >&2
    exit 1
  fi
done

if ! compgen -G "/tmp/fw_chunks_new/chunk_*.bin" > /dev/null; then
  echo "Error: no fw_payload chunk files found under /tmp/fw_chunks_new" >&2
  exit 1
fi

# Check/start relay
if nc -z -w 2 "$RELAY_HOST" "$RELAY_PORT" 2>/dev/null; then
    echo "[OK] Relay running at ${RELAY_HOST}:${RELAY_PORT}"
else
    echo "[info] Starting relay..."
    powershell.exe -NoProfile -Command "Start-Process python -ArgumentList 'C:\Users\24242\jlink_relay.py' -WindowStyle Normal" 2>/dev/null
    sleep 5
    if nc -z -w 2 "$RELAY_HOST" "$RELAY_PORT" 2>/dev/null; then
        echo "[OK] Relay started"
    else
        echo "[FAIL] Cannot reach relay. Is J-Link GDB Server running?" >&2
        exit 1
    fi
fi

RUN_TAG="${RUN_TAG:-run_$(date +%Y%m%d_%H%M%S)}"
BOOT_LOG="/tmp/boot_${RUN_TAG}.log"

echo "[info] Kernel run time: ${BOOT_TIMEOUT}s"
echo "[info] Run tag: ${RUN_TAG}"
echo "[info] fw chunks: $(find /tmp/fw_chunks_new -maxdepth 1 -name 'chunk_*.bin' | wc -l)"
echo ""

# Combined boot + klog dump in single GDB session
# The GDB script uses a Python timer to interrupt after KERNEL_RUN_SECS,
# then dumps klog before exiting. No separate dump step needed.
# Timeout = kernel_run + 600s margin for DDR zeroing + restore + dump
OUTER_TIMEOUT=$((BOOT_TIMEOUT + 600))
echo "=== Running linux_boot.gdb (combined boot + dump, outer timeout ${OUTER_TIMEOUT}s) ==="
KERNEL_RUN_SECS="$BOOT_TIMEOUT" RUN_TAG="$RUN_TAG" \
  timeout "$OUTER_TIMEOUT" "$GDB" -batch -x "$SCRIPT" 2>&1 | tee "$BOOT_LOG" || true

echo ""
echo "=== Done ==="
echo "Log: ${BOOT_LOG}"
echo "Klog binary: /tmp/klog_${RUN_TAG}.bin"
echo "Klog strings: /tmp/boot_${RUN_TAG}.strings"
