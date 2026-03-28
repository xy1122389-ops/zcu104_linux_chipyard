#!/usr/bin/env bash
set -euo pipefail

FW=${1:-/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.bin}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TCL_SCRIPT="$SCRIPT_DIR/runtime_a53_bp_ladder.tcl"
RUNNER="$SCRIPT_DIR/run_xsdb_single_server.sh"
TS=$(date +%Y%m%d_%H%M%S)
LOG="$SCRIPT_DIR/../logs/runtime_a53_bp_ladder_${TS}.log"
SETUP_LOG="$SCRIPT_DIR/../logs/runtime_a53_bp_ladder_setup_${TS}.log"

if [[ ! -f "$FW" ]]; then
  echo "Error: payload not found: $FW" >&2
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

{
  echo "==== setup psu_init + bit + payload ===="
  bash "$SCRIPT_DIR/run_ps_ddr_init_linux.sh"
  bash "$SCRIPT_DIR/load_linux_fw_payload.sh" "$FW"
  echo
  echo "==== ladder probe ===="
  "$RUNNER" "$TCL_SCRIPT"
} > "$SETUP_LOG" 2>&1 || true

cp "$SETUP_LOG" "$LOG"
echo "LOG:$LOG"
grep -aE '^BP_ADDR_' "$LOG" || true
