#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
OUTDIR="$FPGA_DIR/logs/manual_ir_select_plus1_probe_$(date +%Y%m%d_%H%M%S)"
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

mkmode0() {
  local payload6="$1"
  cat <<EOF
irscan uscale.ps $OUTER_IR
set sel [drscan uscale.ps 1 0 7 0x05 6 $payload6 3 0]
echo SEL=\$sel
irscan uscale.ps $OUTER_IR
set dt [drscan uscale.ps 1 1 7 0x20 33 0x0 3 0]
echo DTMCS=\$dt
shutdown
EOF
}

mkmode1() {
  local payload6="$1"
  cat <<EOF
irscan uscale.ps $OUTER_IR
set sel [drscan uscale.ps 3 0 6 $payload6 7 0x05 1 0]
echo SEL=\$sel
irscan uscale.ps $OUTER_IR
set dt [drscan uscale.ps 1 1 7 0x20 33 0x0 3 0]
echo DTMCS=\$dt
shutdown
EOF
}

# Candidate 6-bit payload encodings for desired 5-bit IR:
# raw      : 0b0iiii i  -> value=ir
# lshift0  : 0biiiii0 -> value=(ir << 1)
# raw_hi1  : 0b1iiii i  -> value=ir | 0x20
# lshift1  : 0biiiii1 -> value=(ir << 1) | 1
declare -A CANDIDATES=(
  [dtmcs_raw]=0x10
  [dtmcs_lshift0]=0x20
  [dtmcs_raw_hi1]=0x30
  [dtmcs_lshift1]=0x21
  [dbus_raw]=0x11
  [dbus_lshift0]=0x22
  [dbus_raw_hi1]=0x31
  [dbus_lshift1]=0x23
)

for name in "${!CANDIDATES[@]}"; do
  payload="${CANDIDATES[$name]}"
  run_one "mode0_${name}" < <(mkmode0 "$payload")
  run_one "mode1_${name}" < <(mkmode1 "$payload")
done

python3 - <<'PY' "$OUTDIR" >"$OUTDIR/summary.txt"
from pathlib import Path
import re, sys
outdir = Path(sys.argv[1])
rows = []
for log in sorted(outdir.glob("*.stderr.log")):
    txt = log.read_text(errors="ignore")
    sel = re.search(r"SEL=([0-9A-Fa-f\n]+)\n", txt)
    dt = re.search(r"DTMCS=([0-9A-Fa-f\n]+)\n", txt)
    rows.append((log.stem, "/".join(sel.group(1).strip().splitlines()) if sel else "MISSING", "/".join(dt.group(1).strip().splitlines()) if dt else "MISSING"))
print(f"OUTDIR={outdir}")
for name, sel, dt in rows:
    print(f"{name} SEL={sel} DTMCS={dt}")
PY

cat "$OUTDIR/summary.txt"
