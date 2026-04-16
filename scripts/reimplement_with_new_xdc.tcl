####################################################################
# Reimplement from post_synth.dcp with updated XDC pin constraints
# Usage (from WSL): cmd.exe /c vivado.bat -nojournal -mode batch -source <this_script>
####################################################################

# Use UNC paths that Windows Vivado can access via WSL filesystem
set wsl_prefix "//wsl.localhost/Ubuntu-22.04"
set build_dir "${wsl_prefix}/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig"
set obj_dir   [file join $build_dir "obj"]
set rpt_dir   [file join $obj_dir "report"]
set new_xdc   "${wsl_prefix}/root/chipyard/fpga/vivado_build_pkg/ip-tcl/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig.shell.xdc"

file mkdir $rpt_dir

puts "=== Opening post_synth checkpoint ==="
open_checkpoint [file join $obj_dir "post_synth.dcp"]

# Remove old pin/iostandard constraints for SPI ports so we can apply new ones
# The DCP has the old FMC pin assignments baked in; clear them
foreach port_name {sdio_spi_clk sdio_spi_cs sdio_spi_dat_0 sdio_spi_dat_1 sdio_spi_dat_2 sdio_spi_dat_3} {
    set p [get_ports -quiet $port_name]
    if {$p ne ""} {
        reset_property PACKAGE_PIN $p
        reset_property IOSTANDARD  $p
        reset_property PULLUP      $p
        puts "  cleared constraints on $port_name"
    }
}

puts "=== Reading new XDC constraints ==="
read_xdc $new_xdc
puts "  XDC loaded: $new_xdc"

# Verify new pin assignments
puts "=== Verify new pin assignments ==="
foreach port_name {sdio_spi_clk sdio_spi_cs sdio_spi_dat_0 sdio_spi_dat_1 sdio_spi_dat_2 sdio_spi_dat_3} {
    set p [get_ports -quiet $port_name]
    if {$p ne ""} {
        puts "  $port_name => [get_property PACKAGE_PIN $p] / [get_property IOSTANDARD $p]"
    }
}

puts "=== Opt design ==="
opt_design
write_checkpoint -force [file join $obj_dir "post_opt.dcp"]

puts "=== Place design ==="
place_design
phys_opt_design
write_checkpoint -force [file join $obj_dir "post_place.dcp"]
report_timing_summary -file [file join $rpt_dir "post_place_timing_summary.rpt"]

puts "=== Route design ==="
route_design
write_checkpoint -force [file join $obj_dir "post_route.dcp"]
report_timing_summary -file [file join $rpt_dir "post_route_timing_summary.rpt"]
report_utilization -file [file join $rpt_dir "post_route_utilization.rpt"]
report_drc -file [file join $rpt_dir "post_route_drc.rpt"]

puts "=== Write bitstream ==="
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
write_bitstream -force [file join $obj_dir "ZCU104FPGATestHarness.bit"]

puts "=== Done! Bitstream: [file join $obj_dir ZCU104FPGATestHarness.bit] ==="
