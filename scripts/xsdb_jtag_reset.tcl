# Try to recover ZCU104 via JTAG reset and DAP recovery
connect -url tcp:127.0.0.1:3121

puts "=== Attempting JTAG chain reset ==="
# List JTAG devices
catch {
    jtag targets
} err
puts "JTAG targets: $err"

# Try various reset methods on PS TAP
targets -set -nocase -filter {name =~ "PS TAP"}

# Check available reset types
puts "\n=== Trying different resets ==="
foreach rtype {por srst proc system} {
    catch {
        rst -$rtype
        puts "rst -$rtype: OK"
    } err
    if {$err ne ""} {
        puts "rst -$rtype: $err"
    }
}

# Try plain rst
catch {
    rst
    puts "rst (plain): OK"
} err
if {$err ne ""} {
    puts "rst (plain): $err"
}

after 2000

puts "\n=== Targets after resets ==="
targets

# Try targeting DAP directly
puts "\n=== Try DAP access ==="
catch {
    targets -set -nocase -filter {name =~ "*DAP*"}
    puts "DAP selected"
    # Try reading DAP regs
    catch {
        set val [mrd -force 0xF8000000 1]
        puts "DAP read: $val"
    } e2
    if {$e2 ne ""} {
        puts "DAP read failed: $e2"
    }
} e3

# Alternative: try to use PMU
puts "\n=== Try PMU target ==="
catch {
    targets -set -nocase -filter {name =~ "*PMU*"}
    puts "PMU selected"
    targets
} e4

disconnect
exit
