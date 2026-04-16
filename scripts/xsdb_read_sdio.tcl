# Read SDIO1 registers directly from PS side (via XSDB)
connect -url tcp:127.0.0.1:3121
targets -set -nocase -filter {name =~ "*PSU*"}

puts "=== Reading PS peripherals directly ==="

# UART0 at 0xFF000000
set u [mrd -force 0xFF000004 1]
puts "UART0 (0xFF000004): $u"

# SDIO1 VERSION at 0xFF1700FC
set v [mrd -force 0xFF1700FC 1]
puts "SDIO1_VER (0xFF1700FC): $v"

# SDIO1 base at 0xFF170000
set b [mrd -force 0xFF170000 1]
puts "SDIO1_BASE (0xFF170000): $b"

# SDIO1 caps at 0xFF170040
set c [mrd -force 0xFF170040 1]
puts "SDIO1_CAPS (0xFF170040): $c"

puts "=== Done ==="
disconnect
exit
