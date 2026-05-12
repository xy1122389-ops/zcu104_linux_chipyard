#!/usr/bin/env bash
set -euo pipefail

# start_jlink_server.sh — Start J-Link GDB Server ONCE for RISC-V
# Server stays running; all GDB sessions connect to :3333
# DO NOT kill/restart this server unless absolutely necessary

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LOG="/tmp/jlink_gdbserver.log"
LOG_WIN_WSL="${JLINK_GDB_SERVER_LOG_WSL:-/mnt/c/Windows/Temp/jlink_gdbserver.log}"
LAUNCH_PS1="/tmp/jlink_gdbserver_launch.ps1"
LOCK_FILE="/tmp/jlink_gdbserver.start.lock"
JLINK_HOST="${JLINK_HOST:-127.0.0.1}"
JLINK_PORT="${JLINK_PORT:-3333}"

JLINK_EXE="${JLINK_GDB_SERVER:-C:\\Program Files\\SEGGER\\JLink\\JLinkGDBServerCL.exe}"
JLINK_SERIAL="${JLINK_USB_SERIAL:-601012542}"
JLINK_STARTUP_TIMEOUT_SECS="${JLINK_STARTUP_TIMEOUT_SECS:-20}"
JLINK_LAUNCH_TIMEOUT_SECS="${JLINK_LAUNCH_TIMEOUT_SECS:-15}"
JLINK_FORCE_RESTART="${JLINK_FORCE_RESTART:-0}"

sync_server_log() {
    if [[ -f "$LOG_WIN_WSL" ]]; then
        if command -v iconv >/dev/null 2>&1; then
            iconv -f UTF-16LE -t UTF-8 "$LOG_WIN_WSL" > "$LOG" 2>/dev/null || cat "$LOG_WIN_WSL" > "$LOG" 2>/dev/null || true
        else
            cat "$LOG_WIN_WSL" > "$LOG" 2>/dev/null || true
        fi
    fi
}

server_listening() {
    if command -v nc >/dev/null 2>&1; then
        nc -z -w 1 "$JLINK_HOST" "$JLINK_PORT" >/dev/null 2>&1
        return $?
    fi

    powershell.exe -NoProfile -Command "if (Get-NetTCPConnection -LocalPort $JLINK_PORT -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }" \
        >/dev/null 2>&1
}

jlink_process_running() {
    powershell.exe -NoProfile -Command "if (Get-Process -Name JLinkGDBServerCL -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }" \
        >/dev/null 2>&1
}

server_booted() {
    server_listening && jlink_process_running
}

server_ready() {
    sync_server_log
    jlink_process_running && [[ -f "$LOG" ]] && grep -Eq "Waiting for GDB connection|Connected to target|Connected to 127\.0\.0\.1" "$LOG"
}

jlink_exited() {
    # J-Link shut down early (target connection failed)
    sync_server_log
    [[ -f "$LOG" ]] && grep -q "Shutting down" "$LOG"
}

jlink_halt_timeout() {
    sync_server_log
    [[ -f "$LOG" ]] && grep -q "Timeout while waiting for core to halt after reset and halt request" "$LOG"
}

jlink_target_attach_failed() {
    sync_server_log
    [[ -f "$LOG" ]] && grep -Eq "Could not start CPU core|ERROR: Could not connect to target|Target connection failed" "$LOG"
}

stop_server_processes() {
    powershell.exe -NoProfile -Command 'Stop-Process -Name JLinkGDBServerCL -ErrorAction SilentlyContinue' >/dev/null 2>&1 || true
    for _ in $(seq 1 10); do
        if ! jlink_process_running && ! server_listening; then
            return 0
        fi
        sleep 1
    done
    echo "[jlink] WARN: previous J-Link server did not disappear cleanly; continuing"
    return 0
}

launch_server() {
    local arg_string="$1"
    local win_log
    local launch_script_win

    : > "$LOG"
    rm -f "$LOG_WIN_WSL"
    win_log=$(wslpath -w "$LOG_WIN_WSL")
    cat > "$LAUNCH_PS1" <<EOF
& '$JLINK_EXE' $arg_string *> '$win_log'
EOF
    launch_script_win=$(wslpath -w "$LAUNCH_PS1")

    (
        exec 9>&- || true
        nohup powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$launch_script_win" >/dev/null 2>&1 &
    )
    sleep 1
    return 0
}

