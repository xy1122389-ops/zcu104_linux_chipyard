array set options {
    -probes_path    ""
    -target_index   "0"
    -out_csv        ""
    -out_state      ""
}

for {set i 0} {$i < $argc} {incr i 2} {
    set arg [lindex $argv $i]
    set val [lindex $argv [expr $i+1]]
    if {[info exists options($arg)]} {
        set options($arg) $val
    }
}

if {$options(-probes_path) eq "" || $options(-out_csv) eq "" || $options(-out_state) eq ""} {
    puts "Usage: vivado -mode batch -source upload_jtagtunnel_ila_zcu104.tcl -tclargs -probes_path <ltx> -out_csv <csv> -out_state <state.txt> ?-target_index 0?"
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

set status_pre [get_property STATUS.CORE_STATUS $ila]
set sample_count_pre [get_property STATUS.SAMPLE_COUNT $ila]
set trigger_pos_pre [get_property STATUS.TRIGGER_POSITION $ila]

upload_hw_ila_data $ila
write_hw_ila_data -csv_file $options(-out_csv) [get_hw_ila_data $ila]

set fp [open $options(-out_state) w]
puts $fp "TARGET=$target"
puts $fp "DEVICE=$dev"
puts $fp "ILA=$ila"
puts $fp "STATUS_PRE.CORE_STATUS=$status_pre"
puts $fp "STATUS_PRE.SAMPLE_COUNT=$sample_count_pre"
puts $fp "STATUS_PRE.TRIGGER_POSITION=$trigger_pos_pre"
puts $fp "STATUS.CORE_STATUS=[get_property STATUS.CORE_STATUS $ila]"
puts $fp "STATUS.SAMPLE_COUNT=[get_property STATUS.SAMPLE_COUNT $ila]"
puts $fp "STATUS.TRIGGER_POSITION=[get_property STATUS.TRIGGER_POSITION $ila]"
close $fp

close_hw_target
exit
