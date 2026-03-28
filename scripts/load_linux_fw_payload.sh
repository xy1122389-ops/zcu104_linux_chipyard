#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <fw_payload-flat-path> [bootaddr-hex]" >&2
  exit 1
fi

PAYLOAD_PATH=$(realpath "$1")
BOOTADDR_HEX=${2:-}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TCL_SCRIPT="$SCRIPT_DIR/load_linux_fw_payload.tcl"
RUNNER="$SCRIPT_DIR/run_xsdb_single_server.sh"

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

if [[ -n "$BOOTADDR_HEX" ]]; then
  exec "$RUNNER" "$TCL_SCRIPT" "$PAYLOAD_PATH" "$BOOTADDR_HEX"
fi

exec "$RUNNER" "$TCL_SCRIPT" "$PAYLOAD_PATH"
