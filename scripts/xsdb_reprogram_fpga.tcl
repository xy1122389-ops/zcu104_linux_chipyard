# Re-program FPGA only (skip psu_init since DDR should be OK from last run)
# This re-loads the bitstream and re-initializes PL fabric

set zcu104_cfg "RocketZCU104LinuxBringupConfig"
set windows_obj_dir [string map {/ \\} "//wsl.localhost/Ubuntu-22.04/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.${zcu104_cfg}/obj"]
set windows_bit "${windows_obj_dir}\\ZCU104FPGATestHarness.bit"
set linux_psu_init "/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.${zcu104_cfg}/obj/ip/zcu104ps/psu_init.tcl"

puts "==== Connect ===="
connect -url tcp:127.0.0.1:3121

puts "\n==== Targets ===="
targets

puts "\n==== Select PSU ===="
targets -set -nocase -filter {name =~ "*PSU*"}

puts "\n==== Source psu_init (for helper procs) ===="
source $linux_psu_init

puts "\n==== Program FPGA ===="
puts "bitstream: $windows_bit"
fpga $windows_bit

puts "\n==== Wait 5s ===="
after 5000

puts "\n==== Remove PS-PL isolation ===="
psu_ps_pl_isolation_removal

puts "\n==== Wait 3s ===="
after 3000

puts "\n==== PS-PL reset config ===="
psu_ps_pl_reset_config

puts "\n==== Wait 3s ===="
after 3000

puts "\n==== Test DDR access ===="
set val [mrd -force 0x80000000]
puts "DDR[0x80000000] = $val"

puts "\nDone. FPGA re-programmed."
disconnect
exit
