# Try to clear DAP errors and recover
connect -url tcp:127.0.0.1:3121

puts "=== JTAG Chain ==="
jtag targets

# Try POR via PS TAP
puts "\n=== POR via PS TAP ==="  
targets -set -nocase -filter {name =~ "PS TAP"}
rst -por
puts "POR issued, waiting 8s..."
after 8000

puts "\n=== Targets after POR ==="
set tgt_list [targets]
puts $tgt_list

# Check if DAP recovers
if {[string match "*PSU*" $tgt_list]} {
    puts "\nPSU found!"
    targets -set -nocase -filter {name =~ "*PSU*"}
    set r [mrd -force 0xFF5E0020 1]
    puts "IOPLL: $r"
} else {
    puts "\nPSU not found. Trying SRST..."
    targets -set -nocase -filter {name =~ "PS TAP"}
    rst -srst
    after 5000
    puts "Targets after SRST:"
    targets
    
    # Try one more time
    catch {
        targets -set -nocase -filter {name =~ "*PSU*"}
        puts "PSU found after SRST!"
    } err
    if {$err ne ""} {
        puts "Still no PSU: $err"
        
        puts "\n=== Trying DAP direct access ==="
        catch {
            targets 4
            puts "DAP selected"
            # Try to read - it may fail but clear the error
            catch { mrd -force 0xF8000000 1 }
            after 1000
            targets
        } derr
        if {$derr ne ""} { puts "DAP: $derr" }
    }
}

disconnect
exit
