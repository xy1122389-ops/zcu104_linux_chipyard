array set options {
    -probes_path    ""
    -target_index   "0"
    -seconds        "5"
    -out_log        ""
}

for {set i 0} {$i < $argc} {incr i 2} {
    set arg [lindex $argv $i]
    set val [lindex $argv [expr $i+1]]
    if {[info exists options($arg)]} {
        set options($arg) $val
    }
}

if {$options(-probes_path) eq "" || $options(-out_log) eq ""} {
    puts "Usage: vivado -mode batch -source check_jtagtunnel_ila_idle_status.tcl -tclargs -probes_path <ltx> -out_log <log> ?-target_index 0? ?-seconds 5?"
    exit 2
}

set_param labtools.enable_cs_server false
open_hw_manager
connect_hw_server -url TCP:127.0.0.1:3121
catch {close_hw_target}

set target ""
for {set i 0} {$i < 10} {incr i} {
    catch {refresh_hw_server}
    set targets [get_hw_targets -quiet]
    if {[llength $targets] > $options(-target_index)} {
        set target [lindex $targets $options(-target_index)]
        break
    }
    after 1000
}
if {$target eq ""} {
    puts "ERROR: no hw_target at index $options(-target_index)"
    exit 5
}
open_hw_target $target

set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
set_property PROBES.FILE $options(-probes_path) [current_hw_device]
set_property FULL_PROBES.FILE $options(-probes_path) [current_hw_device]
refresh_hw_device [current_hw_device]

set ila [lindex [get_hw_ilas] 0]
if {$ila eq ""} {
    puts "ERROR: no hw_ila found"
    exit 3
}

set shift_probe [get_hw_probes u_ila_jtag__bscane2_SHIFT]
if {$shift_probe eq ""} {
    puts "ERROR: shift probe not found"
    exit 4
}

foreach p [get_hw_probes -of_objects $ila] {
    set width [get_property WIDTH $p]
    set xbits [string repeat X $width]
    set_property TRIGGER_COMPARE_VALUE "eq${width}'b${xbits}" $p
    set_property CAPTURE_COMPARE_VALUE "eq${width}'b${xbits}" $p
}
set_property TRIGGER_COMPARE_VALUE "eq1'b1" $shift_probe
set_property CONTROL.TRIGGER_POSITION 2048 $ila
set_property CONTROL.WINDOW_COUNT 1 $ila

set fp [open $options(-out_log) w]
puts $fp "TARGET=$target"
puts $fp "DEVICE=$dev"
puts $fp "ILA=$ila"
puts $fp "SHIFT_PROBE=$shift_probe"

run_hw_ila $ila
for {set sec 0} {$sec <= $options(-seconds)} {incr sec} {
    puts $fp "T=$sec STATUS.CORE_STATUS=[get_property STATUS.CORE_STATUS $ila] STATUS.SAMPLE_COUNT=[get_property STATUS.SAMPLE_COUNT $ila] STATUS.TRIGGER_POSITION=[get_property STATUS.TRIGGER_POSITION $ila]"
    flush $fp
    after 1000
}

close $fp
close_hw_target
exit
