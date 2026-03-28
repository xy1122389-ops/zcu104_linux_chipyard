#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

OPENOCD_EXE="${OPENOCD_EXE:-/tmp/riscv-collab-openocd/bin/openocd.exe}"
OPENOCD_SCRIPTS="${OPENOCD_SCRIPTS:-/tmp/riscv-collab-openocd/share/openocd/scripts}"
OUTER_IR="${OUTER_IR:-0x926}"
SPEED="${SPEED:-1000}"
MODE="${MODE:-0}"      # 0=mode0 packet, 1=mode1 packet
SEL_WIDTH="${SEL_WIDTH:-5}"
SEL_PAYLOAD="${SEL_PAYLOAD:-0x10}"

STAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="$FPGA_DIR/logs/manual_dmi_width_validation_m${MODE}_w${SEL_WIDTH}_p${SEL_PAYLOAD#0x}_$STAMP"
mkdir -p "$OUTDIR"

BASE_CFG="$OUTDIR/base_header.cfg"
cat >"$BASE_CFG" <<EOF
adapter driver ftdi
ftdi vid_pid 0x0403 0x6011
adapter serial 07198
ftdi channel 0
ftdi layout_init 0x00e8 0x60eb
transport select jtag
reset_config none
adapter speed $SPEED
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
proc seldbus {} {
  irscan uscale.ps $OUTER_IR
EOF

if [[ "$MODE" == "0" ]]; then
  cat >>"$BASE_CFG" <<EOF
  set x [drscan uscale.ps 1 0 7 0x05 $SEL_WIDTH $SEL_PAYLOAD 3 0]
EOF
else
  cat >>"$BASE_CFG" <<EOF
  set x [drscan uscale.ps 3 0 $SEL_WIDTH $SEL_PAYLOAD 7 0x05 1 0]
EOF
fi

cat >>"$BASE_CFG" <<'EOF'
  echo SEL=$x
}
proc dmiscan {label val} {
  irscan uscale.ps 0x926
  set x [drscan uscale.ps 1 1 7 0x29 42 $val 3 0]
  echo "$label=$x"
  runtest 6
}
proc dtmcsscan {} {
  irscan uscale.ps 0x926
  set x [drscan uscale.ps 1 1 7 0x20 33 0x0 3 0]
  echo DTMCS=$x
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
dtmcsscan
dmiscan REQ_$addr $req
dmiscan NOP1_$addr 0x0
dmiscan NOP2_$addr 0x0
dmiscan NOP3_$addr 0x0
shutdown
EOF
  echo "$cfg"
}

{
  echo "OPENOCD_EXE=$OPENOCD_EXE"
  echo "OPENOCD_SCRIPTS=$OPENOCD_SCRIPTS"
  echo "MODE=$MODE"
  echo "SEL_WIDTH=$SEL_WIDTH"
  echo "SEL_PAYLOAD=$SEL_PAYLOAD"
  echo "OUTER_IR=$OUTER_IR"
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

cat "$OUTDIR/summary.txt"
