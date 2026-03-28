#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 4 ]]; then
  echo "Usage: $0 <ila_dir> <label> <dr_bits> <dr_hex> [jtag_hz]" >&2
  exit 2
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ILA_DIR="$1"
LABEL="$2"
DR_BITS="$3"
DR_HEX="$4"
JTAG_HZ="${5:-10000}"

pkill -f 'capture_jtagtunnel_ila_inline_stim.sh' || true
pkill -f 'run_shiftwindow_inline_matrix.sh' || true

"$SCRIPT_DIR/restart_hw_server_windows.sh" >/dev/null

exec "$SCRIPT_DIR/capture_jtagtunnel_ila_inline_stim.sh" "$ILA_DIR" "$LABEL" "$DR_BITS" "$DR_HEX" "$JTAG_HZ"
