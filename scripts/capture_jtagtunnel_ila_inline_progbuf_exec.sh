#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <ila_dir> <label> [jtag_hz]" >&2
  exit 2
fi

ILA_DIR="$1"
LABEL="$2"
JTAG_HZ="${3:-10000}"
SELECT_PAYLOAD="${SELECT_PAYLOAD:-0x10}"
PROGBUF0_WORD="${PROGBUF0_WORD:-0x00100073}"  # ebreak
SKIP_PROGRAM="${SKIP_PROGRAM:-0}"
COMMAND_WORD="${COMMAND_WORD:-0x00241000}"    # access register, aarsize=2, postexec=1, transfer=0, regno=0x1000
STAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="$FPGA_DIR/logs/jtagtunnel_ila_inline_${LABEL}_${STAMP}"
mkdir -p "$OUTDIR"
XSDB_SCRIPT="$OUTDIR/xsdb_progbuf_exec.tcl"

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

pack_dmi_write() {
  python3 - "$1" "$2" <<'PY'
import sys
addr = int(sys.argv[1], 16)
data = int(sys.argv[2], 16)
v = 0
shift = 0
def add(nbits, value):
    global v, shift
    v |= (value & ((1 << nbits) - 1)) << shift
    shift += nbits
add(1, 1)
add(7, 0x29)
add(42, (addr << 34) | (data << 2) | 0x2)
add(3, 0)
print(f"{shift} 0x{v:x}")
PY
}

pack_dmi_read() {
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
read -r halt_bits halt_val < <(pack_dmi_write 0x10 0x80000001)
read -r pbuf_bits pbuf_val < <(pack_dmi_write 0x20 "$PROGBUF0_WORD")
# default run_program from riscv013_execute_progbuf():
# cmdtype=0, aarsize=2, postexec=1, transfer=0, regno=0x1000
# override with COMMAND_WORD to compare postexec/no-postexec semantics.
read -r cmd_bits cmd_val < <(pack_dmi_write 0x17 "$COMMAND_WORD")
read -r rd_abs_bits rd_abs_val < <(pack_dmi_read 0x16)
read -r rd_d0_bits rd_d0_val < <(pack_dmi_read 0x04)
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
\$seq drshift -capture -integer $halt_bits $halt_val
puts "WRITE_HALTREQ=[\$seq run -hex]"
set seq [jtag sequence]
\$seq irshift -integer 12 0x926
\$seq drshift -capture -integer $nop_bits $nop_val
puts "NOP1_HALTREQ=[\$seq run -hex]"
set seq [jtag sequence]
\$seq irshift -integer 12 0x926
\$seq drshift -capture -integer $pbuf_bits $pbuf_val
puts "WRITE_PROGBUF0=[\$seq run -hex]"
set seq [jtag sequence]
\$seq irshift -integer 12 0x926
\$seq drshift -capture -integer $nop_bits $nop_val
puts "NOP1_PROGBUF0=[\$seq run -hex]"
set seq [jtag sequence]
\$seq irshift -integer 12 0x926
\$seq drshift -capture -integer $cmd_bits $cmd_val
puts "WRITE_COMMAND_PROGBUF=[\$seq run -hex]"
set seq [jtag sequence]
\$seq irshift -integer 12 0x926
\$seq drshift -capture -integer $nop_bits $nop_val
puts "NOP1_COMMAND_PROGBUF=[\$seq run -hex]"
set seq [jtag sequence]
\$seq irshift -integer 12 0x926
\$seq drshift -capture -integer $nop_bits $nop_val
puts "NOP2_COMMAND_PROGBUF=[\$seq run -hex]"
set seq [jtag sequence]
\$seq irshift -integer 12 0x926
\$seq drshift -capture -integer $rd_abs_bits $rd_abs_val
puts "READ_ABSTRACTCS_PROGBUF=[\$seq run -hex]"
set seq [jtag sequence]
\$seq irshift -integer 12 0x926
\$seq drshift -capture -integer $nop_bits $nop_val
puts "NOP1_ABSTRACTCS_PROGBUF=[\$seq run -hex]"
set seq [jtag sequence]
\$seq irshift -integer 12 0x926
\$seq drshift -capture -integer $rd_d0_bits $rd_d0_val
puts "READ_DATA0_PROGBUF=[\$seq run -hex]"
set seq [jtag sequence]
\$seq irshift -integer 12 0x926
\$seq drshift -capture -integer $nop_bits $nop_val
puts "NOP1_DATA0_PROGBUF=[\$seq run -hex]"
set seq [jtag sequence]
\$seq irshift -integer 12 0x926
\$seq drshift -capture -integer $nop_bits $nop_val
puts "NOP2_DATA0_PROGBUF=[\$seq run -hex]"
exit
EOF

pkill -f 'capture_jtagtunnel_ila_inline_stim.sh' || true
pkill -f 'capture_jtagtunnel_ila_inline_xsdbseq.sh' || true
pkill -f 'run_shiftwindow_inline_matrix.sh' || true
if [[ "$SKIP_PROGRAM" != "1" ]]; then
  "$SCRIPT_DIR/restart_hw_server_windows.sh" >/dev/null
fi

SKIP_PROGRAM="$SKIP_PROGRAM" "$SCRIPT_DIR/capture_jtagtunnel_ila_inline_xsdbseq.sh" "$ILA_DIR" "$LABEL" "$XSDB_SCRIPT" "$JTAG_HZ"
