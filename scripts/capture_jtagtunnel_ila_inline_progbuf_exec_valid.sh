#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <ila_dir> <label> [jtag_hz]" >&2
  exit 2
fi
ILA_DIR="$1"
LABEL="$2"
JTAG_HZ="${3:-10000}"
SKIP_PROGRAM="${SKIP_PROGRAM:-1}"
PROGBUF0_WORD="${PROGBUF0_WORD:-0x00100073}"
SELECT_PAYLOAD="${SELECT_PAYLOAD:-0x10}"
"$SCRIPT_DIR/capture_jtagtunnel_ila_inline_progbuf_exec.sh" "$ILA_DIR" "$LABEL" "$JTAG_HZ"
outdir=$(find /root/chipyard/fpga/logs -maxdepth 1 -type d -name "jtagtunnel_ila_inline_${LABEL}_*" | sort | tail -n 1)
state="$outdir/state.txt"
if [[ ! -f "$state" ]]; then
  echo "ERROR: missing state.txt for $LABEL" >&2
  exit 10
fi
if ! grep -q 'STATUS.SAMPLE_COUNT=' "$state"; then
  echo "ERROR: malformed state.txt for $LABEL" >&2
  exit 11
fi
count=$(grep 'STATUS.SAMPLE_COUNT=' "$state" | tail -n1 | cut -d= -f2)
if [[ "$count" == "0" ]]; then
  echo "ERROR: invalid capture, SAMPLE_COUNT=0 for $LABEL" >&2
  exit 12
fi
printf 'VALID_OUTDIR=%s\n' "$outdir"
