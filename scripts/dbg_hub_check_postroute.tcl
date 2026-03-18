set dcp [lindex $argv 0]
puts "=== OPEN_DCP ==="
puts $dcp
open_checkpoint $dcp

puts "=== GET_DEBUG_CORES ==="
set cores [get_debug_cores]
puts [join $cores "\n"]

puts "=== REPORT dbg_hub ==="
set dbg [get_debug_cores dbg_hub]
if {[llength $dbg] == 0} {
  puts "dbg_hub NOT FOUND"
} else {
  report_property $dbg
}

puts "=== REPORT u_ila_heartbeat ==="
set ila [get_debug_cores u_ila_heartbeat]
if {[llength $ila] == 0} {
  puts "u_ila_heartbeat NOT FOUND"
} else {
  report_property $ila
}

puts "=== C_USER_SCAN_CHAIN ==="
if {[llength $dbg] == 0} {
  puts "C_USER_SCAN_CHAIN=N/A"
} else {
  puts "C_USER_SCAN_CHAIN=[get_property C_USER_SCAN_CHAIN $dbg]"
}

puts "=== dbg_hub/clk net ==="
if {[llength $dbg] == 0} {
  puts "dbg_hub/clk=N/A"
} else {
  set clkpin [get_pins dbg_hub/clk]
  puts "PIN=$clkpin"
  set clknets [get_nets -of_objects $clkpin]
  puts "NETS=[join $clknets { }]"
}

puts "=== all_fanin to dbg_hub/clk ==="
if {[llength $dbg] != 0} {
  foreach x [all_fanin -to [get_pins dbg_hub/clk]] {
    puts $x
  }
}

puts "=== report_property dbg_hub/clk pin ==="
if {[llength $dbg] != 0} {
  report_property [get_pins dbg_hub/clk]
}

puts "=== clock driver details ==="
if {[llength $dbg] != 0} {
  set clkpin [get_pins dbg_hub/clk]
  set net [lindex [get_nets -of_objects $clkpin] 0]
  set drvPin [lindex [get_pins -of_objects $net -filter {DIRECTION == OUT}] 0]
  set drvCell [get_cells -of_objects $drvPin]
  puts "DBG_CLK_NET=$net"
  puts "DBG_CLK_DRV_PIN=$drvPin"
  puts "DBG_CLK_DRV_CELL=$drvCell"
  if {[llength $drvCell]} {
    puts "DBG_CLK_DRV_REF=[get_property REF_NAME $drvCell]"
  }
}

puts "=== checkpoint identity ==="
puts "CURRENT_DESIGN=[current_design]"
puts "CHECKPOINT_FILE=$dcp"

close_design
puts "=== DONE ==="
