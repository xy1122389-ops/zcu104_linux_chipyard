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
set linux_payload "/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.bin"
set windows_psu_init {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig\obj\ip\zcu104ps\psu_init.tcl}
set windows_bit {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig\obj\ZCU104FPGATestHarness.bit}
set windows_payload {\\wsl.localhost\Ubuntu-22.04\root\chipyard\software\firemarshal\boards\default\firmware\opensbi\build\platform\generic\firmware\fw_payload.bin}

if {$tcl_platform(platform) eq "windows"} {
  set psu_init_tcl $windows_psu_init
  set bit_file $windows_bit
  set flat_file $windows_payload
} else {
  set psu_init_tcl $linux_psu_init
  set bit_file $linux_bit
  set flat_file $linux_payload
}

set flat_size [file size $flat_file]
set flat_size_aligned [expr {($flat_size + 0xfff) & ~0xfff}]
puts [format "flat_size => 0x%x aligned => 0x%x" $flat_size $flat_size_aligned]

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

show_targets "baseline before payload"
rd 0x100000
rd 0x110000
rd 0x2000000
catch {mwr 0x2000000 0x00000000} cl0
puts "clear msip => $cl0"
rd 0x2000000

targets -set -nocase -filter {name == "APU (L2 Cache Reset)"}
show_targets "selected apu for payload"
catch {memmap -addr 0x00000000 -size $flat_size_aligned -flags 0x7} mm
puts "memmap payload@0 => $mm"
catch {dow -data $flat_file 0x00000000} dw
puts "dow -data fw_payload.bin 0x0 => $dw"
rd 0x00000000

targets -set -nocase -filter {name =~ "*PSU*"}
show_targets "selected psu before enabling clock"
rd 0x1000
rd 0x1004
rd 0x100000
rd 0x110000
rd 0x2000000

catch {mwr 0x1000 0x80000000} b0
puts "mwr 0x1000 0x80000000 => $b0"
catch {mwr 0x1004 0x00000000} b1
puts "mwr 0x1004 0x00000000 => $b1"
catch {mwr 0x100000 0x00000001} cg
puts "mwr 0x100000 0x00000001 => $cg"
rd 0x100000

catch {mwr 0x2000000 0x00000001} ms
puts "mwr 0x2000000 0x00000001 => $ms"

for {set i 0} {$i < 20} {incr i} {
  puts [format "----- liveness poll %d -----" $i]
  rd 0x100000
  rd 0x110000
  rd 0x2000000
  after 100
}

show_targets "after hart liveness probe v3"
disconnect
exit
