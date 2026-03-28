#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <tcl-script> [args...]" >&2
  exit 1
fi

TCL_SCRIPT=$(realpath "$1")
shift

if [[ ! -f "$TCL_SCRIPT" ]]; then
  echo "Error: missing TCL script: $TCL_SCRIPT" >&2
  exit 2
fi

XSDB_BAT_DEFAULT='/mnt/e/PRO_APP/xilinx/Vivado/2021.2/bin/xsdb.bat'
XSDB_BAT="${XSDB_BAT:-$XSDB_BAT_DEFAULT}"

if [[ ! -f "$XSDB_BAT" ]]; then
  echo "Error: xsdb.bat not found: $XSDB_BAT" >&2
  exit 4
fi

if [[ ! -d /mnt/c/Windows/Temp ]]; then
  echo "Error: /mnt/c/Windows/Temp not found" >&2
  exit 5
fi

WIN_TCL=$(wslpath -w "$TCL_SCRIPT")
WIN_XSDB_BAT=$(wslpath -w "$XSDB_BAT")
WIN_WRAPPER=$(mktemp /mnt/c/Windows/Temp/xsdb_single_serverXXXX.cmd)
trap 'rm -f "$WIN_WRAPPER"' EXIT
WIN_WRAPPER_CMD=$(wslpath -w "$WIN_WRAPPER")

WIN_ARGS=()
for arg in "$@"; do
  if [[ -e "$arg" ]]; then
    WIN_ARGS+=("$(wslpath -w "$(realpath "$arg")")")
  else
    WIN_ARGS+=("$arg")
  fi
done

{
  echo '@echo off'
  echo 'pushd C:\Windows\Temp'
  echo 'taskkill /F /IM hw_server.exe >nul 2>&1'
  printf 'call "%s" "%s"' "$WIN_XSDB_BAT" "$WIN_TCL"
  for win_arg in "${WIN_ARGS[@]}"; do
    printf ' "%s"' "$win_arg"
  done
  printf '\r\n'
  echo 'set EC=%ERRORLEVEL%'
  echo 'popd'
  echo 'exit /b %EC%'
} > "$WIN_WRAPPER"

exec cmd.exe /c "$WIN_WRAPPER_CMD"
