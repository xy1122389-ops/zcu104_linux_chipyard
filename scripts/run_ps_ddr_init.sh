#!/usr/bin/env bash
set -euo pipefail

# Preferred: add xsct to PATH, or export XSCT=/path/to/xsct
# Fallback on this machine: Windows xsdb.bat from Vivado 2021.2

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TCL_SCRIPT="$SCRIPT_DIR/run_ps_ddr_init.tcl"
RUNNER="$SCRIPT_DIR/run_xsdb_single_server.sh"

if [[ ! -f "$TCL_SCRIPT" ]]; then
  echo "Error: missing TCL script: $TCL_SCRIPT" >&2
  exit 1
fi

if [[ ! -x "$RUNNER" ]]; then
  echo "Error: missing XSDB runner: $RUNNER" >&2
  exit 2
fi

exec "$RUNNER" "$TCL_SCRIPT"
