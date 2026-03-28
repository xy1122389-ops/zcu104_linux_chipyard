#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
ILA_DIR="${1:-$FPGA_DIR/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupDebugConfig/debug_obj/jtagtunnel_ila_20260326_213703}"
JTAG_HZ="${2:-10000}"
STAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="$FPGA_DIR/logs/progbuf_addi_x1_probe_matrix_$STAMP"
mkdir -p "$OUTDIR"
encode_addi_x1() {
  python3 - "$1" <<'PY2'
import sys
imm=int(sys.argv[1],0)
imm12=imm & 0xfff
insn=(imm12<<20) | (1<<7) | 0x13
print(hex(insn))
PY2
}
run_one() {
  local imm="$1"
  local label="addi_x1_${imm}"
  local word
  word=$(encode_addi_x1 "$imm")
  local log="$OUTDIR/${label}.run.log"
  SKIP_PROGRAM=1 PROGBUF0_WORD="$word" timeout 420 "$SCRIPT_DIR/capture_jtagtunnel_ila_inline_progbuf_exec.sh"     "$ILA_DIR" "$label" "$JTAG_HZ" >"$log" 2>&1
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
for imm in 1 4 20 22 23 32 33 63; do
  run_one "$imm"
done
cat "$OUTDIR/csv_index.txt"
