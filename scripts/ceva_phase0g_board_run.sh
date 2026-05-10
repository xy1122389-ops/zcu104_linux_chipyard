#!/usr/bin/env bash
# Phase 0G board observation via J-Link GDB SBA
# Uses EXISTING Phase0b bitstream (no reflash needed)
# CEVA register access via J-Link monitor WriteU32/ReadU32
#
# Usage:
#   bash scripts/ceva_phase0g_board_run.sh [RUN_TAG]
#
# Prerequisites:
#   - J-Link GDB Server running: bash scripts/start_jlink_server.sh
#   - Board powered, Phase0b bitstream programmed, PS DDR init done
#   - CPU in alive-heartbeat loop (Phase0e completed)

set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

GDB=/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb
JLINK_HOST=${JLINK_HOST:-127.0.0.1}
JLINK_PORT=${JLINK_PORT:-3333}
RUN_TAG=${1:-${RUN_TAG:-phase0g_$(date +%Y%m%d_%H%M%S)}}

LOG_DIR="${REPO_DIR}/logs/${RUN_TAG}"
mkdir -p "$LOG_DIR"
LOG="${LOG_DIR}/phase0g_observe.log"
GDB_SCRIPT="${SCRIPT_DIR}/ceva_phase0g_jlink_observe.gdb"

echo "[phase0g_board_run] ==============================="
echo "[phase0g_board_run] RUN_TAG  = ${RUN_TAG}"
echo "[phase0g_board_run] GDB      = ${GDB}"
echo "[phase0g_board_run] JLINK    = ${JLINK_HOST}:${JLINK_PORT}"
echo "[phase0g_board_run] LOG      = ${LOG}"
echo "[phase0g_board_run] ==============================="

# Sanity: check J-Link port
if ! nc -z -w 3 "${JLINK_HOST}" "${JLINK_PORT}" 2>/dev/null; then
    echo "[ERROR] J-Link port ${JLINK_HOST}:${JLINK_PORT} not reachable"
    echo "[ERROR] Start server: bash scripts/start_jlink_server.sh"
    exit 1
fi
echo "[phase0g_board_run] J-Link port OK"

# Run GDB
echo "[phase0g_board_run] Running GDB observation script..."
timeout 120 "$GDB" -q -batch \
    -ex "set remotetimeout 30" \
    -x "$GDB_SCRIPT" \
    2>&1 | tee "$LOG"

echo ""
echo "[phase0g_board_run] === KEY RESULTS ==="
grep -E "PHASE0G.*(PASS|FAIL|RWBLECNTL_after|hslot_count|INTSTAT)" "$LOG" | head -20

echo ""
PASS_COUNT=$(grep -c "PHASE0G.*PASS" "$LOG" || true)
FAIL_COUNT=$(grep -c "PHASE0G.*FAIL" "$LOG" || true)

if [[ "$PASS_COUNT" -gt 0 ]]; then
    echo "[phase0g_board_run] VERDICT: PASS"
    exit 0
elif [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo "[phase0g_board_run] VERDICT: FAIL"
    exit 1
else
    echo "[phase0g_board_run] VERDICT: UNKNOWN (no PASS/FAIL found in log)"
    exit 2
fi
