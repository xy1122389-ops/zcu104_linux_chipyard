#!/bin/bash
# Phase 0J board run: rwip_driver_init sequence via J-Link GDB SBA
# Tests MASTER_SOFT_RST self-clear and INTCNTL1 init (rwip_driver_init equivalent)
set -euo pipefail

RUN_TAG="${RUN_TAG:-phase0j_$(date +%Y%m%d_%H%M%S)}"
LOG_DIR="/root/chipyard/fpga/logs/${RUN_TAG}"
LOG="${LOG_DIR}/phase0j_rwip_init.log"
GDB_SCRIPT="/root/chipyard/fpga/scripts/ceva_phase0j_jlink_rwip_init.gdb"

export PATH="/root/chipyard/.oclaw-env/bin:/root/chipyard/.oclaw-env/riscv-tools/bin:$PATH"

mkdir -p "$LOG_DIR"
echo "[phase0j_board_run] RUN_TAG=${RUN_TAG}  LOG=${LOG}"

timeout 60 riscv64-unknown-elf-gdb -q -batch -x "$GDB_SCRIPT" 2>&1 | tee "$LOG"
GDB_RC=${PIPESTATUS[0]}

# Print summary
echo ""
grep "^\[PHASE0J\]" "$LOG" | grep -E "J[0-9]:|PASS|FAIL|VERDICT" | tail -30
echo ""
VERDICT=$(grep "VERDICT:" "$LOG" | tail -1)
echo "[phase0j_board_run] ${VERDICT}"

exit $GDB_RC
