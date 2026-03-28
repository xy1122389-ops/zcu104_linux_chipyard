#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
ILA_DIR="${1:-$FPGA_DIR/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/debug_obj/uart_ila_20260326_191447}"
TS=$(date +%Y%m%d_%H%M%S)
OUTDIR="$FPGA_DIR/logs/uart_ila_tx_inject_$TS"
mkdir -p "$OUTDIR"

bash "$SCRIPT_DIR/capture_uart_ila.sh" "$ILA_DIR" tx "$OUTDIR" >"$OUTDIR/capture.log" 2>&1 &
CAP_PID=$!
sleep 3
bash "$SCRIPT_DIR/xsdb_uart_inject_test.sh" > "$OUTDIR/inject.log" 2>&1 || true
wait "$CAP_PID" || true

{
  echo "OUTDIR=$OUTDIR"
  echo "ILA_DIR=$ILA_DIR"
  echo "CAPTURE_LOG=$OUTDIR/capture.log"
  echo "INJECT_LOG=$OUTDIR/inject.log"
  echo "CSV_OUT=$OUTDIR/uart_ila.csv"
} | tee "$OUTDIR/summary.txt"
