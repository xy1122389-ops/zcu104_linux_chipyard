#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
IN_DCP_DEFAULT="$FPGA_DIR/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/obj/post_synth.dcp"
IN_DCP="${1:-$IN_DCP_DEFAULT}"
STAMP=$(date +%Y%m%d_%H%M%S)
OUT_DIR="$FPGA_DIR/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/debug_obj/uart_ila_$STAMP"

mkdir -p "$OUT_DIR"

exec /root/.local/bin/vivado -mode batch -source "$SCRIPT_DIR/insert_ila_uart_zcu104.tcl" -tclargs "$IN_DCP" "$OUT_DIR"
