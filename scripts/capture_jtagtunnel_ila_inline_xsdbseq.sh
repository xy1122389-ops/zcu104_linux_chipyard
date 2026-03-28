#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <ila_dir> <label> <xsdb_script> [jtag_hz]" >&2
  exit 2
fi

ILA_DIR="$1"
LABEL="$2"
XSDB_SCRIPT="$3"
JTAG_HZ="${4:-10000}"
SKIP_PROGRAM="${SKIP_PROGRAM:-0}"
STAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="$FPGA_DIR/logs/jtagtunnel_ila_inline_${LABEL}_${STAMP}"
mkdir -p "$OUTDIR"

BITFILE="$ILA_DIR/ZCU104FPGATestHarness_jtagtunnel_ila.bit"
LTXFILE="$ILA_DIR/jtagtunnel_ila.ltx"

/root/.local/bin/vivado -mode batch -source "$SCRIPT_DIR/capture_jtagtunnel_ila_inline_stim_zcu104.tcl" -tclargs \
  -bitstream_path "$BITFILE" \
  -probes_path "$LTXFILE" \
  -skip_program "$SKIP_PROGRAM" \
  -xsdb_script "$XSDB_SCRIPT" \
  -jtag_hz "$JTAG_HZ" \
  -out_csv "$OUTDIR/jtagtunnel_ila.csv" \
  -out_state "$OUTDIR/state.txt" \
  -out_stim "$OUTDIR/stimulus.log" >"$OUTDIR/vivado.log" 2>&1

cat <<EOF >"$OUTDIR/summary.txt"
OUTDIR=$OUTDIR
LABEL=$LABEL
XSDB_SCRIPT=$XSDB_SCRIPT
JTAG_HZ=$JTAG_HZ
SKIP_PROGRAM=$SKIP_PROGRAM
CSV_OUT=$OUTDIR/jtagtunnel_ila.csv
STATE_OUT=$OUTDIR/state.txt
STIM_OUT=$OUTDIR/stimulus.log
EOF

cat "$OUTDIR/summary.txt"
