if { $argc < 2 } {
  puts "Usage: vivado -mode batch -source scripts/find_uart_probe_candidates.tcl -tclargs <in_post_synth_dcp> <out_file>"
  exit 2
}

set in_dcp [lindex $argv 0]
set out_file [lindex $argv 1]

proc dump_matches {fp label pattern} {
  set nets [lsort [get_nets -hier -quiet -filter "NAME =~ $pattern"]]
  puts $fp "$label pattern=$pattern count=[llength $nets]"
  foreach n $nets {
    puts $fp $n
  }
  puts $fp ""
}

open_checkpoint $in_dcp
set fp [open $out_file w]
puts $fp "IN_DCP=$in_dcp"

dump_matches $fp "UART_AND_DO_ENQ" {*uart*do_enq*}
dump_matches $fp "DO_ENQ" {*do_enq*}
dump_matches $fp "UART_WRAPPER_DO_ENQ" {*uartClockDomainWrapper*do_enq*}
dump_matches $fp "UART_TXEN" {*uart*txen*}
dump_matches $fp "UART_TXQ" {*uart*txq*}
dump_matches $fp "UART_RXQ" {*uart*rxq*}
dump_matches $fp "UART_TXD" {*uart*txd*}
dump_matches $fp "UART_RXD" {*uart*rxd*}
dump_matches $fp "UART_CONTROL_XING" {*uart*control_xing*}
dump_matches $fp "UART_COUPLER" {*coupler_to_device_named_uart_0*}
dump_matches $fp "UART_ONLY" {*uart*}

close $fp
puts "OUT_FILE=$out_file"
exit
