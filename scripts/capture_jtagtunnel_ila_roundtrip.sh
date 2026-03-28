#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
STAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="$FPGA_DIR/logs/jtagtunnel_ila_capture_$STAMP"
mkdir -p "$OUTDIR"

ILA_DIR_DEFAULT="$FPGA_DIR/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupDebugConfig/debug_obj/jtagtunnel_ila_20260324_202832"
ILA_DIR="${1:-$ILA_DIR_DEFAULT}"
BITFILE="$ILA_DIR/ZCU104FPGATestHarness_jtagtunnel_ila.bit"
LTXFILE="$ILA_DIR/jtagtunnel_ila.ltx"

ARM_STATE="$OUTDIR/arm_state.txt"
UPLOAD_STATE="$OUTDIR/upload_state.txt"
CSV_OUT="$OUTDIR/jtagtunnel_ila.csv"
STIM_LOG="$OUTDIR/stimulus.log"

if [[ ! -f "$BITFILE" || ! -f "$LTXFILE" ]]; then
  echo "missing ILA bit/ltx in $ILA_DIR" >&2
  exit 2
fi

/root/.local/bin/vivado -mode batch -source "$SCRIPT_DIR/arm_jtagtunnel_ila_zcu104.tcl" -tclargs \
  -bitstream_path "$BITFILE" \
  -probes_path "$LTXFILE" \
  -out_state "$ARM_STATE" >"$OUTDIR/arm_vivado.log" 2>&1

# Generate the smallest meaningful nested-tunnel traffic burst.
MODE=0 SEL_WIDTH=5 SEL_PAYLOAD=0x10 "$SCRIPT_DIR/manual_dmi_width_validation.sh" >"$STIM_LOG" 2>&1 || true

/root/.local/bin/vivado -mode batch -source "$SCRIPT_DIR/upload_jtagtunnel_ila_zcu104.tcl" -tclargs \
  -probes_path "$LTXFILE" \
  -out_csv "$CSV_OUT" \
  -out_state "$UPLOAD_STATE" >"$OUTDIR/upload_vivado.log" 2>&1

{
  echo "OUTDIR=$OUTDIR"
  echo "ARM_STATE=$ARM_STATE"
  echo "STIM_LOG=$STIM_LOG"
  echo "UPLOAD_STATE=$UPLOAD_STATE"
  echo "CSV_OUT=$CSV_OUT"
} >"$OUTDIR/summary.txt"

cat "$OUTDIR/summary.txt"
