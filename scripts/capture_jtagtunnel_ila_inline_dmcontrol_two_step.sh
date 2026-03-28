#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <ila_dir> <label> <sequence:haltreq_then_resumereq|haltreq_then_dmactive> [jtag_hz]" >&2
  exit 2
fi

ILA_DIR="$1"
LABEL="$2"
SEQ_NAME="$3"
JTAG_HZ="${4:-10000}"
SELECT_PAYLOAD="${SELECT_PAYLOAD:-0x10}"
STAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="$FPGA_DIR/logs/jtagtunnel_ila_inline_${LABEL}_${STAMP}"
mkdir -p "$OUTDIR"
XSDB_SCRIPT="$OUTDIR/xsdb_dmcontrol_two_step.tcl"

case "$SEQ_NAME" in
  haltreq_then_resumereq)
    STEP1=0x80000001
    STEP2=0x40000001
    ;;
  haltreq_then_dmactive)
    STEP1=0x80000001
    STEP2=0x00000001
    ;;
  *)
    echo "Unknown sequence: $SEQ_NAME" >&2
    exit 2
    ;;
esac

pack_select_dbus() {
  python3 - "$SELECT_PAYLOAD" <<'PY'
import sys
payload = int(sys.argv[1], 16)
v = 0
shift = 0
def add(nbits, value):
    global v, shift
    v |= (value & ((1 << nbits) - 1)) << shift
    shift += nbits
add(1, 0)
add(7, 0x05)
add(5, payload)
add(3, 0)
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

pack_dmi_write_dmcontrol() {
  python3 - "$1" <<'PY'
import sys
data = int(sys.argv[1], 16)
v = 0
shift = 0
def add(nbits, value):
    global v, shift
    v |= (value & ((1 << nbits) - 1)) << shift
    shift += nbits
add(1, 1)
add(7, 0x29)
add(42, (0x10 << 34) | (data << 2) | 0x2)
add(3, 0)
print(f"{shift} 0x{v:x}")
PY
}

pack_dmi_read_dmstatus() {
  python3 - <<'PY'
v = 0
shift = 0
def add(nbits, value):
    global v, shift
    v |= (value & ((1 << nbits) - 1)) << shift
    shift += nbits
add(1, 1)
add(7, 0x29)
add(42, 0x4400000001)
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

read -r sel_bits sel_val < <(pack_select_dbus)
read -r dt_bits dt_val < <(pack_dtmcs)
read -r w1_bits w1_val < <(pack_dmi_write_dmcontrol "$STEP1")
read -r w2_bits w2_val < <(pack_dmi_write_dmcontrol "$STEP2")
read -r rd_bits rd_val < <(pack_dmi_read_dmstatus)
read -r nop_bits nop_val < <(pack_dmi_nop)

cat >"$XSDB_SCRIPT" <<EOF
connect -url tcp:127.0.0.1:3121
jtag targets -set -filter {name == "xczu7"}
jtag frequency $JTAG_HZ
set seq [jtag sequence]
\$seq irshift -integer 12 0x926
\$seq drshift -capture -integer $sel_bits $sel_val
puts "SEL=[\$seq run -hex]"
set seq [jtag sequence]
\$seq irshift -integer 12 0x926
\$seq drshift -capture -integer $dt_bits $dt_val
puts "DTMCS=[\$seq run -hex]"
set seq [jtag sequence]
\$seq irshift -integer 12 0x926
\$seq drshift -capture -integer $w1_bits $w1_val
puts "WRITE1_$SEQ_NAME=[\$seq run -hex]"
set seq [jtag sequence]
\$seq irshift -integer 12 0x926
\$seq drshift -capture -integer $nop_bits $nop_val
puts "NOP1_$SEQ_NAME=[\$seq run -hex]"
set seq [jtag sequence]
\$seq irshift -integer 12 0x926
\$seq drshift -capture -integer $w2_bits $w2_val
puts "WRITE2_$SEQ_NAME=[\$seq run -hex]"
set seq [jtag sequence]
\$seq irshift -integer 12 0x926
\$seq drshift -capture -integer $nop_bits $nop_val
puts "NOP2_$SEQ_NAME=[\$seq run -hex]"
set seq [jtag sequence]
\$seq irshift -integer 12 0x926
\$seq drshift -capture -integer $rd_bits $rd_val
puts "READ_DMSTATUS_$SEQ_NAME=[\$seq run -hex]"
set seq [jtag sequence]
\$seq irshift -integer 12 0x926
\$seq drshift -capture -integer $nop_bits $nop_val
puts "NOPR1_$SEQ_NAME=[\$seq run -hex]"
set seq [jtag sequence]
\$seq irshift -integer 12 0x926
\$seq drshift -capture -integer $nop_bits $nop_val
puts "NOPR2_$SEQ_NAME=[\$seq run -hex]"
exit
EOF

pkill -f 'capture_jtagtunnel_ila_inline_stim.sh' || true
pkill -f 'capture_jtagtunnel_ila_inline_xsdbseq.sh' || true
pkill -f 'run_shiftwindow_inline_matrix.sh' || true
"$SCRIPT_DIR/restart_hw_server_windows.sh" >/dev/null

"$SCRIPT_DIR/capture_jtagtunnel_ila_inline_xsdbseq.sh" "$ILA_DIR" "$LABEL" "$XSDB_SCRIPT" "$JTAG_HZ"
