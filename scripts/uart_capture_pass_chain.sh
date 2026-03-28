#!/usr/bin/env bash
set -euo pipefail

FW=${1:-/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.bin}
PORT=${2:-COM11}
DUR=${3:-90}

cd /root/chipyard/fpga
TS=$(date +%Y%m%d_%H%M%S)
UART_LOG="logs/uart_boot_${TS}.log"
CHAIN_LOG="logs/pass_chain_${TS}.log"
KEY_LOG="logs/uart_keywords_${TS}.log"
PWSH_SCRIPT="/tmp/uart_cap_${TS}.ps1"

cat > "$PWSH_SCRIPT" <<'PS1'
param(
  [string]$PortName,
  [string]$OutPath,
  [int]$DurationSec
)
$port = New-Object System.IO.Ports.SerialPort $PortName,115200,'None',8,'one'
$port.ReadTimeout = 200
$port.NewLine = "`n"
$sw = New-Object System.IO.StreamWriter($OutPath)
try {
  $port.Open()
  $sw.WriteLine('UART_OPEN_OK')
  $sw.Flush()
  $end=(Get-Date).AddSeconds($DurationSec)
  while((Get-Date) -lt $end){
    try {
      $line=$port.ReadLine()
      $sw.WriteLine($line)
      $sw.Flush()
    } catch {}
  }
} catch {
  $sw.WriteLine('UART_OPEN_FAIL: ' + $_.Exception.Message)
  $sw.Flush()
} finally {
  if($port.IsOpen){$port.Close()}
  $sw.Close()
}
PS1

WIN_SCRIPT=$(wslpath -w "$PWSH_SCRIPT")
WIN_UART_LOG=$(wslpath -w "/root/chipyard/fpga/$UART_LOG")

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$WIN_SCRIPT" -PortName "$PORT" -OutPath "$WIN_UART_LOG" -DurationSec "$DUR" >/tmp/uart_cap_${TS}.out 2>&1 &
CAP_PID=$!

sleep 2
scripts/runtime_signature_check.sh "$FW" > "$CHAIN_LOG" 2>&1 || true
CHAIN_RC=$?

wait "$CAP_PID" || true

grep -a -i -nE 'opensbi|u-boot|linux version|booting linux|starting kernel|login:' "$UART_LOG" > "$KEY_LOG" || true

OPEN_STATUS=$(head -n 1 "$UART_LOG" 2>/dev/null || true)

echo "UART_PORT:$PORT"
echo "UART_OPEN_LINE:${OPEN_STATUS}"
echo "UART_LOG:$UART_LOG"
echo "CHAIN_LOG:$CHAIN_LOG"
echo "KEY_LOG:$KEY_LOG"
echo "CHAIN_RC:$CHAIN_RC"
echo "KEY_COUNT:$(wc -l < "$KEY_LOG")"
sed -n '1,80p' "$KEY_LOG"
