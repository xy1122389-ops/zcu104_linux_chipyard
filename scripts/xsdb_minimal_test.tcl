# Minimal test: just connect and try DDR read
connect -url tcp:127.0.0.1:3121

puts "=== Targets ==="
targets

puts "\n=== Try PSU target ==="
catch {
    targets -set -nocase -filter {name =~ "*PSU*"}
    puts "PSU selected"
} err
if {$err ne ""} {
    puts "PSU: $err"
    puts "\nTrying Cortex-A53 #0..."
    catch {
        targets -set -nocase -filter {name =~ "*Cortex-A53 #0*"}
        puts "A53#0 selected"
    } err2
    if {$err2 ne ""} {
        puts "A53#0: $err2"
    }
}

#  Test a simple CRL_APB register (known PS reg)
puts "\n=== Test PS register (CRL_APB) ==="
catch {
    set reg [mrd -force 0xFF5E0000 1]
    puts "CRL_APB_IOPLL_CTRL: $reg"
} err3
if {$err3 ne ""} { puts "CRL_APB FAIL: $err3" }

# Test DDR controller register (in PS DDR space)
puts "\n=== Test DDR controller register ==="
catch {
    set ddr_ctrl [mrd -force 0xFD070000 1]
    puts "DDR_CTRL: $ddr_ctrl"
} err4
if {$err4 ne ""} { puts "DDR_CTRL FAIL: $err4" }

# Test actual DDR memory
puts "\n=== Test DDR memory ==="
catch {
    set ddr_mem [mrd -force 0x80000000 1]
    puts "DDR_MEM: $ddr_mem"
} err5
if {$err5 ne ""} { puts "DDR_MEM FAIL: $err5" }

disconnect
exit
