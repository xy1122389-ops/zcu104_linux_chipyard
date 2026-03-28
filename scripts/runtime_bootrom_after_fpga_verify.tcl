proc step {label body} {
  puts "\n==== $label ===="
  flush stdout
  if {[catch {uplevel 1 $body} err opts]} {
    puts "STEP_ERR label=$label err=$err"
    if {[dict exists $opts -errorinfo]} {
      puts [dict get $opts -errorinfo]
    }
    flush stdout
    exit 1
  }
}

proc show_targets_safe {} {
  if {[catch {targets} out]} {
    puts "TARGETS_ERR=[string trim $out]"
  } else {
    puts [string trim $out]
  }
  flush stdout
}

proc select_ps_tap_or_psu {} {
  if {![catch {targets 1}]} { return }
  if {![catch {targets -set -nocase -filter {name == "PS TAP"}}]} { return }
  if {![catch {targets -set -nocase -filter {name =~ "*PSU*"}}]} { return }
  error "unable to select PS TAP or PSU"
}

proc select_psu {} {
  if {![catch {targets -set -nocase -filter {name =~ "*PSU*"}}]} { return }
  error "unable to select PSU"
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

step "connect" {
  connect -url tcp:127.0.0.1:3121
  configparams force-mem-accesses 1
}

step "por recover" {
  select_ps_tap_or_psu
  rst -por
  after 2500
  show_targets_safe
}

step "select psu" {
  select_psu
}

step "source psu_init" {
  source $psu_init_tcl
}

step "run psu_init" {
  psu_init
}

step "program fpga" {
  fpga $bit_file
}

step "post fpga reset release" {
  after 1000
  select_psu
  psu_ps_pl_isolation_removal
  after 1000
  psu_ps_pl_reset_config
}

step "read bootrom head" {
  select_psu
  puts "BOOTROM_10000=[mrd -force 0x00010000 4]"
  puts "BOOTROM_11C40=[mrd -force 0x00011c40 4]"
  puts "BOOTROM_11798=[mrd -force 0x00011798 4]"
}

catch {disconnect}
exit
