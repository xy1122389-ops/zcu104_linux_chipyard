#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
BITFILE_DEFAULT="$FPGA_DIR/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupDebugConfig/obj/ZCU104FPGATestHarness.bit"
BITFILE="${1:-$BITFILE_DEFAULT}"
STAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="$FPGA_DIR/logs/debug_bscan_minimal_regression_$STAMP"
mkdir -p "$OUTDIR"

{
  echo "BITFILE=$BITFILE"
  echo "START=$(date --iso-8601=seconds)"
} >"$OUTDIR/summary.txt"

echo "[1/3] PLD load" | tee -a "$OUTDIR/summary.txt"
PLD_OUT="$OUTDIR/pld_load.log"
scripts/openocd_pld_load_after_init.sh "$BITFILE" >"$PLD_OUT" 2>&1 || true
echo "PLD_LOG=$PLD_OUT" | tee -a "$OUTDIR/summary.txt"

echo "[2/3] minimal DMI validation" | tee -a "$OUTDIR/summary.txt"
DMI_OUT="$OUTDIR/manual_dmi_width_validation.log"
MODE=0 SEL_WIDTH=5 SEL_PAYLOAD=0x10 scripts/manual_dmi_width_validation.sh >"$DMI_OUT" 2>&1 || true
echo "DMI_LOG=$DMI_OUT" | tee -a "$OUTDIR/summary.txt"

echo "[3/3] single-field raw packet probe" | tee -a "$OUTDIR/summary.txt"
RAW_OUT="$OUTDIR/single_field_raw_packet_probe.log"
scripts/single_field_raw_packet_probe.sh >"$RAW_OUT" 2>&1 || true
echo "RAW_LOG=$RAW_OUT" | tee -a "$OUTDIR/summary.txt"

python3 - <<'PY' "$DMI_OUT" "$RAW_OUT" >>"$OUTDIR/summary.txt"
import re, sys
for label, path in [('DMI', sys.argv[1]), ('RAW', sys.argv[2])]:
    text = open(path, errors='ignore').read()
    print(f'== {label} ==')
    for pat in [
        r'Unsupported DTM version',
        r'OUTDIR=.*',
        r'READ 0x10',
        r'READ 0x11',
        r'READ 0x12',
        r'READ 0x16',
        r'mode0_w5_p10.*',
        r'mode0_w8_p10.*',
        r'mode1_w5_p10.*',
        r'mode1_w8_p10.*',
    ]:
        m = re.search(pat, text)
        if m:
            print(m.group(0))
PY

cat "$OUTDIR/summary.txt"
