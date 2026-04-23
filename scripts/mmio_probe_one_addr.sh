#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $0 <addr> [label]" >&2
    exit 2
fi

ADDR="$1"
LABEL="${2:-$1}"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
XSDB_BAT_WIN=$(wslpath -w /mnt/e/PRO_APP/xilinx/Vivado/2021.2/bin/xsdb.bat)

run_tcl() {
    local tcl="$1"
    local win_tcl
    local wrap
    local win_wrap

    win_tcl=$(wslpath -w "$tcl")
    wrap=$(mktemp /mnt/c/Windows/Temp/mmio_probeXXXX.cmd)
    win_wrap=$(wslpath -w "$wrap")
    trap 'rm -f "$wrap"' RETURN

    cat > "$wrap" <<CMD
@echo off
pushd C:\\Windows\\Temp
call "$XSDB_BAT_WIN" -eval "source {$win_tcl}"
popd
CMD
    cmd.exe /c "$win_wrap"
}

stop_tools() {
    powershell.exe -NoProfile -Command 'Stop-Process -Name hw_server,xsdb,JLinkGDBServerCL,JLink -ErrorAction SilentlyContinue' >/dev/null 2>&1 || true
    sleep 2
}

server_ready() {
    powershell.exe -NoProfile -Command "Get-NetTCPConnection -LocalPort 3333 -ErrorAction SilentlyContinue" 2>/dev/null | grep -q "Listen" &&
        [[ -f /tmp/jlink_gdbserver.log ]] &&
        grep -q "Connected to target" /tmp/jlink_gdbserver.log
}

echo "[probe] stopping residual tools"
stop_tools

echo "[probe] DAP recover"
run_tcl "$SCRIPT_DIR/xsdb_recover_dap.tcl" >/tmp/mmio_probe_recover.log 2>&1

echo "[probe] stable_init"
bash "$SCRIPT_DIR/stable_init.sh" >/tmp/mmio_probe_stable_init.log 2>&1

echo "[probe] stopping hw_server/xsdb before J-Link"
powershell.exe -NoProfile -Command 'Stop-Process -Name hw_server,xsdb -ErrorAction SilentlyContinue' >/dev/null 2>&1 || true
sleep 2

echo "[probe] start_jlink_server"
bash "$SCRIPT_DIR/start_jlink_server.sh" >/tmp/mmio_probe_start_jlink.log 2>&1 &

for _ in $(seq 1 20); do
    sleep 2
    if server_ready; then
        break
    fi
done

if ! server_ready; then
    echo "[probe] J-Link server did not become ready" >&2
    tail -n 80 /tmp/mmio_probe_start_jlink.log >&2 || true
    tail -n 80 /tmp/jlink_gdbserver.log >&2 || true
    exit 1
fi

echo "[probe] single address probe: $LABEL @ $ADDR"
MMIO_ADDR="$ADDR" MMIO_LABEL="$LABEL" gdb-multiarch -q -batch -x "$SCRIPT_DIR/mmio_diag_one_addr.gdb"
