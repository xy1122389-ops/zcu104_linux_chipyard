#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
ILA_DIR="${1:?usage: $0 <ila_dir> [repeater_full|opcode2|addr3|addr4] [trigger_value]}"
TRIGGER_PROBE="${2:-repeater_full}"
TRIGGER_VALUE="${3:-1}"
TS=$(date +%Y%m%d_%H%M%S)
OUTDIR="$FPGA_DIR/logs/uart_pbus_ila_${TRIGGER_PROBE}_inject_$TS"
mkdir -p "$OUTDIR"

bash "$SCRIPT_DIR/capture_uart_pbus_ila.sh" "$ILA_DIR" "$TRIGGER_PROBE" "$OUTDIR" "$TRIGGER_VALUE" >"$OUTDIR/capture.log" 2>&1 &
CAP_PID=$!
sleep 3
bash "$SCRIPT_DIR/xsdb_uart_inject_test.sh" > "$OUTDIR/inject.log" 2>&1 || true
wait "$CAP_PID" || true

{
  echo "OUTDIR=$OUTDIR"
  echo "ILA_DIR=$ILA_DIR"
  echo "TRIGGER_PROBE=$TRIGGER_PROBE"
  echo "TRIGGER_VALUE=$TRIGGER_VALUE"
  echo "CAPTURE_LOG=$OUTDIR/capture.log"
  echo "INJECT_LOG=$OUTDIR/inject.log"
  echo "CSV_OUT=$OUTDIR/uart_pbus_ila.csv"
} | tee "$OUTDIR/summary.txt"
