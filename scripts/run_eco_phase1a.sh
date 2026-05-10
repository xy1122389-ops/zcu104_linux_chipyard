#!/bin/bash
# Run ECO flow for CEVA wrapper Phase 1A fix
# Bypasses full synthesis (which deadlocks on Berkeley HardFloat in Vivado 2021.2)
# Instead: OOC-synth only the wrapper, ECO into existing post_route.dcp

set -euo pipefail

VIVADO_BAT_WIN='E:\PRO_APP\xilinx\Vivado\2021.2\bin\vivado.bat'
WSL_UNC='\\wsl.localhost\Ubuntu-22.04'
WIN_DRIVE_PREFIX='Z:'

BUILD_DIR='/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104Phase0bConfig'
OBJ_DIR="${BUILD_DIR}/obj"
LOG="${OBJ_DIR}/eco_phase1a.log"

echo "[ECO] Starting CEVA wrapper ECO at $(date '+%H:%M:%S')"
echo "[ECO] Log: $LOG"

# Check prerequisites
if [[ ! -f "${OBJ_DIR}/post_route.dcp" ]]; then
    echo "[ECO] ERROR: post_route.dcp not found at ${OBJ_DIR}/post_route.dcp"
    exit 1
fi
if [[ ! -f "${BUILD_DIR}/gen-collateral/rw_dm_top_phase0b_real_wrapper.v" ]]; then
    echo "[ECO] ERROR: wrapper RTL not found"
    exit 1
fi

echo "[ECO] post_route.dcp: $(ls -lh ${OBJ_DIR}/post_route.dcp)"
echo "[ECO] Wrapper RTL (fixed): $(ls -lh ${BUILD_DIR}/gen-collateral/rw_dm_top_phase0b_real_wrapper.v)"

# Create a Windows .cmd wrapper (same pattern as build_bitstream_wsl.sh)
WIN_WRAPPER=$(mktemp /mnt/c/Windows/Temp/eco_vivado_XXXXXX.cmd)
WIN_WRAPPER_WIN=$(wslpath -w "$WIN_WRAPPER")
trap 'rm -f "$WIN_WRAPPER"' EXIT

WIN_LOG="${WIN_DRIVE_PREFIX}${LOG}"
WIN_TCL="${WIN_DRIVE_PREFIX}/root/chipyard/fpga/scripts/eco_ceva_wrapper_phase1a.tcl"
BUILD_WIN="${WIN_DRIVE_PREFIX}${BUILD_DIR//\//\\}"

cat > "$WIN_WRAPPER" <<CMD
@echo off
net use ${WIN_DRIVE_PREFIX} ${WSL_UNC} /persistent:no >nul 2>&1
pushd ${BUILD_WIN}
"${VIVADO_BAT_WIN}" -nojournal -mode batch -source "${WIN_TCL}" -log "${WIN_LOG}"
set EC=%ERRORLEVEL%
popd
net use ${WIN_DRIVE_PREFIX} /delete /yes >nul 2>&1
exit /b %EC%
CMD

echo "[ECO] Launching Vivado ECO..."
cmd.exe /c "${WIN_WRAPPER_WIN}" 2>&1 | tee /tmp/eco_vivado_output.txt
VIVADO_EXIT=${PIPESTATUS[0]}

echo "[ECO] Vivado exit code: $VIVADO_EXIT"
echo "[ECO] Checking result..."

BIT="${OBJ_DIR}/ZCU104FPGATestHarness.bit"
ECO_BIT_TIME=$(stat -c %Y "$BIT" 2>/dev/null || echo "0")
echo "[ECO] Bitstream mtime: $(date -d @$ECO_BIT_TIME 2>/dev/null)"

if [[ $VIVADO_EXIT -eq 0 && -f "$BIT" ]]; then
    echo "[ECO] SUCCESS: $(ls -lh $BIT)"
else
    echo "[ECO] FAILED"
    echo "[ECO] Last 20 lines of log:"
    tail -20 "$LOG" 2>/dev/null || tail -20 /tmp/eco_vivado_output.txt
    exit 1
fi

echo "[ECO] Done at $(date '+%H:%M:%S')"
