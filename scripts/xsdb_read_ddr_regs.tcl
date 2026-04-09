# Quick register check: read DDR controller MSTR and PHY status
puts "==== Connect ===="
connect -url tcp:127.0.0.1:3121

puts "\n==== Targets ===="
targets

puts "\n==== Select PSU/DAP ===="
# Try PSU first
if {[catch {targets -set -nocase -filter {name =~ "*PSU*"}} err]} {
    puts "PSU not found, trying DAP..."
    targets -set -nocase -filter {name =~ "*DAP*"}
}

puts "\n==== Read MSTR (FD070000) ===="
set val [mrd -force 0xFD070000]
puts "MSTR = $val"

puts "\n==== Read ADDRMAP2 (FD070208) ===="
set val [mrd -force 0xFD070208]
puts "ADDRMAP2 = $val"

puts "\n==== Read PCCFG (FD070400) ===="
set val [mrd -force 0xFD070400]
puts "PCCFG = $val"

puts "\n==== Read DDR PHY PGCR (FD080120) ===="
set val [mrd -force 0xFD080120]
puts "PGCR = $val"

puts "\n==== DDR Memory test ===="
mwr -force 0x80000000 0xDEADBEEF
mwr -force 0x80000004 0xCAFEBABE
set val1 [mrd -force 0x80000000]
set val2 [mrd -force 0x80000004]
puts "DDR[0x80000000] = $val1"
puts "DDR[0x80000004] = $val2"

# Test bit-13 aliasing: write different values to addr and addr^0x2000
mwr -force 0x80010000 0x11111111
mwr -force 0x80012000 0x22222222
set val_a [mrd -force 0x80010000]
set val_b [mrd -force 0x80012000]
puts "\n==== Bit-13 aliasing test ===="
puts "DDR[0x80010000] = $val_a (expect 0x11111111)"
puts "DDR[0x80012000] = $val_b (expect 0x22222222)"

disconnect
exit
