# Skip DDR test - just POR + init + program + isolation
# Then let J-Link handle testing
connect -url tcp:127.0.0.1:3121

# POR
puts "=== POR ==="
targets -set -nocase -filter {name =~ "PS TAP"} 
rst -por
after 6000

# Check targets
puts "\n=== Targets ==="
targets

# PSU init
puts "\n=== psu_init ==="
targets -set -nocase -filter {name =~ "*PSU*"}
set psu_file {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig\obj\ip\zcu104ps\psu_init.tcl}
source $psu_file
psu_init
puts "psu_init done"

# DDR status only (no actual DDR access)
set stat [mrd -force 0xFD070004 1]
puts "DDR operating: $stat"

# Program bitstream
puts "\n=== Program bitstream ==="
targets -set -nocase -filter {name =~ "*PL*"}
set bit_file {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig\obj\ZCU104FPGATestHarness.bit}
fpga $bit_file
after 3000
puts "Bitstream done"

# Isolation removal
puts "\n=== Isolation + Reset ==="
targets -set -nocase -filter {name =~ "*PSU*"}
psu_ps_pl_isolation_removal
after 2000
psu_ps_pl_reset_config
puts "PS-PL configured"

# Verify PS-side registers still accessible (DON'T access DDR!)
puts "\n=== Post-config check ==="
set pl0 [mrd -force 0xFF5E00C0 1]
puts "PL0_REF_CTRL: $pl0"

set afim6r [mrd -force 0xFF9B0000 1]
puts "AFIFM6_RDCTRL: $afim6r"

set afim6w [mrd -force 0xFF9B0014 1]
puts "AFIFM6_WRCTRL: $afim6w"

# Check SDIO1 VERSION from PS side
set ver [mrd -force 0xFF1700FC 1]
puts "SDIO1_VER (PS-side): $ver"

puts "\n=== READY FOR J-LINK ==="
disconnect
exit
