array set options {
    -bitstream_path ""
    -probes_path    ""
    -target_index   "0"
    -trigger_probe  "repeater_full"
    -trigger_value  "1"
    -out_state      ""
}

for {set i 0} {$i < $argc} {incr i 2} {
    set arg [lindex $argv $i]
    set val [lindex $argv [expr $i+1]]
    if {[info exists options($arg)]} {
        set options($arg) $val
    }
}

if {$options(-bitstream_path) eq "" || $options(-probes_path) eq "" || $options(-out_state) eq ""} {
    puts "Usage: vivado -mode batch -source arm_uart_pbus_ila_zcu104.tcl -tclargs -bitstream_path <bit> -probes_path <ltx> -out_state <state> ?-trigger_probe repeater_full|opcode2|addr3|addr4? ?-trigger_value 0|1?"
    exit 2
}

set_param labtools.enable_cs_server false
open_hw_manager
connect_hw_server -url TCP:127.0.0.1:3121
catch {close_hw_target}

set target [lindex [get_hw_targets] $options(-target_index)]
if {$target eq ""} {
    puts "ERROR: no hw_target at index $options(-target_index)"
    exit 5
}
open_hw_target $target

set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
set_property PROBES.FILE $options(-probes_path) [current_hw_device]
set_property FULL_PROBES.FILE $options(-probes_path) [current_hw_device]
set_property PROGRAM.FILE $options(-bitstream_path) [current_hw_device]
program_hw_devices [current_hw_device]
refresh_hw_device [current_hw_device]

set ila [lindex [get_hw_ilas] 0]
if {$ila eq ""} {
    puts "ERROR: no hw_ila found"
    exit 3
}

set probes [get_hw_probes -of_objects $ila]
if {[llength $probes] < 4} {
    puts "ERROR: expected at least 4 hw_probes, got [llength $probes]"
    puts "PROBES=$probes"
    exit 4
}

set repeater_full_probe ""
set opcode2_probe ""
set addr3_probe ""
set addr4_probe ""
set all_probe_names {}
foreach p $probes {
    set pname [get_property NAME $p]
    lappend all_probe_names $pname
    if {$repeater_full_probe eq "" && [string match "*_repeater_io_full*" $pname]} {
        set repeater_full_probe $p
    }
    if {$opcode2_probe eq "" && [string match "*control_xing_out_a_bits_opcode[2]*" $pname]} {
        set opcode2_probe $p
    }
    if {$addr3_probe eq "" && [string match "*control_xing_out_a_bits_address[3]*" $pname]} {
        set addr3_probe $p
    }
    if {$addr4_probe eq "" && [string match "*control_xing_out_a_bits_address[4]*" $pname]} {
        set addr4_probe $p
    }
}

if {$repeater_full_probe eq "" || $opcode2_probe eq "" || $addr3_probe eq "" || $addr4_probe eq ""} {
    puts "ERROR: could not resolve repeater_full/opcode2/addr3/addr4 probes"
    puts "PROBE_NAMES=$all_probe_names"
    exit 5
}

foreach p [list $repeater_full_probe $opcode2_probe $addr3_probe $addr4_probe] {
    set_property TRIGGER_COMPARE_VALUE "eq1'bX" $p
    set_property CAPTURE_COMPARE_VALUE "eq1'bX" $p
}

if {$options(-trigger_probe) eq "opcode2"} {
    set trigger_probe_obj $opcode2_probe
} elseif {$options(-trigger_probe) eq "addr3"} {
    set trigger_probe_obj $addr3_probe
} elseif {$options(-trigger_probe) eq "addr4"} {
    set trigger_probe_obj $addr4_probe
} else {
    set trigger_probe_obj $repeater_full_probe
}

set_property TRIGGER_COMPARE_VALUE "eq1'b$options(-trigger_value)" $trigger_probe_obj
set_property CONTROL.TRIGGER_POSITION 8192 $ila
set_property CONTROL.WINDOW_COUNT 1 $ila
run_hw_ila $ila

set fp [open $options(-out_state) w]
puts $fp "TARGET=$target"
puts $fp "DEVICE=$dev"
puts $fp "ILA=$ila"
puts $fp "TRIGGER_PROBE=$options(-trigger_probe)"
puts $fp "TRIGGER_VALUE=$options(-trigger_value)"
puts $fp "ALL_PROBES=$all_probe_names"
puts $fp "REPEATER_FULL_PROBE=$repeater_full_probe"
puts $fp "OPCODE2_PROBE=$opcode2_probe"
puts $fp "ADDR3_PROBE=$addr3_probe"
puts $fp "ADDR4_PROBE=$addr4_probe"
close $fp

close_hw_target
exit
