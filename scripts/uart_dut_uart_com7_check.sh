#!/usr/bin/env bash
set -euo pipefail

DUR=${1:-25}
BAUD=${2:-115200}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd /root/chipyard/fpga

TS=$(date +%Y%m%d_%H%M%S)
OUTDIR="logs/uart_dut_uart_com7_${TS}"
mkdir -p "$OUTDIR"
PORT=COM7

PWSH_SCRIPT="/tmp/uart_dut_${TS}_${PORT}.ps1"
cat > "$PWSH_SCRIPT" <<'PS1'
param(
  [string]$PortName,
  [string]$OutDir,
  [int]$DurationSec,
  [int]$BaudRate
)
$logPath = Join-Path $OutDir ($PortName + ".log")
$port = New-Object System.IO.Ports.SerialPort $PortName,$BaudRate,'None',8,'one'
$port.ReadTimeout = 200
$port.DtrEnable = $true
$port.RtsEnable = $true
$sw = New-Object System.IO.StreamWriter($logPath)
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
WIN_OUTDIR=$(wslpath -w "/root/chipyard/fpga/$OUTDIR")
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$WIN_SCRIPT" -PortName "$PORT" -OutDir "$WIN_OUTDIR" -DurationSec "$DUR" -BaudRate "$BAUD" >"/tmp/uart_dut_${TS}_${PORT}.out" 2>&1 &
CAP_PID=$!

sleep 2
bash "$SCRIPT_DIR/xsdb_uart_inject_test.sh" > "$OUTDIR/inject.log" 2>&1 || true

wait "$CAP_PID" || true
rm -f "$PWSH_SCRIPT"

grep -a -n 'UART_TEST_ZCU104_115200' "$OUTDIR/${PORT}.log" > "$OUTDIR/${PORT}.keywords.log" || true

{
  echo "OUTDIR=$OUTDIR"
  echo "PORT=$PORT"
  echo "OPEN_LINE=$(head -n 1 "$OUTDIR/${PORT}.log" 2>/dev/null || true)"
  echo "KEY_COUNT=$(wc -l < "$OUTDIR/${PORT}.keywords.log")"
  sed -n '1,20p' "$OUTDIR/${PORT}.keywords.log"
} | tee "$OUTDIR/summary.txt"
