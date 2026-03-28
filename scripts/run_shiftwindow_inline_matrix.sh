#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <ila_dir> <tag>" >&2
  exit 2
fi

ILA_DIR="$1"
TAG="$2"
OUTDIR="$FPGA_DIR/logs/shiftwindow_inline_matrix_${TAG}_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"

run_one() {
  local label="$1"
  local bits="$2"
  local hex="$3"
  local log="$OUTDIR/${label}.log"
  "$SCRIPT_DIR/capture_jtagtunnel_ila_inline_stim.sh" "$ILA_DIR" "$label" "$bits" "$hex" 10000 >"$log" 2>&1
  local capdir
  capdir=$(grep -oP '^OUTDIR=\K.*' "$log" | tail -n 1 || true)
  if [[ -z "$capdir" ]]; then
    echo "LABEL=$label OUTDIR_MISSING" | tee -a "$OUTDIR/summary.txt"
    return 1
  fi
  echo "LABEL=$label CAPDIR=$capdir" | tee -a "$OUTDIR/summary.txt"
}

: >"$OUTDIR/summary.txt"
echo "ILA_DIR=$ILA_DIR" | tee -a "$OUTDIR/summary.txt"

run_one allzeros 16 0x0000
run_one bit1     16 0x0002
run_one w5       16 0x100A
run_one w8       19 0x1010

ALLZEROS_DIR=$(grep -oP '^LABEL=allzeros CAPDIR=\K.*' "$OUTDIR/summary.txt" | tail -n 1)
BIT1_DIR=$(grep -oP '^LABEL=bit1 CAPDIR=\K.*' "$OUTDIR/summary.txt" | tail -n 1)
W5_DIR=$(grep -oP '^LABEL=w5 CAPDIR=\K.*' "$OUTDIR/summary.txt" | tail -n 1)
W8_DIR=$(grep -oP '^LABEL=w8 CAPDIR=\K.*' "$OUTDIR/summary.txt" | tail -n 1)

python3 "$SCRIPT_DIR/summarize_jtagtunnel_first_window.py" \
  "$ALLZEROS_DIR/jtagtunnel_ila.csv" \
  "$BIT1_DIR/jtagtunnel_ila.csv" \
  "$W5_DIR/jtagtunnel_ila.csv" \
  "$W8_DIR/jtagtunnel_ila.csv" >"$OUTDIR/first_window.txt"

python3 "$SCRIPT_DIR/compare_jtagtunnel_event_values.py" \
  "$ALLZEROS_DIR/jtagtunnel_ila.csv" \
  "$BIT1_DIR/jtagtunnel_ila.csv" \
  "$W5_DIR/jtagtunnel_ila.csv" \
  "$W8_DIR/jtagtunnel_ila.csv" >"$OUTDIR/compare.txt"

cat <<EOF
OUTDIR=$OUTDIR
ALLZEROS_DIR=$ALLZEROS_DIR
BIT1_DIR=$BIT1_DIR
W5_DIR=$W5_DIR
W8_DIR=$W8_DIR
FIRST_WINDOW=$OUTDIR/first_window.txt
COMPARE=$OUTDIR/compare.txt
EOF
