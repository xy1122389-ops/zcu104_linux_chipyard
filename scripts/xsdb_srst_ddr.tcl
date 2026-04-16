# Try PMU GLOBAL_GEN_STORAGE0 and system-level reset
# ZynqMP PMU can trigger a full power cycle of all domains
connect -url tcp:127.0.0.1:3121

# First get PSU target
targets -set -nocase -filter {name =~ "PS TAP"}
rst -por
after 5000
targets -set -nocase -filter {name =~ "*PSU*"}
puts "PSU ok"

# Method 1: PMU GLOBAL_RESET
# 0xFFD80000: PMU_GLOBAL base
# Method: Write to PS_ONLY_RESET or GLOBAL_RESET via PMU
puts "\n=== Method: SRST via PS TAP (resets entire SoC) ==="
targets -set -nocase -filter {name =~ "PS TAP"}

# SRST should toggle the PS_SRST_B pin which resets the entire PS including DDR interface
rst -srst
puts "SRST done, waiting 8s..."  
after 8000

targets -set -nocase -filter {name =~ "*PSU*"}
puts "PSU ok after SRST"

# Now run psu_init
set psu_file {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig\obj\ip\zcu104ps\psu_init.tcl}
source $psu_file
psu_init
puts "psu_init done after SRST"

# Check DDR status  
set stat [mrd -force 0xFD070004 1]
puts "DDR_STAT: $stat"
set pgsr0 [mrd -force 0xFD080030 1]
puts "PHY_PGSR0: $pgsr0"

# Test DDR memory
puts "\n=== DDR Memory Test (after SRST + psu_init) ==="
catch {
    mwr -force 0x80000000 0xA5A5A5A5
    set d [mrd -force 0x80000000 1]
    puts "DDR test: $d"
    puts "*** DDR WORKS! ***"
} derr
if {$derr ne ""} { 
    puts "DDR FAIL: $derr"

    puts "\n=== Trying XSDB memory write to DDR via CRL write path ==="
    # Try writing DDR via different access path
    # Write to DDR through Cortex-A53 context
    catch {
        targets -set -nocase -filter {name =~ "*A53*#0*"}
        puts "A53#0 selected"
        rst -processor
        after 1000
        # Read from A53 perspective
        catch {
            set d2 [mrd -force 0x80000000 1]
            puts "DDR via A53: $d2"
            puts "*** DDR WORKS via A53! ***"
        } derr2
        if {$derr2 ne ""} { puts "DDR via A53 FAIL: $derr2" }
    } err3
    if {$err3 ne ""} { puts "A53 fail: $err3" }
}

disconnect
exit
