#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
BITFILE_DEFAULT="$FPGA_DIR/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupDebugConfig/obj/ZCU104FPGATestHarness.bit"
BITFILE="${1:-$BITFILE_DEFAULT}"

OPENOCD_EXE_DEFAULT='/mnt/c/Users/24242/AppData/Local/Microsoft/WinGet/Packages/xpack-dev-tools.openocd-xpack_Microsoft.Winget.Source_8wekyb3d8bbwe/xpack-openocd-0.12.0-7/bin/openocd.exe'
OPENOCD_SCRIPTS_DEFAULT='/mnt/c/Users/24242/AppData/Local/Microsoft/WinGet/Packages/xpack-dev-tools.openocd-xpack_Microsoft.Winget.Source_8wekyb3d8bbwe/xpack-openocd-0.12.0-7/openocd/scripts'
OPENOCD_EXE="${OPENOCD_EXE:-$OPENOCD_EXE_DEFAULT}"
OPENOCD_SCRIPTS="${OPENOCD_SCRIPTS:-$OPENOCD_SCRIPTS_DEFAULT}"

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

STAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="$FPGA_DIR/logs/openocd_probe_riscv_bscan_abits_$STAMP"
mkdir -p "$OUTDIR"

WIN_TEMP_DIR='/mnt/c/Users/24242/AppData/Local/Temp'
WIN_BIT="$WIN_TEMP_DIR/ZCU104FPGATestHarness_debug_chainpos1.bit"
cp -f "$BITFILE" "$WIN_BIT"

WIN_LOAD_CFG="$WIN_TEMP_DIR/openocd_pld_load_debug_chainpos1.cfg"
cat >"$WIN_LOAD_CFG" <<'EOF'
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
reset_config none
transport select jtag
adapter speed 1000
source [find target/xilinx_zynqmp.cfg]
pld create uscale.pld virtex2 -chain-position uscale.ps -no_jstart
init
pld load 0 C:/Users/24242/AppData/Local/Temp/ZCU104FPGATestHarness_debug_chainpos1.bit
shutdown
EOF

WIN_PROBE_CFG="$WIN_TEMP_DIR/openocd_probe_riscv_bscan_abits_chainpos1.cfg"
cat >"$WIN_PROBE_CFG" <<'EOF'
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
reset_config none
transport select jtag
adapter speed 1000
source [find target/xilinx_zynqmp.cfg]
target create riscv_bscan_ps riscv -chain-position uscale.ps
targets riscv_bscan_ps
riscv use_bscan_tunnel 5
init
targets
shutdown
EOF

LOAD_STDOUT="$OUTDIR/pld_load.stdout.log"
LOAD_STDERR="$OUTDIR/pld_load.stderr.log"
PROBE_STDOUT="$OUTDIR/probe.stdout.log"
PROBE_STDERR="$OUTDIR/probe.stderr.log"

"$OPENOCD_EXE" -s "$OPENOCD_SCRIPTS" -f "$(wslpath -w "$WIN_LOAD_CFG")" >"$LOAD_STDOUT" 2>"$LOAD_STDERR"
"$OPENOCD_EXE" -s "$OPENOCD_SCRIPTS" -f "$(wslpath -w "$WIN_PROBE_CFG")" >"$PROBE_STDOUT" 2>"$PROBE_STDERR"

CLASSIFICATION="UNKNOWN"
ABITS=$(grep -oE 'abits=([0-9]+)' "$PROBE_STDERR" | tail -n1 | cut -d= -f2 || true)
DTMCONTROL=$(grep -oE 'dtmcontrol=0x[0-9a-fA-F]+' "$PROBE_STDERR" | tail -n1 | cut -d= -f2 || true)

if grep -q 'unsupported DTM version' "$PROBE_STDERR"; then
  CLASSIFICATION='UNSUPPORTED_DTM_VERSION'
elif grep -q 'abits=0' "$PROBE_STDERR"; then
  CLASSIFICATION='ABITS_ZERO'
elif [[ -n "${ABITS:-}" ]]; then
  CLASSIFICATION='ABITS_NONZERO'
elif grep -q 'libusb_open() failed' "$PROBE_STDERR"; then
  CLASSIFICATION='OPEN_DEVICE_FAILED'
fi

SUMMARY="$OUTDIR/summary.txt"
{
  echo "BITFILE=$BITFILE"
  echo "WIN_BIT=$WIN_BIT"
  echo "CLASSIFICATION=$CLASSIFICATION"
  echo "DTMCONTROL=${DTMCONTROL:-}"
  echo "ABITS=${ABITS:-}"
  echo "LOAD_STDOUT=$LOAD_STDOUT"
  echo "LOAD_STDERR=$LOAD_STDERR"
  echo "PROBE_STDOUT=$PROBE_STDOUT"
  echo "PROBE_STDERR=$PROBE_STDERR"
} >"$SUMMARY"

cat "$SUMMARY"
