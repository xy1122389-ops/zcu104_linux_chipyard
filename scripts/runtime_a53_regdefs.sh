#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TCL_SCRIPT="$SCRIPT_DIR/runtime_a53_regdefs.tcl"
RUNNER="$SCRIPT_DIR/run_xsdb_single_server.sh"
TS=$(date +%Y%m%d_%H%M%S)
LOG="$SCRIPT_DIR/../logs/runtime_a53_regdefs_${TS}.log"

if [[ ! -f "$TCL_SCRIPT" ]]; then
  echo "Error: missing TCL script: $TCL_SCRIPT" >&2
  exit 2
fi

if [[ ! -x "$RUNNER" ]]; then
  echo "Error: missing XSDB runner: $RUNNER" >&2
  exit 3
fi

"$RUNNER" "$TCL_SCRIPT" > "$LOG" 2>&1 || true
echo "LOG:$LOG"
