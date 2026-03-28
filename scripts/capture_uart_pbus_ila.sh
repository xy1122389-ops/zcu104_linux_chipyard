#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
ILA_DIR="${1:?usage: $0 <ila_dir> <repeater_full|opcode2|addr3|addr4> <outdir> [trigger_value]}"
TRIGGER_PROBE="${2:?usage: $0 <ila_dir> <repeater_full|opcode2|addr3|addr4> <outdir> [trigger_value]}"
OUTDIR="${3:?usage: $0 <ila_dir> <repeater_full|opcode2|addr3|addr4> <outdir> [trigger_value]}"
TRIGGER_VALUE="${4:-1}"

mkdir -p "$OUTDIR"
BITFILE="$ILA_DIR/ZCU104FPGATestHarness_uart_pbus_ila.bit"
LTXFILE="$ILA_DIR/uart_pbus_ila.ltx"
ARM_STATE="$OUTDIR/arm_state.txt"
CSV_OUT="$OUTDIR/uart_pbus_ila.csv"
UPLOAD_STATE="$OUTDIR/upload_state.txt"

/root/.local/bin/vivado -mode batch -source "$SCRIPT_DIR/arm_uart_pbus_ila_zcu104.tcl" -tclargs \
  -bitstream_path "$BITFILE" \
  -probes_path "$LTXFILE" \
  -trigger_probe "$TRIGGER_PROBE" \
  -trigger_value "$TRIGGER_VALUE" \
  -out_state "$ARM_STATE" >"$OUTDIR/arm_vivado.log" 2>&1

/root/.local/bin/vivado -mode batch -source "$SCRIPT_DIR/upload_jtagtunnel_ila_zcu104.tcl" -tclargs \
  -probes_path "$LTXFILE" \
  -out_csv "$CSV_OUT" \
  -out_state "$UPLOAD_STATE" >"$OUTDIR/upload_vivado.log" 2>&1

{
  echo "OUTDIR=$OUTDIR"
  echo "ILA_DIR=$ILA_DIR"
  echo "TRIGGER_PROBE=$TRIGGER_PROBE"
  echo "TRIGGER_VALUE=$TRIGGER_VALUE"
  echo "BITFILE=$BITFILE"
  echo "LTXFILE=$LTXFILE"
  echo "CSV_OUT=$CSV_OUT"
} >"$OUTDIR/summary.txt"

cat "$OUTDIR/summary.txt"
