#!/usr/bin/env bash
set -euo pipefail

PORT=${1:-COM5}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TS=$(date +%Y%m%d_%H%M%S)
HEALTH_LOG="$SCRIPT_DIR/../logs/runtime_round_baseline_health_${TS}.log"
UART_LOG="$SCRIPT_DIR/../logs/runtime_round_baseline_uart_${TS}.log"
PWSH_SCRIPT="/tmp/runtime_round_uart_open_${TS}.ps1"

"$SCRIPT_DIR/runtime_debug_healthcheck.sh" > "$HEALTH_LOG" 2>&1 || true

cat > "$PWSH_SCRIPT" <<'PS1'
param([string]$PortName,[string]$OutPath)
$sw = New-Object System.IO.StreamWriter($OutPath)
try {
  $port = New-Object System.IO.Ports.SerialPort $PortName,115200,'None',8,'one'
  $port.Open()
  $sw.WriteLine('UART_OPEN_OK')
  $sw.Flush()
  $port.Close()
} catch {
  $sw.WriteLine('UART_OPEN_FAIL: ' + $_.Exception.Message)
  $sw.Flush()
} finally {
  $sw.Close()
}
PS1

WIN_SCRIPT=$(wslpath -w "$PWSH_SCRIPT")
WIN_UART_LOG=$(wslpath -w "$UART_LOG")
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$WIN_SCRIPT" -PortName "$PORT" -OutPath "$WIN_UART_LOG" >/tmp/runtime_round_uart_open_${TS}.out 2>&1 || true

echo "HEALTH_LOG:$HEALTH_LOG"
echo "UART_LOG:$UART_LOG"
grep -aE '^(CONNECT_OK|PSU_SELECT_OK|APU_SELECT_OK|A53_0_SELECT_OK|A53_0_REG_PC_OK|A53_0_REG_CPSR_OK)' "$HEALTH_LOG" || true
head -n 1 "$UART_LOG" 2>/dev/null || true
