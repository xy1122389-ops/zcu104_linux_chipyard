#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
OUTDIR="$FPGA_DIR/logs/bscan_nested_select_sweep_$(date +%Y%m%d_%H%M%S)"
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

payloads=(0x08 0x09 0x10 0x11 0x12 0x18)
widths=(4 5 6 7 8)

for w in "${widths[@]}"; do
  for p in "${payloads[@]}"; do
    run_one "mode0_w${w}_p${p#0x}" <<EOF
irscan uscale.ps $OUTER_IR
set sel [drscan uscale.ps 1 0 7 0x05 $w $p 3 0]
echo SEL=\$sel
irscan uscale.ps $OUTER_IR
set dt [drscan uscale.ps 1 1 7 0x20 33 0x0 3 0]
echo DTMCS=\$dt
shutdown
EOF
  done
done

for w in "${widths[@]}"; do
  for p in "${payloads[@]}"; do
    run_one "mode1_w${w}_p${p#0x}" <<EOF
irscan uscale.ps $OUTER_IR
set sel [drscan uscale.ps 3 0 $w $p 7 0x05 1 0]
echo SEL=\$sel
irscan uscale.ps $OUTER_IR
set dt [drscan uscale.ps 1 1 7 0x20 33 0x0 3 0]
echo DTMCS=\$dt
shutdown
EOF
  done
done

python3 - <<'PY' "$OUTDIR" >"$OUTDIR/summary.txt"
from pathlib import Path
import re, sys

outdir = Path(sys.argv[1])
pat = re.compile(r"(mode[01])_w(\d+)_p([0-9a-f]+)\.stderr\.log")
seen = []
for log in sorted(outdir.glob("*.stderr.log")):
    m = pat.fullmatch(log.name)
    if not m:
        continue
    mode, width, payload = m.groups()
    text = log.read_text(errors="ignore")
    fields = {}
    for key in ("SEL", "DTMCS"):
        mm = re.search(rf"{key}=([0-9A-Fa-f\n]+)\n", text)
        if mm:
            fields[key] = "/".join([x for x in mm.group(1).strip().splitlines() if x])
        else:
            fields[key] = "MISSING"
    seen.append((mode, int(width), payload, fields["SEL"], fields["DTMCS"]))

print(f"OUTDIR={outdir}")
print("MODE WIDTH PAYLOAD SEL DTMCS")
for row in seen:
    print("%s %d 0x%s %s %s" % row)

def uniq(rows, idx):
    return sorted(set(r[idx] for r in rows))

for mode in ("mode0", "mode1"):
    rows = [r for r in seen if r[0] == mode]
    print(f"== {mode} unique SEL count = {len(uniq(rows, 3))}")
    for v in uniq(rows, 3):
        print(f"SEL {v}")
    print(f"== {mode} unique DTMCS count = {len(uniq(rows, 4))}")
    for v in uniq(rows, 4):
        print(f"DTMCS {v}")
PY

cat "$OUTDIR/summary.txt"
