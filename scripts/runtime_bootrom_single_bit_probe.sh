#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <label> <psu_init.tcl> <bitfile>" >&2
  exit 1
fi

LABEL=$1
PSU_INIT=$(realpath "$2")
BITFILE=$(realpath "$3")
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TCL_SCRIPT="$SCRIPT_DIR/runtime_bootrom_single_bit_probe.tcl"
RUNNER="$SCRIPT_DIR/run_xsdb_single_server.sh"
TS=$(date +%Y%m%d_%H%M%S)
LOG="$SCRIPT_DIR/../logs/runtime_bootrom_single_bit_probe_${LABEL}_${TS}.log"

if [[ ! -f "$TCL_SCRIPT" ]]; then
  echo "Error: missing TCL script: $TCL_SCRIPT" >&2
  exit 2
fi

if [[ ! -x "$RUNNER" ]]; then
  echo "Error: missing XSDB runner: $RUNNER" >&2
  exit 3
fi

"$RUNNER" "$TCL_SCRIPT" "$PSU_INIT" "$BITFILE" > "$LOG" 2>&1 || true
echo "LABEL:$LABEL"
echo "LOG:$LOG"
grep -a '^BOOTROM_' "$LOG" || true
