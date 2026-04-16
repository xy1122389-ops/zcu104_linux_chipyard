# Complete flow: POR → init → A53 DDR test → bitstream → J-Link prep
# KEY: Never access DDR via PSU target! Use A53 context instead.
connect -url tcp:127.0.0.1:3121

# POR
puts "=== POR ==="
targets -set -nocase -filter {name =~ "PS TAP"}
rst -por
after 6000

puts "=== Targets ==="
targets

# psu_init
puts "\n=== psu_init ==="
targets -set -nocase -filter {name =~ "*PSU*"}
set psu_file {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig\obj\ip\zcu104ps\psu_init.tcl}
source $psu_file
psu_init
puts "psu_init done"

# DDR status (controller regs only, NOT DDR memory!)
set stat [mrd -force 0xFD070004 1]
puts "DDR_STAT: $stat"

# Now try A53 to access DDR
puts "\n=== DDR via A53 ==="
targets -set -nocase -filter {name =~ "*Cortex-A53 #0*"}
puts "A53 selected"

# Write boot loop at reset vector so A53 doesn't crash
mwr -force 0xFFFF0000 0x14000000

# Release A53 from reset
rst -processor -clear-registers
after 500
stop
after 500
puts "A53 stopped"

# Now try DDR access via A53
catch {
    mwr -force 0x80000000 0xDEADBEEF
    mwr -force 0x80000004 0xCAFEBABE
    set d0 [mrd -force 0x80000000 1]
    set d1 [mrd -force 0x80000004 1]
    puts "DDR[0]: $d0"
    puts "DDR[1]: $d1"
    puts "*** DDR WORKS via A53! ***"
} derr
if {$derr ne ""} {
    puts "DDR via A53 FAIL: $derr"
    puts "*** PHYSICAL POWER CYCLE NEEDED ***"
}

# Program bitstream
puts "\n=== Program bitstream ==="
targets -set -nocase -filter {name =~ "*PL*"}
set bit_file {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig\obj\ZCU104FPGATestHarness.bit}
fpga $bit_file
after 3000
puts "Bitstream done"

# PS-PL isolation + reset
puts "\n=== Isolation + Reset ==="
targets -set -nocase -filter {name =~ "*PSU*"}
psu_ps_pl_isolation_removal
after 2000
psu_ps_pl_reset_config
puts "PS-PL configured"

# Final checks
puts "\n=== Verify ==="
set pl0 [mrd -force 0xFF5E00C0 1]
puts "PL0_REF: $pl0"
set ver [mrd -force 0xFF1700FC 1]
puts "SDIO1_VER: $ver"

puts "\n=== READY ==="
disconnect
exit
