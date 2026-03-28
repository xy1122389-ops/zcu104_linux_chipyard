#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <ltx_path> <out_csv> <out_state>" >&2
  exit 2
fi

LTX="$1"
OUTCSV="$2"
OUTSTATE="$3"

cat > /tmp/restart_hw_server_probe.ps1 <<'PS'
$p = Get-CimInstance Win32_Process | Where-Object Name -eq 'hw_server.exe'
if ($p) {
  $p | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
}
Start-Process -FilePath 'E:\PRO_APP\xilinx\Vivado\2021.2\bin\unwrapped\win64.o\hw_server.exe' -ArgumentList '-D','-I20','-s','TCP:127.0.0.1:3121'
for ($i = 0; $i -lt 20; $i++) {
  Start-Sleep -Milliseconds 500
  $ok = Test-NetConnection -ComputerName 127.0.0.1 -Port 3121 -InformationLevel Quiet
  if ($ok) { exit 0 }
}
exit 7
PS

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File /tmp/restart_hw_server_probe.ps1

/root/.local/bin/vivado -mode batch \
  -source "$SCRIPT_DIR/upload_existing_ila_data_zcu104.tcl" \
  -tclargs \
  -probes_path "$LTX" \
  -out_csv "$OUTCSV" \
  -out_state "$OUTSTATE"
