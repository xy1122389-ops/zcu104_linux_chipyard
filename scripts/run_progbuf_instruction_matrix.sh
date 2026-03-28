#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

ILA_DIR="${1:-$FPGA_DIR/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupDebugConfig/debug_obj/jtagtunnel_ila_20260326_213703}"
JTAG_HZ="${2:-10000}"
STAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="$FPGA_DIR/logs/progbuf_instruction_matrix_$STAMP"
mkdir -p "$OUTDIR"

declare -a CASES=(
  "nop 0x00000013"
  "addi_x0_1 0x00100013"
  "addi_x0_2 0x00200013"
  "addi_x1_1 0x00100093"
  "ecall 0x00000073"
  "ebreak 0x00100073"
  "csrr_x0_dcsr 0x7b002073"
  "csrr_x1_dcsr 0x7b0020f3"
)

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
  {
    echo "CASE=$label"
    echo "WORD=$word"
    cat "$capture_dir/stimulus.log"
    echo "CSV=$capture_dir/jtagtunnel_ila.csv"
    echo
  } >>"$OUTDIR/captures.txt"
  echo "$label $capture_dir/jtagtunnel_ila.csv" >>"$OUTDIR/csv_index.txt"
}

: >"$OUTDIR/summary.txt"
: >"$OUTDIR/captures.txt"
: >"$OUTDIR/csv_index.txt"

for case_entry in "${CASES[@]}"; do
  read -r label word <<<"$case_entry"
  run_one "$label" "$word"
done

BASE_CSV=$(awk '$1=="nop"{print $2}' "$OUTDIR/csv_index.txt")
if [[ -z "$BASE_CSV" ]]; then
  echo "ERROR: nop base capture missing" >&2
  exit 1
fi

{
  echo "OUTDIR=$OUTDIR"
  echo "ILA_DIR=$ILA_DIR"
  echo "BASE=nop"
  echo
} >"$OUTDIR/compare.txt"

while read -r label csv; do
  [[ "$label" == "nop" ]] && continue
  echo "### $label" >>"$OUTDIR/compare.txt"
  python3 "$SCRIPT_DIR/compare_jtagtunnel_event_values.py" "$BASE_CSV" "$csv" >>"$OUTDIR/compare.txt"
  echo >>"$OUTDIR/compare.txt"
done <"$OUTDIR/csv_index.txt"

cat "$OUTDIR/compare.txt"
