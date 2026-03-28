#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FW=${1:-/root/chipyard/fpga/src/main/resources/zcu104/sdboot/build/sdboot.bin}
TS=$(date +%Y%m%d_%H%M%S)
LOG="/root/chipyard/fpga/logs/baremetal_gpio_probe_${TS}.log"

{
  echo "FW=$FW"
  echo "==== psu_init + bitstream ===="
  bash "$SCRIPT_DIR/run_ps_ddr_init_linux.sh"
  echo
  echo "==== load baremetal bin ===="
  bash "$SCRIPT_DIR/load_linux_fw_payload.sh" "$FW"
  echo
  echo "==== pulse tile reset and kick ===="
  bash "$SCRIPT_DIR/pulse_tile_reset_and_kick.sh"
  echo
  echo "==== gpio toggle probe ===="
  bash "$SCRIPT_DIR/xsdb_gpio_toggle_probe.sh"
} | tee "$LOG"

echo "LOG=$LOG"
