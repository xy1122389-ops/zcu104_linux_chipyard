#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
RUNNER="$SCRIPT_DIR/run_xsdb_single_server.sh"
TCL_SCRIPT="$SCRIPT_DIR/runtime_uart_mmio_semantics.tcl"
TS=$(date +%Y%m%d_%H%M%S)
LOG="$SCRIPT_DIR/../logs/runtime_uart_mmio_semantics_${TS}.log"

"$RUNNER" "$TCL_SCRIPT" > "$LOG" 2>&1 || true
echo "LOG:$LOG"
grep -aE '^(BASE_|POSTCFG_|WRITE_TXDATA|TXSNAP_|REREAD_ROUND|REREAD_)' "$LOG" || true
