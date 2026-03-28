#!/usr/bin/env bash
set -euo pipefail

FW=${1:-/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.bin}
PORT=${2:-COM11}
DUR=${3:-150}
BAUD=${4:-115200}
BOOTADDR_HEX=${5:-}

cd /root/chipyard/fpga
TS=$(date +%Y%m%d_%H%M%S)
UART_LOG="logs/uart_boot_payload_${TS}.log"
INIT_LOG="logs/ps_ddr_init_manual_${TS}.log"
PAYLOAD_LOG="logs/load_payload_manual_${TS}.log"
KEY_LOG="logs/uart_keywords_payload_${TS}.log"
PWSH_SCRIPT="/tmp/uart_cap_payload_${TS}.ps1"

cat > "$PWSH_SCRIPT" <<'PS1'
param([string]$PortName,[string]$OutPath,[int]$DurationSec,[int]$BaudRate)
$port = New-Object System.IO.Ports.SerialPort $PortName,$BaudRate,'None',8,'one'
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
      if ($port.BytesToRead -gt 0) {
        $chunk = $port.ReadExisting()
        if ($chunk.Length -gt 0) {
          $sw.Write($chunk)
          $sw.Flush()
        }
      }
      Start-Sleep -Milliseconds 20
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

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$WIN_SCRIPT" -PortName "$PORT" -OutPath "$WIN_UART_LOG" -DurationSec "$DUR" -BaudRate "$BAUD" >/tmp/uart_cap_payload_${TS}.out 2>&1 &
CAP_PID=$!

sleep 2
scripts/run_ps_ddr_init_linux.sh > "$INIT_LOG" 2>&1 || true
RC1=$?
scripts/load_linux_fw_payload.sh "$FW" ${BOOTADDR_HEX:+"$BOOTADDR_HEX"} > "$PAYLOAD_LOG" 2>&1 || true
RC2=$?

wait "$CAP_PID" || true

grep -a -i -nE 'opensbi|u-boot|linux version|booting linux|starting kernel|login:|sbi' "$UART_LOG" > "$KEY_LOG" || true

echo "UART_PORT:$PORT"
echo "UART_BAUD:$BAUD"
echo "BOOTADDR_HEX:${BOOTADDR_HEX:-0x80000000}"
echo "UART_OPEN_LINE:$(head -n 1 "$UART_LOG" 2>/dev/null || true)"
echo "UART_LOG:$UART_LOG"
echo "INIT_LOG:$INIT_LOG"
echo "PAYLOAD_LOG:$PAYLOAD_LOG"
echo "KEY_LOG:$KEY_LOG"
echo "RC1:$RC1"
echo "RC2:$RC2"
echo "KEY_COUNT:$(wc -l < "$KEY_LOG")"
sed -n '1,80p' "$KEY_LOG"
