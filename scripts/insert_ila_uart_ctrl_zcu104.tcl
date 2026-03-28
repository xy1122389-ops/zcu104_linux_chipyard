if { $argc < 2 } {
  puts "Usage: vivado -mode batch -source scripts/insert_ila_uart_ctrl_zcu104.tcl -tclargs <in_post_synth_dcp> <out_dir>"
  exit 2
}

set in_dcp [lindex $argv 0]
set out_dir [lindex $argv 1]

proc log_step {msg} {
  puts "STEP=[clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}] $msg"
  flush stdout
}

proc first_net {patterns} {
  foreach pattern $patterns {
    set nets [lsort [get_nets -hier -quiet -filter "NAME =~ $pattern"]]
    if { [llength $nets] > 0 } {
      return [lindex $nets 0]
    }
  }
  return ""
}

file mkdir $out_dir
log_step "OPEN_DCP $in_dcp"
open_checkpoint $in_dcp

set clk_net [get_nets -quiet _dutWrangler_auto_out_clock]
if { $clk_net eq "" } {
  set clk_net [get_nets -quiet clk_out1]
}

set wrap_enq_net [first_net [list \
  {*uartClockDomainWrapper/do_enq} \
]]
set uart_enq_net [first_net [list \
  {*uartClockDomainWrapper/uart_0/do_enq} \
]]
set txq_enq_net [first_net [list \
  {*uartClockDomainWrapper/uart_0/txq/do_enq} \
  {*uart_0/txq/do_enq} \
]]
set txen_net [first_net [list \
  {*uartClockDomainWrapper/txen0} \
  {*uartClockDomainWrapper/uart_0/txen0} \
  {*uart_0/txen0} \
]]

set missing {}
foreach {name netobj} [list \
  clk_net $clk_net \
  wrap_enq_net $wrap_enq_net \
  uart_enq_net $uart_enq_net \
  txq_enq_net $txq_enq_net \
  txen_net $txen_net \
] {
  if { $netobj eq "" } { lappend missing $name }
}
if { [llength $missing] > 0 } {
  puts "ERROR: missing required nets: $missing"
  exit 3
}

log_step "NETS clk=$clk_net wrap_enq=$wrap_enq_net uart_enq=$uart_enq_net txq_enq=$txq_enq_net txen=$txen_net"

log_step "CREATE_DEBUG_CORE"
create_debug_core u_ila_uart_ctrl ila
set dbg [get_debug_cores u_ila_uart_ctrl]
set_property C_DATA_DEPTH 16384 $dbg
set_property C_INPUT_PIPE_STAGES 0 $dbg

create_debug_port u_ila_uart_ctrl probe
create_debug_port u_ila_uart_ctrl probe
create_debug_port u_ila_uart_ctrl probe

set_property port_width 1 [get_debug_ports u_ila_uart_ctrl/probe0]
set_property port_width 1 [get_debug_ports u_ila_uart_ctrl/probe1]
set_property port_width 1 [get_debug_ports u_ila_uart_ctrl/probe2]
set_property port_width 1 [get_debug_ports u_ila_uart_ctrl/probe3]

connect_debug_port u_ila_uart_ctrl/clk    $clk_net
connect_debug_port u_ila_uart_ctrl/probe0 $wrap_enq_net
connect_debug_port u_ila_uart_ctrl/probe1 $uart_enq_net
connect_debug_port u_ila_uart_ctrl/probe2 $txq_enq_net
connect_debug_port u_ila_uart_ctrl/probe3 $txen_net

log_step "BEGIN_OPT_DESIGN"
opt_design
log_step "END_OPT_DESIGN"
log_step "BEGIN_PLACE_DESIGN"
place_design
log_step "END_PLACE_DESIGN"
log_step "BEGIN_ROUTE_DESIGN"
route_design
log_step "END_ROUTE_DESIGN"

set out_dcp "$out_dir/post_route_uart_ctrl_ila.dcp"
set out_ltx "$out_dir/uart_ctrl_ila.ltx"
set out_bit "$out_dir/ZCU104FPGATestHarness_uart_ctrl_ila.bit"

log_step "WRITE_DCP $out_dcp"
write_checkpoint -force $out_dcp
log_step "WRITE_LTX $out_ltx"
write_debug_probes -force $out_ltx
log_step "WRITE_BIT $out_bit"
write_bitstream -force $out_bit

puts "UART CTRL ILA insertion complete"
puts "OUT_DCP=$out_dcp"
puts "OUT_LTX=$out_ltx"
puts "OUT_BIT=$out_bit"
exit
