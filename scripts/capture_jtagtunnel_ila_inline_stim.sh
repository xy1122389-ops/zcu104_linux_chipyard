#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

if [[ $# -lt 4 ]]; then
  echo "Usage: $0 <ila_dir> <label> <dr_bits> <dr_hex> [jtag_hz]" >&2
  exit 2
fi

ILA_DIR="$1"
LABEL="$2"
DR_BITS="$3"
DR_HEX="$4"
JTAG_HZ="${5:-10000}"
STAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="$FPGA_DIR/logs/jtagtunnel_ila_inline_${LABEL}_${STAMP}"
mkdir -p "$OUTDIR"

BITFILE="$ILA_DIR/ZCU104FPGATestHarness_jtagtunnel_ila.bit"
LTXFILE="$ILA_DIR/jtagtunnel_ila.ltx"

/root/.local/bin/vivado -mode batch -source "$SCRIPT_DIR/capture_jtagtunnel_ila_inline_stim_zcu104.tcl" -tclargs \
  -bitstream_path "$BITFILE" \
  -probes_path "$LTXFILE" \
  -dr_bits "$DR_BITS" \
  -dr_hex "$DR_HEX" \
  -jtag_hz "$JTAG_HZ" \
  -out_csv "$OUTDIR/jtagtunnel_ila.csv" \
  -out_state "$OUTDIR/state.txt" \
  -out_stim "$OUTDIR/stimulus.log" >"$OUTDIR/vivado.log" 2>&1

cat <<EOF >"$OUTDIR/summary.txt"
OUTDIR=$OUTDIR
LABEL=$LABEL
DR_BITS=$DR_BITS
DR_HEX=$DR_HEX
JTAG_HZ=$JTAG_HZ
CSV_OUT=$OUTDIR/jtagtunnel_ila.csv
STATE_OUT=$OUTDIR/state.txt
STIM_OUT=$OUTDIR/stimulus.log
EOF

cat "$OUTDIR/summary.txt"
