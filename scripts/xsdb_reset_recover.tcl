# Try to recover ZCU104 from DAP error state
connect -url tcp:127.0.0.1:3121

puts "=== Current targets ==="
targets

puts "\n=== Trying system reset via PS TAP ==="
catch {
    targets -set -nocase -filter {name =~ "PS TAP"}
    puts "Selected PS TAP"
    # Try system reset
    rst -system
    puts "System reset issued"
    after 3000
} err
if {$err ne ""} {
    puts "PS TAP reset failed: $err"
}

puts "\n=== Targets after reset ==="
targets

# Try to select PSU
catch {
    targets -set -nocase -filter {name =~ "*PSU*"}
    puts "PSU target found!"
} err2
if {$err2 ne ""} {
    puts "PSU still not available: $err2"
    
    # Try PL target for bitstream programming
    puts "\n=== Trying PL target ==="
    catch {
        targets -set -nocase -filter {name =~ "*PL*"}
        puts "PL target selected"
        targets
    } err3
    if {$err3 ne ""} {
        puts "PL target failed: $err3"
    }
}

disconnect
exit
