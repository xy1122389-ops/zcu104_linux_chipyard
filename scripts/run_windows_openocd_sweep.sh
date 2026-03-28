#!/usr/bin/env bash
set -euo pipefail

OPENOCD_EXE='/mnt/c/Users/24242/AppData/Local/Microsoft/WinGet/Packages/xpack-dev-tools.openocd-xpack_Microsoft.Winget.Source_8wekyb3d8bbwe/xpack-openocd-0.12.0-7/bin/openocd.exe'
SCRIPTS_DIR='/mnt/c/Users/24242/AppData/Local/Microsoft/WinGet/Packages/xpack-dev-tools.openocd-xpack_Microsoft.Winget.Source_8wekyb3d8bbwe/xpack-openocd-0.12.0-7/openocd/scripts'
TASKKILL_EXE='/mnt/c/Windows/System32/taskkill.exe'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TS=$(date +%Y%m%d_%H%M%S)
OUTDIR="$SCRIPT_DIR/../logs/windows_openocd_sweep_${TS}"
mkdir -p "$OUTDIR"

"$TASKKILL_EXE" /F /IM hw_server.exe > "$OUTDIR/taskkill_hw_server.log" 2>&1 || true

configs=(
  "smt2_nc:$SCRIPT_DIR/openocd_zcu104_native_try.cfg"
  "hs2:$SCRIPT_DIR/openocd_zcu104_win_hs2.cfg"
  "hs3:$SCRIPT_DIR/openocd_zcu104_win_hs3.cfg"
  "custom:$SCRIPT_DIR/openocd_zcu104_win_custom.cfg"
  "custom_serial:$SCRIPT_DIR/openocd_zcu104_win_custom_serial.cfg"
)

for entry in "${configs[@]}"; do
  label=${entry%%:*}
  cfg=${entry#*:}
  log="$OUTDIR/${label}.log"
  timeout 20s "$OPENOCD_EXE" -s "$SCRIPTS_DIR" -f "$cfg" > "$log" 2>&1 || true
done

echo "OUTDIR:$OUTDIR"
for entry in "${configs[@]}"; do
  label=${entry%%:*}
  log="$OUTDIR/${label}.log"
  echo "==== $label ===="
  rg -n "Error:|Info :|Warn :|Hardware thread awareness|Listening on port|unable to open ftdi|tap/device found|Examination failed|JTAG scan chain|targets" "$log" || sed -n '1,80p' "$log"
done
