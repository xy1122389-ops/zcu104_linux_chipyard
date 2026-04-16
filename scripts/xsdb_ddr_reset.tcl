# Try PMU-based system reset for full DDR recovery
connect -url tcp:127.0.0.1:3121

# First POR to get PSU accessible
targets -set -nocase -filter {name =~ "PS TAP"}
rst -por
after 5000

targets -set -nocase -filter {name =~ "*PSU*"}
puts "PSU ok"

# Check DDR status before any init
puts "\n=== Pre-init DDR controller regs ==="
set stat0 [mrd -force 0xFD070004 1]
puts "DDR_STAT (pre-init): $stat0"

# Try triggering PMU system reset
# CRL_APB_RST_LPD_TOP has PS_ONLY_RST at bit 15  
# Let's try: PMU_GLOBAL_GLOBAL_RESET
puts "\n=== Attempting system reset via PMU ==="
# Write to PMU_GLOBAL GLOBAL_RESET (0xFFD80100)
# Bit 0: FPD_RST = 1 (FPD reset)
# Bit 1: RPU_LSR = 1 (RPU lockstep reset)  
# Bit 4: PS_ONLY_RST = 1 (PS system reset)
catch {
    # Try PS_ONLY_RST
    mwr -force 0xFFD80700 0x00000001
    puts "PMU PS_ONLY_RST triggered"
} err
if {$err ne ""} { puts "PMU reset failed: $err" }

# Or try CRL_RESET_CTRL1 to toggle DDR reset
puts "\n=== Trying DDR subsystem reset ==="
# DDRC software reset: CRF_APB_RST_DDR_SS at 0xFD1A0108
set ddr_rst [mrd -force 0xFD1A0108 1]
puts "RST_DDR_SS: $ddr_rst"

# Assert DDR controller reset
mwr -force 0xFD1A0108 0x0000000C
after 100
# Deassert DDR controller reset  
mwr -force 0xFD1A0108 0x00000000
after 100

puts "\n=== Run psu_init again ==="
set psu_file {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig\obj\ip\zcu104ps\psu_init.tcl}
source $psu_file
psu_init
puts "psu_init done"

puts "\n=== Post re-init DDR status ==="
set stat1 [mrd -force 0xFD070004 1]
puts "DDR_STAT: $stat1"
set pgsr0 [mrd -force 0xFD080030 1]
puts "PHY_PGSR0: $pgsr0"

# Test DDR memory with small timeout handling
puts "\n=== DDR Memory Test ==="
configparams force-mem-accesses 1
catch {
    mwr -force 0x80000000 0x12345678
    set d [mrd -force 0x80000000 1]
    puts "DDR test: $d"
    puts "*** DDR WORKS! ***"
} derr
if {$derr ne ""} { 
    puts "DDR FAIL: $derr"
    puts "\n*** PHYSICAL POWER CYCLE MAY BE REQUIRED ***"
}

disconnect
exit
