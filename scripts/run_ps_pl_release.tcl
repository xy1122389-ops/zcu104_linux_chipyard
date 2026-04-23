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

set windows_obj_dir [string map {/ \\} "//wsl.localhost/Ubuntu-22.04/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.${zcu104_cfg}/obj"]
set psu_init_tcl "${windows_obj_dir}\\ip\\zcu104ps\\psu_init.tcl"

step "connect hw_server" {
  connect -url tcp:127.0.0.1:3121
}

step "select PSU target" {
  targets -set -nocase -filter {name =~ "*PSU*"}
}

step "source psu_init.tcl" {
  source $psu_init_tcl
}

step "remove PS-PL isolation" {
  psu_ps_pl_isolation_removal
}

step "wait for isolation removal" {
  after 2000
}

step "apply PS-PL reset config" {
  psu_ps_pl_reset_config
}

step "done" {
  puts "PS-PL isolation removed for $zcu104_cfg."
  puts "psu_init.tcl used: $psu_init_tcl"
}

step "disconnect" {
  disconnect
}

exit
