# gen_xsa_for_pmufw.tcl
# Run with: vivado -mode batch -source gen_xsa_for_pmufw.tcl
# Generates zcu104.xsa from existing implemented project (no re-synthesis needed)

set xpr_path {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig\ZCU104FPGATestHarness.xpr}
set xsa_out {C:\tmp\pmufw_build\zcu104.xsa}
set bit_path {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig\obj\ZCU104FPGATestHarness.bit}

puts "\[gen_xsa\] Opening project: $xpr_path"
open_project $xpr_path

puts "\[gen_xsa\] Writing hw_platform (XSA) to: $xsa_out"
file mkdir {C:\tmp\pmufw_build}
write_hw_platform -fixed -force -include_bit $xsa_out

puts "\[gen_xsa\] DONE. XSA written to: $xsa_out"
exit
