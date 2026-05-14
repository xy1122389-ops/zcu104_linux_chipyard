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

if {[info exists ::env(POST_FPGA_PROGRAM_WAIT_MS)] && $::env(POST_FPGA_PROGRAM_WAIT_MS) ne ""} {
  set post_fpga_program_wait_ms $::env(POST_FPGA_PROGRAM_WAIT_MS)
} else {
  set post_fpga_program_wait_ms 3000
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
  # Give hw_server time to enumerate all JTAG targets
  after 3000
}

step "show targets" {
  targets
}

step "select PSU target" {
  # Try PSU first (available when PS has booted, e.g. from SD/QSPI FSBL)
  set psu_found 0
  if {![catch {targets -set -nocase -filter {name =~ "*PSU*"}}]} {
    puts "PSU target found directly"
    set psu_found 1
  }

  if {!$psu_found} {
    puts "PSU target not found. Board may be in JTAG-boot / pre-init state."
    puts "Attempting system reset via PS TAP to bring up PSU..."

    # Issue a system reset through the PS TAP to restart the PMU ROM.
    # This re-initializes the PS subsystem and makes the PSU target appear.
    if {![catch {targets -set -nocase -filter {name =~ "*PS TAP*"}}]} {
      catch {rst -system}
      puts "System reset issued. Waiting 8 s for PMU boot..."
      after 8000
    } else {
      puts "WARN: PS TAP target also not found!"
      after 3000
    }

    # Re-scan targets and try PSU again
    puts "Targets after reset:"
    targets
    if {![catch {targets -set -nocase -filter {name =~ "*PSU*"}}]} {
      puts "PSU target found after system reset"
      set psu_found 1
    }
  }

  if {!$psu_found} {
    # Last resort: try "Cortex*#0" (some board revisions / post-FSBL states)
    if {![catch {targets -set -nocase -filter {name =~ "*Cortex*#0*"}}]} {
      puts "Using Cortex-A53 #0 as fallback target"
    } else {
      error "PSU target not available after system reset.\nAvailable targets:\n[targets]\n\nFix: Power-cycle ZCU104 (turn OFF power switch, wait 10s, turn ON), then re-run."
    }
  }
  targets
}

step "source psu_init.tcl" {
  source $psu_init_tcl
}

step "run psu_init (PS DDR init first)" {
  psu_init
}

step "relax IOU secure gating for boot devices" {
  # Match Xilinx U-Boot's post-psu_init sequence so SD0/SD1/QSPI/NAND are
  # accessible to non-secure masters. Rocket's S_AXI_LPD path is hardwired
  # as privileged + non-secure, so without this override SDIO1 can return
  # bus errors even when clocks/resets were set up correctly by psu_init.
  mwr -force 0xFF240000 0x04920492
  mwr -force 0xFF240004 0x00920492
}

if {[info exists ::env(SKIP_FPGA_PROGRAM)] && $::env(SKIP_FPGA_PROGRAM) eq "1"} {
  puts "\n==== SKIP FPGA programming (SKIP_FPGA_PROGRAM=1) ===="
} else {
  step "program FPGA bitstream" {
    # Rocket core starts immediately after FPGA programming (PowerOnResetFPGAOnly).
    # Do NOT wait here. BootROM can reach its first DDR touch well under 1 s,
    # so PS-PL isolation must be removed immediately after fpga.
    fpga $bit_file
  }
}

step "remove PS-PL isolation" {
  psu_ps_pl_isolation_removal
}

step "wait after isolation removal" {
  puts "Waiting ${post_fpga_program_wait_ms} ms for PL settle / DS39 heartbeat..."
  after 2000
  after $post_fpga_program_wait_ms
}

if {[info exists ::env(FORCE_PS_PL_RESET_CONFIG)] && $::env(FORCE_PS_PL_RESET_CONFIG) eq "1"} {
  step "PS-PL reset config" {
    psu_ps_pl_reset_config
  }
} else {
  puts "\n==== PS-PL reset config (skipped) ===="
  puts "Skipping psu_ps_pl_reset_config: EMIO GPIO reset is not connected to PL reset in this design."
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
