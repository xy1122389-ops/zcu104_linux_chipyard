set outdir [file normalize "/root/chipyard/fpga/logs/same_session_haltreq_a11_replay_20260327_203042"]
set ltxfile [file normalize "/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupDebugConfig/debug_obj/jtagtunnel_ila_20260326_213703/jtagtunnel_ila.ltx"]
set repeats 1
set jtag_hz 10000

proc write_state {path target dev ila} {
  set fp [open $path w]
  puts $fp "TARGET=$target"
  puts $fp "DEVICE=$dev"
  puts $fp "ILA=$ila"
  puts $fp "STATUS_PRE.CORE_STATUS=[get_property STATUS.CORE_STATUS $ila]"
  puts $fp "STATUS_PRE.SAMPLE_COUNT=[get_property STATUS.SAMPLE_COUNT $ila]"
  close $fp
}

proc append_state {path ila stim_rc} {
  set fp [open $path a]
  puts $fp "STATUS_POST.CORE_STATUS=[get_property STATUS.CORE_STATUS $ila]"
  puts $fp "STATUS_POST.SAMPLE_COUNT=[get_property STATUS.SAMPLE_COUNT $ila]"
  puts $fp "STIM_RC=$stim_rc"
  close $fp
}

set_param labtools.enable_cs_server false
open_hw_manager
connect_hw_server -url TCP:127.0.0.1:3121
catch {close_hw_target}
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
if {$target eq ""} {
  puts "ERROR: no hw_target"
  exit 5
}
open_hw_target $target
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
set_property PROBES.FILE $ltxfile [current_hw_device]
set_property FULL_PROBES.FILE $ltxfile [current_hw_device]
refresh_hw_device [current_hw_device]
set ila [lindex [get_hw_ilas] 0]
if {$ila eq ""} {
  puts "ERROR: no hw_ila found"
  exit 3
}
set pos_probe [get_hw_probes inst_jtag_tunnel/posCounter_reg]
if {$pos_probe eq ""} {
  puts "ERROR: posCounter probe not found"
  exit 4
}
set xsdb_bat "E:\\PRO_APP\\xilinx\\Vivado\\2021.2\\bin\\xsdb.bat"

for {set idx 1} {$idx <= $repeats} {incr idx} {
  set label "haltreq_a11_r$idx"
  set sampleDir [file join $outdir $label]
  file mkdir $sampleDir
  set csvOut [file join $sampleDir jtagtunnel_ila.csv]
  set stateOut [file join $sampleDir state.txt]
  set stimOut [file join $sampleDir stimulus.log]
  set xsdbTcl [file nativename [file join $sampleDir xsdb_replay.tcl]]

  reset_hw_ila $ila
  foreach p [get_hw_probes -of_objects $ila] {
    set width [get_property WIDTH $p]
    set xbits [string repeat X $width]
    set_property TRIGGER_COMPARE_VALUE "eq${width}'b${xbits}" $p
    set_property CAPTURE_COMPARE_VALUE "eq${width}'b${xbits}" $p
  }
  set_property TRIGGER_COMPARE_VALUE "eq8'h08" $pos_probe
  set_property CONTROL.TRIGGER_POSITION 2048 $ila
  set_property CONTROL.WINDOW_COUNT 1 $ila
  run_hw_ila $ila

  set fp_xsdb [open $xsdbTcl w]
  puts $fp_xsdb "connect -url tcp:127.0.0.1:3121"
  puts $fp_xsdb {jtag targets -set -filter {name == "xczu7"}}
  puts $fp_xsdb "jtag frequency $jtag_hz"
  puts $fp_xsdb {set seq [jtag sequence]}
  puts $fp_xsdb {$seq irshift -integer 12 0x926}
  puts $fp_xsdb [format {$seq drshift -capture -integer %d 0x%x} 16 0x100a]
  puts $fp_xsdb {puts "SEL=[$seq run -hex]"}
  puts $fp_xsdb {set seq [jtag sequence]}
  puts $fp_xsdb {$seq irshift -integer 12 0x926}
  puts $fp_xsdb [format {$seq drshift -capture -integer %d 0x%x} 44 0x41]
  puts $fp_xsdb {puts "DTMCS=[$seq run -hex]"}
  puts $fp_xsdb {set seq [jtag sequence]}
  puts $fp_xsdb {$seq irshift -integer 12 0x926}
  puts $fp_xsdb [format {$seq drshift -capture -integer %d 0x%x} 53 0x420000000653]
  puts $fp_xsdb {puts "WRITE_HALTREQ=[$seq run -hex]"}
  puts $fp_xsdb {set seq [jtag sequence]}
  puts $fp_xsdb {$seq irshift -integer 12 0x926}
  puts $fp_xsdb [format {$seq drshift -capture -integer %d 0x%x} 53 0x53]
  puts $fp_xsdb {puts "PRENOP1=[$seq run -hex]"}
  puts $fp_xsdb {set seq [jtag sequence]}
  puts $fp_xsdb {$seq irshift -integer 12 0x926}
  puts $fp_xsdb [format {$seq drshift -capture -integer %d 0x%x} 53 0x53]
  puts $fp_xsdb {puts "PRENOP2=[$seq run -hex]"}
  puts $fp_xsdb {set seq [jtag sequence]}
  puts $fp_xsdb {$seq irshift -integer 12 0x926}
  puts $fp_xsdb [format {$seq drshift -capture -integer %d 0x%x} 53 0x440000000153]
  puts $fp_xsdb {puts "READ_0x11=[$seq run -hex]"}
  puts $fp_xsdb {set seq [jtag sequence]}
  puts $fp_xsdb {$seq irshift -integer 12 0x926}
  puts $fp_xsdb [format {$seq drshift -capture -integer %d 0x%x} 53 0x53]
  puts $fp_xsdb {puts "POSTNOP1=[$seq run -hex]"}
  puts $fp_xsdb {set seq [jtag sequence]}
  puts $fp_xsdb {$seq irshift -integer 12 0x926}
  puts $fp_xsdb [format {$seq drshift -capture -integer %d 0x%x} 53 0x53]
  puts $fp_xsdb {puts "POSTNOP2=[$seq run -hex]"}
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
