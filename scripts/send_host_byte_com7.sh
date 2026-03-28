#!/usr/bin/env bash
set -euo pipefail

BYTE_HEX=${1:-5A}
PORT=${2:-COM7}

TS=$(date +%Y%m%d_%H%M%S)
LOG="/root/chipyard/fpga/logs/send_host_byte_${PORT}_${TS}.log"
PWSH="/tmp/send_host_${PORT}_${TS}.ps1"

cat > "$PWSH" <<'PS1'
param([string]$PortName,[string]$ByteHex)
$port = New-Object System.IO.Ports.SerialPort $PortName,115200,'None',8,'one'
$port.DtrEnable = $true
$port.RtsEnable = $true
try {
  $port.Open()
  Start-Sleep -Milliseconds 200
  $b = [Convert]::ToByte($ByteHex, 16)
  $bytes = [byte[]]($b)
  $port.Write($bytes, 0, $bytes.Length)
  Start-Sleep -Milliseconds 200
  Write-Output ("SEND_OK byte=0x" + $ByteHex)
} catch {
  Write-Output ("SEND_FAIL: " + $_.Exception.Message)
} finally {
  if ($port.IsOpen) { $port.Close() }
}
PS1

WIN_PWSH=$(wslpath -w "$PWSH")
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$WIN_PWSH" -PortName "$PORT" -ByteHex "$BYTE_HEX" | tee "$LOG"
rm -f "$PWSH"
echo "LOG=$LOG"
