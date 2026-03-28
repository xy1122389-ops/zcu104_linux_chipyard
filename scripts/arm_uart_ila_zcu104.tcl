array set options {
    -bitstream_path ""
    -probes_path    ""
    -target_index   "0"
    -trigger_probe  "tx"
    -trigger_value  "0"
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
    puts "Usage: vivado -mode batch -source arm_uart_ila_zcu104.tcl -tclargs -bitstream_path <bit> -probes_path <ltx> -out_state <state> ?-trigger_probe tx|rx? ?-trigger_value 0|1?"
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
if {[llength $probes] < 3} {
    puts "ERROR: expected at least 3 hw_probes, got [llength $probes]"
    puts "PROBES=$probes"
    exit 4
}

set tx_probe ""
set rx_probe ""
set rst_probe ""
set enq_probe ""
set all_probe_names {}
foreach p $probes {
    set pname [get_property NAME $p]
    lappend all_probe_names $pname
    if {$tx_probe eq "" && [string match "*uart_txd_OBUF*" $pname]} {
        set tx_probe $p
    }
    if {$rx_probe eq "" && [string match "*uart_rxd_IBUF*" $pname]} {
        set rx_probe $p
    }
    if {$rst_probe eq "" && [string match "*_dutWrangler_auto_out_reset*" $pname]} {
        set rst_probe $p
    }
    if {$enq_probe eq "" && [string match "*do_enq*" $pname]} {
        set enq_probe $p
    }
}

if {$tx_probe eq "" || $rx_probe eq "" || $rst_probe eq ""} {
    puts "ERROR: could not resolve tx/rx/reset probes"
    puts "PROBE_NAMES=$all_probe_names"
    exit 5
}

foreach p [list $tx_probe $rx_probe $rst_probe] {
    if {$p ne ""} {
        set_property TRIGGER_COMPARE_VALUE "eq1'bX" $p
        set_property CAPTURE_COMPARE_VALUE "eq1'bX" $p
    }
}

if {$options(-trigger_probe) eq "rx"} {
    set trigger_probe_obj $rx_probe
} elseif {$options(-trigger_probe) eq "enq"} {
    if {$enq_probe eq ""} {
        puts "ERROR: requested enq trigger but no do_enq probe was found"
        puts "PROBE_NAMES=$all_probe_names"
        exit 6
    }
    set trigger_probe_obj $enq_probe
} else {
    set trigger_probe_obj $tx_probe
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
puts $fp "TX_PROBE=$tx_probe"
puts $fp "RX_PROBE=$rx_probe"
puts $fp "RST_PROBE=$rst_probe"
puts $fp "ENQ_PROBE=$enq_probe"
close $fp

close_hw_target
exit
