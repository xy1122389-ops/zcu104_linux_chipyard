if { $argc < 2 } {
  puts "Usage: vivado -mode batch -source scripts/insert_ila_uart_pbus_zcu104.tcl -tclargs <in_post_synth_dcp> <out_dir>"
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

set repeater_full_net [first_net [list \
  {*pbus/coupler_to_device_named_uart_0/_repeater_io_full} \
  {*pbus/coupler_to_device_named_uart_0/fragmenter/repeater/full0} \
]]
set opcode2_net [first_net [list \
  {*pbus/coupler_to_device_named_uart_0/fragmenter/repeater/_pbus_auto_coupler_to_device_named_uart_0_control_xing_out_a_bits_opcode[2]} \
  {*_pbus_auto_coupler_to_device_named_uart_0_control_xing_out_a_bits_opcode[2]} \
]]
set addr3_net [first_net [list \
  {*pbus/coupler_to_device_named_uart_0/fragmenter/repeater/_pbus_auto_coupler_to_device_named_uart_0_control_xing_out_a_bits_address[3]} \
  {*_pbus_auto_coupler_to_device_named_uart_0_control_xing_out_a_bits_address[3]} \
]]
set addr4_net [first_net [list \
  {*pbus/coupler_to_device_named_uart_0/fragmenter/repeater/_pbus_auto_coupler_to_device_named_uart_0_control_xing_out_a_bits_address[4]} \
  {*_pbus_auto_coupler_to_device_named_uart_0_control_xing_out_a_bits_address[4]} \
]]

set missing {}
foreach {name netobj} [list \
  clk_net $clk_net \
  repeater_full_net $repeater_full_net \
  opcode2_net $opcode2_net \
  addr3_net $addr3_net \
  addr4_net $addr4_net \
] {
  if { $netobj eq "" } { lappend missing $name }
}
if { [llength $missing] > 0 } {
  puts "ERROR: missing required nets: $missing"
  exit 3
}

log_step "NETS clk=$clk_net repeater_full=$repeater_full_net opcode2=$opcode2_net addr3=$addr3_net addr4=$addr4_net"

log_step "CREATE_DEBUG_CORE"
create_debug_core u_ila_uart_pbus ila
set dbg [get_debug_cores u_ila_uart_pbus]
set_property C_DATA_DEPTH 16384 $dbg
set_property C_INPUT_PIPE_STAGES 0 $dbg

create_debug_port u_ila_uart_pbus probe
create_debug_port u_ila_uart_pbus probe
create_debug_port u_ila_uart_pbus probe

set_property port_width 1 [get_debug_ports u_ila_uart_pbus/probe0]
set_property port_width 1 [get_debug_ports u_ila_uart_pbus/probe1]
set_property port_width 1 [get_debug_ports u_ila_uart_pbus/probe2]
set_property port_width 1 [get_debug_ports u_ila_uart_pbus/probe3]

connect_debug_port u_ila_uart_pbus/clk    $clk_net
connect_debug_port u_ila_uart_pbus/probe0 $repeater_full_net
connect_debug_port u_ila_uart_pbus/probe1 $opcode2_net
connect_debug_port u_ila_uart_pbus/probe2 $addr3_net
connect_debug_port u_ila_uart_pbus/probe3 $addr4_net

log_step "BEGIN_OPT_DESIGN"
opt_design
log_step "END_OPT_DESIGN"
log_step "BEGIN_PLACE_DESIGN"
place_design
log_step "END_PLACE_DESIGN"
log_step "BEGIN_ROUTE_DESIGN"
route_design
log_step "END_ROUTE_DESIGN"

set out_dcp "$out_dir/post_route_uart_pbus_ila.dcp"
set out_ltx "$out_dir/uart_pbus_ila.ltx"
set out_bit "$out_dir/ZCU104FPGATestHarness_uart_pbus_ila.bit"

log_step "WRITE_DCP $out_dcp"
write_checkpoint -force $out_dcp
log_step "WRITE_LTX $out_ltx"
write_debug_probes -force $out_ltx
log_step "WRITE_BIT $out_bit"
write_bitstream -force $out_bit

puts "UART PBUS ILA insertion complete"
puts "OUT_DCP=$out_dcp"
puts "OUT_LTX=$out_ltx"
puts "OUT_BIT=$out_bit"
exit
