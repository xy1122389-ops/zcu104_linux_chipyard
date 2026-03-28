proc step {label body} {
  puts "\n==== $label ===="
  flush stdout
  if {[catch {uplevel 1 $body} err opts]} {
    puts "STEP_ERR label=$label err=$err"
    if {[dict exists $opts -errorinfo]} {
      puts [dict get $opts -errorinfo]
    }
  }
}

proc sel_a53_0 {} {
  if {![catch {targets 9}]} { return 1 }
  if {![catch {targets -set -nocase -filter {name =~ "*Cortex-A53 #0*"}}]} { return 1 }
  return 0
}

proc sel_apu_any {} {
  if {![catch {targets -set -nocase -filter {name == "APU (L2 Cache Reset)"}}]} { return 1 }
  if {![catch {targets -set -nocase -filter {name == "APU"}}]} { return 1 }
  if {![catch {targets 8}]} { return 1 }
  return 0
}

proc emit_ctx {} {
  if {![sel_a53_0]} {
    puts "SIG_PC=NA"
    puts "SIG_SP=NA"
    return
  }
  if {[catch {rrd pc} pcv]} {
    puts "SIG_PC_ERR=$pcv"
  } else {
    puts "SIG_PC=$pcv"
  }
  if {[catch {rrd sp} spv]} {
    puts "SIG_SP_ERR=$spv"
  } else {
    puts "SIG_SP=$spv"
  }
}

proc emit_mem_words {} {
  if {![sel_apu_any]} {
    puts "SIG_MEM_ERR=cannot_select_apu"
    return
  }

  if {[catch {set m200 [mrd 0x200 2]} err200]} {
    puts "SIG_MEM200_ERR=$err200"
  } else {
    foreach line [split $m200 "\n"] {
      if {[regexp {\s*200:\s+([0-9A-Fa-f]+)} $line -> w200]} { puts "SIG_W_0200=$w200" }
      if {[regexp {\s*204:\s+([0-9A-Fa-f]+)} $line -> w204]} { puts "SIG_W_0204=$w204" }
    }
  }

  if {[catch {set m1e0 [mrd 0x1e0 2]} err1e0]} {
    puts "SIG_MEM1E0_ERR=$err1e0"
  } else {
    foreach line [split $m1e0 "\n"] {
      if {[regexp {\s*1E0:\s+([0-9A-Fa-f]+)} $line -> w1e0]} { puts "SIG_W_01E0=$w1e0" }
      if {[regexp {\s*1E4:\s+([0-9A-Fa-f]+)} $line -> w1e4]} { puts "SIG_W_01E4=$w1e4" }
    }
  }
}

if {$argc != 1} {
  puts stderr "usage: runtime_signature_probe.tcl <fw_payload-flat-path>"
  exit 2
}

set flat_file [lindex $argv 0]
set payload_psddr_addr 0x00000000
set bootaddr_reg_lo 0x1000
set bootaddr_reg_hi 0x1004
set msip_addr 0x2000000
set flat_size [file size $flat_file]
set flat_size_aligned [expr {($flat_size + 0xfff) & ~0xfff}]

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

step "connect" { connect -url tcp:127.0.0.1:3121 }
step "select PS TAP" { targets 1 }
step "rst por" { rst -por }
step "wait after por" { after 2000 }
step "select PSU" { targets -set -nocase -filter {name =~ "*PSU*"} }
step "source psu_init" { source $psu_init_tcl }
step "run psu_init" { psu_init }
step "program fpga" { fpga $bit_file }
step "wait after fpga" { after 1000 }
step "remove isolation" { psu_ps_pl_isolation_removal }
step "apply reset config" { psu_ps_pl_reset_config }
step "select APU for payload" {
  if {![sel_apu_any]} { error "cannot select APU" }
}
step "force mem" { configparams force-mem-accesses 1 }
step "memmap payload" { memmap -addr $payload_psddr_addr -size $flat_size_aligned -flags 0x7 }
step "download payload" { dow -data $flat_file $payload_psddr_addr }
step "select PSU for bootaddr" { targets -set -nocase -filter {name =~ "*PSU*"} }
step "program bootaddr + msip" {
  mwr $bootaddr_reg_lo 0x80000000
  mwr $bootaddr_reg_hi 0x00000000
  mwr $msip_addr 0x1
}
step "a53 rst-processor" {
  targets -set -nocase -filter {name =~ "*Cortex-A53 #0*"}
  rst -processor
  after 100
}
step "run short and stop" {
  targets -set -nocase -filter {name =~ "*Cortex-A53 #0*"}
  catch {con}
  after 300
  catch {stop}
}
step "emit signature ctx" { emit_ctx }
step "emit signature mem" { emit_mem_words }
step "disconnect" { disconnect }
exit 0
