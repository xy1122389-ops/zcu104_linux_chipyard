#!/usr/bin/env bash
set -euo pipefail

# stable_init.sh — Unified ZCU104 LinuxBringup init
# Burns correct 19MB LinuxBringup bit, runs psu_init, leaves GPIO[31]=0

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TCL_SCRIPT="$SCRIPT_DIR/xsdb_stable_init.tcl"

if [[ ! -f "$TCL_SCRIPT" ]]; then
    echo "Error: missing $TCL_SCRIPT" >&2
    exit 1
fi

WIN_TCL=$(wslpath -w "$TCL_SCRIPT")
XSDB_BAT="${XSDB_BAT:-/mnt/e/PRO_APP/xilinx/Vivado/2021.2/bin/xsdb.bat}"
WIN_XSDB_BAT=$(wslpath -w "$XSDB_BAT")

WIN_WRAPPER=$(mktemp /mnt/c/Windows/Temp/xsdb_stable_initXXXX.cmd)
trap 'rm -f "$WIN_WRAPPER"' EXIT
WIN_WRAPPER_CMD=$(wslpath -w "$WIN_WRAPPER")

cat > "$WIN_WRAPPER" <<CMD
@echo off
pushd C:\\Windows\\Temp
call "$WIN_XSDB_BAT" -eval "source {$WIN_TCL}"
set EC=%ERRORLEVEL%
popd
exit /b %EC%
CMD

echo "[stable_init] Programming LinuxBringup bit + full PS init + GPIO[31]=0"
echo "[stable_init] TCL: $WIN_TCL"
echo ""
cmd.exe /c "$WIN_WRAPPER_CMD"
EC=$?
echo ""
if [[ $EC -eq 0 ]]; then
    echo "[stable_init] SUCCESS — ready for J-Link"
else
    echo "[stable_init] FAILED (exit code $EC)" >&2
fi
exit $EC
