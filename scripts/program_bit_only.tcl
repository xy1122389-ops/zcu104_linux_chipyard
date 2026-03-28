if {$argc != 1} {
  error "usage: xsdb program_bit_only.tcl <bit-file>"
}

set bitfile [lindex $argv 0]

connect -url tcp:127.0.0.1:3121
targets -set -nocase -filter {name =~ "*PSU*"}
fpga "$bitfile"
disconnect
exit
