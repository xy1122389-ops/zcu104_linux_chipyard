#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
OUTDIR="$FPGA_DIR/logs/orthogonal_width_payloadlen_probe_$(date +%Y%m%d_%H%M%S)"
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

mkprobe() {
  local mode="$1"
  local wfield="$2"
  local plen="$3"
  local payload="$4"
  if [[ "$mode" == "0" ]]; then
    cat <<EOF
irscan uscale.ps $OUTER_IR
set sel [drscan uscale.ps 1 0 7 0x$(printf '%02x' "$wfield") $plen $payload 3 0]
echo SEL=\$sel
irscan uscale.ps $OUTER_IR
set dt [drscan uscale.ps 1 1 7 0x20 33 0x0 3 0]
echo DTMCS=\$dt
shutdown
EOF
  else
    cat <<EOF
irscan uscale.ps $OUTER_IR
set sel [drscan uscale.ps 3 0 $plen $payload 7 0x$(printf '%02x' "$wfield") 1 0]
echo SEL=\$sel
irscan uscale.ps $OUTER_IR
set dt [drscan uscale.ps 1 1 7 0x20 33 0x0 3 0]
echo DTMCS=\$dt
shutdown
EOF
  fi
}

declare -a combos=(
  "mode0_w6_len5 0 6 5 0x10"
  "mode0_w8_len5 0 8 5 0x10"
  "mode1_w6_len5 1 6 5 0x10"
  "mode1_w8_len5 1 8 5 0x10"
  "mode0_w5_len7 0 5 7 0x10"
  "mode1_w5_len7 1 5 7 0x10"
)

for combo in "${combos[@]}"; do
  read -r name mode wfield plen payload <<<"$combo"
  run_one "$name" < <(mkprobe "$mode" "$wfield" "$plen" "$payload")
done

python3 - <<'PY' "$OUTDIR" >"$OUTDIR/summary.txt"
from pathlib import Path
import re, sys
outdir = Path(sys.argv[1])
print(f"OUTDIR={outdir}")
for log in sorted(outdir.glob("*.stderr.log")):
    txt = log.read_text(errors="ignore")
    sel = re.search(r"SEL=([0-9A-Fa-f\n]+)\n", txt)
    dt = re.search(r"DTMCS=([0-9A-Fa-f\n]+)\n", txt)
    sel_txt = "/".join(sel.group(1).strip().splitlines()) if sel else "MISSING"
    dt_txt = "/".join(dt.group(1).strip().splitlines()) if dt else "MISSING"
    print(f"{log.stem} SEL={sel_txt} DTMCS={dt_txt}")
PY

cat "$OUTDIR/summary.txt"
