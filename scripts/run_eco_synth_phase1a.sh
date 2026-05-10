#!/usr/bin/env bash
# run_eco_synth_phase1a.sh
# Launch ECO at SYNTHESIS CHECKPOINT level (avoids 493-port mismatch)
# The OOC DCP (eco_wrapper_ooc.dcp) must already exist from previous OOC synth run.

set -euo pipefail

VIVADO_BAT_WIN='E:\PRO_APP\xilinx\Vivado\2021.2\bin\vivado.bat'
WSL_UNC='\\wsl.localhost\Ubuntu-22.04'
WIN_DRIVE_PREFIX='Z:'

CONFIG_NAME="RocketZCU104Phase0bConfig"
BUILD_DIR="/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.${CONFIG_NAME}"
OBJ_DIR="${BUILD_DIR}/obj"
TCL_SCRIPT="/root/chipyard/fpga/scripts/eco_synth_wrapper_phase1a.tcl"
LOG_FILE="${OBJ_DIR}/eco_synth_phase1a.log"
BIT_FILE="${OBJ_DIR}/ZCU104FPGATestHarness.bit"
OOC_DCP="${OBJ_DIR}/eco_wrapper_ooc.dcp"
POST_SYNTH="${OBJ_DIR}/post_synth.dcp"

echo "[ECO-SYNTH] Starting Phase 1A ECO at synthesis level at $(date '+%H:%M:%S')"
echo "[ECO-SYNTH] Log: $LOG_FILE"

# Verify prerequisites
if [[ ! -f "$OOC_DCP" ]]; then
    echo "[ECO-SYNTH] FAIL: OOC DCP not found: $OOC_DCP"
    echo "[ECO-SYNTH] Run run_eco_phase1a.sh first to generate OOC DCP."
    exit 1
fi
if [[ ! -f "$POST_SYNTH" ]]; then
    echo "[ECO-SYNTH] FAIL: post_synth.dcp not found: $POST_SYNTH"
    exit 1
fi

echo "[ECO-SYNTH] OOC DCP:      $(ls -lh $OOC_DCP)"
echo "[ECO-SYNTH] post_synth:   $(ls -lh $POST_SYNTH)"

BUILD_START_EPOCH=$(date +%s)

WIN_WRAPPER=$(mktemp /mnt/c/Windows/Temp/eco_synth_vivado_XXXXXX.cmd)
trap 'rm -f "$WIN_WRAPPER"' EXIT
WIN_WRAPPER_WIN=$(wslpath -w "$WIN_WRAPPER")

cat > "$WIN_WRAPPER" <<CMD
@echo off
net use Z: ${WSL_UNC} /persistent:no >nul 2>&1
pushd Z:${OBJ_DIR//\//\\}
"${VIVADO_BAT_WIN}" -nojournal -mode batch -source "${WIN_DRIVE_PREFIX}${TCL_SCRIPT}" -log "${WIN_DRIVE_PREFIX}${LOG_FILE}"
set EC=%ERRORLEVEL%
popd
net use Z: /delete /yes >nul 2>&1
exit /b %EC%
CMD

echo "[ECO-SYNTH] Launching Vivado (ECO at synthesis level, ~25 min)..."
cmd.exe /c "${WIN_WRAPPER_WIN}" 2>&1 | tee -a "$LOG_FILE"
EC=${PIPESTATUS[0]}

echo ""
echo "[ECO-SYNTH] Vivado exit code: $EC"
echo "[ECO-SYNTH] Checking result..."
BIT_MTIME=$(stat -c '%y' "$BIT_FILE" 2>/dev/null || echo "NOT FOUND")
echo "[ECO-SYNTH] Bitstream mtime: $BIT_MTIME"

BIT_NOW=$(stat -c %Y "$BIT_FILE" 2>/dev/null || echo 0)
if [[ "$BIT_NOW" -gt "$BUILD_START_EPOCH" ]]; then
    echo "[ECO-SYNTH] SUCCESS: $(ls -lh $BIT_FILE)"
else
    echo "[ECO-SYNTH] FAIL: Bitstream not updated (mtime not advanced)"
    tail -20 "$LOG_FILE"
    exit 1
fi

echo "[ECO-SYNTH] Done at $(date '+%H:%M:%S')"
