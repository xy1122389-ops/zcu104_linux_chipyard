#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <ila_dir> <label> <progbuf0_word_hex> [jtag_hz]" >&2
  exit 2
fi

ILA_DIR="$1"
LABEL="$2"
PROGBUF0_WORD="$3"
JTAG_HZ="${4:-10000}"
LTXFILE="$ILA_DIR/jtagtunnel_ila.ltx"

"$SCRIPT_DIR/restart_hw_server_windows.sh" >/dev/null

SKIP_PROGRAM=1 PROGBUF0_WORD="$PROGBUF0_WORD" timeout 420 \
  "$SCRIPT_DIR/capture_jtagtunnel_ila_inline_progbuf_exec.sh" \
  "$ILA_DIR" "$LABEL" "$JTAG_HZ" >/tmp/"${LABEL}".run.log 2>&1 || true

LATEST=$(find "$FPGA_DIR/logs" -maxdepth 1 -type d -name "jtagtunnel_ila_inline_${LABEL}_*" | sort | tail -n 1 || true)
if [[ -n "$LATEST" && -f "$LATEST/jtagtunnel_ila.csv" && -f "$LATEST/state.txt" ]]; then
  echo "MODE=inline"
  echo "OUTDIR=$LATEST"
  exit 0
fi

pkill -f "capture_jtagtunnel_ila_inline_progbuf_exec.sh .* ${LABEL} " 2>/dev/null || true
pkill -f "capture_jtagtunnel_ila_inline_xsdbseq.sh .* ${LABEL} " 2>/dev/null || true

STAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="$FPGA_DIR/logs/jtagtunnel_ila_upload_only_${LABEL}_recover_${STAMP}"
mkdir -p "$OUTDIR"

/root/.local/bin/vivado -mode batch \
  -source "$SCRIPT_DIR/upload_existing_ila_data_zcu104.tcl" \
  -tclargs \
  -probes_path "$LTXFILE" \
  -out_csv "$OUTDIR/jtagtunnel_ila.csv" \
  -out_state "$OUTDIR/state.txt" >"$OUTDIR/vivado.log" 2>&1

echo "MODE=recover"
echo "OUTDIR=$OUTDIR"
