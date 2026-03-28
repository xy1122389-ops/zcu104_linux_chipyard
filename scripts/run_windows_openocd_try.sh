#!/usr/bin/env bash
set -euo pipefail

OPENOCD_EXE_WIN='C:\Users\24242\AppData\Local\Microsoft\WinGet\Packages\xpack-dev-tools.openocd-xpack_Microsoft.Winget.Source_8wekyb3d8bbwe\xpack-openocd-0.12.0-7\bin\openocd.exe'
SCRIPTS_DIR_WIN='C:\Users\24242\AppData\Local\Microsoft\WinGet\Packages\xpack-dev-tools.openocd-xpack_Microsoft.Winget.Source_8wekyb3d8bbwe\xpack-openocd-0.12.0-7\openocd\scripts'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CFG_WIN=$(wslpath -w "$SCRIPT_DIR/openocd_zcu104_win_try.cfg")
TS=$(date +%Y%m%d_%H%M%S)
LOG="$SCRIPT_DIR/../logs/windows_openocd_zcu104_try_${TS}.log"
WRAPPER="/tmp/windows_openocd_zcu104_try_${TS}.cmd"
WRAPPER_WIN=$(wslpath -w "$WRAPPER")

cat > "$WRAPPER" <<EOF
@echo off
pushd C:\Windows\Temp
"$OPENOCD_EXE_WIN" -s "$SCRIPTS_DIR_WIN" -f "$CFG_WIN"
set EC=%ERRORLEVEL%
popd
exit /b %EC%
EOF

cmd.exe /c "$WRAPPER_WIN" > "$LOG" 2>&1 || true

echo "LOG:$LOG"
sed -n '1,160p' "$LOG"
