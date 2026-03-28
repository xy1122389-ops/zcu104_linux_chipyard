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

proc show_targets {} {
  catch {puts [targets]} err
  if {$err ne ""} {
    puts $err
  }
}

proc select_psu_target {} {
  if {![catch {targets -set -nocase -filter {name =~ "*PSU*"}}]} {
    show_targets
    return
  }
  if {![catch {targets -set -nocase -filter {name == "PS TAP"}}]} {
    show_targets
    return
  }
  error "unable to select PSU target (tried *PSU* and PS TAP)"
}

proc select_apu_target {} {
  if {![catch {targets -set -nocase -filter {name == "APU (L2 Cache Reset)"}}]} {
    show_targets
    return
  }
  if {![catch {targets -set -nocase -filter {name =~ "*APU*"}}]} {
    show_targets
    return
  }
  error "unable to select APU target (tried APU (L2 Cache Reset) and *APU*)"
}

proc rd_ddr_sentinel {tag addr count delay_ms} {
  puts $tag
  for {set i 0} {$i < $count} {incr i} {
    catch {mrd -force $addr} rv
    puts [format {sample[%02d] => %s} $i $rv]
    after $delay_ms
  }
}

# Chipyard sees DDR at 0x8000_0000, while XSDB accesses PS DDR physical 0x0000_0000.
set chip_ddr_sentinel 0x8FF00000
set ps_ddr_sentinel 0x0FF00000

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

step "check input files" {
  if {![file exists $psu_init_tcl]} {
    error "missing psu_init.tcl: $psu_init_tcl"
  }
  if {![file exists $bit_file]} {
    error "missing bitstream: $bit_file"
  }
  puts "psu_init.tcl = $psu_init_tcl"
  puts "bitstream    = $bit_file"
  puts [format "chip_ddr_sentinel = 0x%08X" $chip_ddr_sentinel]
  puts [format "ps_ddr_sentinel   = 0x%08X" $ps_ddr_sentinel]
}

step "connect hw_server" {
  connect -url tcp:127.0.0.1:3121
}

step "select PSU target" {
  select_psu_target
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
  select_psu_target
}

step "remove PS-PL isolation" {
  psu_ps_pl_isolation_removal
}

step "switch to APU target for PS DDR access" {
  select_apu_target
}

step "enable APU forced memory access" {
  configparams force-mem-accesses 1
}

step "add PS DDR memmap for sentinel window" {
  memmap -addr $ps_ddr_sentinel -size 0x1000 -flags 0x7
  puts [format "sentinel memmap: addr=0x%08X size=0x1000" $ps_ddr_sentinel]
}

step "clear DDR sentinel before reset release" {
  mwr -force $ps_ddr_sentinel 0x00000000
  puts [mrd -force $ps_ddr_sentinel]
}

step "switch back to PSU target for reset release" {
  select_psu_target
}

step "apply PS-PL reset config" {
  psu_ps_pl_reset_config
}

step "switch to APU target for post-reset sampling" {
  select_apu_target
}

step "sample DDR sentinel after reset release" {
  rd_ddr_sentinel "watch PS DDR 0x0FF00000 after psu_ps_pl_reset_config (Chipyard 0x8FF00000)" $ps_ddr_sentinel 200 100
}

step "final targets" {
  show_targets
}

step "disconnect" {
  disconnect
}

exit
