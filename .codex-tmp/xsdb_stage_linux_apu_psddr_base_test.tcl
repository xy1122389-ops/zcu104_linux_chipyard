proc show_targets {tag} {
  puts ""
  puts "===== $tag : targets ====="
  catch {puts [targets]} err
  if {$err ne ""} { puts $err }
}

proc rd {addr} {
  catch {mrd -force $addr} rv
  puts [format "mrd %s => %s" $addr $rv]
}

connect -url tcp:127.0.0.1:3121
targets -set -nocase -filter {name =~ "*PSU*"}
catch {rst -por} r0
puts "rst -por => $r0"
after 2000

set linux_psu_init "/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/obj/ip/zcu104ps/psu_init.tcl"
set linux_bit "/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/obj/ZCU104FPGATestHarness.bit"
set windows_psu_init {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig\obj\ip\zcu104ps\psu_init.tcl}
set windows_bit {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig\obj\ZCU104FPGATestHarness.bit}

if {$tcl_platform(platform) eq "windows"} {
  set psu_init_tcl $windows_psu_init
  set bit_file $windows_bit
} else {
  set psu_init_tcl $linux_psu_init
  set bit_file $linux_bit
}

catch {source $psu_init_tcl} src
puts "source => $src"
catch {psu_init} ps
puts "psu_init => $ps"
catch {fpga $bit_file} fp
puts "fpga => $fp"
after 1000
catch {psu_ps_pl_isolation_removal} iso
puts "psu_ps_pl_isolation_removal => $iso"
after 1000
catch {psu_ps_pl_reset_config} rc
puts "psu_ps_pl_reset_config => $rc"
after 1000
catch {configparams force-mem-accesses 1} fm
puts "configparams force-mem-accesses 1 => $fm"

targets -set -nocase -filter {name == "APU (L2 Cache Reset)"}
show_targets "selected apu target"
catch {mwr 0x00000000 0x11223344} wr
puts "mwr 0x00000000 0x11223344 => $wr"
rd 0x00000000
show_targets "after apu psddr base test"

disconnect
exit
