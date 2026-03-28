#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
BITFILE_DEFAULT="$FPGA_DIR/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupDebugConfig/obj/ZCU104FPGATestHarness.bit"
BITFILE="${1:-$BITFILE_DEFAULT}"
OUTER_IR="${2:-0x923}"
TUNNEL_TYPE="${3:-0}"
SKIP_PLD_LOAD="${SKIP_PLD_LOAD:-0}"

OPENOCD_EXE_DEFAULT='/tmp/riscv-collab-openocd/bin/openocd.exe'
OPENOCD_SCRIPTS_DEFAULT='/tmp/riscv-collab-openocd/share/openocd/scripts'
OPENOCD_EXE="${OPENOCD_EXE:-$OPENOCD_EXE_DEFAULT}"
OPENOCD_SCRIPTS="${OPENOCD_SCRIPTS:-$OPENOCD_SCRIPTS_DEFAULT}"
PLD_OPENOCD_EXE_DEFAULT='/mnt/c/Users/24242/AppData/Local/Microsoft/WinGet/Packages/xpack-dev-tools.openocd-xpack_Microsoft.Winget.Source_8wekyb3d8bbwe/xpack-openocd-0.12.0-7/bin/openocd.exe'
PLD_OPENOCD_SCRIPTS_DEFAULT='/mnt/c/Users/24242/AppData/Local/Microsoft/WinGet/Packages/xpack-dev-tools.openocd-xpack_Microsoft.Winget.Source_8wekyb3d8bbwe/xpack-openocd-0.12.0-7/openocd/scripts'
PLD_OPENOCD_EXE="${PLD_OPENOCD_EXE:-$PLD_OPENOCD_EXE_DEFAULT}"
PLD_OPENOCD_SCRIPTS="${PLD_OPENOCD_SCRIPTS:-$PLD_OPENOCD_SCRIPTS_DEFAULT}"

if [[ ! -f "$BITFILE" ]]; then
  echo "missing bitfile: $BITFILE" >&2
  exit 2
fi
if [[ ! -f "$OPENOCD_EXE" ]]; then
  echo "missing openocd.exe: $OPENOCD_EXE" >&2
  exit 3
fi
if [[ ! -d "$OPENOCD_SCRIPTS" ]]; then
  echo "missing OpenOCD scripts dir: $OPENOCD_SCRIPTS" >&2
  exit 4
fi
if [[ ! -f "$PLD_OPENOCD_EXE" ]]; then
  echo "missing pld openocd.exe: $PLD_OPENOCD_EXE" >&2
  exit 5
fi
if [[ ! -d "$PLD_OPENOCD_SCRIPTS" ]]; then
  echo "missing pld OpenOCD scripts dir: $PLD_OPENOCD_SCRIPTS" >&2
  exit 6
fi

STAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="$FPGA_DIR/logs/openocd_probe_riscv_collab_ir_${OUTER_IR#0x}_t${TUNNEL_TYPE}_$STAMP"
mkdir -p "$OUTDIR"

WIN_TEMP_DIR='/mnt/c/Users/24242/AppData/Local/Temp'
WIN_BIT="$WIN_TEMP_DIR/ZCU104FPGATestHarness_debug_collab_${OUTER_IR#0x}_t${TUNNEL_TYPE}_${STAMP}.bit"
WIN_BIT_BASENAME=$(basename "$WIN_BIT")
cp -f "$BITFILE" "$WIN_BIT"

WIN_LOAD_CFG="$WIN_TEMP_DIR/openocd_pld_load_debug_collab_${OUTER_IR#0x}_t${TUNNEL_TYPE}.cfg"
cat >"$WIN_LOAD_CFG" <<EOF
bindto 127.0.0.1
gdb_port disabled
telnet_port disabled
tcl_port disabled
debug_level 1
adapter driver ftdi
ftdi vid_pid 0x0403 0x6011
adapter serial 07198
ftdi channel 0
ftdi layout_init 0x00e8 0x60eb
transport select jtag
reset_config none
adapter speed 1000
source [find target/xilinx_zynqmp.cfg]
pld create uscale.pld virtex2 -chain-position uscale.ps -no_jstart
init
pld load 0 C:/Users/24242/AppData/Local/Temp/$WIN_BIT_BASENAME
shutdown
EOF

