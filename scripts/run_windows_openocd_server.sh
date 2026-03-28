#!/usr/bin/env bash
set -euo pipefail

OPENOCD_EXE='/mnt/c/Users/24242/AppData/Local/Microsoft/WinGet/Packages/xpack-dev-tools.openocd-xpack_Microsoft.Winget.Source_8wekyb3d8bbwe/xpack-openocd-0.12.0-7/bin/openocd.exe'
SCRIPTS_DIR='/mnt/c/Users/24242/AppData/Local/Microsoft/WinGet/Packages/xpack-dev-tools.openocd-xpack_Microsoft.Winget.Source_8wekyb3d8bbwe/xpack-openocd-0.12.0-7/openocd/scripts'
CFG='/root/chipyard/fpga/scripts/openocd_zcu104_win_custom_serial_1000_server.cfg'
LOG="/root/chipyard/fpga/logs/windows_openocd_server_$(date +%Y%m%d_%H%M%S).log"

"$OPENOCD_EXE" -s "$SCRIPTS_DIR" -f "$CFG" > "$LOG" 2>&1
