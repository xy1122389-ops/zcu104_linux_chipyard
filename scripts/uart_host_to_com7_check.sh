#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TS=$(date +%Y%m%d_%H%M%S)
LOG="/root/chipyard/fpga/logs/uart_host_to_com7_check_${TS}.log"
PWSH="/tmp/send_com7_${TS}.ps1"

cat > "$PWSH" <<'PS1'
param([string]$PortName = 'COM7')
$port = New-Object System.IO.Ports.SerialPort $PortName,115200,'None',8,'one'
$port.DtrEnable = $true
$port.RtsEnable = $true
try {
  $port.Open()
  Start-Sleep -Milliseconds 200
  $bytes = [System.Text.Encoding]::ASCII.GetBytes("Z")
  $port.Write($bytes, 0, $bytes.Length)
  Start-Sleep -Milliseconds 200
  Write-Output "SEND_OK"
} catch {
  Write-Output ("SEND_FAIL: " + $_.Exception.Message)
} finally {
  if ($port.IsOpen) { $port.Close() }
}
PS1

WIN_PWSH=$(wslpath -w "$PWSH")

{
  echo "==== send host byte to COM7 ===="
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$WIN_PWSH"
  echo
  echo "==== probe DUT uart rx ===="
  bash "$SCRIPT_DIR/xsdb_uart_rx_probe.sh"
} | tee "$LOG"

rm -f "$PWSH"
echo "LOG=$LOG"
