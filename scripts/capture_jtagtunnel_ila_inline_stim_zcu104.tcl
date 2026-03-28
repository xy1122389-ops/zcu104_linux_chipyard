array set options {
    -bitstream_path ""
    -probes_path    ""
    -target_index   "0"
    -skip_program   "0"
    -dr_bits        ""
    -dr_hex         ""
    -xsdb_script    ""
    -jtag_hz        "10000"
    -out_csv        ""
    -out_state      ""
    -out_stim       ""
}

for {set i 0} {$i < $argc} {incr i 2} {
    set arg [lindex $argv $i]
    set val [lindex $argv [expr $i+1]]
    if {[info exists options($arg)]} {
        set options($arg) $val
    }
}

foreach req {-bitstream_path -probes_path -out_csv -out_state -out_stim} {
    if {$options($req) eq ""} {
        puts "Usage: vivado -mode batch -source capture_jtagtunnel_ila_inline_stim_zcu104.tcl -tclargs -bitstream_path <bit> -probes_path <ltx> -dr_bits <n> -dr_hex <hex> -out_csv <csv> -out_state <state> -out_stim <stimlog> ?-jtag_hz 10000? ?-target_index 0?"
        exit 2
    }
}
if {$options(-xsdb_script) eq ""} {
    foreach req {-dr_bits -dr_hex} {
        if {$options($req) eq ""} {
            puts "Usage: vivado -mode batch -source capture_jtagtunnel_ila_inline_stim_zcu104.tcl -tclargs -bitstream_path <bit> -probes_path <ltx> -dr_bits <n> -dr_hex <hex> -out_csv <csv> -out_state <state> -out_stim <stimlog> ?-jtag_hz 10000? ?-target_index 0?"
            exit 2
        }
    }
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
if {$options(-skip_program) ne "1"} {
    set_property PROGRAM.FILE $options(-bitstream_path) [current_hw_device]
    program_hw_devices [current_hw_device]
}
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
run_hw_ila $ila

set xsdb_bat "E:\\PRO_APP\\xilinx\\Vivado\\2021.2\\bin\\xsdb.bat"
set generated_xsdb_script 0
if {$options(-xsdb_script) eq ""} {
    set xsdb_tcl [file nativename [file join $::env(TEMP) [format "xsdb_inline_%d.tcl" [pid]]]]
    set fp_xsdb [open $xsdb_tcl w]
    puts $fp_xsdb "connect -url tcp:127.0.0.1:3121"
    puts $fp_xsdb "jtag targets -set -filter {name == \"xczu7\"}"
    puts $fp_xsdb "jtag frequency $options(-jtag_hz)"
    puts $fp_xsdb {set seq [jtag sequence]}
    puts $fp_xsdb {$seq irshift -integer 12 0x926}
    puts $fp_xsdb "\$seq drshift -capture -integer $options(-dr_bits) $options(-dr_hex)"
    puts $fp_xsdb {puts "RUN=[$seq run -hex]"}
    puts $fp_xsdb {$seq delete}
    puts $fp_xsdb "exit"
    close $fp_xsdb
    set generated_xsdb_script 1
} else {
    set xsdb_tcl [file nativename $options(-xsdb_script)]
}

set stim_cmd [list cmd /c $xsdb_bat $xsdb_tcl]
set stim_out ""
set stim_rc [catch {set stim_out [eval exec $stim_cmd]} stim_err]
set fp_stim [open $options(-out_stim) w]
puts $fp_stim $stim_out
if {$stim_rc != 0} {
    puts $fp_stim $stim_err
}
close $fp_stim
if {$generated_xsdb_script} {
    file delete -force $xsdb_tcl
}

upload_hw_ila_data $ila
write_hw_ila_data -force -csv_file $options(-out_csv) [get_hw_ila_data $ila]

set fp [open $options(-out_state) w]
puts $fp "TARGET=$target"
puts $fp "DEVICE=$dev"
puts $fp "ILA=$ila"
puts $fp "SHIFT_PROBE=$shift_probe"
puts $fp "SKIP_PROGRAM=$options(-skip_program)"
puts $fp "STATUS.CORE_STATUS=[get_property STATUS.CORE_STATUS $ila]"
puts $fp "STATUS.SAMPLE_COUNT=[get_property STATUS.SAMPLE_COUNT $ila]"
puts $fp "STATUS.TRIGGER_POSITION=[get_property STATUS.TRIGGER_POSITION $ila]"
puts $fp "STIM_RC=$stim_rc"
close $fp

close_hw_target
exit
