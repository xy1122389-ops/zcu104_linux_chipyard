#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

OPENOCD_EXE="${OPENOCD_EXE:-/tmp/riscv-collab-openocd/bin/openocd.exe}"
OPENOCD_SCRIPTS="${OPENOCD_SCRIPTS:-/tmp/riscv-collab-openocd/share/openocd/scripts}"
STAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="$FPGA_DIR/logs/manual_dmi_minimal_validation_$STAMP"
mkdir -p "$OUTDIR"

BASE_CFG="$OUTDIR/base_header.cfg"
cat >"$BASE_CFG" <<'EOF'
adapter driver ftdi
ftdi vid_pid 0x0403 0x6011
adapter serial 07198
ftdi channel 0
ftdi layout_init 0x00e8 0x60eb
transport select jtag
reset_config none
adapter speed 1000
set _CHIPNAME uscale
jtag newtap $_CHIPNAME tap -irlen 4 -ircapture 0x1 -irmask 0xf -expected-id 0x5ba00477
jtag newtap $_CHIPNAME ps -irlen 12 -ircapture 0x1 -irmask 0x03 -ignore-version \
  -expected-id 0x04711093 -expected-id 0x04710093 -expected-id 0x04721093 -expected-id 0x04720093 \
  -expected-id 0x04739093 -expected-id 0x04730093 -expected-id 0x04738093 -expected-id 0x04740093 \
  -expected-id 0x04750093 -expected-id 0x04759093 -expected-id 0x04758093
set jtag_configured 0
jtag configure $_CHIPNAME.ps -event setup {
  global _CHIPNAME
  global jtag_configured
  if { $jtag_configured == 0 } {
    irscan $_CHIPNAME.ps 0x824
    drscan $_CHIPNAME.ps 32 0x00000003
    runtest 100
    set jtag_configured 1
    jtag arp_init
  }
}
proc seldbus {} {
  irscan uscale.ps 0x926
  set x [drscan uscale.ps 1 0 7 0x05 5 0x11 3 0]
  echo SEL=$x
}
proc dmiscan {label val} {
  irscan uscale.ps 0x926
  set x [drscan uscale.ps 1 1 7 0x29 42 $val 3 0]
  echo "$label=$x"
  runtest 6
}
EOF

run_cfg() {
  local name="$1"
  local cfg="$2"
  local timeout_s="${3:-20}"
  cmd.exe /c "pushd C:\\ && taskkill /F /IM openocd.exe /IM hw_server.exe" >/dev/null 2>&1 || true
  python3 - <<'PY' "$OPENOCD_EXE" "$OPENOCD_SCRIPTS" "$cfg" "$OUTDIR/$name.stderr.log" "$timeout_s"
import subprocess
import sys
from pathlib import Path

exe, scripts, cfg, stderr_log, timeout_s = sys.argv[1:]
cfg_win = subprocess.check_output(["wslpath", "-w", cfg], text=True).strip()
with open(stderr_log, "w") as fe:
    p = subprocess.Popen([exe, "-s", scripts, "-f", cfg_win], stdout=subprocess.DEVNULL, stderr=fe)
    try:
        p.wait(timeout=int(timeout_s))
        print(f"STATUS=EXIT:{p.returncode}")
    except subprocess.TimeoutExpired:
        p.kill()
        print("STATUS=TIMEOUT")
PY
}

make_read_cfg() {
  local addr="$1"
  local cfg="$OUTDIR/read_${addr}.cfg"
  local req
  req=$(python3 - <<PY
addr = int("$addr", 16)
print(hex((addr << 34) | 0x1))
PY
)
  cat "$BASE_CFG" >"$cfg"
  cat >>"$cfg" <<EOF
init
seldbus
dmiscan REQ_$addr $req
dmiscan NOP1_$addr 0x0
dmiscan NOP2_$addr 0x0
dmiscan NOP3_$addr 0x0
shutdown
EOF
  echo "$cfg"
}

make_dmcontrol_cfg() {
  local name="$1"
  local data="$2"
  local cfg="$OUTDIR/${name}.cfg"
  local req
  req=$(python3 - <<PY
data = int("$data", 16)
print(hex((0x10 << 34) | (data << 2) | 0x2))
PY
)
  cat "$BASE_CFG" >"$cfg"
  cat >>"$cfg" <<EOF
init
seldbus
dmiscan WRITE_${name} $req
dmiscan NOP1_${name} 0x0
dmiscan NOP2_${name} 0x0
dmiscan READ_DMSTATUS_${name} 0x4400000001
dmiscan NOPR1_${name} 0x0
dmiscan NOPR2_${name} 0x0
shutdown
EOF
  echo "$cfg"
}

{
  echo "OPENOCD_EXE=$OPENOCD_EXE"
  echo "OPENOCD_SCRIPTS=$OPENOCD_SCRIPTS"
} >"$OUTDIR/summary.txt"

for addr in 0x10 0x11 0x12 0x16; do
  cfg=$(make_read_cfg "$addr")
  {
    echo "=== READ $addr ==="
    run_cfg "read_${addr}" "$cfg" 20
    sed -n '1,160p' "$OUTDIR/read_${addr}.stderr.log"
    echo
  } >>"$OUTDIR/summary.txt"
done

declare -A DMCONTROL_CASES=(
  [dmactive]=0x00000001
  [haltreq]=0x80000001
)

for name in "${!DMCONTROL_CASES[@]}"; do
  cfg=$(make_dmcontrol_cfg "$name" "${DMCONTROL_CASES[$name]}")
  {
    echo "=== DMCONTROL $name ==="
    run_cfg "$name" "$cfg" 20
    sed -n '1,180p' "$OUTDIR/$name.stderr.log"
    echo
  } >>"$OUTDIR/summary.txt"
done

cat "$OUTDIR/summary.txt"
