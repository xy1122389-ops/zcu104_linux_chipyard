#!/usr/bin/env bash
set -euo pipefail

# Preferred: add xsct to PATH, or export XSCT=/path/to/xsct
# Fallback on this machine: Windows xsdb.bat from Vivado 2021.2

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TCL_SCRIPT="$SCRIPT_DIR/run_ps_ddr_init.tcl"

if [[ ! -f "$TCL_SCRIPT" ]]; then
  echo "Error: missing TCL script: $TCL_SCRIPT" >&2
  exit 1
fi

if [[ -n "${XSCT:-}" ]]; then
  exec "$XSCT" "$TCL_SCRIPT"
fi

if command -v xsct >/dev/null 2>&1; then
  exec xsct "$TCL_SCRIPT"
fi

if command -v xsdb >/dev/null 2>&1; then
  exec xsdb "$TCL_SCRIPT"
fi

XSDB_BAT_DEFAULT='/mnt/e/PRO_APP/xilinx/Vivado/2021.2/bin/xsdb.bat'
XSDB_BAT="${XSDB_BAT:-$XSDB_BAT_DEFAULT}"

if [[ ! -f "$XSDB_BAT" ]]; then
  echo "Error: xsct/xsdb not found in PATH, and XSDB_BAT does not exist: $XSDB_BAT" >&2
  echo "Set XSCT=/path/to/xsct or XSDB_BAT=/path/to/xsdb.bat and retry." >&2
  exit 2
fi

if [[ ! -d /mnt/c/Windows/Temp ]]; then
  echo "Error: /mnt/c/Windows/Temp not found; cannot create Windows-side xsdb wrapper." >&2
  exit 3
fi

WIN_TCL=$(wslpath -w "$TCL_SCRIPT")
WIN_WRAPPER=$(mktemp /mnt/c/Windows/Temp/xsdb_wrapperXXXX.cmd)
trap 'rm -f "$WIN_WRAPPER"' EXIT
WIN_WRAPPER_CMD=$(wslpath -w "$WIN_WRAPPER")
WIN_XSDB_BAT=$(wslpath -w "$XSDB_BAT")

cat > "$WIN_WRAPPER" <<CMD
@echo off
pushd C:\Windows\Temp
call "$WIN_XSDB_BAT" -eval "source {$WIN_TCL}"
set EC=%ERRORLEVEL%
popd
exit /b %EC%
CMD

exec cmd.exe /c "$WIN_WRAPPER_CMD"
