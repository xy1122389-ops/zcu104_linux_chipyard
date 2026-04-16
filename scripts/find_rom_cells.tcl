# Find the BootROM cells in the flattened post_route netlist

set wrkdir "//wsl.localhost/Ubuntu-22.04/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/obj"

puts "=== Opening post_route.dcp ==="
open_checkpoint [file join $wrkdir post_route.dcp]

# Try different patterns to find the ROM
puts "\n=== Search 1: *bootrom* ==="
set cells1 [get_cells -hierarchical -filter {NAME =~ *bootrom*}]
puts "bootrom cells: [llength $cells1]"
foreach c [lrange $cells1 0 4] { puts "  $c [get_property REF_NAME $c]" }

puts "\n=== Search 2: *rom* (non-primitive) ==="
set cells2 [get_cells -hierarchical -filter {NAME =~ *rom* && IS_PRIMITIVE == 0}]
puts "rom hier cells: [llength $cells2]"
foreach c [lrange $cells2 0 9] { puts "  $c [get_property REF_NAME $c]" }

puts "\n=== Search 3: *BootROM* ==="
set cells3 [get_cells -hierarchical -filter {NAME =~ *BootROM*}]
puts "BootROM cells: [llength $cells3]"
foreach c [lrange $cells3 0 4] { puts "  $c [get_property REF_NAME $c]" }

puts "\n=== Search 4: Top-level hierarchy ==="
set top_cells [get_cells]
puts "Top-level cells: [llength $top_cells]"
foreach c $top_cells { puts "  $c [get_property REF_NAME $c]" }

puts "\n=== Search 5: Second-level hierarchy ==="
foreach tc $top_cells {
  set children [get_cells -quiet ${tc}/*]
  if {[llength $children] > 0} {
    puts "  ${tc}/ has [llength $children] children"
    foreach ch [lrange $children 0 4] {
      puts "    $ch [get_property REF_NAME $ch]"
    }
    if {[llength $children] > 5} { puts "    ..." }
  }
}

puts "\n=== Search 6: *_GEN* cells ==="
set gen_cells [get_cells -hierarchical -filter {NAME =~ *_GEN*} -quiet]
puts "_GEN cells: [llength $gen_cells]"
foreach c [lrange $gen_cells 0 9] { puts "  $c [get_property REF_NAME $c]" }

puts "\n=== Search 7: LUT cells with 'rom' or 'ROM' in net names ==="
set rom_nets [get_nets -hierarchical -filter {NAME =~ *rom*} -quiet]
puts "rom nets: [llength $rom_nets]"
foreach n [lrange $rom_nets 0 9] { puts "  $n" }

close_design
puts "=== Done ==="
