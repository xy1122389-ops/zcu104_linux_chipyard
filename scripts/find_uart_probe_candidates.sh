#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
IN_DCP="${1:-$FPGA_DIR/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/obj/post_synth.dcp}"
TS=$(date +%Y%m%d_%H%M%S)
OUT="$FPGA_DIR/logs/find_uart_probe_candidates_$TS.log"

/root/.local/bin/vivado -mode batch -source "$SCRIPT_DIR/find_uart_probe_candidates.tcl" -tclargs "$IN_DCP" "$OUT" >/tmp/find_uart_probe_candidates_$TS.stdout 2>&1

cat /tmp/find_uart_probe_candidates_$TS.stdout
echo "LOG=$OUT"
