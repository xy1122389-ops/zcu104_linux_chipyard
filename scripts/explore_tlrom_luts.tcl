# Explore TLROM LUT structure in post_route.dcp
# Runs in Vivado batch mode

set wrkdir "//wsl.localhost/Ubuntu-22.04/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/obj"

puts "=== Opening post_route.dcp ==="
open_checkpoint [file join $wrkdir post_route.dcp]

puts "=== Finding TLROM cells ==="
set tlrom_cells [get_cells -hierarchical -filter {NAME =~ *TLROM*}]
puts "Total TLROM cells: [llength $tlrom_cells]"

# Show hierarchy
set tlrom_hier [get_cells -hierarchical -filter {NAME =~ *TLROM* && IS_PRIMITIVE == 0}]
puts "\nTLROM hierarchy cells: [llength $tlrom_hier]"
foreach c $tlrom_hier {
  puts "  HIER: $c [get_property REF_NAME $c]"
}

# Find LUT cells
set tlrom_luts [get_cells -hierarchical -filter {NAME =~ *TLROM* && REF_NAME =~ LUT*}]
puts "\nTLROM LUT cells: [llength $tlrom_luts]"

# Categorize by LUT type
foreach luttype {LUT1 LUT2 LUT3 LUT4 LUT5 LUT6 LUT6_2} {
  set count [llength [get_cells -hierarchical -filter "NAME =~ *TLROM* && REF_NAME == $luttype"]]
  if {$count > 0} {
    puts "  $luttype: $count"
  }
}

# Show a few example LUT cells with their properties
puts "\n=== Sample LUT6 cells ==="
set sample_luts [lrange [get_cells -hierarchical -filter {NAME =~ *TLROM* && REF_NAME == LUT6}] 0 4]
foreach lut $sample_luts {
  set init [get_property INIT $lut]
  set pins [get_pins -of_objects $lut]
  set nets {}
  foreach pin $pins {
    set net [get_nets -of_objects $pin -quiet]
    lappend nets "[get_property REF_PIN_NAME $pin]=$net"
  }
  puts "  $lut"
  puts "    INIT=$init"
  puts "    PINS: $nets"
}

# Find the _GEN output register/wire structure
puts "\n=== Looking for _GEN related cells ==="
set gen_cells [get_cells -hierarchical -filter {NAME =~ *TLROM*_GEN*}]
puts "GEN cells: [llength $gen_cells]"
foreach c [lrange $gen_cells 0 9] {
  puts "  $c [get_property REF_NAME $c]"
}

# Check MUXF7/MUXF8 cells
foreach muxtype {MUXF7 MUXF8 MUXF9} {
  set count [llength [get_cells -hierarchical -filter "NAME =~ *TLROM* && REF_NAME == $muxtype"]]
  if {$count > 0} {
    puts "\n$muxtype cells: $count"
  }
}

# Summary: total primitive cells
set all_prims [get_cells -hierarchical -filter {NAME =~ *TLROM* && IS_PRIMITIVE == 1}]
puts "\nTotal TLROM primitive cells: [llength $all_prims]"
set ref_names {}
foreach c $all_prims {
  set rn [get_property REF_NAME $c]
  dict incr ref_names $rn
}
foreach {rn cnt} $ref_names {
  puts "  $rn: $cnt"
}

close_design
puts "=== Done ==="
