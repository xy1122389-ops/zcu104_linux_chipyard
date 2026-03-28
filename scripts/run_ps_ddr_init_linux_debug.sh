#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TCL_SCRIPT="$SCRIPT_DIR/run_ps_ddr_init_linux_debug.tcl"
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
