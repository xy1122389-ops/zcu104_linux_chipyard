if { $argc < 2 } {
  puts "Usage: vivado -mode batch -source scripts/insert_ila_spi_sd_zcu104.tcl -tclargs <in_dcp> <out_dir>"
  exit 2
}

proc first_nonempty {candidates} {
  foreach item $candidates {
    if { $item ne "" && [llength $item] > 0 } {
      return [lindex $item 0]
    }
  }
  return ""
}

proc net_of_pin {pin_name} {
  return [get_nets -quiet -of_objects [get_pins -quiet $pin_name]]
}

set in_dcp [lindex $argv 0]
set out_dir [lindex $argv 1]

file mkdir $out_dir
open_checkpoint $in_dcp

# Sample in the stable fabric clock domain. SPI init runs at 400 kHz,
# so this is sufficient to compare Linux and baremetal waveforms.
set clk_net [first_nonempty [list \
  [get_nets -quiet _dutWrangler_auto_out_clock] \
  [get_nets -quiet _sys_clock_ibufds_O] \
]]

# Post-route naming is much closer to pad-facing buffered signals than the
# original RTL names. Probe the internal nets feeding the SD shell buffers.
set spi_sck_net [first_nonempty [list \
  [get_nets -hier -quiet -filter {NAME =~ */mac/sdio_spi_clk_OBUF}] \
  [get_nets -quiet sdio_spi_clk_OBUF] \
  [net_of_pin sdio_spi_clk_OBUFT_inst/I] \
  [get_nets -quiet auto_io_out_sck] \
]]
set spi_cs_net [first_nonempty [list \
  [get_nets -hier -quiet -filter {NAME =~ */mac/sdio_spi_dat_3_OBUF}] \
  [get_nets -hier -quiet -filter {NAME =~ */mac/auto_io_out_cs_0}] \
  [get_nets -quiet auto_io_out_cs_0] \
  [get_nets -quiet sdio_spi_dat_3_OBUF] \
  [get_nets -quiet chiptop0_n_246] \
  [net_of_pin sdio_spi_dat_3_OBUFT_inst/I] \
]]
set spi_mosi_net [first_nonempty [list \
  [get_nets -hier -quiet -filter {NAME =~ */mac/*txd*1_n_0*}] \
  [get_nets -hier -quiet -filter {NAME =~ */mac/auto_io_out_dq_0_o}] \
  [get_nets -quiet auto_io_out_dq_0_o] \
  [get_nets -quiet sdio_spi_cs_OBUF] \
  [net_of_pin sdio_spi_cs_OBUFT_inst/I] \
]]

# SD card MISO enters on sdio_spi_dat_0, then passes through a two-flop
# synchronizer before reaching ChipTop.
set spi_miso_raw_net [first_nonempty [list \
  [get_nets -quiet sdio_spi_dat_0_IBUF] \
  [net_of_pin sdio_spi_dat_0_IBUF_inst/O] \
]]
set spi_miso_sync_net [first_nonempty [list \
  [get_nets -quiet io_spi_bbIn_dq_1_i_REG_1] \
  [get_nets -quiet io_spi_bbIn_dq_1_i_REG] \
  [get_nets -quiet -of_objects [get_pins -quiet io_spi_bbIn_dq_1_i_REG_1/Q]] \
  [get_nets -quiet -of_objects [get_pins -quiet io_spi_bbIn_dq_1_i_REG/Q]] \
]]

set missing {}
foreach {name netobj} [list \
  clk_net $clk_net \
  spi_sck_net $spi_sck_net \
  spi_cs_net $spi_cs_net \
  spi_mosi_net $spi_mosi_net \
  spi_miso_raw_net $spi_miso_raw_net \
  spi_miso_sync_net $spi_miso_sync_net \
] {
  if { $netobj eq "" } { lappend missing $name }
}
if { [llength $missing] > 0 } {
  puts "ERROR: missing required nets: $missing"
  exit 3
}

puts "Resolved SPI-SD nets:"
puts "  clk   = $clk_net"
puts "  sck   = $spi_sck_net"
puts "  cs    = $spi_cs_net"
puts "  mosi  = $spi_mosi_net"
puts "  miso0 = $spi_miso_raw_net"
puts "  miso1 = $spi_miso_sync_net"

create_debug_core u_ila_spi_sd ila
set dbg [get_debug_cores u_ila_spi_sd]
set_property C_DATA_DEPTH 8192 $dbg
set_property C_INPUT_PIPE_STAGES 0 $dbg

for {set i 0} {$i < 4} {incr i} {
  create_debug_port u_ila_spi_sd probe
}

foreach probe {probe0 probe1 probe2 probe3 probe4} {
  set_property port_width 1 [get_debug_ports u_ila_spi_sd/$probe]
}

connect_debug_port u_ila_spi_sd/clk    $clk_net
connect_debug_port u_ila_spi_sd/probe0 $spi_sck_net
connect_debug_port u_ila_spi_sd/probe1 $spi_cs_net
connect_debug_port u_ila_spi_sd/probe2 $spi_mosi_net
connect_debug_port u_ila_spi_sd/probe3 $spi_miso_raw_net
connect_debug_port u_ila_spi_sd/probe4 $spi_miso_sync_net

puts "SPI-SD probe mapping:"
puts "  probe0 = SPI SCK internal net feeding sdio_spi_clk OBUFT"
puts "  probe1 = SPI CS internal net feeding sdio_spi_dat_3 / DAT3"
puts "  probe2 = SPI MOSI internal net feeding sdio_spi_cs / CMD"
puts "  probe3 = raw SD DAT0 / MISO after input buffer"
puts "  probe4 = synchronized MISO into ChipTop"

opt_design
place_design
route_design

set out_dcp "$out_dir/post_route_spi_sd_ila.dcp"
set out_ltx "$out_dir/spi_sd_ila.ltx"
set out_bit "$out_dir/ZCU104FPGATestHarness_spi_sd_ila.bit"

write_checkpoint -force $out_dcp
write_debug_probes -force $out_ltx
write_bitstream -force $out_bit

puts "SPI-SD ILA insertion complete"
puts "OUT_DCP=$out_dcp"
puts "OUT_LTX=$out_ltx"
puts "OUT_BIT=$out_bit"
exit