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

if {[info exists ::env(CHIPYARD_ZCU104_CFG)] && $::env(CHIPYARD_ZCU104_CFG) ne ""} {
  set zcu104_cfg $::env(CHIPYARD_ZCU104_CFG)
} else {
  set zcu104_cfg "RocketZCU104LinuxBringupConfig"
}

if {[info exists ::env(CHIPYARD_BITSTREAM_WINDOWS)] && $::env(CHIPYARD_BITSTREAM_WINDOWS) ne "" &&
    [info exists ::env(CHIPYARD_PSU_INIT_TCL_WINDOWS)] && $::env(CHIPYARD_PSU_INIT_TCL_WINDOWS) ne ""} {
  set psu_init_tcl $::env(CHIPYARD_PSU_INIT_TCL_WINDOWS)
  set bit_file $::env(CHIPYARD_BITSTREAM_WINDOWS)
} else {
  set windows_obj_dir [string map {/ \\} "//wsl.localhost/Ubuntu-22.04/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.${zcu104_cfg}/obj"]
  set psu_init_tcl "${windows_obj_dir}\\ip\\zcu104ps\\psu_init.tcl"
  set bit_file "${windows_obj_dir}\\ZCU104FPGATestHarness.bit"
}

step "check input files" {
  puts "zcu104_cfg   = $zcu104_cfg"
  puts "psu_init.tcl = $psu_init_tcl"
  puts "bitstream    = $bit_file"
  if {![file exists $psu_init_tcl]} { error "missing psu_init.tcl: $psu_init_tcl" }
  if {![file exists $bit_file]} { error "missing bitstream: $bit_file" }
}

step "connect hw_server" {
  connect -url tcp:127.0.0.1:3121
  after 3000
}

step "select PSU target" {
  targets -set -nocase -filter {name =~ "*PSU*"}
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
  puts "Waiting 5000 ms for PL settle / DS39 heartbeat..."
  after 5000
}

step "final message" {
  puts ""
  puts "PS DDR init + FPGA download completed."
  puts "STOP HERE before isolation removal/reset toggle."
  puts "This mode is intended for J-Link attach before Rocket runs into PS/DDR paths."
}

step "disconnect" {
  disconnect
}

exit