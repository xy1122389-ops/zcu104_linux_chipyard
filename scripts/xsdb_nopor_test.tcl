# Test WITHOUT POR: just connect and check what's there
connect -url tcp:127.0.0.1:3121

puts "=== Current targets ==="
targets

# Try PSU
puts "\n=== Try accessing PS registers ==="
catch {
    targets -set -nocase -filter {name =~ "*PSU*"}
    puts "PSU ok"
    set r [mrd -force 0xFF5E0020 1]
    puts "IOPLL_CTRL: $r"
} err
if {$err ne ""} {
    puts "PSU fail: $err"
    
    # Try A53 instead
    puts "\nTrying A53..."
    catch {
        targets -set -filter {name =~ "*A53*" && name =~ "*#0*"}
        puts "A53#0 ok"
    } err2
    if {$err2 ne ""} { puts "A53 fail: $err2" }
}

# The board may be in a bad state. Try writing to DAP CTRL/STAT to clear errors
puts "\n=== Try JTAG level ops ==="
catch {
    # Scan the JTAG chain
    set jtag_list [jtag targets]
    puts "JTAG: $jtag_list"
    
    # Try to do a JTAG reset
    jtag sequence arm_dap [list state RESET]
} jerr
if {[info exists jerr] && $jerr ne ""} { puts "JTAG ops: $jerr" }

disconnect
exit
