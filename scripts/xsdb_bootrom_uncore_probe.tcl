proc step {label body} {
  puts ""
  puts "==== $label ===="
  flush stdout
  if {[catch {uplevel 1 $body} err opts]} {
    puts stderr "ERROR in $label: $err"
    if {[dict exists $opts -errorinfo]} {
      puts stderr [dict get $opts -errorinfo]
    }
    flush stderr
    exit 1
  }
}

proc rd_words {base count} {
  for {set i 0} {$i < $count} {incr i} {
    set addr [expr {$base + 4 * $i}]
    catch {mrd -force $addr} rv
    puts [format {mrd 0x%08X => %s} $addr $rv]
  }
}

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

step "connect hw_server" {
  connect -url tcp:127.0.0.1:3121
}

step "select PSU target" {
  targets -set -nocase -filter {name =~ "*PSU*"}
  puts [targets]
}

step "source psu_init.tcl" {
  source $psu_init_tcl
}

step "run psu_init" {
  psu_init
}

step "program FPGA bitstream" {
  fpga $bit_file
}

step "wait after FPGA program" {
  after 1000
}

step "reselect PSU target" {
  targets -set -nocase -filter {name =~ "*PSU*"}
}

step "remove PS-PL isolation" {
  psu_ps_pl_isolation_removal
}

step "bootrom words before reset release" {
  rd_words 0x00010000 16
}

step "write and read pbus bootaddr before reset release" {
  mwr -force 0x00001000 0x13579BDF
  puts [mrd -force 0x00001000]
}

step "apply PS-PL reset config" {
  psu_ps_pl_reset_config
}

step "show targets after reset release" {
  puts [targets]
}

step "bootrom words after reset release" {
  rd_words 0x00010000 16
}

step "watch pbus bootaddr after reset release" {
  for {set i 0} {$i < 20} {incr i} {
    catch {mrd -force 0x00001000} rv
    puts [format {sample[%d] => %s} $i $rv]
    after 100
  }
}

step "disconnect" {
  disconnect
}

exit
