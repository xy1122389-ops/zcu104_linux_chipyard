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

proc select_psu_target {} {
  if {![catch {targets -set -nocase -filter {name =~ "*PSU*"}}]} { return }
  error "unable to select PSU"
}

proc select_apu_target {} {
  if {![catch {targets -set -nocase -filter {name == "APU (L2 Cache Reset)"}}]} { return }
  if {![catch {targets -set -nocase -filter {name == "APU"}}]} { return }
  if {![catch {targets 8}]} { return }
  error "unable to select APU"
}

proc select_a53_0 {} {
  if {![catch {targets 9}]} { return }
  if {![catch {targets -set -nocase -filter {name =~ "*Cortex-A53 #0*"}}]} { return }
  error "unable to select Cortex-A53 #0"
}

proc recover_targets_por {} {
  puts "RECOVER_ACTION=rst_por_retry"
  select_ps_tap_or_psu
  rst -por
  after 2500
}

proc rr {name} {
  if {[catch {rrd $name} out]} { return "ERR:[string trim $out]" }
  return [string trim $out]
}

proc mr {addr words} {
  if {[catch {mrd $addr $words} out]} { return "ERR:[string trim $out]" }
  return [string trim $out]
}

proc pc_to_hex {pcraw} {
  if {[regexp -nocase {pc:\s*([0-9a-f]+)} $pcraw -> hx]} { return [string toupper $hx] }
  if {[regexp -nocase {0x([0-9a-f]+)} $pcraw -> hx2]} { return [string toupper $hx2] }
  return ""
}

if {$argc != 1} {
  puts stderr "usage: runtime_0200_recover_and_step.tcl <fw_payload-flat-path>"
  exit 2
}

set flat_file [lindex $argv 0]
set payload_psddr_addr 0x00000000
set bootaddr 0x80000000
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

step "check inputs" {
  if {![file exists $psu_init_tcl]} { error "missing psu_init.tcl: $psu_init_tcl" }
  if {![file exists $bit_file]} { error "missing bitstream: $bit_file" }
  if {![file exists $flat_file]} { error "missing payload: $flat_file" }
  puts "PSU_INIT=$psu_init_tcl"
  puts "BIT_FILE=$bit_file"
  puts "PAYLOAD=$flat_file"
  puts [format "PAYLOAD_SIZE_ALIGNED=0x%x" $flat_size_aligned]
}

step "connect" {
  connect -url tcp:127.0.0.1:3121
  configparams force-mem-accesses 1
}

step "initial targets" {
  show_targets_safe
}

step "ensure psu visible" {
  if {[catch {select_psu_target} err]} {
    puts "INITIAL_PSU_SELECT_ERR=$err"
    recover_targets_por
    show_targets_safe
    select_psu_target
  }
  show_targets_safe
}

step "source psu_init" {
  source $psu_init_tcl
}

step "run psu_init" {
  psu_init
}

step "program bitstream" {
  fpga $bit_file
}

step "wait after fpga" {
  after 1000
}

step "reselect psu after fpga" {
  if {[catch {select_psu_target} err]} {
    puts "POST_FPGA_PSU_SELECT_ERR=$err"
    recover_targets_por
    show_targets_safe
    select_psu_target
  }
  show_targets_safe
}

step "remove isolation + reset config" {
  psu_ps_pl_isolation_removal
  after 1000
  psu_ps_pl_reset_config
}

step "download payload" {
  select_apu_target
  memmap -addr $payload_psddr_addr -size $flat_size_aligned -flags 0x7
  dow -data $flat_file $payload_psddr_addr
  puts "PAYLOAD_MRD0=[mr $payload_psddr_addr 1]"
}

step "program bootaddr + msip" {
  select_psu_target
  mwr $bootaddr_reg_lo 0x80000000
  mwr $bootaddr_reg_hi 0x00000000
  mwr $msip_addr 0x1
  puts "BOOTADDR_LO=[mr $bootaddr_reg_lo 1]"
  puts "BOOTADDR_HI=[mr $bootaddr_reg_hi 1]"
  puts "MSIP=[mr $msip_addr 1]"
}

step "pre release snapshot" {
  select_apu_target
  puts "PRE_MEM_01E0=[mr 0x1e0 2]"
  puts "PRE_MEM_0200=[mr 0x200 2]"
  select_a53_0
  puts "PRE_PC=[rr pc]"
  puts "PRE_CPSR=[rr cpsr]"
}

step "park a53 at 0x200" {
  select_a53_0
  catch {stop}
  catch {bpremove -all}
  bpadd -type hw -addr 0x0000000000000200
  rst -processor
  after 100
  catch {con}
  after 300
  catch {stop}
  puts "PARK_PC=[rr pc]"
  puts "PARK_CPSR=[rr cpsr]"
}

step "remove bp and single-step" {
  catch {bpremove -all}
  for {set i 1} {$i <= 5} {incr i} {
    catch {stp}
    set pcv [rr pc]
    set cpsrv [rr cpsr]
    puts [format "STEP%d_PC=%s" $i $pcv]
    puts [format "STEP%d_CPSR=%s" $i $cpsrv]
  }
}

step "summary" {
  set final_pc [rr pc]
  puts "FINAL_PC=$final_pc"
  puts "FINAL_CPSR=[rr cpsr]"
  puts "FINAL_PC_HEX=[pc_to_hex $final_pc]"
  select_apu_target
  puts "FINAL_MEM_0200=[mr 0x200 2]"
}

catch {bpremove -all}
catch {disconnect}
exit 0
