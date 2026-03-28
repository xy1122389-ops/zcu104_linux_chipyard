#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

ILA_DIR="${1:-$FPGA_DIR/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupDebugConfig/debug_obj/jtagtunnel_ila_20260326_213703}"
JTAG_HZ="${2:-10000}"
STAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="$FPGA_DIR/logs/progbuf_xori_x0_probe_matrix_$STAMP"
mkdir -p "$OUTDIR"

encode_xori_x0() {
  python3 - "$1" <<'PY'
import sys
imm = int(sys.argv[1], 0)
imm12 = imm & 0xfff
# xori rd=x0, rs1=x0, funct3=100, opcode=0x13
insn = (imm12 << 20) | (0 << 15) | (4 << 12) | (0 << 7) | 0x13
print(hex(insn))
PY
}

run_one() {
  local imm="$1"
  local label="xori_x0_${imm}"
  local word
  word=$(encode_xori_x0 "$imm")
  local log="$OUTDIR/${label}.run.log"
  "$SCRIPT_DIR/capture_jtagtunnel_progbuf_single_with_recover.sh" \
    "$ILA_DIR" "$label" "$word" "$JTAG_HZ" >"$log" 2>&1

  local capture_dir
  capture_dir=$(grep -oP '^OUTDIR=\K.*' "$log" | tail -n 1 || true)
  local mode
  mode=$(grep -oP '^MODE=\K.*' "$log" | tail -n 1 || true)
  if [[ -z "$capture_dir" || ! -f "$capture_dir/jtagtunnel_ila.csv" ]]; then
    echo "CASE=$label WORD=$word MODE=${mode:-unknown} STATUS=FAILED" | tee -a "$OUTDIR/summary.txt"
    return 1
  fi
  echo "$label $capture_dir/jtagtunnel_ila.csv" >>"$OUTDIR/csv_index.txt"
  {
    echo "CASE=$label"
    echo "WORD=$word"
    echo "MODE=$mode"
    if [[ -f "$capture_dir/state.txt" ]]; then
      cat "$capture_dir/state.txt"
    fi
    echo "CSV=$capture_dir/jtagtunnel_ila.csv"
    echo
  } >>"$OUTDIR/captures.txt"
}

: >"$OUTDIR/summary.txt"
: >"$OUTDIR/captures.txt"
: >"$OUTDIR/csv_index.txt"

for imm in 20 22 23 32 63; do
  run_one "$imm"
done

{
  echo "OUTDIR=$OUTDIR"
  echo "ILA_DIR=$ILA_DIR"
  echo
  cat "$OUTDIR/csv_index.txt"
} >"$OUTDIR/index.txt"

cat "$OUTDIR/index.txt"
