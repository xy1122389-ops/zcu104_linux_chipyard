# Try DDR access via A53 target instead of PSU
connect -url tcp:127.0.0.1:3121

puts "=== Current targets ==="
targets

# Select A53 core
puts "\n=== Try A53 #0 ==="
catch {
    targets -set -nocase -filter {name =~ "*Cortex-A53 #0*"}
    puts "A53 #0 selected"
    
    # Release from APU reset
    puts "Releasing from reset..."
    rst -processor
    after 1000
    stop
    after 500
    
    puts "Trying DDR read via A53..."
    catch {
        set d [mrd -force 0x80000000 4]
        puts "DDR via A53: $d"
        puts "*** DDR WORKS VIA A53! ***"
    } derr
    if {$derr ne ""} { puts "DDR via A53 FAIL: $derr" }
    
    # Try SDIO1 register via A53
    catch {
        set v [mrd -force 0xFF1700FC 1]
        puts "SDIO1 via A53: $v"
    } serr
    if {$serr ne ""} { puts "SDIO1 via A53 FAIL: $serr" }
} err
if {$err ne ""} {
    puts "A53 fail: $err"
}

# Also try via PSU with force-mem-accesses
puts "\n=== Try PSU with force-mem-accesses ==="
catch {
    targets -set -nocase -filter {name =~ "*PSU*"}
    configparams force-mem-accesses 1
    set d2 [mrd -force 0x80000000 1]
    puts "DDR via PSU (force): $d2"
} perr
if {$perr ne ""} { puts "PSU DDR FAIL: $perr" }

disconnect
exit
