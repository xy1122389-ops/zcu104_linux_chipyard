#!/bin/bash
# Incremental Vivado rebuild for Phase 1A hready_in_r RTL fix
# Runs full synth+impl+bitstream but uses post_synth.dcp and post_route.dcp
# as incremental references to speed up (typically 45-90 min vs 3-4h full)
#
# Usage: bash scripts/run_incremental_rebuild_phase1a.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FPGA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

CONFIG_NAME="${CONFIG_NAME:-RocketZCU104Phase0bConfig}"
BUILD_DIR="${FPGA_DIR}/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.${CONFIG_NAME}"
OBJ_DIR="${BUILD_DIR}/obj"
TCL_SCRIPT="${SCRIPT_DIR}/incremental_rebuild_phase1a.tcl"

VIVADO_BAT_WIN='E:\PRO_APP\xilinx\Vivado\2021.2\bin\vivado.bat'
WSL_UNC='\\wsl.localhost\Ubuntu-22.04'
WIN_DRIVE_PREFIX='Z:'

BIT_FILE="${OBJ_DIR}/ZCU104FPGATestHarness.bit"
LOG_FILE="${OBJ_DIR}/incremental_rebuild.log"

echo "[incr-rebuild] ================================================"
echo "[incr-rebuild] Phase 1A Incremental Rebuild (hready_in_r fix)"
echo "[incr-rebuild] CONFIG: $CONFIG_NAME"
echo "[incr-rebuild] ================================================"

# Pre-flight checks
for f in "${OBJ_DIR}/post_synth.dcp" "${OBJ_DIR}/post_route.dcp" "${BUILD_DIR}/vsrcs_win.f"; do
    if [[ ! -f "$f" ]]; then
        echo "[incr-rebuild] ERROR: Required file missing: $f"
        exit 1
    fi
done

echo "[incr-rebuild] Pre-flight checks PASS"
echo "[incr-rebuild] RTL change: hready_in_r register in rw_dm_top_phase0b_real_wrapper.v"
echo "[incr-rebuild] Wrapper file: $(grep -c 'hready_in_r' "${FPGA_DIR}/../generators/chipyard/src/main/resources/vsrc/ceva/rw_dm_top_phase0b_real_wrapper.v" 2>/dev/null || echo '?') occurrences of hready_in_r in wrapper"

# Map Windows path for TCL script
WIN_TCL="${WIN_DRIVE_PREFIX}${TCL_SCRIPT}"

# Build the CMD wrapper
WIN_WRAPPER=$(mktemp /mnt/c/Windows/Temp/vivado_incr_XXXXXX.cmd)
trap 'rm -f "$WIN_WRAPPER"' EXIT
WIN_WRAPPER_WIN=$(wslpath -w "$WIN_WRAPPER")

# Convert OBJ_DIR to Windows path
WIN_OBJ_DIR="${WIN_DRIVE_PREFIX}${OBJ_DIR//\//\\}"
WIN_BUILD_DIR="${WIN_DRIVE_PREFIX}${BUILD_DIR//\//\\}"

cat > "$WIN_WRAPPER" <<CMD
@echo off
net use Z: ${WSL_UNC} /persistent:no >nul 2>&1
pushd ${WIN_OBJ_DIR}
"${VIVADO_BAT_WIN}" -nojournal -mode batch -source "${WIN_TCL}" -tclargs -BUILD_DIR "${WIN_BUILD_DIR}" -OBJ_DIR "${WIN_OBJ_DIR}"
set EC=%ERRORLEVEL%
popd
net use Z: /delete /yes >nul 2>&1
exit /b %EC%
CMD

echo "[incr-rebuild] Launching Windows Vivado (incremental)..."
echo "[incr-rebuild] Log: $LOG_FILE"
START_TIME=$(date +%s)

cmd.exe /c "$WIN_WRAPPER_WIN" 2>&1 | tee "$LOG_FILE"
EXIT_CODE=${PIPESTATUS[0]}

END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))
echo "[incr-rebuild] Elapsed: ${ELAPSED}s ($((ELAPSED/60)) min)"

if [[ $EXIT_CODE -ne 0 ]]; then
    echo "[incr-rebuild] FAILED (exit=$EXIT_CODE)"
    echo "[incr-rebuild] Check log: $LOG_FILE"
    exit 1
fi

# Check bitstream was updated
if [[ -f "$BIT_FILE" ]]; then
    BIT_TIME=$(stat -c %Y "$BIT_FILE")
    if (( BIT_TIME > START_TIME )); then
        echo "[incr-rebuild] SUCCESS: New bitstream generated at $(date -d @$BIT_TIME)"
        ls -lh "$BIT_FILE"
    else
        echo "[incr-rebuild] WARNING: Bitstream not updated (old file remains)"
        ls -lh "$BIT_FILE"
        exit 1
    fi
else
    echo "[incr-rebuild] ERROR: Bitstream not found"
    exit 1
fi
