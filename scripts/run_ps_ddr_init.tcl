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

set linux_psu_init "/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104Config/obj/ip/zcu104ps/psu_init.tcl"
set linux_bit "/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104Config/obj/ZCU104FPGATestHarness.bit"
set windows_psu_init {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104Config\obj\ip\zcu104ps\psu_init.tcl}
set windows_bit {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104Config\obj\ZCU104FPGATestHarness.bit}

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

step "program FPGA bitstream" {
  fpga $bit_file
}

step "wait after FPGA program" {
  after 1000
}

step "reselect PSU target" {
  targets -set -nocase -filter {name =~ "*PSU*"}
  targets
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
  puts "PS DDR init + FPGA download flow completed."
  puts "Now open the UART terminal and look for:"
  puts "  hello from baremetal"
  puts "  ddr test start"
  puts "  ddr fixed pass"
  puts "  ddr linear pass"
  puts "  ddr test pass"
}

step "disconnect" {
  disconnect
}

exit
