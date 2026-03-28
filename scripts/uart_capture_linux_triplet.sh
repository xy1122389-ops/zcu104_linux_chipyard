#!/usr/bin/env bash
set -euo pipefail

FW=${1:-/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.bin}
DUR=${2:-150}
BAUD=${3:-115200}
KICK_MODE=${4:-clock}

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd /root/chipyard/fpga

TS=$(date +%Y%m%d_%H%M%S)
OUTDIR="logs/uart_linux_triplet_${TS}"
mkdir -p "$OUTDIR"

PORTS=(COM5 COM6 COM7)
CAP_SCRIPTS=()
CAP_PIDS=()
WIN_OUTDIR=$(wslpath -w "/root/chipyard/fpga/$OUTDIR")

for port in "${PORTS[@]}"; do
  PWSH_SCRIPT="/tmp/uart_triplet_${TS}_${port}.ps1"
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
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$WIN_SCRIPT" -PortName "$port" -OutDir "$WIN_OUTDIR" -DurationSec "$DUR" -BaudRate "$BAUD" >/tmp/uart_triplet_${TS}_${port}.out 2>&1 &
  CAP_PIDS+=("$!")
done

sleep 2
bash "$SCRIPT_DIR/run_ps_ddr_init_linux.sh" > "$OUTDIR/ps_ddr_init.log" 2>&1 || true
bash "$SCRIPT_DIR/load_linux_fw_payload.sh" "$FW" > "$OUTDIR/load_payload.log" 2>&1 || true
if [[ "$KICK_MODE" == "pulse" ]]; then
  bash "$SCRIPT_DIR/pulse_tile_reset_and_kick.sh" > "$OUTDIR/clock_kick.log" 2>&1 || true
else
  bash "$SCRIPT_DIR/enable_tile_clock_and_kick.sh" > "$OUTDIR/clock_kick.log" 2>&1 || true
fi

for pid in "${CAP_PIDS[@]}"; do
  wait "$pid" || true
done

for ps1 in "${CAP_SCRIPTS[@]}"; do
  rm -f "$ps1"
done

for port in "${PORTS[@]}"; do
  grep -a -i -nE 'linux version|booting linux|starting kernel|kernel command line|freeing unused kernel|opensbi|u-boot|login:' "$OUTDIR/${port}.log" > "$OUTDIR/${port}.keywords.log" || true
done

{
  echo "OUTDIR=$OUTDIR"
  for port in "${PORTS[@]}"; do
    echo "PORT=$port"
    echo "OPEN_LINE=$(head -n 1 "$OUTDIR/${port}.log" 2>/dev/null || true)"
    echo "KEY_COUNT=$(wc -l < "$OUTDIR/${port}.keywords.log")"
    sed -n '1,40p' "$OUTDIR/${port}.keywords.log"
  done
} | tee "$OUTDIR/summary.txt"
