#!/bin/bash
# recover_bitstream_from_dcp.sh
# Re-generate bitstream from post_route.dcp (no re-synthesis/place/route needed)
# Fixes: DRC LUTLP-1 Combinatorial Loop in CEVA rw_dm_ahb_if_ahb2reg/hready_reg_0
#
# Usage:
#   bash scripts/recover_bitstream_from_dcp.sh
#   CONFIG_NAME=RocketZCU104Phase0bConfig bash scripts/recover_bitstream_from_dcp.sh

set -euo pipefail

VIVADO_BAT_WIN='E:\PRO_APP\xilinx\Vivado\2021.2\bin\vivado.bat'
WSL_UNC='\\wsl.localhost\Ubuntu-22.04'
WIN_DRIVE_PREFIX='Z:'

CONFIG_NAME="${CONFIG_NAME:-RocketZCU104Phase0bConfig}"
BUILD_DIR="/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.${CONFIG_NAME}/obj"
MODEL="ZCU104FPGATestHarness"
DCP_FILE="${BUILD_DIR}/post_route.dcp"
BIT_FILE="${BUILD_DIR}/${MODEL}.bit"
TCL_SCRIPT="/root/chipyard/fpga/scripts/fix_comb_loop_write_bitstream.tcl"
BUILD_START_EPOCH=$(date +%s)

echo "=== CEVA BT5.2 Phase1A: Recovery Bitstream Generation ==="
echo "Config: $CONFIG_NAME"
echo "DCP: $DCP_FILE"
echo "Bitstream output: $BIT_FILE"

# Verify DCP exists
if [[ ! -f "$DCP_FILE" ]]; then
    echo "[FAIL] post_route.dcp not found: $DCP_FILE"
    exit 1
fi
ls -lh "$DCP_FILE"

WIN_WRAPPER=$(mktemp /mnt/c/Windows/Temp/vivado_recoverXXXXXX.cmd)
trap 'rm -f "$WIN_WRAPPER"' EXIT
WIN_WRAPPER_WIN=$(wslpath -w "$WIN_WRAPPER")

WIN_BUILD_DIR="${WIN_DRIVE_PREFIX}${BUILD_DIR}"
WIN_TCL="${WIN_DRIVE_PREFIX}${TCL_SCRIPT}"

cat > "$WIN_WRAPPER" <<CMD
@echo off
REM Map WSL filesystem to a drive letter
net use Z: ${WSL_UNC} /persistent:no >nul 2>&1
pushd Z:${BUILD_DIR//\//\\}
"${VIVADO_BAT_WIN}" -nojournal -mode batch -source "${WIN_TCL}"
set EC=%ERRORLEVEL%
popd
net use Z: /delete /yes >nul 2>&1
exit /b %EC%
CMD

echo "[1/2] Launching Vivado to write bitstream from checkpoint..."
echo "  This should take ~5-15 minutes (much faster than full rebuild)"

LOG_FILE="${BUILD_DIR}/recover_bitstream.log"
cmd.exe /c "${WIN_WRAPPER_WIN}" 2>&1 | tee "$LOG_FILE"
EC=${PIPESTATUS[0]}

echo ""
echo "[2/2] Recovery complete (exit code: $EC)"

if [[ $EC -ne 0 ]]; then
    echo "[FAIL] Vivado returned non-zero exit code"
    tail -30 "$LOG_FILE"
    exit "$EC"
fi

if grep -qiE '^ERROR:' "$LOG_FILE" 2>/dev/null; then
    echo "[FAIL] Vivado log contains ERROR lines"
    grep -iE '^ERROR:' "$LOG_FILE" | head -20
    exit 1
fi

if [[ -f "${BIT_FILE}" ]]; then
    BIT_MTIME=$(stat -c %Y "${BIT_FILE}")
    if [[ $BIT_MTIME -lt $BUILD_START_EPOCH ]]; then
        echo "[FAIL] Bitstream timestamp did not advance during this run"
        ls -la "${BIT_FILE}"
        exit 1
    fi
    ls -lh "${BIT_FILE}"
    echo "[OK] Bitstream generated successfully"
else
    echo "[FAIL] Bitstream not found at $BIT_FILE"
    exit 1
fi
