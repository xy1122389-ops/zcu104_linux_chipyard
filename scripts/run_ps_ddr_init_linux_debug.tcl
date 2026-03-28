proc step {label body} {
  puts "\n==== $label ===="
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

proc show_targets_safe {} {
  if {[catch {targets} out]} {
    puts "TARGETS_ERR=[string trim $out]"
  } else {
    puts $out
  }
}

proc select_psu_target {} {
  targets -set -nocase -filter {name =~ "*PSU*"}
}

proc recover_psu_target {} {
  puts "PSU_RECOVER_ACTION=rst_por_retry"
  if {![catch {targets 1}]} {
    rst -por
    after 2500
    return
  }
  targets -set -nocase -filter {name == "PS TAP"}
  rst -por
  after 2500
}

set debug_psu_init "/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupDebugConfig/obj/ip/zcu104ps/psu_init.tcl"
set debug_bit "/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupDebugConfig/obj/ZCU104FPGATestHarness.bit"
set windows_psu_init {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupDebugConfig\obj\ip\zcu104ps\psu_init.tcl}
set windows_bit {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupDebugConfig\obj\ZCU104FPGATestHarness.bit}

if {$tcl_platform(platform) eq "windows"} {
  set psu_init_tcl $windows_psu_init
  set bit_file $windows_bit
} else {
  set psu_init_tcl $debug_psu_init
  set bit_file $debug_bit
}

step "check input files" {
  if {![file exists $psu_init_tcl]} {
    error "missing psu_init.tcl: $psu_init_tcl"
  }
  if {![file exists $bit_file]} {
    error "missing bitstream: $bit_file"
  }
  puts "psu_init.tcl = $psu_init_tcl"
  puts "bitstream    = $bit_file"
}

step "connect hw_server" {
  connect -url tcp:127.0.0.1:3121
}

step "show targets" {
  show_targets_safe
}

step "select PSU target" {
  if {[catch {select_psu_target} err]} {
    puts "PSU_SELECT_FIRST_ERR=$err"
    recover_psu_target
    show_targets_safe
    select_psu_target
  }
  show_targets_safe
}

step "source psu_init.tcl" {
  source $psu_init_tcl
}

step "run psu_init (PS DDR init first)" {
  psu_init
}

step "program FPGA bitstream" {
  fpga $bit_file
}

step "wait after FPGA program" {
  after 1000
}

step "reselect PSU target" {
  if {[catch {select_psu_target} err]} {
    puts "PSU_RESELECT_ERR=$err"
    recover_psu_target
    show_targets_safe
    select_psu_target
  }
  show_targets_safe
}

step "remove PS-PL isolation" {
  psu_ps_pl_isolation_removal
}

step "wait after isolation removal" {
  after 1000
}

step "apply PS-PL reset config" {
  psu_ps_pl_reset_config
}

step "final message" {
  puts "PS DDR init + Linux bringup DEBUG bitstream download completed."
}

step "disconnect" {
  disconnect
}

exit
