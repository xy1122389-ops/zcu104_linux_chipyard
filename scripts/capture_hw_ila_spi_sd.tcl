if {$argc < 2} {
  puts "Usage: vivado -mode batch -source scripts/capture_hw_ila_spi_sd.tcl -tclargs <ltx_file> <out_base> ?timeout_mins?"
  exit 2
}

proc find_probe_by_name {ila probe_name} {
  foreach probe [get_hw_probes -of_objects $ila] {
    if {[get_property NAME $probe] eq $probe_name} {
      return $probe
    }
  }
  return ""
}

set ltx_file [lindex $argv 0]
set out_base [lindex $argv 1]
set timeout_mins [lindex $argv 2]
if {$timeout_mins eq ""} {
  set timeout_mins 15
}

set cs_probe_name chiptop0/system/spiClockDomainWrapper/spi_0/mac/sdio_spi_dat_3_OBUF

set_param labtools.enable_cs_server false
open_hw_manager
connect_hw_server -allow_non_jtag
catch {close_hw_target}
set target [lindex [get_hw_targets] 0]
open_hw_target $target

set dev [lindex [get_hw_devices] 0]
if {$dev eq ""} {
  puts "ERROR: no hardware device found"
  exit 3
}

current_hw_device $dev
set_property BSCAN_SWITCH_USER_MASK 0001 $dev
set_property PROBES.FILE $ltx_file $dev
set_property FULL_PROBES.FILE $ltx_file $dev
refresh_hw_device $dev

set ila [lindex [get_hw_ilas] 0]
if {$ila eq ""} {
  puts "ERROR: no ILA found after refresh"
  exit 4
}
current_hw_ila $ila

set cs_probe [find_probe_by_name $ila $cs_probe_name]
if {$cs_probe eq ""} {
  puts "ERROR: failed to locate CS probe '$cs_probe_name'"
  puts "Available probes:"
  foreach probe [get_hw_probes -of_objects $ila] {
    puts "  [get_property NAME $probe]"
  }
  exit 5
}

reset_hw_ila $ila
set_property CONTROL.DATA_DEPTH 8192 $ila
set_property CONTROL.WINDOW_COUNT 1 $ila
set_property CONTROL.TRIGGER_POSITION 512 $ila
set_property CONTROL.TRIGGER_CONDITION AND $ila

foreach probe [get_hw_probes -of_objects $ila] {
  set_property TRIGGER_COMPARE_VALUE eq1'bX $probe
  set_property CAPTURE_COMPARE_VALUE eq1'bX $probe
}
set_property TRIGGER_COMPARE_VALUE eq1'b0 $cs_probe

puts "HW_DEVICE=$dev"
puts "ILA=$ila"
puts "LTX=$ltx_file"
puts "OUT_BASE=$out_base"
puts "TIMEOUT_MINS=$timeout_mins"
puts "TRIGGER_PROBE=$cs_probe_name"
puts "TRIGGER_COMPARE=eq1'b0"

run_hw_ila $ila
puts "ILA armed; waiting for trigger"

set wait_rc [catch {wait_on_hw_ila -timeout $timeout_mins $ila} wait_msg]
if {$wait_rc != 0} {
  puts "WAIT_RESULT=TIMEOUT_OR_ERROR"
  puts "WAIT_MESSAGE=$wait_msg"
} else {
  puts "WAIT_RESULT=TRIGGERED"
}

set data [upload_hw_ila_data $ila]
current_hw_ila_data $data

set out_ila [write_hw_ila_data -force $out_base $data]
set out_csv [write_hw_ila_data -force -csv_file $out_base $data]
set out_vcd [write_hw_ila_data -force -vcd_file $out_base $data]

puts "STATUS.CORE_STATUS=[get_property STATUS.CORE_STATUS $ila]"
puts "STATUS.SAMPLE_COUNT=[get_property STATUS.SAMPLE_COUNT $ila]"
puts "STATUS.TRIGGER_POSITION=[get_property STATUS.TRIGGER_POSITION $ila]"
puts "OUT_ILA=$out_ila"
puts "OUT_CSV=$out_csv"
puts "OUT_VCD=$out_vcd"

close_hw_target
disconnect_hw_server
close_hw_manager

if {$wait_rc != 0} {
  exit 6
}
exit