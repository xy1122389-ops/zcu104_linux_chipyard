# Test DDR access and SDIO1 from PS side
connect -url tcp:127.0.0.1:3121
targets -set -nocase -filter {name =~ "*PSU*"}

puts "=== DDR Access Test ==="
catch {
    set ddr [mrd -force 0x80000000 4]
    puts "DDR 0x80000000: $ddr"
} err
if {$err ne ""} { puts "DDR FAIL: $err" }

puts "\n=== SDIO1 Test ==="
catch {
    set ver [mrd -force 0xFF1700FC 1]
    puts "SDIO1_VER: $ver"
} err2
if {$err2 ne ""} { puts "SDIO1 FAIL: $err2" }

puts "\n=== AFIFM6 Config ==="
set r1 [mrd -force 0xFF9B0000 1]
puts "AFIFM6_RDCTRL: $r1"
set r2 [mrd -force 0xFF9B0014 1]
puts "AFIFM6_WRCTRL: $r2"

disconnect
exit
