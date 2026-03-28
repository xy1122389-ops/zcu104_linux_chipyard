#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

ILA_DIR_DEFAULT="$FPGA_DIR/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupDebugConfig/debug_obj/jtagtunnel_ila_20260324_190128"
ILA_DIR="${1:-$ILA_DIR_DEFAULT}"
BITFILE="$ILA_DIR/ZCU104FPGATestHarness_jtagtunnel_ila.bit"
LTXFILE="$ILA_DIR/jtagtunnel_ila.ltx"

if [[ ! -f "$BITFILE" ]]; then
  echo "missing bitfile: $BITFILE" >&2
  exit 2
fi
if [[ ! -f "$LTXFILE" ]]; then
  echo "missing ltx: $LTXFILE" >&2
  exit 3
fi

exec /root/.local/bin/vivado -mode batch -source "$SCRIPT_DIR/program_jtagtunnel_ila_zcu104.tcl" -tclargs \
  -bitstream_path "$BITFILE" \
  -probes_path "$LTXFILE" \
  -target_index 0
