array set options {
    -bitstream_path ""
    -probes_path    ""
    -target_index   "0"
}

for {set i 0} {$i < $argc} {incr i 2} {
    set arg [lindex $argv $i]
    set val [lindex $argv [expr $i+1]]
    if {[info exists options($arg)]} {
        set options($arg) $val
    }
}

set bitstream_path $options(-bitstream_path)
set probes_path    $options(-probes_path)
set target_index   $options(-target_index)

if {$bitstream_path eq "" || $probes_path eq ""} {
    puts "Usage: vivado -mode batch -source program_jtagtunnel_ila_zcu104.tcl -tclargs -bitstream_path <bit> -probes_path <ltx> ?-target_index 0?"
    exit 2
}

set_param labtools.enable_cs_server false
open_hw_manager
connect_hw_server -allow_non_jtag
catch {close_hw_target}

set target [lindex [get_hw_targets] $target_index]
if {$target eq ""} {
    puts "ERROR: no hw_target at index $target_index"
    puts [get_hw_targets]
    exit 3
}
puts "TARGET=$target"
open_hw_target $target

set dev [lindex [get_hw_devices] 0]
if {$dev eq ""} {
    puts "ERROR: no hw_device found"
    exit 4
}
puts "DEVICE=$dev"
current_hw_device $dev
set_property PROBES.FILE $probes_path [current_hw_device]
set_property FULL_PROBES.FILE $probes_path [current_hw_device]
set_property PROGRAM.FILE $bitstream_path [current_hw_device]
program_hw_devices [current_hw_device]
refresh_hw_device [current_hw_device]

puts "=== HW_ILAS ==="
foreach i [get_hw_ilas] {puts $i}

close_hw_target
exit
