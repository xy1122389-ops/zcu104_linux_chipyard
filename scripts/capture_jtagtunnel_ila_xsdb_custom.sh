#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
STAMP=$(date +%Y%m%d_%H%M%S)

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <ila_dir> <label> <dr_bits> <dr_hex> [jtag_hz]" >&2
  exit 2
fi

ILA_DIR="$1"
LABEL="$2"
DR_BITS="$3"
DR_HEX="$4"
JTAG_HZ="${5:-10000}"

BITFILE="$ILA_DIR/ZCU104FPGATestHarness_jtagtunnel_ila.bit"
LTXFILE="$ILA_DIR/jtagtunnel_ila.ltx"
if [[ ! -f "$BITFILE" || ! -f "$LTXFILE" ]]; then
  echo "missing bit/ltx in $ILA_DIR" >&2
  exit 3
fi

OUTDIR="$FPGA_DIR/logs/jtagtunnel_ila_xsdb_custom_${LABEL}_${STAMP}"
mkdir -p "$OUTDIR"

ARM_STATE="$OUTDIR/arm_state.txt"
UPLOAD_STATE="$OUTDIR/upload_state.txt"
CSV_OUT="$OUTDIR/jtagtunnel_ila.csv"
STIM_LOG="$OUTDIR/stimulus.log"

/root/.local/bin/vivado -mode batch -source "$SCRIPT_DIR/arm_jtagtunnel_ila_zcu104.tcl" -tclargs \
  -bitstream_path "$BITFILE" \
  -probes_path "$LTXFILE" \
  -out_state "$ARM_STATE" >"$OUTDIR/arm_vivado.log" 2>&1

"$SCRIPT_DIR/xsdb_send_bscan_raw.sh" 0x926 "$DR_BITS" "$DR_HEX" "$JTAG_HZ" >"$STIM_LOG" 2>&1 || true

/root/.local/bin/vivado -mode batch -source "$SCRIPT_DIR/upload_jtagtunnel_ila_zcu104.tcl" -tclargs \
  -probes_path "$LTXFILE" \
  -out_csv "$CSV_OUT" \
  -out_state "$UPLOAD_STATE" >"$OUTDIR/upload_vivado.log" 2>&1

{
  echo "OUTDIR=$OUTDIR"
  echo "LABEL=$LABEL"
  echo "DR_BITS=$DR_BITS"
  echo "DR_HEX=$DR_HEX"
  echo "JTAG_HZ=$JTAG_HZ"
  echo "ARM_STATE=$ARM_STATE"
  echo "STIM_LOG=$STIM_LOG"
  echo "UPLOAD_STATE=$UPLOAD_STATE"
  echo "CSV_OUT=$CSV_OUT"
} >"$OUTDIR/summary.txt"

cat "$OUTDIR/summary.txt"

