#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TCL_SCRIPT="$SCRIPT_DIR/run_ps_ddr_init_no_release.tcl"
XSDB_BAT_DEFAULT='/mnt/e/PRO_APP/xilinx/Vivado/2021.2/bin/xsdb.bat'
XSDB_BAT="${XSDB_BAT:-$XSDB_BAT_DEFAULT}"

if [[ ! -f "$XSDB_BAT" ]]; then
  echo "Error: XSDB_BAT not found: $XSDB_BAT" >&2
  exit 2
fi

WIN_TCL=$(wslpath -w "$TCL_SCRIPT")
WIN_WRAPPER=$(mktemp /mnt/c/Windows/Temp/xsdb_wrapper_no_releaseXXXX.cmd)
trap 'rm -f "$WIN_WRAPPER"' EXIT
WIN_WRAPPER_CMD=$(wslpath -w "$WIN_WRAPPER")
WIN_XSDB_BAT=$(wslpath -w "$XSDB_BAT")
WIN_CFG=${CHIPYARD_ZCU104_CFG:-RocketZCU104LinuxBringupConfig}
WIN_DIRECT_PATH_LINES=""

if [[ -n "${CHIPYARD_BITSTREAM_LINUX:-}" && -n "${CHIPYARD_BITSTREAM_WINDOWS:-}" && -n "${CHIPYARD_PSU_INIT_TCL_LINUX:-}" && -n "${CHIPYARD_PSU_INIT_TCL_WINDOWS:-}" ]]; then
  WIN_DIRECT_PATH_LINES+="set \"CHIPYARD_BITSTREAM_LINUX=${CHIPYARD_BITSTREAM_LINUX}\""$'\n'
  WIN_DIRECT_PATH_LINES+="set \"CHIPYARD_BITSTREAM_WINDOWS=${CHIPYARD_BITSTREAM_WINDOWS}\""$'\n'
  WIN_DIRECT_PATH_LINES+="set \"CHIPYARD_PSU_INIT_TCL_LINUX=${CHIPYARD_PSU_INIT_TCL_LINUX}\""$'\n'
  WIN_DIRECT_PATH_LINES+="set \"CHIPYARD_PSU_INIT_TCL_WINDOWS=${CHIPYARD_PSU_INIT_TCL_WINDOWS}\""$'\n'
fi

cat > "$WIN_WRAPPER" <<CMD
@echo off
set "CHIPYARD_ZCU104_CFG=$WIN_CFG"
${WIN_DIRECT_PATH_LINES}pushd C:\Windows\Temp
call "$WIN_XSDB_BAT" "$WIN_TCL"
set EC=%ERRORLEVEL%
popd
exit /b %EC%
CMD

cmd.exe /c "$WIN_WRAPPER_CMD"