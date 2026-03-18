if { $argc < 2 } {
  puts "Usage: vivado -mode batch -source scripts/insert_ila_heartbeat_zcu104.tcl -tclargs <in_post_synth_dcp> <out_dir>"
  exit 2
}

set in_dcp [lindex $argv 0]
set out_dir [lindex $argv 1]

file mkdir $out_dir
open_checkpoint $in_dcp

# Heartbeat domain nets discovered from post-route design.
set clk_net       [get_nets -quiet _dutWrangler_auto_out_clock]
set rst_net       [get_nets -quiet _dutWrangler_auto_out_reset]
set reg25_net     [get_nets -quiet heartbeat_out_OBUF]
set hb_port_net   [get_nets -quiet heartbeat_out]
# Top-level output port net may be inaccessible from fabric routing in debug insertion;
# use the equivalent OBUF input net for ILA probing when needed.
set hb_probe_net  [get_nets -quiet heartbeat_out_OBUF]
set pll_lock_net  [get_nets -quiet harnessSysPLL/inst/locked]

set reg_lo8_nets [list \
  [get_nets -quiet REG_reg_n_0_\[0\]] \
  [get_nets -quiet REG_reg_n_0_\[1\]] \
  [get_nets -quiet REG_reg_n_0_\[2\]] \
  [get_nets -quiet REG_reg_n_0_\[3\]] \
  [get_nets -quiet REG_reg_n_0_\[4\]] \
  [get_nets -quiet REG_reg_n_0_\[5\]] \
  [get_nets -quiet REG_reg_n_0_\[6\]] \
  [get_nets -quiet REG_reg_n_0_\[7\]] \
]

set missing {}
foreach {name netobj} [list \
  clk_net $clk_net \
  rst_net $rst_net \
  reg25_net $reg25_net \
  hb_probe_net $hb_probe_net \
  pll_lock_net $pll_lock_net \
] {
  if { $netobj eq "" } { lappend missing $name }
}
for {set i 0} {$i < 8} {incr i} {
  if { [lindex $reg_lo8_nets $i] eq "" } { lappend missing "reg_lo8_$i" }
}
if { [llength $missing] > 0 } {
  puts "ERROR: missing required nets: $missing"
  exit 3
}

create_debug_core u_ila_heartbeat ila
set dbg [get_debug_cores u_ila_heartbeat]
set_property C_DATA_DEPTH 4096 $dbg
set_property C_INPUT_PIPE_STAGES 0 $dbg

create_debug_port u_ila_heartbeat probe
create_debug_port u_ila_heartbeat probe
create_debug_port u_ila_heartbeat probe
create_debug_port u_ila_heartbeat probe

set_property port_width 8 [get_debug_ports u_ila_heartbeat/probe0]
set_property port_width 1 [get_debug_ports u_ila_heartbeat/probe1]
set_property port_width 1 [get_debug_ports u_ila_heartbeat/probe2]
set_property port_width 1 [get_debug_ports u_ila_heartbeat/probe3]
set_property port_width 1 [get_debug_ports u_ila_heartbeat/probe4]

connect_debug_port u_ila_heartbeat/clk $clk_net
connect_debug_port u_ila_heartbeat/probe0 $reg_lo8_nets
connect_debug_port u_ila_heartbeat/probe1 $reg25_net
connect_debug_port u_ila_heartbeat/probe2 $hb_probe_net
connect_debug_port u_ila_heartbeat/probe3 $rst_net
connect_debug_port u_ila_heartbeat/probe4 $pll_lock_net

if { $hb_port_net ne "" } {
  puts "NOTE: heartbeat_out top-level port net exists as '$hb_port_net' but probe2 uses '$hb_probe_net' for routable fabric observation."
}

# Stable backend flow: inject debug on post-synth DCP, then run implementation.
opt_design
place_design
route_design

set out_dcp "$out_dir/post_route_ila.dcp"
set out_ltx "$out_dir/heartbeat_ila.ltx"
set out_bit "$out_dir/ZCU104FPGATestHarness_ila.bit"

write_checkpoint -force $out_dcp
write_debug_probes -force $out_ltx
write_bitstream -force $out_bit

puts "ILA insertion complete"
puts "OUT_DCP=$out_dcp"
puts "OUT_LTX=$out_ltx"
puts "OUT_BIT=$out_bit"
exit