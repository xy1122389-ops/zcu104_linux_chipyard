#!/usr/bin/env bash
set -euo pipefail

DUR=${1:-25}
BAUD=${2:-115200}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd /root/chipyard/fpga

TS=$(date +%Y%m%d_%H%M%S)
OUTDIR="logs/uart_inject_triplet_${TS}"
mkdir -p "$OUTDIR"
PORTS=(COM5 COM6 COM7)
CAP_SCRIPTS=()
CAP_PIDS=()

for port in "${PORTS[@]}"; do
  PWSH_SCRIPT="/tmp/uart_inject_${TS}_${port}.ps1"
  CAP_SCRIPTS+=("$PWSH_SCRIPT")
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
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$WIN_SCRIPT" -PortName "$port" -OutDir "$WIN_OUTDIR" -DurationSec "$DUR" -BaudRate "$BAUD" >/tmp/uart_inject_${TS}_${port}.out 2>&1 &
  CAP_PIDS+=("$!")
done

sleep 2
bash "$SCRIPT_DIR/xsdb_uart_inject_test.sh" > "$OUTDIR/inject.log" 2>&1 || true

for pid in "${CAP_PIDS[@]}"; do
  wait "$pid" || true
done
for ps1 in "${CAP_SCRIPTS[@]}"; do
  rm -f "$ps1"
done

for port in "${PORTS[@]}"; do
  grep -a -n 'UART_TEST_ZCU104_115200' "$OUTDIR/${port}.log" > "$OUTDIR/${port}.keywords.log" || true
done

{
  echo "OUTDIR=$OUTDIR"
  for port in "${PORTS[@]}"; do
    echo "PORT=$port"
    echo "OPEN_LINE=$(head -n 1 "$OUTDIR/${port}.log" 2>/dev/null || true)"
    echo "KEY_COUNT=$(wc -l < "$OUTDIR/${port}.keywords.log")"
    sed -n '1,20p' "$OUTDIR/${port}.keywords.log"
  done
} | tee "$OUTDIR/summary.txt"
