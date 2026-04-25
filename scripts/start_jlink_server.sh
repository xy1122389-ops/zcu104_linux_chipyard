#!/usr/bin/env bash
set -euo pipefail

# start_jlink_server.sh — Start J-Link GDB Server ONCE for RISC-V
# Server stays running; all GDB sessions connect to :3333
# DO NOT kill/restart this server unless absolutely necessary

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LOG="/tmp/jlink_gdbserver.log"

JLINK_EXE="${JLINK_GDB_SERVER:-C:\\Program Files\\SEGGER\\JLink\\JLinkGDBServerCL.exe}"
JLINK_SERIAL="${JLINK_USB_SERIAL:-601012542}"

server_listening() {
    powershell.exe -NoProfile -Command "if (Get-NetTCPConnection -LocalPort 3333 -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }" \
        >/dev/null 2>&1
}

server_ready() {
    server_listening && [[ -f "$LOG" ]] && grep -Eq "Waiting for GDB connection|Connected to target" "$LOG"
}

launch_server() {
    local arg_string="$1"
    : > "$LOG"
    powershell.exe -NoProfile -Command "
        Start-Process -FilePath '$JLINK_EXE' \
            -ArgumentList '$arg_string' \
            -WindowStyle Hidden \
            -RedirectStandardOutput '$(wslpath -w "$LOG")'
    "
}

wait_for_server() {
    echo "[jlink] Waiting for GDB Server to become ready..."
    for i in $(seq 1 15); do
        sleep 2
        if server_ready; then
            echo "[jlink] GDB Server is listening on :3333"
            echo "[jlink] Ready for GDB connections."
            return 0
        fi
        echo "[jlink]   ...waiting ($i/15)"
    done
    return 1
}

# Check if server is already running on port 3333
if server_ready; then
    echo "[jlink] GDB Server already listening on :3333 — reusing existing instance"
    echo "[jlink] DO NOT restart. Use 'target remote :3333' from GDB."
    exit 0
fi

echo "[jlink] Starting J-Link GDB Server on :3333 (background)..."
echo "[jlink] Log: $LOG"
echo ""

primary_args="-select USB=$JLINK_SERIAL -device RISC-V -endian little -if JTAG -speed 1000 -JTAGConf 0,0 -port 3333 -LocalhostOnly 0 -noir -noexit"
fallback_args="-select USB=$JLINK_SERIAL -device RISC-V -endian little -if JTAG -speed 1000 -JTAGConf 0,0 -port 3333 -LocalhostOnly 0 -noexit"

echo "[jlink] Attempt 1: start with -noir and without -noreset/-nohalt"
launch_server "$primary_args"
if wait_for_server; then
    exit 0
fi

echo "[jlink] Attempt 1 did not reach ready state; retrying without -noir"
powershell.exe -NoProfile -Command 'Stop-Process -Name JLinkGDBServerCL -ErrorAction SilentlyContinue' >/dev/null 2>&1 || true
sleep 2
launch_server "$fallback_args"
if wait_for_server; then
    exit 0
fi

echo "[jlink] TIMEOUT: GDB Server did not start within 30s" >&2
echo "[jlink] Check log: $LOG" >&2
if [[ -f "$LOG" ]]; then
    echo "[jlink] Last 10 lines of log:"
    tail -10 "$LOG"
fi
exit 1
