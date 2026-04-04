# xsdb_ddr_readback.tcl — Read DDR first 128 bytes to verify content integrity

connect -url tcp:127.0.0.1:3121
configparams force-mem-accesses 1
targets -set -nocase -filter {name =~ "*PSU*"}

puts "\n=== DDR readback: 32 words (128 bytes) from PS DDR 0x00000000 ==="
puts "Ground truth (from fw_payload.bin): offset 0x42 should be part of 'add a0,s0,zero' (0x00040533)\n"

for {set i 0} {$i < 32} {incr i} {
    set addr [expr {$i * 4}]
    set val [mrd -force -value $addr]
    puts [format "  DDR 0x%04x : 0x%08x" $addr $val]
}

puts "\n=== Extended range 0x80-0xff (for context) ==="
for {set i 32} {$i < 64} {incr i} {
    set addr [expr {$i * 4}]
    set val [mrd -force -value $addr]
    puts [format "  DDR 0x%04x : 0x%08x" $addr $val]
}

disconnect
exit
