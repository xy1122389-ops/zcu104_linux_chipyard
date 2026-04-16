# Fix: write bootloop via PSU, release A53, then test DDR via A53
connect -url tcp:127.0.0.1:3121

# POR
targets -set -nocase -filter {name =~ "PS TAP"}
rst -por
after 6000

# psu_init
targets -set -nocase -filter {name =~ "*PSU*"}
set psu_file {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig\obj\ip\zcu104ps\psu_init.tcl}
source $psu_file
psu_init
puts "psu_init done"
set stat [mrd -force 0xFD070004 1]
puts "DDR_STAT: $stat"

# Write bootloop at A53 reset vector via PSU context
# 0xFFFF0000 is OCM (on-chip memory) used as reset vector
# b 0 = branch to self (infinite loop) = 0x14000000 (ARM64)
puts "\n=== Write A53 bootloop ==="
mwr -force 0xFFFF0000 0x14000000
puts "Bootloop written"

# Release A53 from reset
puts "\n=== Release A53 ==="
targets -set -nocase -filter {name =~ "*Cortex-A53 #0*"}
rst -processor -clear-registers
after 1000
catch { stop }
after 500
puts "A53 released & stopped"

# Read A53 PC
catch {
    set pc [rrd pc]
    puts "A53 PC: $pc"
}

# Test DDR via A53 context
puts "\n=== DDR via A53 ==="
catch {
    mwr -force 0x80000000 0xDEADBEEF
    set d [mrd -force 0x80000000 1]
    puts "DDR: $d"
    mwr -force 0x80000004 0xCAFEBABE
    set d2 [mrd -force 0x80000004 1]
    puts "DDR+4: $d2"
    puts "*** DDR WORKS! ***"
} derr
if {$derr ne ""} {
    puts "DDR FAIL: $derr"
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
puts "PS-PL done"

# Verify
puts "\n=== Final verify ==="
set ver [mrd -force 0xFF1700FC 1]
puts "SDIO1_VER: $ver"

puts "\n=== READY FOR J-LINK ==="
disconnect
exit