WIN_PROBE_CFG="$WIN_TEMP_DIR/openocd_probe_riscv_collab_ir_${OUTER_IR#0x}_t${TUNNEL_TYPE}.cfg"
cat >"$WIN_PROBE_CFG" <<EOF
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
set _CHIPNAME uscale
jtag newtap \$_CHIPNAME tap -irlen 4 -ircapture 0x1 -irmask 0xf -expected-id 0x5ba00477
jtag newtap \$_CHIPNAME ps -irlen 12 -ircapture 0x1 -irmask 0x03 -ignore-version \\
  -expected-id 0x04711093 -expected-id 0x04710093 -expected-id 0x04721093 -expected-id 0x04720093 \\
  -expected-id 0x04739093 -expected-id 0x04730093 -expected-id 0x04738093 -expected-id 0x04740093 \\
  -expected-id 0x04750093 -expected-id 0x04759093 -expected-id 0x04758093
set jtag_configured 0
jtag configure \$_CHIPNAME.ps -event setup {
  global _CHIPNAME
  global jtag_configured
  if { \$jtag_configured == 0 } {
    irscan \$_CHIPNAME.ps 0x824
    drscan \$_CHIPNAME.ps 32 0x00000003
    runtest 100
    set jtag_configured 1
    jtag arp_init
  }
}
target create riscv_bscan_ps riscv -chain-position uscale.ps
riscv set_bscan_tunnel_ir $OUTER_IR
riscv use_bscan_tunnel 5 $TUNNEL_TYPE
init
targets
shutdown
EOF

LOAD_STDOUT="$OUTDIR/pld_load.stdout.log"
LOAD_STDERR="$OUTDIR/pld_load.stderr.log"
PROBE_STDOUT="$OUTDIR/probe.stdout.log"
PROBE_STDERR="$OUTDIR/probe.stderr.log"

# Clear stale Windows OpenOCD instances that can keep the FT4232 interface busy.
if [[ "$SKIP_PLD_LOAD" != "1" ]]; then
  cmd.exe /c "pushd C:\\ && taskkill /F /IM openocd.exe /IM hw_server.exe" >/dev/null 2>&1 || true
  "$PLD_OPENOCD_EXE" -s "$PLD_OPENOCD_SCRIPTS" -f "$(wslpath -w "$WIN_LOAD_CFG")" >"$LOAD_STDOUT" 2>"$LOAD_STDERR"
fi
cmd.exe /c "pushd C:\\ && taskkill /F /IM openocd.exe /IM hw_server.exe" >/dev/null 2>&1 || true
"$OPENOCD_EXE" -s "$OPENOCD_SCRIPTS" -f "$(wslpath -w "$WIN_PROBE_CFG")" >"$PROBE_STDOUT" 2>"$PROBE_STDERR"

CLASSIFICATION="UNKNOWN"
DTMCS=$(grep -oE 'DTMCS: 0x0 -> 0x[0-9a-fA-F]+' "$PROBE_STDERR" | tail -n1 | awk '{print $5}' || true)
VERSION=$(grep -oE 'version=0x?[0-9a-fA-F]+' "$PROBE_STDERR" | tail -n1 | cut -d= -f2 || true)
ABITS=$(grep -oE 'abits=0x?[0-9a-fA-F]+' "$PROBE_STDERR" | tail -n1 | cut -d= -f2 || true)

if grep -q 'Examined RISC-V core' "$PROBE_STDERR"; then
  CLASSIFICATION='DM_PROGRESS'
elif grep -q 'Unsupported DTM version' "$PROBE_STDERR"; then
  CLASSIFICATION='UNSUPPORTED_DTM'
elif grep -q 'abits=0' "$PROBE_STDERR"; then
  CLASSIFICATION='ABITS_ZERO'
elif [[ -n "${DTMCS:-}" ]]; then
  CLASSIFICATION='DTM_SEEN'
fi

SUMMARY="$OUTDIR/summary.txt"
{
  echo "BITFILE=$BITFILE"
  echo "OUTER_IR=$OUTER_IR"
  echo "TUNNEL_TYPE=$TUNNEL_TYPE"
  echo "SKIP_PLD_LOAD=$SKIP_PLD_LOAD"
  echo "CLASSIFICATION=$CLASSIFICATION"
  echo "DTMCS=${DTMCS:-}"
  echo "VERSION=${VERSION:-}"
  echo "ABITS=${ABITS:-}"
  echo "LOAD_STDERR=$LOAD_STDERR"
  echo "PROBE_STDERR=$PROBE_STDERR"
} >"$SUMMARY"

cat "$SUMMARY"
