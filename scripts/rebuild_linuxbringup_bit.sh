#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TCL_SCRIPT="$SCRIPT_DIR/rebuild_linuxbringup_bit.tcl"
VIVADO_BAT_DEFAULT='/mnt/e/PRO_APP/xilinx/Vivado/2021.2/bin/vivado.bat'
VIVADO_BAT="${VIVADO_BAT:-$VIVADO_BAT_DEFAULT}"

if [[ ! -f "$VIVADO_BAT" ]]; then
  echo "missing vivado.bat: $VIVADO_BAT" >&2
  exit 1
fi

WIN_VIVADO=$(wslpath -w "$VIVADO_BAT")
WIN_TCL=$(wslpath -w "$TCL_SCRIPT")
WIN_PROJDIR='\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig'

WIN_WRAPPER=$(mktemp /mnt/c/Windows/Temp/rebuild_linuxbringup_bitXXXX.cmd)
trap 'rm -f "$WIN_WRAPPER"' EXIT
WIN_WRAPPER_CMD=$(wslpath -w "$WIN_WRAPPER")

{
  echo '@echo off'
  printf 'pushd "%s"\r\n' "$WIN_PROJDIR"
  printf 'call "%s" -mode batch -source "%s"\r\n' "$WIN_VIVADO" "$WIN_TCL"
  echo 'set EC=%ERRORLEVEL%'
  echo 'popd'
  echo 'exit /b %EC%'
} > "$WIN_WRAPPER"

exec cmd.exe /c "$WIN_WRAPPER_CMD"
