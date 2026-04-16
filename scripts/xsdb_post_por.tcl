# After POR reset, check targets and try full init
connect -url tcp:127.0.0.1:3121

puts "=== Post-POR targets ==="
targets -set -nocase -filter {name =~ "PS TAP"}

# Do POR again to be safe
puts "Issuing POR..."
rst -por
after 5000
puts "Wait complete"

puts "\n=== All targets now ==="
targets

# Check if PSU appeared
puts "\n=== Looking for PSU ==="
catch {
    targets -set -nocase -filter {name =~ "*PSU*"}
    puts "Found PSU!"
    targets
} err
if {$err ne ""} {
    puts "PSU not found: $err"
    
    # Check if A53 appeared
    catch {
        targets -set -nocase -filter {name =~ "*A53*"}
        puts "Found A53!"
        targets
    } err2
    if {$err2 ne ""} {
        puts "A53 not found: $err2"
        
        # List what we have
        puts "\nAvailable targets:"
        targets
    }
}

disconnect
exit
