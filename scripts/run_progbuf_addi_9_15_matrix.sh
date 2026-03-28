#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

ILA_DIR="${1:-$FPGA_DIR/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupDebugConfig/debug_obj/jtagtunnel_ila_20260326_213703}"
JTAG_HZ="${2:-10000}"
STAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="$FPGA_DIR/logs/progbuf_addi_9_15_matrix_$STAMP"
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
  local label="$1"
  local word="$2"
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

for imm in 9 10 11 12 13 14 15; do
  label="addi_x0_${imm}"
  word=$(encode_addi_x0 "$imm")
  run_one "$label" "$word"
done

BASE0="/root/chipyard/fpga/logs/jtagtunnel_ila_inline_addi_x0_0_20260327_092625/jtagtunnel_ila.csv"
BASE1="/root/chipyard/fpga/logs/jtagtunnel_ila_inline_addi_x0_1_20260327_092813/jtagtunnel_ila.csv"
BASE2="/root/chipyard/fpga/logs/jtagtunnel_ila_inline_addi_x0_2_20260327_093002/jtagtunnel_ila.csv"
BASE4="/root/chipyard/fpga/logs/jtagtunnel_ila_inline_addi_x0_4_20260327_093354/jtagtunnel_ila.csv"

{
  echo "OUTDIR=$OUTDIR"
  echo "ILA_DIR=$ILA_DIR"
  echo
} >"$OUTDIR/compare.txt"

while read -r label csv; do
  echo "### $label vs addi0" >>"$OUTDIR/compare.txt"
  python3 "$SCRIPT_DIR/compare_jtagtunnel_event_values.py" "$BASE0" "$csv" >>"$OUTDIR/compare.txt"
  echo >>"$OUTDIR/compare.txt"
  echo "### $label vs addi1" >>"$OUTDIR/compare.txt"
  python3 "$SCRIPT_DIR/compare_jtagtunnel_event_values.py" "$BASE1" "$csv" >>"$OUTDIR/compare.txt"
  echo >>"$OUTDIR/compare.txt"
  echo "### $label vs addi2" >>"$OUTDIR/compare.txt"
  python3 "$SCRIPT_DIR/compare_jtagtunnel_event_values.py" "$BASE2" "$csv" >>"$OUTDIR/compare.txt"
  echo >>"$OUTDIR/compare.txt"
  echo "### $label vs addi4" >>"$OUTDIR/compare.txt"
  python3 "$SCRIPT_DIR/compare_jtagtunnel_event_values.py" "$BASE4" "$csv" >>"$OUTDIR/compare.txt"
  echo >>"$OUTDIR/compare.txt"
done <"$OUTDIR/csv_index.txt"

cat "$OUTDIR/compare.txt"
