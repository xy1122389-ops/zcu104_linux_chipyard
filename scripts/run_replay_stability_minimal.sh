#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
ILA_DIR="${1:-$FPGA_DIR/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupDebugConfig/debug_obj/jtagtunnel_ila_20260326_213703}"
STAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="$FPGA_DIR/logs/replay_stability_minimal_$STAMP"
mkdir -p "$OUTDIR"
run_one() {
  local label="$1"
  local word="$2"
  local log="$OUTDIR/${label}.run.log"
  "$SCRIPT_DIR/capture_jtagtunnel_progbuf_single_with_recover.sh" "$ILA_DIR" "$label" "$word" 10000 >"$log" 2>&1 || true
  local outdir mode
  outdir=$(grep -oP '^OUTDIR=\K.*' "$log" | tail -n1 || true)
  mode=$(grep -oP '^MODE=\K.*' "$log" | tail -n1 || true)
  echo "LABEL=$label MODE=${mode:-unknown} OUTDIR=${outdir:-missing}" >> "$OUTDIR/summary.txt"
  if [[ -n "$outdir" && -f "$outdir/jtagtunnel_ila.csv" ]]; then
    echo "$label $outdir/jtagtunnel_ila.csv" >> "$OUTDIR/csv_index.txt"
  fi
}
: > "$OUTDIR/summary.txt"
: > "$OUTDIR/csv_index.txt"
for i in 1 2 3; do
  run_one "ebreak_postexec1_stable_$i" 0x00100073
  sleep 2
done
for i in 1 2 3; do
  run_one "addi_x0_20_stable_$i" 0x01400013
  sleep 2
done
if [[ -s "$OUTDIR/csv_index.txt" ]]; then
  python3 "$SCRIPT_DIR/classify_jtagtunnel_event_classes.py" $(awk '{print $2}' "$OUTDIR/csv_index.txt") > "$OUTDIR/classes.txt"
fi
printf 'OUTDIR=%s\n' "$OUTDIR"
find "$OUTDIR" -maxdepth 1 -type f -printf '%f %s\n' | sort