wait_for_server() {
    echo "[jlink] Waiting for GDB Server to become ready..."
    for i in $(seq 1 "$JLINK_STARTUP_TIMEOUT_SECS"); do
        sleep 1
        sync_server_log
        if server_ready; then
            echo "[jlink] GDB Server is listening on :3333"
            echo "[jlink] Ready for GDB connections."
            return 0
        fi
        if jlink_exited; then
            echo "[jlink]   J-Link exited early (target connection failed)"
            tail -5 "$LOG" | sed 's/^/[jlink]   /'
            return 1
        fi
        echo "[jlink]   ...waiting ($i/${JLINK_STARTUP_TIMEOUT_SECS})"
    done
    return 1
}

# Fast path: if a healthy server is already up, do not block on the start lock.
if [[ "$JLINK_FORCE_RESTART" != "1" ]] && server_ready; then
    echo "[jlink] GDB Server already listening on :3333 — reusing existing instance"
    echo "[jlink] DO NOT restart. Use 'target remote :3333' from GDB."
    exit 0
fi

if [[ "$JLINK_FORCE_RESTART" == "1" ]]; then
    echo "[jlink] FORCE_RESTART=1: bypassing healthy-server reuse checks"
fi

if command -v flock >/dev/null 2>&1; then
    exec 9>"$LOCK_FILE"
    if ! flock -w 30 9; then
        echo "[jlink] FAIL: timed out waiting for J-Link start lock ($LOCK_FILE)" >&2
        exit 1
    fi
fi

# Re-check after taking the lock to avoid a race with another starter.
if [[ "$JLINK_FORCE_RESTART" != "1" ]] && server_ready; then
    echo "[jlink] GDB Server already listening on :3333 — reusing existing instance"
    echo "[jlink] DO NOT restart. Use 'target remote :3333' from GDB."
    exit 0
fi

echo "[jlink] Starting J-Link GDB Server on ${JLINK_HOST}:${JLINK_PORT} (background)..."
echo "[jlink] Log: $LOG"
echo ""

stop_server_processes

primary_args="-select USB=$JLINK_SERIAL -device RISC-V -endian little -if JTAG -speed 1000 -JTAGConf 0,0 -port $JLINK_PORT -LocalhostOnly 0 -noir -nohalt -noreset"
fallback_args="-select USB=$JLINK_SERIAL -device RISC-V -endian little -if JTAG -speed 1000 -JTAGConf 0,0 -port $JLINK_PORT -LocalhostOnly 0 -nohalt -noreset"

echo "[jlink] Attempt 1: start with -noir -nohalt -noreset"
launch_server "$primary_args"
if wait_for_server; then
    exit 0
fi

if jlink_halt_timeout; then
    echo "[jlink] FAIL: JTAG TAP is visible, but the core could not be halted." >&2
    echo "[jlink] This is not a startup-flag issue; skipping the fallback retry." >&2
    echo "[jlink] Likely causes:" >&2
    echo "[jlink]   1. board/debug state is corrupted after repeated reprogram/reset cycles" >&2
    echo "[jlink]   2. Rocket debug system side is stuck even though the JTAG side responds" >&2
    echo "[jlink] Recommended recovery:" >&2
    echo "[jlink]   - full power-cycle the ZCU104 (OFF 10s -> ON)" >&2
    echo "[jlink]   - rerun: bash scripts/program_phase0b_bit.sh" >&2
    echo "[jlink]   - rerun: bash scripts/start_jlink_server.sh" >&2
    exit 1
fi

if jlink_target_attach_failed; then
    echo "[jlink] FAIL: J-Link reached the target, but target attach failed on the first attempt." >&2
    echo "[jlink] Skipping the immediate fallback retry to avoid destabilizing the USB device state." >&2
    echo "[jlink] Recommended recovery:" >&2
    echo "[jlink]   - rerun: bash scripts/program_phase0b_bit.sh" >&2
    echo "[jlink]   - rerun: bash scripts/start_jlink_server.sh" >&2
    exit 1
fi

echo "[jlink] Attempt 1 did not reach ready state; retrying without -noir"
stop_server_processes
sleep 2
launch_server "$fallback_args"
if wait_for_server; then
    exit 0
fi

echo "[jlink] TIMEOUT: GDB Server did not start within ${JLINK_STARTUP_TIMEOUT_SECS}s per attempt" >&2
echo "[jlink] Check log: $LOG" >&2
sync_server_log
if [[ -f "$LOG" ]]; then
    echo "[jlink] Last 10 lines of log:"
    tail -10 "$LOG"
fi
exit 1
