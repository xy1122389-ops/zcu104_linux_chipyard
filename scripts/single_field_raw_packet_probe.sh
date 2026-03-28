#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
OUTDIR="$FPGA_DIR/logs/single_field_raw_packet_probe_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"

OPENOCD_EXE="${OPENOCD_EXE:-/tmp/riscv-collab-openocd/bin/openocd.exe}"
OPENOCD_SCRIPTS="${OPENOCD_SCRIPTS:-/tmp/riscv-collab-openocd/share/openocd/scripts}"
OUTER_IR="${OUTER_IR:-0x926}"
SPEED="${SPEED:-1000}"

mkbase() {
  cat <<EOF
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

pack_mode0() {
  python3 - <<'PY' "$1" "$2"
import sys
width = int(sys.argv[1])
payload = int(sys.argv[2], 16)
v = 0
shift = 0
def add(nbits, value):
    global v, shift
    v |= (value & ((1 << nbits) - 1)) << shift
    shift += nbits
add(1, 0)
add(7, width)
add(width, payload)
add(3, 0)
print(f"{shift} 0x{v:x}")
PY
}

pack_mode1() {
  python3 - <<'PY' "$1" "$2"
import sys
width = int(sys.argv[1])
payload = int(sys.argv[2], 16)
v = 0
shift = 0
def add(nbits, value):
    global v, shift
    v |= (value & ((1 << nbits) - 1)) << shift
    shift += nbits
add(3, 0)
add(width, payload)
add(7, width)
add(1, 0)
print(f"{shift} 0x{v:x}")
PY
}

pack_dtmcs() {
  python3 - <<'PY'
v = 0
shift = 0
def add(nbits, value):
    global v, shift
    v |= (value & ((1 << nbits) - 1)) << shift
    shift += nbits
add(1, 1)
add(7, 0x20)
add(33, 0)
add(3, 0)
print(f"{shift} 0x{v:x}")
PY
}

pack_dmi_read() {
  python3 - <<'PY' "$1"
import sys
addr = int(sys.argv[1], 16)
payload = (addr << 34) | 0x1
v = 0
shift = 0
def add(nbits, value):
    global v, shift
    v |= (value & ((1 << nbits) - 1)) << shift
    shift += nbits
add(1, 1)
add(7, 0x29)
add(42, payload)
add(3, 0)
print(f"{shift} 0x{v:x}")
PY
}

pack_dmi_nop() {
  python3 - <<'PY'
v = 0
shift = 0
def add(nbits, value):
    global v, shift
    v |= (value & ((1 << nbits) - 1)) << shift
    shift += nbits
add(1, 1)
add(7, 0x29)
add(42, 0)
add(3, 0)
print(f"{shift} 0x{v:x}")
PY
}

mkprobe() {
  local mode="$1"
  local width="$2"
  local payload="$3"
  local selbits selval dtbits dtval reqbits reqval nopbits nopval
  if [[ "$mode" == "0" ]]; then
    read -r selbits selval < <(pack_mode0 "$width" "$payload")
  else
    read -r selbits selval < <(pack_mode1 "$width" "$payload")
  fi
  read -r dtbits dtval < <(pack_dtmcs)
  read -r reqbits reqval < <(pack_dmi_read 0x10)
  read -r nopbits nopval < <(pack_dmi_nop)
  cat <<EOF
irscan uscale.ps $OUTER_IR
set sel [drscan uscale.ps $selbits $selval]
echo SEL=\$sel
irscan uscale.ps $OUTER_IR
set dt [drscan uscale.ps $dtbits $dtval]
echo DTMCS=\$dt
irscan uscale.ps $OUTER_IR
set req [drscan uscale.ps $reqbits $reqval]
echo REQ=\$req
runtest 6
irscan uscale.ps $OUTER_IR
set nop1 [drscan uscale.ps $nopbits $nopval]
echo NOP1=\$nop1
shutdown
EOF
}

declare -a combos=(
  "mode0_w5_p10 0 5 0x10"
  "mode0_w8_p10 0 8 0x10"
  "mode1_w5_p10 1 5 0x10"
  "mode1_w8_p10 1 8 0x10"
)

for combo in "${combos[@]}"; do
  read -r name mode width payload <<<"$combo"
  run_one "$name" < <(mkprobe "$mode" "$width" "$payload")
done

python3 - <<'PY' "$OUTDIR" >"$OUTDIR/summary.txt"
from pathlib import Path
import re, sys
outdir = Path(sys.argv[1])
print(f"OUTDIR={outdir}")
for log in sorted(outdir.glob("*.stderr.log")):
    txt = log.read_text(errors="ignore")
    vals = {}
    for key in ("SEL", "DTMCS", "REQ", "NOP1"):
        m = re.search(rf"{key}=([0-9A-Fa-f\n]+)\n", txt)
        vals[key] = "/".join(m.group(1).strip().splitlines()) if m else "MISSING"
    print(f"{log.stem} SEL={vals['SEL']} DTMCS={vals['DTMCS']} REQ={vals['REQ']} NOP1={vals['NOP1']}")
PY

cat "$OUTDIR/summary.txt"
