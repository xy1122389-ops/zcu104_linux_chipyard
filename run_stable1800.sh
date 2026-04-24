#!/usr/bin/env bash
set -euo pipefail

# run_stable1800.sh - Launch 1800-second stability test
# Assumes: stable_init already done, JLink server started

cd /root/chipyard/fpga

RUN_TAG="stable1800_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/tmp/boot_${RUN_TAG}.log"

echo "[$(date)] === STABLE1800 LONG-RUN TEST ===" | tee "$LOG_FILE"
echo "[$(date)] RUN_TAG=$RUN_TAG" | tee -a "$LOG_FILE"
echo "[$(date)] LOG=$LOG_FILE" | tee -a "$LOG_FILE"
echo "$RUN_TAG" > /tmp/current_run_tag.txt
echo "$LOG_FILE" > /tmp/current_run_log.txt

# Verify chunks exist
CHUNK_COUNT=$(ls /tmp/fw_chunks_new/chunk_*.bin 2>/dev/null | wc -l)
echo "[$(date)] Found $CHUNK_COUNT fw_payload chunks" | tee -a "$LOG_FILE"
if [[ $CHUNK_COUNT -ne 5 ]]; then
    echo "[ERROR] Expected 5 chunks, got $CHUNK_COUNT" | tee -a "$LOG_FILE"
    exit 1
fi

# Launch main GDB boot with 1800s kernel run
echo "[$(date)] Launching GDB with KERNEL_RUN_SECS=1800..." | tee -a "$LOG_FILE"
echo "[$(date)] Command: JLINK_HOST=127.0.0.1 JLINK_PORT=3333 KERNEL_RUN_SECS=1800 timeout 4200 riscv64-unknown-elf-gdb -q -batch -x scripts/linux_boot.gdb" | tee -a "$LOG_FILE"
echo "[$(date)] Note: 4200s timeout = 33min(Phases1-6) + 30min(kernel) + 5min(klog) + buffer" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

export JLINK_HOST=127.0.0.1
export JLINK_PORT=3333
export KERNEL_RUN_SECS=1800
export RUN_TAG="$RUN_TAG"

# Launch GDB boot - timeout 4200s (Phases 1-6: ~33min, kernel: 30min, klog: 5min, buffer: 5min)
timeout 4200 /root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb \
    -q -batch -x scripts/linux_boot.gdb 2>&1 | tee -a "$LOG_FILE" || {
        EXIT_CODE=$?
        echo "[$(date)] GDB finished with exit code $EXIT_CODE" | tee -a "$LOG_FILE"
        if [[ $EXIT_CODE -eq 124 ]]; then
            echo "[WARNING] Timeout (4200s) reached - check if Phase 7 kernel ran full 1800s" | tee -a "$LOG_FILE"
        fi
    }

echo "[$(date)] === STABLE1800 COMPLETE ===" | tee -a "$LOG_FILE"
echo "[$(date)] Log saved to: $LOG_FILE" | tee -a "$LOG_FILE"
ls -lh "$LOG_FILE"
