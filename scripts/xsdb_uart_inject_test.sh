#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
RUNNER="$SCRIPT_DIR/run_xsdb_single_server.sh"
TCL_SCRIPT="$SCRIPT_DIR/xsdb_uart_inject_test.tcl"

exec "$RUNNER" "$TCL_SCRIPT"
