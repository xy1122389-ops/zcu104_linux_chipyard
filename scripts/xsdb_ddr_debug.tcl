# Debug DDR training: POR → psu_init → check DDR status registers
connect -url tcp:127.0.0.1:3121

# POR
targets -set -nocase -filter {name =~ "PS TAP"}
rst -por
after 5000
puts "POR done"

# Select PSU  
targets -set -nocase -filter {name =~ "*PSU*"}
puts "PSU ok"

# Source and run psu_init with visible output
set psu_file {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig\obj\ip\zcu104ps\psu_init.tcl}
source $psu_file

puts "\n=== Running psu_init... ==="
psu_init
puts "psu_init done"

puts "\n=== DDR Status Registers ==="
# DDR_CTRL STAT (0xFD070004) - bit 0: operating mode
set stat [mrd -force 0xFD070004 1]
puts "DDR_STAT: $stat"

# DDR_CTRL MSTR (0xFD070000) - master register
set mstr [mrd -force 0xFD070000 1]
puts "DDR_MSTR: $mstr"

# DDR PHY PGSR0 (0xFD080030) - training status
set pgsr0 [mrd -force 0xFD080030 1]
puts "PHY_PGSR0: $pgsr0"

# DDR PHY PGSR1 (0xFD080034) - more status
set pgsr1 [mrd -force 0xFD080034 1]
puts "PHY_PGSR1: $pgsr1"

# DDR PHY GPR0 (0xFD080080) - general purpose
catch {
    set gpr0 [mrd -force 0xFD080080 1]
    puts "PHY_GPR0: $gpr0"
}

# DDR PHY RIDR (0xFD080000) - revision id  
set ridr [mrd -force 0xFD080000 1]
puts "PHY_RIDR: $ridr"

# DDR PHY DSGCR (0xFD080090)
set dsgcr [mrd -force 0xFD080090 1]
puts "PHY_DSGCR: $dsgcr"

puts "\n=== DDR Access Test ==="
catch {
    mwr -force 0x80000000 0xCAFEBABE
    set d [mrd -force 0x80000000 1]
    puts "DDR R/W: $d"
} derr
if {$derr ne ""} { puts "DDR FAIL: $derr" }

# Also test DDR controller directly (no DDR memory, just control regs)
puts "\n=== DDR Controller Regs ==="
set d1 [mrd -force 0xFD070018 1]
puts "DDR_MRSTAT: $d1"
set d2 [mrd -force 0xFD070060 1]
puts "DDR_RFSHCTL3: $d2"
set d3 [mrd -force 0xFD070200 1]
puts "DDR_ADDRMAP0: $d3"

disconnect
exit
