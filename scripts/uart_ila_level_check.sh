#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
ILA_DIR="${1:-$FPGA_DIR/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/debug_obj/uart_ila_20260326_191447}"
PROBE="${2:?usage: $0 <ila_dir> <tx|rx|enq> <0|1>}"
VALUE="${3:?usage: $0 <ila_dir> <tx|rx|enq> <0|1>}"
TS=$(date +%Y%m%d_%H%M%S)
OUTDIR="$FPGA_DIR/logs/uart_ila_${PROBE}_level_${VALUE}_$TS"
mkdir -p "$OUTDIR"

bash "$SCRIPT_DIR/capture_uart_ila.sh" "$ILA_DIR" "$PROBE" "$OUTDIR" "$VALUE" >"$OUTDIR/capture.log" 2>&1 || true

{
  echo "OUTDIR=$OUTDIR"
  echo "ILA_DIR=$ILA_DIR"
  echo "PROBE=$PROBE"
  echo "VALUE=$VALUE"
  echo "CAPTURE_LOG=$OUTDIR/capture.log"
  echo "ARM_STATE=$OUTDIR/arm_state.txt"
  echo "UPLOAD_STATE=$OUTDIR/upload_state.txt"
  echo "CSV_OUT=$OUTDIR/uart_ila.csv"
} | tee "$OUTDIR/summary.txt"
