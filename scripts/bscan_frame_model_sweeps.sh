#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
OUTDIR="$FPGA_DIR/logs/bscan_frame_model_sweeps_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"

OPENOCD_EXE="${OPENOCD_EXE:-/tmp/riscv-collab-openocd/bin/openocd.exe}"
OPENOCD_SCRIPTS="${OPENOCD_SCRIPTS:-/tmp/riscv-collab-openocd/share/openocd/scripts}"

mkbase() {
  cat <<'EOF'
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
init
EOF
}

run_one() {
  local name="$1"
  local cfg="$OUTDIR/$name.cfg"
  shift
  {
    mkbase
    cat
  } >"$cfg"

  cmd.exe /c "pushd C:\\ && taskkill /F /IM openocd.exe /IM hw_server.exe" >/dev/null 2>&1 || true
  python3 - <<'PY' "$OPENOCD_EXE" "$OPENOCD_SCRIPTS" "$cfg" "$OUTDIR/$name.stderr.log"
import subprocess, sys
exe, scripts, cfg, err = sys.argv[1:]
cfg_win = subprocess.check_output(["wslpath", "-w", cfg], text=True).strip()
with open(err, "w") as fe:
    p = subprocess.Popen([exe, "-s", scripts, "-f", cfg_win], stdout=subprocess.DEVNULL, stderr=fe)
    try:
        p.wait(timeout=20)
        print(f"STATUS=EXIT:{p.returncode}")
    except subprocess.TimeoutExpired:
        p.kill()
        print("STATUS=TIMEOUT")
PY
}

for a in 0x10 0x11 0x12 0x13; do
  run_one "ir_pair_mode0_${a}" <<EOF
irscan uscale.ps 0x926
set pa [drscan uscale.ps 1 0 7 0x05 5 $a 3 0]
echo A=\$pa
irscan uscale.ps 0x926
set pb [drscan uscale.ps 1 0 7 0x05 5 0x00 3 0]
echo B=\$pb
shutdown
EOF
done

for a in 0x10 0x11; do
  run_one "ir_pair_mode1_${a}" <<EOF
irscan uscale.ps 0x926
set pa [drscan uscale.ps 3 0 5 $a 7 0x05 1 0]
echo A=\$pa
irscan uscale.ps 0x926
set pb [drscan uscale.ps 3 0 5 0x00 7 0x05 1 0]
echo B=\$pb
shutdown
EOF
done

for p in 0x00 0x01 0x02 0x04 0x08 0x10 0x1f; do
  run_one "dmi_after_payload_${p}" <<EOF
irscan uscale.ps 0x926
set sel [drscan uscale.ps 1 0 7 0x05 5 $p 3 0]
echo SEL=\$sel
irscan uscale.ps 0x926
set req [drscan uscale.ps 1 1 7 0x29 42 0x4400000001 3 0]
echo REQ=\$req
runtest 6
irscan uscale.ps 0x926
set nop [drscan uscale.ps 1 1 7 0x29 42 0x0 3 0]
echo NOP=\$nop
shutdown
EOF
done

for p in 0x08 0x09 0x10 0x18; do
  run_one "dtmcs_after_payload_${p}" <<EOF
irscan uscale.ps 0x926
set sel [drscan uscale.ps 1 0 7 0x05 5 $p 3 0]
echo SEL=\$sel
irscan uscale.ps 0x926
set dt [drscan uscale.ps 1 1 7 0x20 33 0x0 3 0]
echo DTMCS=\$dt
shutdown
EOF
done

{
  echo "OUTDIR=$OUTDIR"
  for f in "$OUTDIR"/*.stderr.log; do
    echo "==== $(basename "$f")"
    sed -n '1,120p' "$f"
  done
} >"$OUTDIR/summary.txt"

cat "$OUTDIR/summary.txt"
