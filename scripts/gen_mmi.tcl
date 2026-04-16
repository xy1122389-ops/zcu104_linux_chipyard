# gen_mmi.tcl — Open post_route DCP, generate MMI and re-write bitstream
# Usage: vivado -mode batch -source gen_mmi.tcl

set fpga_dir [file normalize [file dirname [info script]]/..]
set cfg "chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig"
set gen  "${fpga_dir}/generated-src/${cfg}/obj"
set dcp  "${gen}/post_route.dcp"

# Use Windows-friendly paths for output
set win_temp "C:/Windows/Temp"
set mmi  "${win_temp}/bootrom.mmi"
set bit  "${win_temp}/ZCU104FPGATestHarness_fresh.bit"

puts "Opening $dcp ..."
open_checkpoint $dcp

# Show ROM BRAMs - use REF_NAME filter for UltraScale+
puts "\n=== All RAMB cells ==="
set all_brams [get_cells -hierarchical -filter {REF_NAME =~ RAMB*}]
puts "Total RAMB cells: [llength $all_brams]"
foreach b $all_brams {
    set name [get_property NAME $b]
    if {[regexp -nocase {rom|boot|TLROM|maskrom} $name]} {
        puts "ROM: $name  [get_property REF_NAME $b]"
    }
}

puts "\n=== First 20 RAMB cells ==="
set cnt 0
foreach b $all_brams {
    if {$cnt >= 20} break
    puts "  [get_property NAME $b]  [get_property REF_NAME $b]"
    incr cnt
}

write_mem_info -force $mmi
puts "MMI written: $mmi"

write_bitstream -force $bit
puts "Bitstream written: $bit"

close_design
puts "DONE."
