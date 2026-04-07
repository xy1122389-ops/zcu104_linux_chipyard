#!/usr/bin/env bash
# multi_boot.sh — Run multiple Linux boot attempts, stop on success
#
# Usage: ./scripts/multi_boot.sh [MAX_ATTEMPTS] [KERNEL_RUN_SECS]
#   Default: 5 attempts, 600s kernel run each

set -euo pipefail

MAX_ATTEMPTS="${1:-5}"
KERNEL_RUN_SECS="${2:-600}"

echo "==================================="
echo " Multi-boot: up to ${MAX_ATTEMPTS} attempts"
echo " Kernel run: ${KERNEL_RUN_SECS}s each"
echo "==================================="

for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
    RUN_TAG="multi_${attempt}_$(date +%H%M%S)"
    echo ""
    echo "========================================="
    echo " Attempt ${attempt}/${MAX_ATTEMPTS}  tag=${RUN_TAG}"
    echo "========================================="
    
    KERNEL_RUN_SECS="$KERNEL_RUN_SECS" RUN_TAG="$RUN_TAG" \
        bash scripts/start_linux_boot.sh "$KERNEL_RUN_SECS" || true
    
    # Analyze results
    STRINGS_FILE="/tmp/boot_${RUN_TAG}.strings"
    LOG_FILE="/tmp/boot_${RUN_TAG}.log"
    
    if [[ ! -f "$STRINGS_FILE" ]]; then
        echo "[attempt $attempt] FAILED: no strings file. Skipping analysis."
        continue
    fi
    
    echo ""
    echo "--- Attempt ${attempt} analysis ---"
    
    # Check milestones
    HAS_PANIC=$(grep -ci 'kernel panic' "$STRINGS_FILE" || true)
    HAS_OOPS=$(grep -ci 'oops' "$STRINGS_FILE" || true)
    HAS_FREEING=$(grep -ci 'freeing unused' "$STRINGS_FILE" || true)
    HAS_RUNINIT=$(grep -ci 'run /init\|run /sbin' "$STRINGS_FILE" || true)
    HAS_WELCOME=$(grep -ci 'welcome\|login\|#\|busybox' "$STRINGS_FILE" || true)
    
    echo "  Kernel panic : ${HAS_PANIC}"
    echo "  Oops         : ${HAS_OOPS}"
    echo "  Freeing mem  : ${HAS_FREEING}"
    echo "  Run /init    : ${HAS_RUNINIT}"
    echo "  Userspace    : ${HAS_WELCOME}"
    
    if [[ "$HAS_FREEING" -gt 0 && "$HAS_PANIC" -eq 0 && "$HAS_OOPS" -eq 0 ]]; then
        echo ""
        echo "****** SUCCESS! Kernel reached 'Freeing unused' without crash! ******"
        echo "****** Log: ${LOG_FILE} ******"
        echo "****** Strings: ${STRINGS_FILE} ******"
        exit 0
    fi
    
    if [[ "$HAS_RUNINIT" -gt 0 ]]; then
        echo ""
        echo "****** PARTIAL SUCCESS! Kernel reached init execution! ******"
        echo "****** Log: ${LOG_FILE} ******"
        exit 0
    fi
    
    echo "  -> Boot crashed. Continuing to next attempt..."
    sleep 5
done

echo ""
echo "All ${MAX_ATTEMPTS} attempts exhausted without clean boot."
echo "Check logs in /tmp/boot_multi_*.log"
exit 1
