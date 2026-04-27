#!/usr/bin/env bash
# phase1_verify_ps_chain.sh
#
# Phase 1: 验证 PS 侧链路 (PMUFW/FSBL/bitstream/arm_stub)
# 通过 XSDB 在 JTAG 模式下运行
#
# 前提:
#   SW6 已切换为 JTAG 模式 (全部 OFF = PS_MODE=0=JTAG)
#   ZCU104 已断电重上电
#   BOOT_v2.BIN 仍在 SD p1 (不会被此脚本访问)
#
# 使用:
#   bash scripts/phase1_verify_ps_chain.sh [--cfg RocketZCU104LinuxBringupConfig]
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TCL_SCRIPT="$SCRIPT_DIR/phase1_verify_ps_chain.tcl"

CHIPYARD_ZCU104_CFG="${CHIPYARD_ZCU104_CFG:-RocketZCU104LinuxBringupConfig}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cfg) CHIPYARD_ZCU104_CFG="$2"; shift 2 ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done
export CHIPYARD_ZCU104_CFG

XSDB_BAT="/mnt/e/PRO_APP/xilinx/Vivado/2021.2/bin/xsdb.bat"
if [[ ! -f "$XSDB_BAT" ]]; then
    echo "Error: xsdb.bat not found: $XSDB_BAT" >&2
    exit 2
fi

WIN_TCL=$(wslpath -w "$TCL_SCRIPT")
WIN_WRAPPER=$(mktemp /mnt/c/Windows/Temp/phase1_ps_chainXXXX.cmd)
trap 'rm -f "$WIN_WRAPPER"' EXIT
WIN_WRAPPER_CMD=$(wslpath -w "$WIN_WRAPPER")
WIN_XSDB_BAT=$(wslpath -w "$XSDB_BAT")

cat > "$WIN_WRAPPER" <<CMD
@echo off
set "CHIPYARD_ZCU104_CFG=${CHIPYARD_ZCU104_CFG}"
pushd C:\Windows\Temp
call "${WIN_XSDB_BAT}" -eval "source {${WIN_TCL}}"
set EC=%ERRORLEVEL%
popd
exit /b %EC%
CMD

echo "[Phase 1] Starting PS chain verification..."
echo "[Phase 1] Config: ${CHIPYARD_ZCU104_CFG}"
echo "[Phase 1] JTAG mode expected: SW6 all OFF (PS_MODE=0)"
echo ""

cmd.exe /c "$WIN_WRAPPER_CMD"
EC=$?
echo ""
if [[ $EC -eq 0 ]]; then
    echo "[Phase 1] XSDB script completed (exit 0)."
else
    echo "[Phase 1] XSDB script exited with code $EC."
fi
exit $EC
