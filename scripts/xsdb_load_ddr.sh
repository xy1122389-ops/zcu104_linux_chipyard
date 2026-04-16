#!/usr/bin/env bash
set -euo pipefail

# xsdb_load_ddr.sh — Load OpenSBI firmware + DTB into PS DDR via ARM core
# Wrapper that invokes XSDB (Windows-side) to run xsdb_load_ddr.tcl

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TCL_SCRIPT="$SCRIPT_DIR/xsdb_load_ddr.tcl"
FW_BIN_ORIG=/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.bin
FW_PADDED=/tmp/fw_payload_padded_0x2000.bin

if [[ ! -f "$TCL_SCRIPT" ]]; then
  echo "Error: missing TCL script: $TCL_SCRIPT" >&2
  exit 1
fi

if [[ ! -f "$FW_BIN_ORIG" ]]; then
  echo "Error: missing firmware binary: $FW_BIN_ORIG" >&2
  exit 1
fi

# NOTE: padding workaround DISABLED — it causes +0x2000 destination shift.
# XSDB mwr -bin writes are correct without padding; the readback (mrd) is
# what's broken. Loading original file directly gives correct DDR layout.
# truncate -s 8192 "$FW_PADDED"
# cat "$FW_BIN_ORIG" >> "$FW_PADDED"

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

WIN_DTB_PATH_LINE=
if [[ -n "${DTB_PATH:-}" ]]; then
  WIN_DTB_PATH=$(wslpath -w "$DTB_PATH")
  WIN_DTB_PATH_LINE="set DTB_PATH=$WIN_DTB_PATH"
fi

cat > "$WIN_WRAPPER" <<CMD
@echo off
pushd C:\Windows\Temp
%WIN_DTB_PATH_LINE%
call "$WIN_XSDB_BAT" -eval "source {$WIN_TCL}"
set EC=%ERRORLEVEL%
popd
exit /b %EC%
CMD

exec cmd.exe /c "$WIN_WRAPPER_CMD"
