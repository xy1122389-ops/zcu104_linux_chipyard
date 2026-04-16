# Simpler A53 DDR test - just select A53, stop, read
connect -url tcp:127.0.0.1:3121

puts "=== Targets ==="
targets

# Select A53 core
targets -set -nocase -filter {name =~ "*Cortex-A53 #0*"}
puts "A53 #0 selected"

# Just try to read DDR directly
puts "\n=== DDR read via A53 #0 ==="
catch {
    set d [mrd -force 0x80000000 4]
    puts "DDR: $d"
} derr
if {$derr ne ""} { 
    puts "DDR FAIL: $derr"
    
    # Try with configparams
    configparams force-mem-accesses 1
    catch {
        set d2 [mrd -force 0x80000000 4]
        puts "DDR (force): $d2"
    } derr2
    if {$derr2 ne ""} { puts "DDR (force) FAIL: $derr2" }
}

# Try OCM (0xFFFC0000) - this should work
puts "\n=== OCM test ==="
catch {
    set ocm [mrd -force 0xFFFC0000 4]
    puts "OCM: $ocm"
} oerr
if {$oerr ne ""} { puts "OCM FAIL: $oerr" }

# Read A53 PC
puts "\n=== A53 state ==="
catch {
    rrd
} rerr

disconnect
exit
