#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FPGA_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

ILA_DIR="${1:-$FPGA_DIR/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupDebugConfig/debug_obj/jtagtunnel_ila_20260326_213703}"
REPEATS="${2:-3}"
JTAG_HZ="${3:-10000}"
REOPEN_TARGET="${4:-0}"
RECONNECT_SERVER="${5:-0}"
SKIP_SERVER_RESTART="${6:-0}"
OUTDIR="$FPGA_DIR/logs/same_session_ebreak_replay_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"
TCL="$OUTDIR/replay.tcl"

python3 - "$TCL" "$OUTDIR" "$ILA_DIR" "$REPEATS" "$JTAG_HZ" "$REOPEN_TARGET" "$RECONNECT_SERVER" <<'PY'
import sys
from pathlib import Path

tcl_path = Path(sys.argv[1])
outdir = Path(sys.argv[2])
ila_dir = Path(sys.argv[3])
repeats = int(sys.argv[4])
jtag_hz = int(sys.argv[5])
reopen_target = int(sys.argv[6])
reconnect_server = int(sys.argv[7])

def add_fields(fields):
    v = 0
    shift = 0
    for nbits, value in fields:
        v |= (value & ((1 << nbits) - 1)) << shift
        shift += nbits
    return shift, v

sel_bits, sel_val = add_fields([(1,0),(7,0x05),(5,0x10),(3,0)])
dtm_bits, dtm_val = add_fields([(1,1),(7,0x20),(33,0),(3,0)])
halt_bits, halt_val = add_fields([(1,1),(7,0x29),((42), (0x10 << 34) | (0x80000001 << 2) | 0x2),(3,0)])
pbuf_bits, pbuf_val = add_fields([(1,1),(7,0x29),((42), (0x20 << 34) | (0x00100073 << 2) | 0x2),(3,0)])
cmd_bits, cmd_val = add_fields([(1,1),(7,0x29),((42), (0x17 << 34) | (0x00241000 << 2) | 0x2),(3,0)])
rd_abs_bits, rd_abs_val = add_fields([(1,1),(7,0x29),((42), (0x16 << 34) | 0x1),(3,0)])
rd_d0_bits, rd_d0_val = add_fields([(1,1),(7,0x29),((42), (0x04 << 34) | 0x1),(3,0)])
nop_bits, nop_val = add_fields([(1,1),(7,0x29),(42,0),(3,0)])

ltx = ila_dir / "jtagtunnel_ila.ltx"

