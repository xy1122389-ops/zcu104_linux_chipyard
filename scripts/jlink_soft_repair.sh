#!/usr/bin/env bash
set -euo pipefail

JLINK_ID='USB\VID_1366&PID_0101\000601012542'
HUB_ID='USB\VID_05E3&PID_0610\6&202FA33D&0&2'

run_step() {
    local label="$1"
    shift
    echo
    echo "=== $label ==="
    set +e
    "$@"
    local ec=$?
    set -e
    echo "[exit=$ec]"
}

echo "=== Initial Status ==="
bash scripts/jlink_status.sh

run_step "devcon status J-Link" \
    /mnt/c/Windows/System32/devcon.exe status "@$JLINK_ID"

run_step "devcon stack J-Link" \
    /mnt/c/Windows/System32/devcon.exe stack "@$JLINK_ID"

run_step "pnputil enum J-Link" \
    /mnt/c/Windows/System32/pnputil.exe /enum-devices /instanceid "$JLINK_ID" /properties /location

run_step "devcon rescan" \
    /mnt/c/Windows/System32/devcon.exe rescan

run_step "pnputil restart hub" \
    /mnt/c/Windows/System32/pnputil.exe /restart-device "$HUB_ID"

run_step "pnputil restart J-Link" \
    /mnt/c/Windows/System32/pnputil.exe /restart-device "$JLINK_ID"

echo
echo "=== Final Status ==="
bash scripts/jlink_status.sh
