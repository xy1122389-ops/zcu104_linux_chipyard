set bit_file [lindex $argv 0]
set ltx_file [lindex $argv 1]

if {$bit_file eq "" || $ltx_file eq ""} {
  puts "Usage: vivado -mode batch -source scripts/list_hw_ila_spi_sd.tcl -tclargs <bit> <ltx>"
  exit 2
}

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

puts "HW_DEVICE=$dev"
puts "BIT=$bit_file"
puts "LTX=$ltx_file"

set ilas [get_hw_ilas]
puts "ILA_COUNT=[llength $ilas]"
foreach ila $ilas {
  puts "ILA=$ila"
  foreach probe [get_hw_probes -of_objects $ila] {
    puts "  PROBE=$probe"
  }
}

close_hw_target
disconnect_hw_server
close_hw_manager
exit