text = r"""set outdir [file normalize "__OUTDIR__"]
set ltxfile [file normalize "__LTXFILE__"]
set repeats __REPEATS__
set jtag_hz __JTAG_HZ__
set reopen_target __REOPEN_TARGET__
set reconnect_server __RECONNECT_SERVER__

proc write_state {{path target dev ila}} {{
  set fp [open $path w]
  puts $fp "TARGET=$target"
  puts $fp "DEVICE=$dev"
  puts $fp "ILA=$ila"
  puts $fp "STATUS_PRE.CORE_STATUS=[get_property STATUS.CORE_STATUS $ila]"
  puts $fp "STATUS_PRE.SAMPLE_COUNT=[get_property STATUS.SAMPLE_COUNT $ila]"
  close $fp
}}

proc append_state {{path ila stim_rc}} {{
  set fp [open $path a]
  puts $fp "STATUS_POST.CORE_STATUS=[get_property STATUS.CORE_STATUS $ila]"
  puts $fp "STATUS_POST.SAMPLE_COUNT=[get_property STATUS.SAMPLE_COUNT $ila]"
  puts $fp "STIM_RC=$stim_rc"
  close $fp
}}

proc bind_hw {{ltxfile}} {{
  set dev [lindex [get_hw_devices] 0]
  current_hw_device $dev
  set_property PROBES.FILE $ltxfile [current_hw_device]
  set_property FULL_PROBES.FILE $ltxfile [current_hw_device]
  refresh_hw_device [current_hw_device]
  set ila [lindex [get_hw_ilas] 0]
  if {{$ila eq ""}} {{
    puts "ERROR: no hw_ila found"
    exit 3
  }}
  set pos_probe [get_hw_probes inst_jtag_tunnel/posCounter_reg]
  if {{$pos_probe eq ""}} {{
    puts "ERROR: posCounter probe not found"
    exit 4
  }}
  return [list $dev $ila $pos_probe]
}}

proc find_target {} {
  set target ""
  for {set i 0} {$i < 10} {incr i} {
    catch {refresh_hw_server}
    set targets [get_hw_targets -quiet]
    if {[llength $targets] > 0} {
      set target [lindex $targets 0]
      break
    }
    after 1000
  }
  return $target
}

set_param labtools.enable_cs_server false
open_hw_manager
connect_hw_server -url TCP:127.0.0.1:3121
catch {{close_hw_target}}
set target [find_target]
if {{$target eq ""}} {{
  puts "ERROR: no hw_target"
  exit 5
}}
open_hw_target $target
lassign [bind_hw $ltxfile] dev ila pos_probe
set xsdb_bat "E:\\PRO_APP\\xilinx\\Vivado\\2021.2\\bin\\xsdb.bat"

for {{set idx 1}} {{$idx <= $repeats}} {{incr idx}} {{
  if {{$idx > 1}} {{
    if {{$reconnect_server}} {{
      catch {{close_hw_target}}
      catch {{disconnect_hw_server}}
      connect_hw_server -url TCP:127.0.0.1:3121
      set target [find_target]
      if {{$target eq ""}} {{
        puts "ERROR: no hw_target after reconnect"
        exit 6
      }}
      open_hw_target $target
      lassign [bind_hw $ltxfile] dev ila pos_probe
    }} elseif {{$reopen_target}} {{
      catch {{close_hw_target}}
      open_hw_target $target
      lassign [bind_hw $ltxfile] dev ila pos_probe
    }}
  }}
  set label "ebreak_r$idx"
  set sampleDir [file join $outdir $label]
  file mkdir $sampleDir
  set csvOut [file join $sampleDir jtagtunnel_ila.csv]
  set stateOut [file join $sampleDir state.txt]
  set stimOut [file join $sampleDir stimulus.log]
  set xsdbTcl [file nativename [file join $sampleDir xsdb_replay.tcl]]

  reset_hw_ila $ila
  foreach p [get_hw_probes -of_objects $ila] {{
    set width [get_property WIDTH $p]
    set xbits [string repeat X $width]
    set_property TRIGGER_COMPARE_VALUE "eq${{width}}'b${{xbits}}" $p
    set_property CAPTURE_COMPARE_VALUE "eq${{width}}'b${{xbits}}" $p
  }}
  set_property TRIGGER_COMPARE_VALUE "eq8'h08" $pos_probe
  set_property CONTROL.TRIGGER_POSITION 2048 $ila
  set_property CONTROL.WINDOW_COUNT 1 $ila
  run_hw_ila $ila

  set fp_xsdb [open $xsdbTcl w]
  puts $fp_xsdb "connect -url tcp:127.0.0.1:3121"
  puts $fp_xsdb "jtag targets -set -filter {name == \"xczu7\"}"
  puts $fp_xsdb "jtag frequency $jtag_hz"
  puts $fp_xsdb {set seq [jtag sequence]}
  puts $fp_xsdb {$seq irshift -integer 12 0x926}
  puts $fp_xsdb [format {$seq drshift -capture -integer %d 0x%x} __SEL_BITS__ __SEL_VAL__]
  puts $fp_xsdb {puts "SEL=[$seq run -hex]"}
  puts $fp_xsdb {set seq [jtag sequence]}
  puts $fp_xsdb {$seq irshift -integer 12 0x926}
  puts $fp_xsdb [format {$seq drshift -capture -integer %d 0x%x} __DTM_BITS__ __DTM_VAL__]
  puts $fp_xsdb {puts "DTMCS=[$seq run -hex]"}
  puts $fp_xsdb {set seq [jtag sequence]}
  puts $fp_xsdb {$seq irshift -integer 12 0x926}
  puts $fp_xsdb [format {$seq drshift -capture -integer %d 0x%x} __HALT_BITS__ __HALT_VAL__]
  puts $fp_xsdb {puts "WRITE_HALTREQ=[$seq run -hex]"}
  puts $fp_xsdb {set seq [jtag sequence]}
  puts $fp_xsdb {$seq irshift -integer 12 0x926}
  puts $fp_xsdb [format {$seq drshift -capture -integer %d 0x%x} __NOP_BITS__ __NOP_VAL__]
  puts $fp_xsdb {puts "NOP1_HALTREQ=[$seq run -hex]"}
  puts $fp_xsdb {set seq [jtag sequence]}
  puts $fp_xsdb {$seq irshift -integer 12 0x926}
  puts $fp_xsdb [format {$seq drshift -capture -integer %d 0x%x} __PBUF_BITS__ __PBUF_VAL__]
  puts $fp_xsdb {puts "WRITE_PROGBUF0=[$seq run -hex]"}
  puts $fp_xsdb {set seq [jtag sequence]}
  puts $fp_xsdb {$seq irshift -integer 12 0x926}
  puts $fp_xsdb [format {$seq drshift -capture -integer %d 0x%x} __NOP_BITS__ __NOP_VAL__]
  puts $fp_xsdb {puts "NOP1_PROGBUF0=[$seq run -hex]"}
  puts $fp_xsdb {set seq [jtag sequence]}
  puts $fp_xsdb {$seq irshift -integer 12 0x926}
  puts $fp_xsdb [format {$seq drshift -capture -integer %d 0x%x} __CMD_BITS__ __CMD_VAL__]
  puts $fp_xsdb {puts "WRITE_COMMAND=[$seq run -hex]"}
  puts $fp_xsdb {set seq [jtag sequence]}
  puts $fp_xsdb {$seq irshift -integer 12 0x926}
  puts $fp_xsdb [format {$seq drshift -capture -integer %d 0x%x} __NOP_BITS__ __NOP_VAL__]
  puts $fp_xsdb {puts "NOP1_COMMAND=[$seq run -hex]"}
  puts $fp_xsdb {set seq [jtag sequence]}
  puts $fp_xsdb {$seq irshift -integer 12 0x926}
  puts $fp_xsdb [format {$seq drshift -capture -integer %d 0x%x} __NOP_BITS__ __NOP_VAL__]
  puts $fp_xsdb {puts "NOP2_COMMAND=[$seq run -hex]"}
  puts $fp_xsdb {set seq [jtag sequence]}
  puts $fp_xsdb {$seq irshift -integer 12 0x926}
  puts $fp_xsdb [format {$seq drshift -capture -integer %d 0x%x} __RD_ABS_BITS__ __RD_ABS_VAL__]
  puts $fp_xsdb {puts "READ_ABSTRACTCS=[$seq run -hex]"}
  puts $fp_xsdb {set seq [jtag sequence]}
  puts $fp_xsdb {$seq irshift -integer 12 0x926}
  puts $fp_xsdb [format {$seq drshift -capture -integer %d 0x%x} __NOP_BITS__ __NOP_VAL__]
  puts $fp_xsdb {puts "NOP1_ABSTRACTCS=[$seq run -hex]"}
  puts $fp_xsdb {set seq [jtag sequence]}
  puts $fp_xsdb {$seq irshift -integer 12 0x926}
  puts $fp_xsdb [format {$seq drshift -capture -integer %d 0x%x} __RD_D0_BITS__ __RD_D0_VAL__]
  puts $fp_xsdb {puts "READ_DATA0=[$seq run -hex]"}
  puts $fp_xsdb {set seq [jtag sequence]}
  puts $fp_xsdb {$seq irshift -integer 12 0x926}
  puts $fp_xsdb [format {$seq drshift -capture -integer %d 0x%x} __NOP_BITS__ __NOP_VAL__]
  puts $fp_xsdb {puts "NOP1_DATA0=[$seq run -hex]"}
  puts $fp_xsdb {set seq [jtag sequence]}
  puts $fp_xsdb {$seq irshift -integer 12 0x926}
  puts $fp_xsdb [format {$seq drshift -capture -integer %d 0x%x} __NOP_BITS__ __NOP_VAL__]
  puts $fp_xsdb {puts "NOP2_DATA0=[$seq run -hex]"}
  puts $fp_xsdb {exit}
  close $fp_xsdb

  write_state $stateOut $target $dev $ila
  set stim_cmd [list cmd /c $xsdb_bat $xsdbTcl]
  set stim_out ""
  set stim_rc [catch {set stim_out [eval exec $stim_cmd]} stim_err]
  set fp_stim [open $stimOut w]
  puts $fp_stim $stim_out
  if {$stim_rc != 0} {
    puts $fp_stim $stim_err
  }
  close $fp_stim

  wait_on_hw_ila $ila
  set ilaData [upload_hw_ila_data $ila]
  write_hw_ila_data -force -csv_file $csvOut $ilaData
  append_state $stateOut $ila $stim_rc
}

close_hw_target
exit
"""
t = (text
     .replace("__OUTDIR__", str(outdir))
     .replace("__LTXFILE__", str(ltx))
     .replace("__REPEATS__", str(repeats))
     .replace("__JTAG_HZ__", str(jtag_hz))
     .replace("__REOPEN_TARGET__", str(reopen_target))
     .replace("__RECONNECT_SERVER__", str(reconnect_server))
     .replace("__SEL_BITS__", str(sel_bits))
     .replace("__SEL_VAL__", hex(sel_val))
     .replace("__DTM_BITS__", str(dtm_bits))
     .replace("__DTM_VAL__", hex(dtm_val))
     .replace("__HALT_BITS__", str(halt_bits))
     .replace("__HALT_VAL__", hex(halt_val))
     .replace("__PBUF_BITS__", str(pbuf_bits))
     .replace("__PBUF_VAL__", hex(pbuf_val))
     .replace("__CMD_BITS__", str(cmd_bits))
     .replace("__CMD_VAL__", hex(cmd_val))
     .replace("__RD_ABS_BITS__", str(rd_abs_bits))
     .replace("__RD_ABS_VAL__", hex(rd_abs_val))
     .replace("__RD_D0_BITS__", str(rd_d0_bits))
     .replace("__RD_D0_VAL__", hex(rd_d0_val))
     .replace("__NOP_BITS__", str(nop_bits))
     .replace("__NOP_VAL__", hex(nop_val))
     .replace("{{", "{")
     .replace("}}", "}"))
tcl_path.write_text(t)
PY

if [[ "$SKIP_SERVER_RESTART" != "1" ]]; then
  /root/chipyard/fpga/scripts/restart_hw_server_windows.sh >/dev/null
fi
/root/.local/bin/vivado -mode batch -source "$TCL" >"$OUTDIR/vivado.log" 2>&1

if find "$OUTDIR" -mindepth 2 -maxdepth 2 -name 'jtagtunnel_ila.csv' | grep -q .; then
  python3 "$SCRIPT_DIR/classify_jtagtunnel_event_classes.py" \
    $(find "$OUTDIR" -mindepth 2 -maxdepth 2 -name 'jtagtunnel_ila.csv' | sort) \
    >"$OUTDIR/classes.txt"
fi

echo "OUTDIR=$OUTDIR"
find "$OUTDIR" -maxdepth 2 -type f -printf '%P %s\n' | sort
