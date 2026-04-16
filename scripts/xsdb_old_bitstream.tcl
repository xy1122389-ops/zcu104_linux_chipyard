# Test with OLD known-working bitstream
connect -url tcp:127.0.0.1:3121

# POR
targets -set -nocase -filter {name =~ "PS TAP"}
rst -por
after 6000

# psu_init
targets -set -nocase -filter {name =~ "*PSU*"}
# Use the SAME (correct 32-bit DDR) psu_init
set psu_file {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig\obj\ip\zcu104ps\psu_init.tcl}
source $psu_file
psu_init
puts "psu_init done"
set stat [mrd -force 0xFD070004 1]
puts "DDR_STAT: $stat"

# Program OLD bitstream (known working, 1MB window)
puts "\n=== Program OLD bitstream ==="
targets -set -nocase -filter {name =~ "*PL*"}
set bit_file {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig\obj\ZCU104FPGATestHarness.bit.bak.pre_2mb_20260414_092855}
fpga $bit_file
after 3000
puts "OLD bitstream done"

# Isolation + reset
targets -set -nocase -filter {name =~ "*PSU*"}
psu_ps_pl_isolation_removal
after 2000
psu_ps_pl_reset_config
puts "PS-PL done"

# Check
set ver [mrd -force 0xFF1700FC 1]
puts "SDIO1_VER: $ver"

puts "\n=== READY - Try J-Link with OLD bitstream ==="
disconnect
exit
