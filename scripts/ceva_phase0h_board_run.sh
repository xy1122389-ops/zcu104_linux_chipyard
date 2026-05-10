#!/usr/bin/env bash
# Phase 0H board observation — BT RWBTEN + CLKN via J-Link GDB SBA
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

GDB=/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-gdb
JLINK_HOST=${JLINK_HOST:-127.0.0.1}
JLINK_PORT=${JLINK_PORT:-3333}
RUN_TAG=${1:-${RUN_TAG:-phase0h_$(date +%Y%m%d_%H%M%S)}}

LOG_DIR="${REPO_DIR}/logs/${RUN_TAG}"
mkdir -p "$LOG_DIR"
LOG="${LOG_DIR}/phase0h_observe.log"

echo "[phase0h_board_run] RUN_TAG=${RUN_TAG}  LOG=${LOG}"

if ! nc -z -w 3 "${JLINK_HOST}" "${JLINK_PORT}" 2>/dev/null; then
    echo "[ERROR] J-Link port not reachable — start: bash scripts/start_jlink_server.sh"
    exit 1
fi

timeout 120 "$GDB" -q -batch \
    -ex "set remotetimeout 30" \
    -x "${SCRIPT_DIR}/ceva_phase0h_jlink_observe.gdb" \
    2>&1 | tee "$LOG"

echo ""
grep -E "PHASE0H.*(PASS|FAIL|RWBTCNTL|hslot_count|INTSTAT)" "$LOG" | head -20

PASS_COUNT=$(grep -c "PHASE0H.*PASS" "$LOG" || true)
FAIL_COUNT=$(grep -c "PHASE0H.*FAIL" "$LOG" || true)

if   [[ "$PASS_COUNT" -gt 0 ]]; then echo "[phase0h_board_run] VERDICT: PASS"; exit 0
elif [[ "$FAIL_COUNT" -gt 0 ]]; then echo "[phase0h_board_run] VERDICT: FAIL"; exit 1
else echo "[phase0h_board_run] VERDICT: UNKNOWN"; exit 2; fi
