#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
TOOLWRAP_DIR="$SCRIPT_DIR/toolwrap"
TS=$(date +%Y%m%d_%H%M%S)
LOG="$FPGA_DIR/logs/zcu104_linuxbringup_make_bitstream_${TS}.log"
CONFIG=${1:-RocketZCU104LinuxBringupConfig}
FIRTOOL_DEFAULT="/root/chipyard/.oclaw-env/bin/firtool"

cd "$FPGA_DIR"
echo "SUB_PROJECT=zcu104" | tee "$LOG"
echo "CONFIG=$CONFIG" | tee -a "$LOG"
echo "LOG=$LOG" | tee -a "$LOG"
if [[ -z "${FIRTOOL_BIN:-}" && -x "$FIRTOOL_DEFAULT" ]]; then
  export FIRTOOL_BIN="$FIRTOOL_DEFAULT"
fi
if [[ -d "$TOOLWRAP_DIR" ]]; then
  export PATH="$TOOLWRAP_DIR:$PATH"
fi
echo "FIRTOOL_BIN=${FIRTOOL_BIN:-unset}" | tee -a "$LOG"
echo "PATH_HEAD=${PATH%%:*}" | tee -a "$LOG"

set -o pipefail
make "SUB_PROJECT=zcu104" "CONFIG=$CONFIG" bitstream 2>&1 | tee -a "$LOG"
