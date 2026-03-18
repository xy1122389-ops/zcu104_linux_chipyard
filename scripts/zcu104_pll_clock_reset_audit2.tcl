set dcp [lindex $argv 0]
open_checkpoint $dcp

puts "=== PORTS ==="
puts "sys_clock_p=[get_ports sys_clock_p]"
puts "sys_clock_n=[get_ports sys_clock_n]"

puts "=== CLKIN1 FANIN ==="
set clkin_pin [get_pins harnessSysPLL/inst/mmcme4_adv_inst/CLKIN1]
set clkin_net [get_nets -of_objects $clkin_pin]
puts "CLKIN1_PIN=$clkin_pin"
puts "CLKIN1_NET=$clkin_net"
foreach n [all_fanin -to $clkin_pin -flat] { puts $n }

puts "=== PLL RESET FANIN ==="
set rst_pin [get_pins harnessSysPLL/inst/mmcme4_adv_inst/RST]
set rst_net [get_nets -of_objects $rst_pin]
puts "RST_PIN=$rst_pin"
puts "RST_NET=$rst_net"
set rst_fanin [all_fanin -to $rst_pin -flat]
foreach n $rst_fanin { puts $n }

puts "=== RST DRIVER CANDIDATE ==="
set rst_drv ""
foreach n $rst_fanin {
  if {[string match */Q $n]} {
    set rst_drv $n
    break
  }
}
puts "RST_DRV_PIN=$rst_drv"
if {$rst_drv ne ""} {
  puts "RST_DRV_CELL=[get_cells -of_objects [get_pins $rst_drv]]"
}

puts "=== REPORT_CLOCKS ==="
report_clocks

puts "=== REPORT_CLOCK_NETWORKS ==="
if {[catch {report_clock_networks} msg]} {
  puts "report_clock_networks_failed=$msg"
}

close_design
puts "=== DONE ==="
