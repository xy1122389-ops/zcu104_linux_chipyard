#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
RUNNER="$SCRIPT_DIR/run_xsdb_single_server.sh"
TCL_SCRIPT="$SCRIPT_DIR/enable_tile_clock_and_kick.tcl"

exec "$RUNNER" "$TCL_SCRIPT"
