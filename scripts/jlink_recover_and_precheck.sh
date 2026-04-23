#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${JLINK_RECOVER_LOG_DIR:-/tmp/jlink_recover}"
mkdir -p "$LOG_DIR"

JLINK_PNP_QUERY='Get-PnpDevice -PresentOnly | Where-Object { $_.FriendlyName -like "*J-Link*" -or $_.InstanceId -like "*VID_1366*" } | Select-Object Status,Class,FriendlyName,InstanceId | ConvertTo-Json -Compress'

ts() {
    date +"%Y%m%d_%H%M%S"
}

hw_server_listening() {
    powershell.exe -NoProfile -Command "Get-NetTCPConnection -LocalPort 3121 -ErrorAction SilentlyContinue" 2>/dev/null | grep -q "Listen"
}

ensure_hw_server() {
    if hw_server_listening; then
        echo "[recover] hw_server already listening on :3121"
        return 0
    fi

    echo "[recover] starting hw_server on :3121"
    powershell.exe -NoProfile -Command 'Start-Process -FilePath "E:\PRO_APP\xilinx\Vivado\2021.2\bin\hw_server.bat" -WindowStyle Hidden' 2>/dev/null || true
    for _ in $(seq 1 15); do
        sleep 1
        if hw_server_listening; then
            echo "[recover] hw_server is listening on :3121"
            return 0
        fi
    done

    echo "[recover] FAILED: hw_server did not start on :3121" >&2
    return 1
}

jlink_present() {
    local out
    out=$(powershell.exe -NoProfile -Command "$JLINK_PNP_QUERY" 2>/dev/null | tr -d '\r')
    [[ -n "$out" && "$out" != "null" && "$out" != "[]" ]]
}

stop_residual_tools() {
    echo "[recover] stopping residual hw_server/xsdb processes (preserve healthy J-Link server)"
    pkill -f "hw_server|xsdb" 2>/dev/null || true
    powershell.exe -NoProfile -Command 'Stop-Process -Name hw_server,xsdb -ErrorAction SilentlyContinue' 2>/dev/null || true
    sleep 2
}

stamp=$(ts)

echo "[recover] status before init"
bash scripts/jlink_status.sh | tee "$LOG_DIR/status_before_${stamp}.log"

if ! jlink_present; then
    echo
    echo "[recover] No present J-Link device on Windows; aborting before stable_init."
    exit 2
fi

echo
ensure_hw_server

echo
echo "[recover] running stable init"
bash scripts/stable_init.sh | tee "$LOG_DIR/stable_init_${stamp}.log"

echo
echo "[recover] status after init"
bash scripts/jlink_status.sh | tee "$LOG_DIR/status_after_init_${stamp}.log"

if ! jlink_present; then
    echo
    echo "[recover] J-Link disappeared after stable_init; aborting before server start."
    exit 3
fi

echo
stop_residual_tools

echo
echo "[recover] starting J-Link server"
bash scripts/start_jlink_server.sh | tee "$LOG_DIR/start_server_${stamp}.log"

echo
echo "[recover] precheck run #1"
gdb-multiarch -q -batch -x scripts/jlink_precheck.gdb | tee "$LOG_DIR/precheck1_${stamp}.log"

echo
echo "[recover] precheck run #2"
gdb-multiarch -q -batch -x scripts/jlink_precheck.gdb | tee "$LOG_DIR/precheck2_${stamp}.log"
