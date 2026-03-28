set_param labtools.enable_cs_server false
open_hw_manager
connect_hw_server -allow_non_jtag
catch {close_hw_target}
puts "=== HW_TARGETS ==="
foreach hw_target [get_hw_targets] {
  puts $hw_target
}
exit
