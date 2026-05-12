#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
JLINK_USB_INSTANCE="${JLINK_USB_INSTANCE:-USB\VID_1366&PID_0101\000601012542}"
JLINK_HOST="${JLINK_HOST:-127.0.0.1}"
JLINK_PORT="${JLINK_PORT:-3333}"
GDB_BIN="${GDB_BIN:-riscv64-unknown-elf-gdb}"

export PATH="/root/chipyard/.oclaw-env/bin:/root/chipyard/.oclaw-env/riscv-tools/bin:${PATH}"

status_snapshot() {
    echo "[jlink-guard] === status snapshot ==="
    bash "${SCRIPT_DIR}/jlink_status.sh" || true
}

jlink_present_ok() {
    JLINK_USB_INSTANCE="$JLINK_USB_INSTANCE" python3 - <<'PY'
import json
import os
import subprocess
import sys

instance = os.environ["JLINK_USB_INSTANCE"]
cmd = [
    "powershell.exe",
    "-NoProfile",
    "-Command",
    '$dev = Get-PnpDevice | Where-Object { $_.FriendlyName -like "*J-Link*" -or $_.InstanceId -like "*VID_1366*" } | Select-Object Status,Class,FriendlyName,InstanceId,Present | ConvertTo-Json -Compress -Depth 3; $dev',
]
out = subprocess.check_output(cmd, text=True).replace("\r", "").strip()
data = json.loads(out)
if isinstance(data, dict):
    data = [data]
match = [d for d in data if d.get("InstanceId") == instance]
if match and match[0].get("Status") == "OK" and match[0].get("Present") is True:
    sys.exit(0)
sys.exit(1)
PY
}

gdb_precheck() {
    timeout 20 "${GDB_BIN}" -q -batch -x "${SCRIPT_DIR}/jlink_precheck.gdb" 2>&1
}

start_or_reuse_server() {
    if bash "${SCRIPT_DIR}/start_jlink_server.sh"; then
        return 0
    fi

    if nc -z -w 3 "$JLINK_HOST" "$JLINK_PORT" 2>/dev/null; then
        echo "[jlink-guard] WARN: start_jlink_server.sh returned nonzero, but ${JLINK_HOST}:${JLINK_PORT} is listening; continue to GDB precheck"
        return 0
    fi

    echo "[jlink-guard] FAIL: start_jlink_server.sh did not produce a usable listener on ${JLINK_HOST}:${JLINK_PORT}" >&2
    status_snapshot
    return 1
}

status_snapshot

if ! jlink_present_ok; then
    echo "[jlink-guard] FAIL: J-Link ${JLINK_USB_INSTANCE} is not Present/OK on Windows." >&2
    echo "[jlink-guard] Abort before touching GDB or restarting the server." >&2
    exit 2
fi

echo "[jlink-guard] J-Link USB device is Present/OK"

echo "[jlink-guard] Starting or reusing J-Link server on ${JLINK_HOST}:${JLINK_PORT}"
start_or_reuse_server

echo "[jlink-guard] Running minimal GDB precheck"
precheck_out=""
if ! precheck_out="$(gdb_precheck)"; then
    printf '%s\n' "$precheck_out"
    echo "[jlink-guard] WARN: GDB precheck failed; forcing one J-Link server restart" >&2
    if ! JLINK_FORCE_RESTART=1 bash "${SCRIPT_DIR}/start_jlink_server.sh"; then
        echo "[jlink-guard] FAIL: forced J-Link server restart failed after precheck failure" >&2
        status_snapshot
        exit 3
    fi

    echo "[jlink-guard] Re-running minimal GDB precheck after forced restart"
    if ! precheck_out="$(gdb_precheck)"; then
        printf '%s\n' "$precheck_out"
        echo "[jlink-guard] FAIL: GDB precheck failed after forced restart" >&2
        status_snapshot
        exit 3
    fi
fi

printf '%s\n' "$precheck_out"

echo "[jlink-guard] PASS: J-Link server and target precheck succeeded"