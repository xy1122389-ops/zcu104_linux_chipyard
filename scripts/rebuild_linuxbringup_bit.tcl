set linux_proj "/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/ZCU104FPGATestHarness.xpr"
set linux_out_bit "/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/obj/ZCU104FPGATestHarness.bit"
set windows_proj "ZCU104FPGATestHarness.xpr"
set windows_out_bit "obj/ZCU104FPGATestHarness.bit"

if {$tcl_platform(platform) eq "windows"} {
  set proj $windows_proj
  set out_bit $windows_out_bit
} else {
  set proj $linux_proj
  set out_bit $linux_out_bit
}

if {![file exists $proj]} {
  error "missing project: $proj"
}

open_project $proj
reset_run synth_1
reset_run impl_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

open_run impl_1
if {![file exists $out_bit]} {
  error "bitstream not found after impl_1: $out_bit"
}
puts "BITSTREAM_READY=$out_bit"
close_project
exit
