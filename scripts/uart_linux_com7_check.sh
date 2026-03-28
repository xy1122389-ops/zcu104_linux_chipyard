#!/usr/bin/env bash
set -euo pipefail

FW=${1:-/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.bin}
DUR=${2:-150}
BAUD=${3:-115200}
KICK_MODE=${4:-clock}

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd /root/chipyard/fpga

TS=$(date +%Y%m%d_%H%M%S)
OUTDIR="logs/uart_linux_com7_${TS}"
mkdir -p "$OUTDIR"
PORT=COM7

PWSH_SCRIPT="/tmp/uart_linux_${TS}_${PORT}.ps1"
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
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$WIN_SCRIPT" -PortName "$PORT" -OutDir "$WIN_OUTDIR" -DurationSec "$DUR" -BaudRate "$BAUD" >"/tmp/uart_linux_${TS}_${PORT}.out" 2>&1 &
CAP_PID=$!

sleep 2
bash "$SCRIPT_DIR/run_ps_ddr_init_linux.sh" > "$OUTDIR/ps_ddr_init.log" 2>&1 || true
bash "$SCRIPT_DIR/load_linux_fw_payload.sh" "$FW" > "$OUTDIR/load_payload.log" 2>&1 || true
if [[ "$KICK_MODE" == "pulse" ]]; then
  bash "$SCRIPT_DIR/pulse_tile_reset_and_kick.sh" > "$OUTDIR/clock_kick.log" 2>&1 || true
else
  bash "$SCRIPT_DIR/enable_tile_clock_and_kick.sh" > "$OUTDIR/clock_kick.log" 2>&1 || true
fi

wait "$CAP_PID" || true
rm -f "$PWSH_SCRIPT"

grep -a -i -nE 'linux version|booting linux|starting kernel|kernel command line|freeing unused kernel|opensbi|u-boot|login:' "$OUTDIR/${PORT}.log" > "$OUTDIR/${PORT}.keywords.log" || true

{
  echo "OUTDIR=$OUTDIR"
  echo "PORT=$PORT"
  echo "OPEN_LINE=$(head -n 1 "$OUTDIR/${PORT}.log" 2>/dev/null || true)"
  echo "KEY_COUNT=$(wc -l < "$OUTDIR/${PORT}.keywords.log")"
  sed -n '1,40p' "$OUTDIR/${PORT}.keywords.log"
} | tee "$OUTDIR/summary.txt"
