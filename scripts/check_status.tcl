connect -url tcp:127.0.0.1:3121
after 2000
puts "=== Available targets ==="
targets
puts ""
puts "=== Read DDR sentinel (0x00000000 = Rocket 0x80000000) ==="
targets -set -nocase -filter {name =~ "*PSU*"}
set val [mrd -force -value 0x00000000]
puts [format "  DDR[0x00000000] = 0x%08x" $val]
set val2 [mrd -force -value 0x00000004]
puts [format "  DDR[0x00000004] = 0x%08x" $val2]
set val3 [mrd -force -value 0x00000008]
puts [format "  DDR[0x00000008] = 0x%08x" $val3]
set val4 [mrd -force -value 0x0000000c]
puts [format "  DDR[0x0000000c] = 0x%08x" $val4]
set val5 [mrd -force -value 0x00000040]
puts [format "  DDR[0x00000040] = 0x%08x" $val5]
# Also check if firmware is still there at offset 0x10 (not touched by DDR test)
set val6 [mrd -force -value 0x00000010]
puts [format "  DDR[0x00000010] = 0x%08x (should be OpenSBI)" $val6]
disconnect
exit
