#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <label_base> <progbuf0_word_hex> <repeats> [jtag_hz]" >&2
  exit 2
fi

LABEL_BASE="$1"
PROGBUF0_WORD="$2"
REPEATS="$3"
JTAG_HZ="${4:-10000}"
ILA_DIR="${ILA_DIR:-$FPGA_DIR/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupDebugConfig/debug_obj/jtagtunnel_ila_20260326_213703}"

STAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="$FPGA_DIR/logs/progbuf_replay_stability_${LABEL_BASE}_${STAMP}"
mkdir -p "$OUTDIR"

: >"$OUTDIR/csv_index.txt"

for ((i=1; i<=REPEATS; i++)); do
  label="${LABEL_BASE}_r${i}"
  log="$OUTDIR/${label}.run.log"
  "$SCRIPT_DIR/capture_jtagtunnel_progbuf_single_with_recover.sh" \
    "$ILA_DIR" "$label" "$PROGBUF0_WORD" "$JTAG_HZ" >"$log" 2>&1 || true
  outdir=$(grep -oP '^OUTDIR=\K.*' "$log" | tail -n 1 || true)
  mode=$(grep -oP '^MODE=\K.*' "$log" | tail -n 1 || true)
  {
    echo "LABEL=$label"
    echo "MODE=${mode:-unknown}"
    echo "OUTDIR=${outdir:-missing}"
    echo
  } >>"$OUTDIR/summary.txt"
  if [[ -n "$outdir" && -f "$outdir/jtagtunnel_ila.csv" ]]; then
    echo "$label $outdir/jtagtunnel_ila.csv" >>"$OUTDIR/csv_index.txt"
  fi
done

if [[ -s "$OUTDIR/csv_index.txt" ]]; then
  python3 "$SCRIPT_DIR/classify_jtagtunnel_event_classes.py" $(awk '{print $2}' "$OUTDIR/csv_index.txt") \
    >"$OUTDIR/classes.txt"
fi

echo "OUTDIR=$OUTDIR"
find "$OUTDIR" -maxdepth 1 -type f -printf '%f %s\n' | sort
