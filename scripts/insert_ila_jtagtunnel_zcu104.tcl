if { $argc < 2 } {
  puts "Usage: vivado -mode batch -source scripts/insert_ila_jtagtunnel_zcu104.tcl -tclargs <in_post_synth_dcp> <out_dir>"
  exit 2
}

set in_dcp [lindex $argv 0]
set out_dir [lindex $argv 1]

file mkdir $out_dir
open_checkpoint $in_dcp

proc qnet {cell_name} {
  set pin [get_pins -quiet ${cell_name}/Q]
  if { $pin eq "" } { return "" }
  return [get_nets -quiet -of_objects $pin]
}

set clk_net         [get_nets -quiet _dutWrangler_auto_out_clock]
if { $clk_net eq "" } {
  set clk_net [get_nets -quiet _dutWrangler_auto_out_clock_BUFG]
}
if { $clk_net eq "" } {
  set clk_net [get_nets -quiet chiptop0/clock]
}
set pre_clk_net     [get_nets -quiet inst_jtag_tunnel/_inst_jtag_tunnel_jtag_tck]
set shift_net       [get_nets -quiet inst_jtag_tunnel/_bscane2_SHIFT]
set tdi_net         [get_nets -quiet _inst_jtag_tunnel_jtag_tdi]
set tms_net         [get_nets -quiet inst_jtag_tunnel/_inst_jtag_tunnel_jtag_tms]
set tdo_net         [get_nets -quiet inst_jtag_tunnel/_system_debug_systemjtag_jtag_TDO_data]
set tdi_reg_net     [qnet inst_jtag_tunnel/tdiRegister_reg]

set shift_counter_nets [list \
  [qnet {inst_jtag_tunnel/shiftCounter_reg[0]}] \
  [qnet {inst_jtag_tunnel/shiftCounter_reg[1]}] \
  [qnet {inst_jtag_tunnel/shiftCounter_reg[2]}] \
  [qnet {inst_jtag_tunnel/shiftCounter_reg[3]}] \
  [qnet {inst_jtag_tunnel/shiftCounter_reg[4]}] \
  [qnet {inst_jtag_tunnel/shiftCounter_reg[5]}] \
  [qnet {inst_jtag_tunnel/shiftCounter_reg[6]}] \
]

set pos_counter_nets [list \
  [qnet {inst_jtag_tunnel/posCounter_reg[0]}] \
  [qnet {inst_jtag_tunnel/posCounter_reg[1]}] \
  [qnet {inst_jtag_tunnel/posCounter_reg[2]}] \
  [qnet {inst_jtag_tunnel/posCounter_reg[3]}] \
  [qnet {inst_jtag_tunnel/posCounter_reg[4]}] \
  [qnet {inst_jtag_tunnel/posCounter_reg[5]}] \
  [qnet {inst_jtag_tunnel/posCounter_reg[6]}] \
  [qnet {inst_jtag_tunnel/posCounter_reg[7]}] \
]

set neg_counter_nets [list \
  [qnet {inst_jtag_tunnel/negCounter_reg[0]}] \
  [qnet {inst_jtag_tunnel/negCounter_reg[1]}] \
  [qnet {inst_jtag_tunnel/negCounter_reg[2]}] \
  [qnet {inst_jtag_tunnel/negCounter_reg[3]}] \
  [qnet {inst_jtag_tunnel/negCounter_reg[4]}] \
  [qnet {inst_jtag_tunnel/negCounter_reg[5]}] \
  [qnet {inst_jtag_tunnel/negCounter_reg[6]}] \
  [qnet {inst_jtag_tunnel/negCounter_reg[7]}] \
]

set missing {}
foreach {name netobj} [list \
  clk_net $clk_net \
  pre_clk_net $pre_clk_net \
  shift_net $shift_net \
  tdi_net $tdi_net \
  tms_net $tms_net \
  tdo_net $tdo_net \
  tdi_reg_net $tdi_reg_net \
] {
  if { $netobj eq "" } { lappend missing $name }
}
for {set i 0} {$i < 7} {incr i} {
  if { [lindex $shift_counter_nets $i] eq "" } { lappend missing "shift_counter_$i" }
}
for {set i 0} {$i < 8} {incr i} {
  if { [lindex $pos_counter_nets $i] eq "" } { lappend missing "pos_counter_$i" }
  if { [lindex $neg_counter_nets $i] eq "" } { lappend missing "neg_counter_$i" }
}
if { [llength $missing] > 0 } {
  puts "ERROR: missing required nets: $missing"
  exit 3
}

create_debug_core u_ila_jtag ila
set dbg [get_debug_cores u_ila_jtag]
set_property C_DATA_DEPTH 4096 $dbg
set_property C_INPUT_PIPE_STAGES 0 $dbg

for {set i 0} {$i < 8} {incr i} {
  create_debug_port u_ila_jtag probe
}

set_property port_width 1 [get_debug_ports u_ila_jtag/probe0]
set_property port_width 1 [get_debug_ports u_ila_jtag/probe1]
set_property port_width 1 [get_debug_ports u_ila_jtag/probe2]
set_property port_width 1 [get_debug_ports u_ila_jtag/probe3]
set_property port_width 1 [get_debug_ports u_ila_jtag/probe4]
set_property port_width 1 [get_debug_ports u_ila_jtag/probe5]
set_property port_width 7 [get_debug_ports u_ila_jtag/probe6]
set_property port_width 8 [get_debug_ports u_ila_jtag/probe7]
set_property port_width 8 [get_debug_ports u_ila_jtag/probe8]

connect_debug_port u_ila_jtag/clk    $clk_net
connect_debug_port u_ila_jtag/probe0 $pre_clk_net
connect_debug_port u_ila_jtag/probe1 $shift_net
connect_debug_port u_ila_jtag/probe2 $tdi_net
connect_debug_port u_ila_jtag/probe3 $tms_net
connect_debug_port u_ila_jtag/probe4 $tdo_net
connect_debug_port u_ila_jtag/probe5 $tdi_reg_net
connect_debug_port u_ila_jtag/probe6 $shift_counter_nets
connect_debug_port u_ila_jtag/probe7 $pos_counter_nets
connect_debug_port u_ila_jtag/probe8 $neg_counter_nets

opt_design
place_design
route_design

set out_dcp "$out_dir/post_route_ila.dcp"
set out_ltx "$out_dir/jtagtunnel_ila.ltx"
set out_bit "$out_dir/ZCU104FPGATestHarness_jtagtunnel_ila.bit"

write_checkpoint -force $out_dcp
write_debug_probes -force $out_ltx
write_bitstream -force $out_bit

puts "ILA insertion complete"
puts "OUT_DCP=$out_dcp"
puts "OUT_LTX=$out_ltx"
puts "OUT_BIT=$out_bit"
exit
