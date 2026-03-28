if { $argc < 2 } {
  puts "Usage: vivado -mode batch -source scripts/insert_ila_uart_zcu104.tcl -tclargs <in_post_synth_dcp> <out_dir>"
  exit 2
}

set in_dcp [lindex $argv 0]
set out_dir [lindex $argv 1]

proc log_step {msg} {
  puts "STEP=[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}] $msg"
  flush stdout
}

file mkdir $out_dir
log_step "OPEN_DCP $in_dcp"
open_checkpoint $in_dcp

set clk_net [get_nets -quiet _dutWrangler_auto_out_clock]
if { $clk_net eq "" } {
  set clk_net [get_nets -quiet clk_out1]
}
set rst_net [get_nets -quiet _dutWrangler_auto_out_reset]
set tx_net  [get_nets -quiet uart_txd_OBUF]
set rx_net  [get_nets -quiet uart_rxd_IBUF]
set enq_candidates [lsort [get_nets -hier -quiet -filter {NAME =~ *uartClockDomainWrapper*uart_0/txq/do_enq*}]]
if { [llength $enq_candidates] == 0 } {
  set enq_candidates [lsort [get_nets -hier -quiet -filter {NAME =~ *uart_0/txq/do_enq*}]]
}
set enq_net ""
if { [llength $enq_candidates] > 0 } {
  set enq_net [lindex $enq_candidates 0]
}

set missing {}
foreach {name netobj} [list \
  clk_net $clk_net \
  rst_net $rst_net \
  tx_net $tx_net \
  rx_net $rx_net \
] {
  if { $netobj eq "" } { lappend missing $name }
}
if { [llength $missing] > 0 } {
  puts "ERROR: missing required nets: $missing"
  exit 3
}
log_step "NETS clk=$clk_net rst=$rst_net tx=$tx_net rx=$rx_net enq=$enq_net enq_candidates=$enq_candidates"

log_step "CREATE_DEBUG_CORE"
create_debug_core u_ila_uart ila
set dbg [get_debug_cores u_ila_uart]
set_property C_DATA_DEPTH 16384 $dbg
set_property C_INPUT_PIPE_STAGES 0 $dbg

create_debug_port u_ila_uart probe
create_debug_port u_ila_uart probe
create_debug_port u_ila_uart probe

set_property port_width 1 [get_debug_ports u_ila_uart/probe0]
set_property port_width 1 [get_debug_ports u_ila_uart/probe1]
set_property port_width 1 [get_debug_ports u_ila_uart/probe2]
set_property port_width 1 [get_debug_ports u_ila_uart/probe3]

connect_debug_port u_ila_uart/clk    $clk_net
connect_debug_port u_ila_uart/probe0 $tx_net
connect_debug_port u_ila_uart/probe1 $rx_net
connect_debug_port u_ila_uart/probe2 $rst_net
if { $enq_net ne "" } {
  connect_debug_port u_ila_uart/probe3 $enq_net
} else {
  connect_debug_port u_ila_uart/probe3 $tx_net
}

log_step "BEGIN_OPT_DESIGN"
opt_design
log_step "END_OPT_DESIGN"
log_step "BEGIN_PLACE_DESIGN"
place_design
log_step "END_PLACE_DESIGN"
log_step "BEGIN_ROUTE_DESIGN"
route_design
log_step "END_ROUTE_DESIGN"

set out_dcp "$out_dir/post_route_uart_ila.dcp"
set out_ltx "$out_dir/uart_ila.ltx"
set out_bit "$out_dir/ZCU104FPGATestHarness_uart_ila.bit"

log_step "WRITE_DCP $out_dcp"
write_checkpoint -force $out_dcp
log_step "WRITE_LTX $out_ltx"
write_debug_probes -force $out_ltx
log_step "WRITE_BIT $out_bit"
write_bitstream -force $out_bit

puts "UART ILA insertion complete"
puts "OUT_DCP=$out_dcp"
puts "OUT_LTX=$out_ltx"
puts "OUT_BIT=$out_bit"
exit
