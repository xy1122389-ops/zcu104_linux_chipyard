#!/usr/bin/env bash
set -euo pipefail

echo "=== J-Link PnP ==="
powershell.exe -NoProfile -Command 'Get-PnpDevice | Where-Object { $_.FriendlyName -like "*J-Link*" -or $_.InstanceId -like "*VID_1366*" } | Select-Object Status,Class,FriendlyName,InstanceId,Present | Format-Table -AutoSize'

echo
echo "=== J-Link Processes ==="
powershell.exe -NoProfile -Command 'Get-Process | Where-Object { $_.ProcessName -like "JLink*" -or $_.ProcessName -like "SEGGER*" } | Select-Object ProcessName,Id,Path | Format-Table -AutoSize' || true

echo
echo "=== J-Link Ports ==="
powershell.exe -NoProfile -Command 'Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -in 3333,2332,2333 } | Select-Object LocalAddress,LocalPort,OwningProcess,State | Format-Table -AutoSize' || true

echo
echo "=== J-Link Log Tail ==="
if [[ -f /tmp/jlink_gdbserver.log ]]; then
    tail -n 40 /tmp/jlink_gdbserver.log
else
    echo "/tmp/jlink_gdbserver.log not found"
fi

echo
echo "=== J-Link Commander Enumeration ==="
if [[ -x "/mnt/c/Program Files/SEGGER/JLink/JLink.exe" ]]; then
    cmd_file=$(mktemp /tmp/jlink_enumXXXX.jlink)
    trap 'rm -f "$cmd_file"' EXIT
    cat > "$cmd_file" <<'EOF'
ShowEmuList
exit
EOF
    '/mnt/c/Program Files/SEGGER/JLink/JLink.exe' -CommandFile "$cmd_file" || true
else
    echo "JLink.exe not found"
fi
