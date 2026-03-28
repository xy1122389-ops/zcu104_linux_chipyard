#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

BITFILE_DEFAULT="$FPGA_DIR/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupDebugConfig/obj/ZCU104FPGATestHarness.bit"
BITFILE="${1:-$BITFILE_DEFAULT}"

OPENOCD_EXE='/mnt/c/Users/24242/AppData/Local/Microsoft/WinGet/Packages/xpack-dev-tools.openocd-xpack_Microsoft.Winget.Source_8wekyb3d8bbwe/xpack-openocd-0.12.0-7/bin/openocd.exe'
OPENOCD_SCRIPTS='/mnt/c/Users/24242/AppData/Local/Microsoft/WinGet/Packages/xpack-dev-tools.openocd-xpack_Microsoft.Winget.Source_8wekyb3d8bbwe/xpack-openocd-0.12.0-7/openocd/scripts'

STAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="$FPGA_DIR/logs/openocd_pld_load_after_init_$STAMP"
mkdir -p "$OUTDIR"

WIN_BIT='/mnt/c/Users/24242/AppData/Local/Temp/ZCU104FPGATestHarness_debug_after_init.bit'
cp -f "$BITFILE" "$WIN_BIT"

CFG='/mnt/c/Users/24242/AppData/Local/Temp/openocd_pld_load_after_init.cfg'
cat >"$CFG" <<'EOF'
bindto 127.0.0.1
gdb_port disabled
telnet_port disabled
tcl_port disabled
debug_level 3
adapter driver ftdi
ftdi vid_pid 0x0403 0x6011
adapter serial 07198
ftdi channel 0
ftdi layout_init 0x00e8 0x60eb
transport select jtag
reset_config none
adapter speed 1000
jtag newtap uscale tap -irlen 4 -ircapture 0x1 -irmask 0xf -expected-id 0x5ba00477
jtag newtap uscale ps -irlen 12 -ircapture 0x1 -irmask 0x03 -ignore-version \
  -expected-id 0x14730093 -expected-id 0x04730093
pld create uscale.pld virtex2 -chain-position uscale.ps -no_jstart
init
scan_chain
pld load uscale.pld C:/Users/24242/AppData/Local/Temp/ZCU104FPGATestHarness_debug_after_init.bit
shutdown
EOF

STDOUT_LOG="$OUTDIR/stdout.log"
STDERR_LOG="$OUTDIR/stderr.log"

cmd.exe /c "pushd C:\\ && taskkill /F /IM openocd.exe /IM hw_server.exe" >/dev/null 2>&1 || true

python3 - <<'PY' "$OPENOCD_EXE" "$OPENOCD_SCRIPTS" "$(wslpath -w "$CFG")" "$STDOUT_LOG" "$STDERR_LOG"
import subprocess
import sys

exe, scripts, cfg, stdout_log, stderr_log = sys.argv[1:]
with open(stdout_log, "w") as fo, open(stderr_log, "w") as fe:
    p = subprocess.Popen([exe, "-s", scripts, "-f", cfg], stdout=fo, stderr=fe)
    try:
        p.wait(timeout=180)
        print(f"EXIT={p.returncode}")
    except subprocess.TimeoutExpired:
        p.kill()
        print("EXIT=TIMEOUT")
PY

{
  echo "BITFILE=$BITFILE"
  echo "CFG=$CFG"
  echo "STDOUT_LOG=$STDOUT_LOG"
  echo "STDERR_LOG=$STDERR_LOG"
} >"$OUTDIR/summary.txt"

cat "$OUTDIR/summary.txt"
