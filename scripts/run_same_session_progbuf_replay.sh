#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

if [[ $# -lt 5 ]]; then
  echo "Usage: $0 <ila_dir> <label_base> <progbuf0_word_hex> <command_word_hex> <repeats> [jtag_hz]" >&2
  exit 2
fi

ILA_DIR="$1"
LABEL_BASE="$2"
PROGBUF0_WORD="$3"
COMMAND_WORD="$4"
REPEATS="$5"
JTAG_HZ="${6:-10000}"
SELECT_PAYLOAD="${SELECT_PAYLOAD:-0x10}"

STAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="$FPGA_DIR/logs/same_session_progbuf_replay_${LABEL_BASE}_${STAMP}"
mkdir -p "$OUTDIR"
TCL="$OUTDIR/replay_same_session.tcl"
DOLLAR='$'

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

read -r SEL_BITS SEL_VAL < <(pack_select_dbus)
read -r DTM_BITS DTM_VAL < <(pack_dtmcs)
read -r HALT_BITS HALT_VAL < <(pack_dmi_write 0x10 0x80000001)
read -r PBUF_BITS PBUF_VAL < <(pack_dmi_write 0x20 "$PROGBUF0_WORD")
read -r CMD_BITS CMD_VAL < <(pack_dmi_write 0x17 "$COMMAND_WORD")
read -r RD_ABS_BITS RD_ABS_VAL < <(pack_dmi_read 0x16)
read -r RD_D0_BITS RD_D0_VAL < <(pack_dmi_read 0x04)
read -r NOP_BITS NOP_VAL < <(pack_dmi_nop)

LTXFILE="$ILA_DIR/jtagtunnel_ila.ltx"

cat > "$TCL" <<EOF
set outdir [file normalize "$OUTDIR"]
set repeats $REPEATS
set labelBase "$LABEL_BASE"
set ltxfile [file normalize "$LTXFILE"]
set jtag_hz $JTAG_HZ

proc write_state {path target dev ila} {
  set fp [open \$path w]
  puts \$fp "TARGET=\$target"
  puts \$fp "DEVICE=\$dev"
  puts \$fp "ILA=\$ila"
  puts \$fp "STATUS_PRE.CORE_STATUS=[get_property STATUS.CORE_STATUS \$ila]"
  puts \$fp "STATUS_PRE.SAMPLE_COUNT=[get_property STATUS.SAMPLE_COUNT \$ila]"
  close \$fp
}

proc append_state {path ila stim_rc} {
  set fp [open \$path a]
  puts \$fp "STATUS_POST.CORE_STATUS=[get_property STATUS.CORE_STATUS \$ila]"
  puts \$fp "STATUS_POST.SAMPLE_COUNT=[get_property STATUS.SAMPLE_COUNT \$ila]"
  puts \$fp "STIM_RC=\$stim_rc"
  close \$fp
}

set_param labtools.enable_cs_server false
open_hw_manager
connect_hw_server -url TCP:127.0.0.1:3121
catch {close_hw_target}
set target ""
for {set i 0} {\$i < 10} {incr i} {
  catch {refresh_hw_server}
  set targets [get_hw_targets -quiet]
  if {[llength \$targets] > 0} {
    set target [lindex \$targets 0]
    break
  }
  after 1000
}
if {\$target eq ""} {
  puts "ERROR: no hw_target"
  exit 5
}
open_hw_target \$target
set dev [lindex [get_hw_devices] 0]
current_hw_device \$dev
set_property PROBES.FILE \$ltxfile [current_hw_device]
set_property FULL_PROBES.FILE \$ltxfile [current_hw_device]
refresh_hw_device [current_hw_device]
set ila [lindex [get_hw_ilas] 0]
if {\$ila eq ""} {
  puts "ERROR: no hw_ila found"
  exit 3
}
set shift_probe [get_hw_probes u_ila_jtag__bscane2_SHIFT]
if {\$shift_probe eq ""} {
  puts "ERROR: shift probe not found"
  exit 4
}
set xsdb_bat "E:\\PRO_APP\\xilinx\\Vivado\\2021.2\\bin\\xsdb.bat"

for {set idx 1} {\$idx <= \$repeats} {incr idx} {
  set label "\${labelBase}_r\${idx}"
  set sampleDir [file join \$outdir \$label]
  file mkdir \$sampleDir
  set csvOut [file join \$sampleDir jtagtunnel_ila.csv]
  set stateOut [file join \$sampleDir state.txt]
  set stimOut [file join \$sampleDir stimulus.log]
  set xsdbTcl [file nativename [file join \$sampleDir xsdb_replay.tcl]]

  foreach p [get_hw_probes -of_objects \$ila] {
    set width [get_property WIDTH \$p]
    set xbits [string repeat X \$width]
    set_property TRIGGER_COMPARE_VALUE "eq\${width}'b\${xbits}" \$p
    set_property CAPTURE_COMPARE_VALUE "eq\${width}'b\${xbits}" \$p
  }
  set_property TRIGGER_COMPARE_VALUE "eq1'b1" \$shift_probe
  set_property CONTROL.TRIGGER_POSITION 2048 \$ila
  set_property CONTROL.WINDOW_COUNT 1 \$ila
  run_hw_ila \$ila

  set fp_xsdb [open \$xsdbTcl w]
  puts \$fp_xsdb "connect -url tcp:127.0.0.1:3121"
  puts \$fp_xsdb "jtag targets -set -filter {name == \\"xczu7\\"}"
  puts \$fp_xsdb "jtag frequency \$jtag_hz"
  puts \$fp_xsdb {set seq [jtag sequence]}
  puts \$fp_xsdb {\$seq irshift -integer 12 0x926}
  puts \$fp_xsdb [format {\\$seq drshift -capture -integer %d 0x%x} $SEL_BITS $SEL_VAL]
  puts \$fp_xsdb {puts "SEL=[\$seq run -hex]"}
  puts \$fp_xsdb {set seq [jtag sequence]}
  puts \$fp_xsdb {\$seq irshift -integer 12 0x926}
  puts \$fp_xsdb [format {\\$seq drshift -capture -integer %d 0x%x} $DTM_BITS $DTM_VAL]
  puts \$fp_xsdb {puts "DTMCS=[\$seq run -hex]"}
  puts \$fp_xsdb {set seq [jtag sequence]}
  puts \$fp_xsdb {\$seq irshift -integer 12 0x926}
  puts \$fp_xsdb [format {\\$seq drshift -capture -integer %d 0x%x} $HALT_BITS $HALT_VAL]
  puts \$fp_xsdb {puts "WRITE_HALTREQ=[\$seq run -hex]"}
  puts \$fp_xsdb {set seq [jtag sequence]}
  puts \$fp_xsdb {\$seq irshift -integer 12 0x926}
  puts \$fp_xsdb [format {\\$seq drshift -capture -integer %d 0x%x} $NOP_BITS $NOP_VAL]
  puts \$fp_xsdb {puts "NOP1_HALTREQ=[\$seq run -hex]"}
  puts \$fp_xsdb {set seq [jtag sequence]}
  puts \$fp_xsdb {\$seq irshift -integer 12 0x926}
  puts \$fp_xsdb [format {\\$seq drshift -capture -integer %d 0x%x} $PBUF_BITS $PBUF_VAL]
  puts \$fp_xsdb {puts "WRITE_PROGBUF0=[\$seq run -hex]"}
  puts \$fp_xsdb {set seq [jtag sequence]}
  puts \$fp_xsdb {\$seq irshift -integer 12 0x926}
  puts \$fp_xsdb [format {\\$seq drshift -capture -integer %d 0x%x} $NOP_BITS $NOP_VAL]
  puts \$fp_xsdb {puts "NOP1_PROGBUF0=[\$seq run -hex]"}
  puts \$fp_xsdb {set seq [jtag sequence]}
  puts \$fp_xsdb {\$seq irshift -integer 12 0x926}
  puts \$fp_xsdb [format {\\$seq drshift -capture -integer %d 0x%x} $CMD_BITS $CMD_VAL]
  puts \$fp_xsdb {puts "WRITE_COMMAND=[\$seq run -hex]"}
  puts \$fp_xsdb {set seq [jtag sequence]}
  puts \$fp_xsdb {\$seq irshift -integer 12 0x926}
  puts \$fp_xsdb [format {\\$seq drshift -capture -integer %d 0x%x} $NOP_BITS $NOP_VAL]
  puts \$fp_xsdb {puts "NOP1_COMMAND=[\$seq run -hex]"}
  puts \$fp_xsdb {set seq [jtag sequence]}
  puts \$fp_xsdb {\$seq irshift -integer 12 0x926}
  puts \$fp_xsdb [format {\\$seq drshift -capture -integer %d 0x%x} $NOP_BITS $NOP_VAL]
  puts \$fp_xsdb {puts "NOP2_COMMAND=[\$seq run -hex]"}
  puts \$fp_xsdb {set seq [jtag sequence]}
  puts \$fp_xsdb {\$seq irshift -integer 12 0x926}
  puts \$fp_xsdb [format {\\$seq drshift -capture -integer %d 0x%x} $RD_ABS_BITS $RD_ABS_VAL]
  puts \$fp_xsdb {puts "READ_ABSTRACTCS=[\$seq run -hex]"}
  puts \$fp_xsdb {set seq [jtag sequence]}
  puts \$fp_xsdb {\$seq irshift -integer 12 0x926}
  puts \$fp_xsdb [format {\\$seq drshift -capture -integer %d 0x%x} $NOP_BITS $NOP_VAL]
  puts \$fp_xsdb {puts "NOP1_ABSTRACTCS=[\$seq run -hex]"}
  puts \$fp_xsdb {set seq [jtag sequence]}
  puts \$fp_xsdb {\$seq irshift -integer 12 0x926}
  puts \$fp_xsdb [format {\\$seq drshift -capture -integer %d 0x%x} $RD_D0_BITS $RD_D0_VAL]
  puts \$fp_xsdb {puts "READ_DATA0=[\$seq run -hex]"}
  puts \$fp_xsdb {set seq [jtag sequence]}
  puts \$fp_xsdb {\$seq irshift -integer 12 0x926}
  puts \$fp_xsdb [format {\\$seq drshift -capture -integer %d 0x%x} $NOP_BITS $NOP_VAL]
  puts \$fp_xsdb {puts "NOP1_DATA0=[\$seq run -hex]"}
  puts \$fp_xsdb {set seq [jtag sequence]}
  puts \$fp_xsdb {\$seq irshift -integer 12 0x926}
  puts \$fp_xsdb [format {\\$seq drshift -capture -integer %d 0x%x} $NOP_BITS $NOP_VAL]
  puts \$fp_xsdb {puts "NOP2_DATA0=[\$seq run -hex]"}
  puts \$fp_xsdb {exit}
  close \$fp_xsdb

  write_state \$stateOut \$target \$dev \$ila
  set stim_cmd [list cmd /c \$xsdb_bat \$xsdbTcl]
  set stim_out ""
  set stim_rc [catch {set stim_out [eval exec \$stim_cmd]} stim_err]
  set fp_stim [open \$stimOut w]
  puts \$fp_stim \$stim_out
  if {\$stim_rc != 0} {
    puts \$fp_stim \$stim_err
  }
  close \$fp_stim

  upload_hw_ila_data \$ila
  write_hw_ila_data -force -csv_file \$csvOut [get_hw_ila_data \$ila]
  append_state \$stateOut \$ila \$stim_rc
}

close_hw_target
exit
EOF

"$SCRIPT_DIR/restart_hw_server_windows.sh" >/dev/null

/root/.local/bin/vivado -mode batch -source "$TCL" >"$OUTDIR/vivado.log" 2>&1

if find "$OUTDIR" -mindepth 2 -maxdepth 2 -name 'jtagtunnel_ila.csv' | grep -q .; then
  python3 "$SCRIPT_DIR/classify_jtagtunnel_event_classes.py" \
    $(find "$OUTDIR" -mindepth 2 -maxdepth 2 -name 'jtagtunnel_ila.csv' | sort) \
    >"$OUTDIR/classes.txt"
fi

echo "OUTDIR=$OUTDIR"
find "$OUTDIR" -maxdepth 2 -type f -printf '%P %s\n' | sort
