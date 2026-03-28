#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

if [[ $# -lt 4 ]]; then
  echo "Usage: $0 <ila_dir> <label> <dmcontrol_case:dmactive|haltreq|resumereq> <read_addr_hex> [jtag_hz]" >&2
  exit 2
fi

ILA_DIR="$1"
LABEL="$2"
CASE_NAME="$3"
READ_ADDR="$4"
JTAG_HZ="${5:-10000}"
SELECT_PAYLOAD="${SELECT_PAYLOAD:-0x10}"
PRE_READ_NOPS="${PRE_READ_NOPS:-2}"
POST_READ_NOPS="${POST_READ_NOPS:-2}"
STAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="$FPGA_DIR/logs/jtagtunnel_ila_inline_${LABEL}_${STAMP}"
mkdir -p "$OUTDIR"
XSDB_SCRIPT="$OUTDIR/xsdb_control_read_addr_case.tcl"

case "$CASE_NAME" in
  dmactive) DMCONTROL_DATA=0x00000001 ;;
  haltreq)  DMCONTROL_DATA=0x80000001 ;;
  resumereq) DMCONTROL_DATA=0x40000001 ;;
  *)
    echo "Unknown dmcontrol case: $CASE_NAME" >&2
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

pack_dmi_read_addr() {
  python3 - "$1" <<'PY'
import sys
addr = int(sys.argv[1], 16)
v = 0
shift = 0
def add(nbits, value):
    global v, shift
    v |= (value & ((1 << nbits) - 1)) << shift
    shift += nbits
add(1, 1)
add(7, 0x29)
add(42, (addr << 34) | 0x1)
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
read -r wr_bits wr_val < <(pack_dmi_write_dmcontrol "$DMCONTROL_DATA")
read -r rd_bits rd_val < <(pack_dmi_read_addr "$READ_ADDR")
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
\$seq drshift -capture -integer $wr_bits $wr_val
puts "WRITE_$CASE_NAME=[\$seq run -hex]"
EOF

for i in $(seq 1 "$PRE_READ_NOPS"); do
  cat >>"$XSDB_SCRIPT" <<EOF
set seq [jtag sequence]
\$seq irshift -integer 12 0x926
\$seq drshift -capture -integer $nop_bits $nop_val
puts "PRENOP${i}_$CASE_NAME=[\$seq run -hex]"
EOF
done

cat >>"$XSDB_SCRIPT" <<EOF
set seq [jtag sequence]
\$seq irshift -integer 12 0x926
\$seq drshift -capture -integer $rd_bits $rd_val
puts "READ_${READ_ADDR}_$CASE_NAME=[\$seq run -hex]"
EOF

for i in $(seq 1 "$POST_READ_NOPS"); do
  cat >>"$XSDB_SCRIPT" <<EOF
set seq [jtag sequence]
\$seq irshift -integer 12 0x926
\$seq drshift -capture -integer $nop_bits $nop_val
puts "POSTNOP${i}_${READ_ADDR}_$CASE_NAME=[\$seq run -hex]"
EOF
done

echo "exit" >>"$XSDB_SCRIPT"

pkill -f 'capture_jtagtunnel_ila_inline_stim.sh' || true
pkill -f 'capture_jtagtunnel_ila_inline_xsdbseq.sh' || true
pkill -f 'run_shiftwindow_inline_matrix.sh' || true
"$SCRIPT_DIR/restart_hw_server_windows.sh" >/dev/null

"$SCRIPT_DIR/capture_jtagtunnel_ila_inline_xsdbseq.sh" "$ILA_DIR" "$LABEL" "$XSDB_SCRIPT" "$JTAG_HZ"
