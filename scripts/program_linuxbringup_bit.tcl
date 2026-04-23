connect -url tcp:127.0.0.1:3121
after 1000

puts "=== XSDB targets ==="
targets

puts "\n=== Program LinuxBringup PL bitstream ==="
targets -set -filter {name =~ "PL"}
if {![info exists ::env(CHIPYARD_BIT_WIN)] || $::env(CHIPYARD_BIT_WIN) eq ""} {
    error "CHIPYARD_BIT_WIN is not set"
}
set bit_file [string map {\\ /} $::env(CHIPYARD_BIT_WIN)]
puts "Bitstream: $bit_file"
fpga $bit_file
after 3000
puts "LinuxBringup PL bitstream programmed"

disconnect
exit
