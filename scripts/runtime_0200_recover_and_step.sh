#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <fw_payload-flat-path>" >&2
  exit 1
fi

PAYLOAD_PATH=$(realpath "$1")
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TCL_SCRIPT="$SCRIPT_DIR/runtime_0200_recover_and_step.tcl"
RUNNER="$SCRIPT_DIR/run_xsdb_single_server.sh"
TS=$(date +%Y%m%d_%H%M%S)
LOG="$SCRIPT_DIR/../logs/runtime_0200_recover_and_step_${TS}.log"

if [[ ! -f "$PAYLOAD_PATH" ]]; then
  echo "Error: payload not found: $PAYLOAD_PATH" >&2
  exit 2
fi

if [[ ! -f "$TCL_SCRIPT" ]]; then
  echo "Error: missing TCL script: $TCL_SCRIPT" >&2
  exit 3
fi

if [[ ! -x "$RUNNER" ]]; then
  echo "Error: missing XSDB runner: $RUNNER" >&2
  exit 4
fi

"$RUNNER" "$TCL_SCRIPT" "$PAYLOAD_PATH" > "$LOG" 2>&1 || true
echo "LOG:$LOG"
grep -aE '^(INITIAL_PSU_SELECT_ERR|RECOVER_ACTION|PAYLOAD_MRD0|BOOTADDR_|MSIP|PRE_|PARK_|STEP[0-9]+_|FINAL_)' "$LOG" || true
