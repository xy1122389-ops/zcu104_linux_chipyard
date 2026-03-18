set dcp [lindex $argv 0]
open_checkpoint $dcp

puts "=== pll_locked_out path ==="
set p1 [get_ports pll_locked_out]
set n1 [get_nets -of_objects $p1]
puts "PORT=pll_locked_out NET=$n1"
set d1 [lindex [get_pins -of_objects $n1 -filter {DIRECTION == OUT}] 0]
puts "DRV_PIN=$d1"
puts "DRV_CELL=[get_cells -of_objects $d1]"

puts "=== clock_alive_out path ==="
set p2 [get_ports clock_alive_out]
set n2 [get_nets -of_objects $p2]
puts "PORT=clock_alive_out NET=$n2"
set d2 [lindex [get_pins -of_objects $n2 -filter {DIRECTION == OUT}] 0]
set c2 [get_cells -of_objects $d2]
puts "DRV_PIN=$d2"
puts "DRV_CELL=$c2"
if {[llength $c2]} {
  set cp [get_pins -of_objects $c2 -filter {REF_PIN_NAME == C}]
  set cn [get_nets -of_objects $cp]
  puts "DRV_CLK_PIN=$cp"
  puts "DRV_CLK_NET=$cn"
}

puts "=== dut clock net check ==="
set m [get_nets _dutWrangler_auto_out_clock]
puts "DUT_CLK_NET=$m"

close_design
