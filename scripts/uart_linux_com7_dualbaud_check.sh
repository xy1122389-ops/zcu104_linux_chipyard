#!/usr/bin/env bash
set -euo pipefail

FW=${1:-/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.bin}
DUR=${2:-150}
KICK_MODE=${3:-clock}

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd /root/chipyard/fpga

TS=$(date +%Y%m%d_%H%M%S)
OUTDIR="logs/uart_linux_com7_dualbaud_${TS}"
mkdir -p "$OUTDIR"

BAUDS=(115200 921600)

for baud in "${BAUDS[@]}"; do
  RUN_LOG="$OUTDIR/run_${baud}.log"
  echo "START baud=$baud" | tee -a "$OUTDIR/summary.txt"
  bash "$SCRIPT_DIR/uart_linux_com7_check.sh" "$FW" "$DUR" "$baud" "$KICK_MODE" > "$RUN_LOG" 2>&1 || true
  echo "RUN_LOG_$baud=$RUN_LOG" | tee -a "$OUTDIR/summary.txt"

  RUN_SUBDIR=$(grep -a -m1 '^OUTDIR=' "$RUN_LOG" | cut -d= -f2- | tr -d '\r' || true)
  if [[ -n "$RUN_SUBDIR" && -f "$RUN_SUBDIR/summary.txt" ]]; then
    echo "INNER_SUMMARY_$baud=$RUN_SUBDIR/summary.txt" | tee -a "$OUTDIR/summary.txt"
    cat "$RUN_SUBDIR/summary.txt" >> "$OUTDIR/summary.txt"
  fi
done

echo "OUTDIR=$OUTDIR"
cat "$OUTDIR/summary.txt"
