array set options {
    -bitstream_path ""
    -probes_path    ""
    -target_index   "0"
    -trigger_probe  "wrap_enq"
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
    puts "Usage: vivado -mode batch -source arm_uart_ctrl_ila_zcu104.tcl -tclargs -bitstream_path <bit> -probes_path <ltx> -out_state <state> ?-trigger_probe wrap_enq|uart_enq|txq_enq|txen? ?-trigger_value 0|1?"
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

set wrap_enq_probe ""
set uart_enq_probe ""
set txq_enq_probe ""
set txen_probe ""
set all_probe_names {}
foreach p $probes {
    set pname [get_property NAME $p]
    lappend all_probe_names $pname
    if {$wrap_enq_probe eq "" && [string match "*uartClockDomainWrapper/do_enq*" $pname]} {
        set wrap_enq_probe $p
    }
    if {$uart_enq_probe eq "" && [string match "*uartClockDomainWrapper/uart_0/do_enq*" $pname]} {
        set uart_enq_probe $p
    }
    if {$txq_enq_probe eq "" && [string match "*uartClockDomainWrapper/uart_0/txq/do_enq*" $pname]} {
        set txq_enq_probe $p
    }
    if {$txen_probe eq "" && [string match "*uartClockDomainWrapper/txen0*" $pname]} {
        set txen_probe $p
    }
}

if {$wrap_enq_probe eq "" || $uart_enq_probe eq "" || $txq_enq_probe eq "" || $txen_probe eq ""} {
    puts "ERROR: could not resolve wrap_enq/uart_enq/txq_enq/txen probes"
    puts "PROBE_NAMES=$all_probe_names"
    exit 5
}

foreach p [list $wrap_enq_probe $uart_enq_probe $txq_enq_probe $txen_probe] {
    set_property TRIGGER_COMPARE_VALUE "eq1'bX" $p
    set_property CAPTURE_COMPARE_VALUE "eq1'bX" $p
}

if {$options(-trigger_probe) eq "uart_enq"} {
    set trigger_probe_obj $uart_enq_probe
} elseif {$options(-trigger_probe) eq "txq_enq"} {
    set trigger_probe_obj $txq_enq_probe
} elseif {$options(-trigger_probe) eq "txen"} {
    set trigger_probe_obj $txen_probe
} else {
    set trigger_probe_obj $wrap_enq_probe
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
puts $fp "WRAP_ENQ_PROBE=$wrap_enq_probe"
puts $fp "UART_ENQ_PROBE=$uart_enq_probe"
puts $fp "TXQ_ENQ_PROBE=$txq_enq_probe"
puts $fp "TXEN_PROBE=$txen_probe"
close $fp

close_hw_target
exit
