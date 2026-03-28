#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
DEBUG_DIR_DEFAULT="$FPGA_DIR/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupDebugConfig"
DEBUG_DIR="${1:-$DEBUG_DIR_DEFAULT}"
POST_SYNTH_DCP="$DEBUG_DIR/obj/post_synth.dcp"

if [[ ! -f "$POST_SYNTH_DCP" ]]; then
  echo "missing post_synth.dcp: $POST_SYNTH_DCP" >&2
  exit 2
fi

STAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="$FPGA_DIR/logs/shiftwindow_ila_validation_$STAMP"
mkdir -p "$OUTDIR"

BUILD_LOG="$OUTDIR/build_ila.log"
PROGRAM_LOG="$OUTDIR/program_ila.log"
IDLE_LOG="$OUTDIR/idle_status.vivado.log"
IDLE_TXT="$OUTDIR/idle_status.txt"
NOSTIM_COMPARE="$OUTDIR/no_stim_compare.log"
W5_LOG="$OUTDIR/w5_capture.log"
W8_LOG="$OUTDIR/w8_capture.log"

echo "[1/5] Build ILA from $POST_SYNTH_DCP"
"$SCRIPT_DIR/build_jtagtunnel_ila_bit.sh" "$POST_SYNTH_DCP" >"$BUILD_LOG" 2>&1
ILA_DIR=$(grep -oP '^OUT_DCP=.*debug_obj/jtagtunnel_ila_\K[0-9_]+' "$BUILD_LOG" | tail -n 1 || true)
if [[ -z "$ILA_DIR" ]]; then
  echo "failed to parse ILA dir from $BUILD_LOG" >&2
  exit 3
fi
ILA_PATH="$DEBUG_DIR/debug_obj/jtagtunnel_ila_$ILA_DIR"
LTX="$ILA_PATH/jtagtunnel_ila.ltx"

echo "[2/5] Program ILA bit"
"$SCRIPT_DIR/program_jtagtunnel_ila_zcu104.sh" "$ILA_PATH" >"$PROGRAM_LOG" 2>&1

echo "[3/5] Arm idle-status check"
/root/.local/bin/vivado -mode batch -source "$SCRIPT_DIR/check_jtagtunnel_ila_idle_status.tcl" -tclargs \
  -probes_path "$LTX" -out_log "$IDLE_TXT" -seconds 3 >"$IDLE_LOG" 2>&1

echo "[4/5] Upload no-stim captured data"
NOSTIM_DIR="$FPGA_DIR/logs/jtagtunnel_ila_no_stim_upload_$STAMP"
mkdir -p "$NOSTIM_DIR"
/root/.local/bin/vivado -mode batch -source "$SCRIPT_DIR/upload_jtagtunnel_ila_zcu104.tcl" -tclargs \
  -probes_path "$LTX" \
  -out_csv "$NOSTIM_DIR/jtagtunnel_ila.csv" \
  -out_state "$NOSTIM_DIR/upload_state.txt" >"$NOSTIM_DIR/upload_vivado.log" 2>&1

echo "[5/5] Capture w5/w8 with stimulus"
"$SCRIPT_DIR/capture_jtagtunnel_ila_xsdb_custom.sh" "$ILA_PATH" mode0_w5 16 0x100A 10000 >"$W5_LOG" 2>&1 || true
"$SCRIPT_DIR/capture_jtagtunnel_ila_xsdb_custom.sh" "$ILA_PATH" mode0_w8 19 0x1010 10000 >"$W8_LOG" 2>&1 || true

W5_DIR=$(grep -oP '^OUTDIR=\K.*' "$W5_LOG" | tail -n 1 || true)
W8_DIR=$(grep -oP '^OUTDIR=\K.*' "$W8_LOG" | tail -n 1 || true)
if [[ -n "$W5_DIR" && -n "$W8_DIR" ]]; then
  python3 "$SCRIPT_DIR/compare_jtagtunnel_event_values.py" \
    "$NOSTIM_DIR/jtagtunnel_ila.csv" \
    "$W5_DIR/jtagtunnel_ila.csv" \
    "$W8_DIR/jtagtunnel_ila.csv" >"$NOSTIM_COMPARE" || true
fi

cat <<EOF
OUTDIR=$OUTDIR
ILA_PATH=$ILA_PATH
BUILD_LOG=$BUILD_LOG
PROGRAM_LOG=$PROGRAM_LOG
IDLE_TXT=$IDLE_TXT
NOSTIM_DIR=$NOSTIM_DIR
W5_DIR=$W5_DIR
W8_DIR=$W8_DIR
NOSTIM_COMPARE=$NOSTIM_COMPARE
EOF
