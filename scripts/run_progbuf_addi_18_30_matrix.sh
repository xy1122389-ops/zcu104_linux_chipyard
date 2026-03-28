#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

ILA_DIR="${1:-$FPGA_DIR/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupDebugConfig/debug_obj/jtagtunnel_ila_20260326_213703}"
JTAG_HZ="${2:-10000}"
STAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="$FPGA_DIR/logs/progbuf_addi_18_30_matrix_$STAMP"
mkdir -p "$OUTDIR"

encode_addi_x0() {
  python3 - "$1" <<'PY'
import sys
imm = int(sys.argv[1], 0)
imm12 = imm & 0xfff
insn = (imm12 << 20) | 0x13
print(hex(insn))
PY
}

run_one() {
  local imm="$1"
  local label="addi_x0_${imm}"
  local word
  word=$(encode_addi_x0 "$imm")
  local log="$OUTDIR/${label}.run.log"
  PROGBUF0_WORD="$word" timeout 420 "$SCRIPT_DIR/capture_jtagtunnel_ila_inline_progbuf_exec.sh" \
    "$ILA_DIR" "$label" "$JTAG_HZ" >"$log" 2>&1
  local capture_dir
  capture_dir=$(grep -oP '^OUTDIR=\K.*' "$log" | tail -n 1 || true)
  if [[ -z "$capture_dir" || ! -f "$capture_dir/jtagtunnel_ila.csv" ]]; then
    echo "CASE=$label WORD=$word STATUS=FAILED" | tee -a "$OUTDIR/summary.txt"
    return 1
  fi
  echo "$label $capture_dir/jtagtunnel_ila.csv" >>"$OUTDIR/csv_index.txt"
  {
    echo "CASE=$label"
    echo "WORD=$word"
    cat "$capture_dir/stimulus.log"
    echo "CSV=$capture_dir/jtagtunnel_ila.csv"
    echo
  } >>"$OUTDIR/captures.txt"
}

: >"$OUTDIR/summary.txt"
: >"$OUTDIR/captures.txt"
: >"$OUTDIR/csv_index.txt"

for imm in 18 19 21 22 23 24 25 26 28 29 30; do
  run_one "$imm"
done

cat <<EOF >"$OUTDIR/refs.txt"
ADDI_1=/root/chipyard/fpga/logs/jtagtunnel_ila_inline_addi_x0_1_20260327_092813/jtagtunnel_ila.csv
ADDI_4=/root/chipyard/fpga/logs/jtagtunnel_ila_inline_addi_x0_4_20260327_093354/jtagtunnel_ila.csv
ADDI_15=/root/chipyard/fpga/logs/jtagtunnel_ila_inline_addi_x0_15_20260327_100857/jtagtunnel_ila.csv
ADDI_20=/root/chipyard/fpga/logs/jtagtunnel_ila_inline_addi_x0_20_outlierprobe_20260327_102844/jtagtunnel_ila.csv
EOF

{
  echo "OUTDIR=$OUTDIR"
  echo "ILA_DIR=$ILA_DIR"
  echo
} >"$OUTDIR/compare.txt"

BASE1="/root/chipyard/fpga/logs/jtagtunnel_ila_inline_addi_x0_1_20260327_092813/jtagtunnel_ila.csv"
BASE4="/root/chipyard/fpga/logs/jtagtunnel_ila_inline_addi_x0_4_20260327_093354/jtagtunnel_ila.csv"
BASE15="/root/chipyard/fpga/logs/jtagtunnel_ila_inline_addi_x0_15_20260327_100857/jtagtunnel_ila.csv"
BASE20="/root/chipyard/fpga/logs/jtagtunnel_ila_inline_addi_x0_20_outlierprobe_20260327_102844/jtagtunnel_ila.csv"

while read -r label csv; do
  for base_name in ADDI_1 ADDI_4 ADDI_15 ADDI_20; do
    case "$base_name" in
      ADDI_1) base="$BASE1" ;;
      ADDI_4) base="$BASE4" ;;
      ADDI_15) base="$BASE15" ;;
      ADDI_20) base="$BASE20" ;;
    esac
    echo "### $label vs $base_name" >>"$OUTDIR/compare.txt"
    python3 "$SCRIPT_DIR/compare_jtagtunnel_event_values.py" "$base" "$csv" >>"$OUTDIR/compare.txt"
    echo >>"$OUTDIR/compare.txt"
  done
done <"$OUTDIR/csv_index.txt"

cat "$OUTDIR/compare.txt"
