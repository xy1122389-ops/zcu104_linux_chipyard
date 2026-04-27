connect -url tcp:127.0.0.1:3121
after 1000

puts "=== XSDB targets ==="
targets

puts "\n=== Program Dual-Core PL bitstream ==="
targets -set -filter {name =~ "PL"}

if {![info exists ::env(CHIPYARD_BIT_WIN)] || $::env(CHIPYARD_BIT_WIN) eq ""} {
    error "CHIPYARD_BIT_WIN environment variable is not set"
}

set bit_file [string map {\\ /} $::env(CHIPYARD_BIT_WIN)]
puts "Bitstream: $bit_file"

if {![file exists $bit_file]} {
    error "Bitstream file not found: $bit_file"
}

puts "Programming FPGA with dual-core bitstream..."
fpga $bit_file

after 3000
puts "\n=== Dual-core bitstream programmed successfully ==="
puts "Ready to boot dual-core Linux via: scripts/linux_boot_dualcore.gdb"

disconnect
exit
