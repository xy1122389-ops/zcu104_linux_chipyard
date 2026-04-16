# reprogram_fpga_only.tcl — Re-program FPGA without DDR reinit
# Use after firmware is already loaded to DDR.
# This cold-starts Rocket so its D-cache is empty and will fetch fresh DDR data.

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

# Resolve bitstream path
if {[info exists ::env(CHIPYARD_BITSTREAM_LINUX)] && $::env(CHIPYARD_BITSTREAM_LINUX) ne ""} {
  if {$tcl_platform(platform) eq "windows"} {
    set bit_file $::env(CHIPYARD_BITSTREAM_WINDOWS)
    set psu_init_tcl $::env(CHIPYARD_PSU_INIT_TCL_WINDOWS)
  } else {
    set bit_file $::env(CHIPYARD_BITSTREAM_LINUX)
    set psu_init_tcl $::env(CHIPYARD_PSU_INIT_TCL_LINUX)
  }
} else {
  set zcu104_cfg "RocketZCU104LinuxBringupConfig"
  set obj_dir "//wsl.localhost/Ubuntu-22.04/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.${zcu104_cfg}/obj"
  if {$tcl_platform(platform) eq "windows"} {
    set bit_file [string map {/ \\} "${obj_dir}/ZCU104FPGATestHarness.bit"]
    set psu_init_tcl [string map {/ \\} "${obj_dir}/ip/zcu104ps/psu_init.tcl"]
  } else {
    set bit_file "${obj_dir}/ZCU104FPGATestHarness.bit"
    set psu_init_tcl "${obj_dir}/ip/zcu104ps/psu_init.tcl"
  }
}

step "check bitstream" {
  if {![file exists $bit_file]} {
    error "missing bitstream: $bit_file"
  }
  puts "bitstream = $bit_file"
}

step "connect hw_server" {
  connect -url tcp:127.0.0.1:3121
  after 3000
}

step "show targets" {
  targets
}

step "select PSU target" {
  if {![catch {targets -set -nocase -filter {name =~ "*PSU*"}}]} {
    puts "PSU target found"
  } else {
    error "PSU target not available"
  }
}

# Source psu_init.tcl only for the isolation/reset helper procs, NOT calling psu_init
step "source psu_init.tcl (for helper procs only)" {
  source $psu_init_tcl
}

step "program FPGA bitstream (cold-start Rocket)" {
  fpga $bit_file
}

step "wait after FPGA program" {
  puts "Waiting 5000 ms for PL settle..."
  after 5000
}

step "remove PS-PL isolation" {
  psu_ps_pl_isolation_removal
}

step "wait for isolation removal" {
  after 2000
}

step "PS-PL reset config" {
  psu_ps_pl_reset_config
}

step "verify DDR contents still intact" {
  set val0 [mrd -force -value 0x00000000]
  set val1 [mrd -force -value 0x04000000]
  puts [format "  OpenSBI @ DDR 0x00000000 = 0x%08x (should be non-zero)" $val0]
  puts [format "  DTB     @ DDR 0x04000000 = 0x%08x (should be 0xedfe0dd0)" $val1]
}

step "done" {
  puts "FPGA re-programmed. Rocket is now running with cold cache."
  puts "BootROM should detect payload at 0x80000000 and auto-jump in ~3s."
}

step "disconnect" {
  disconnect
}

exit
