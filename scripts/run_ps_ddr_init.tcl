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

if {[info exists ::env(CHIPYARD_BITSTREAM_LINUX)] && $::env(CHIPYARD_BITSTREAM_LINUX) ne ""} {
  if {$tcl_platform(platform) eq "windows"} {
    set bit_file $::env(CHIPYARD_BITSTREAM_WINDOWS)
    set psu_init_tcl $::env(CHIPYARD_PSU_INIT_TCL_WINDOWS)
  } else {
    set bit_file $::env(CHIPYARD_BITSTREAM_LINUX)
    set psu_init_tcl $::env(CHIPYARD_PSU_INIT_TCL_LINUX)
  }
  set zcu104_cfg "direct-bitstream"
} else {
  if {[info exists ::env(CHIPYARD_ZCU104_CFG)] && $::env(CHIPYARD_ZCU104_CFG) ne ""} {
    set zcu104_cfg $::env(CHIPYARD_ZCU104_CFG)
  } else {
    set zcu104_cfg "RocketZCU104Config"
  }

  set linux_obj_dir "/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.${zcu104_cfg}/obj"
  set windows_obj_dir [string map {/ \\} "//wsl.localhost/Ubuntu-22.04/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.${zcu104_cfg}/obj"]
  set linux_psu_init "${linux_obj_dir}/ip/zcu104ps/psu_init.tcl"
  set linux_bit "${linux_obj_dir}/ZCU104FPGATestHarness.bit"
  set windows_psu_init "${windows_obj_dir}\\ip\\zcu104ps\\psu_init.tcl"
  set windows_bit "${windows_obj_dir}\\ZCU104FPGATestHarness.bit"

  if {$tcl_platform(platform) eq "windows"} {
    set psu_init_tcl $windows_psu_init
    set bit_file $windows_bit
  } else {
    set psu_init_tcl $linux_psu_init
    set bit_file $linux_bit
  }
}

step "check input files" {
  puts "zcu104_cfg   = $zcu104_cfg"
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
  targets
}

step "select PSU target" {
  targets -set -nocase -filter {name =~ "*PSU*"}
  targets
}

step "source psu_init.tcl" {
  source $psu_init_tcl
}

step "run psu_init (PS DDR init first)" {
  psu_init
}

if {[info exists ::env(SKIP_FPGA_PROGRAM)] && $::env(SKIP_FPGA_PROGRAM) eq "1"} {
  puts "\n==== SKIP FPGA programming (SKIP_FPGA_PROGRAM=1) ===="
} else {
  step "program FPGA bitstream" {
    # Rocket core starts immediately after FPGA programming (PowerOnResetFPGAOnly).
    # Its first DDR access via AXI HP0 will stall until isolation is removed below.
    fpga $bit_file
  }

  step "wait after FPGA program" {
    after 3000
  }
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

step "final message" {
  puts ""
  puts "PS DDR init + FPGA download + isolation removal completed."
  puts "Configured ZCU104 target: $zcu104_cfg"
  puts "Bitstream used          : $bit_file"
  puts "LED routing and boot behavior depend on the selected generated config."
  puts ""
  puts "Next: load OpenSBI/Linux payload into DDR via XSDB, then use J-Link to boot."
}

step "disconnect" {
  disconnect
}

exit
