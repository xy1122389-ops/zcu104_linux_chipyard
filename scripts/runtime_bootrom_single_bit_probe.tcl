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

proc select_ps_tap_or_psu {} {
  if {![catch {targets 1}]} { return }
  if {![catch {targets -set -nocase -filter {name == "PS TAP"}}]} { return }
  if {![catch {targets -set -nocase -filter {name =~ "*PSU*"}}]} { return }
  error "unable to select PS TAP or PSU"
}

proc select_psu {} {
  if {![catch {targets -set -nocase -filter {name =~ "*PSU*"}}]} { return }
  error "unable to select PSU"
}

if {$argc != 2} {
  puts stderr "usage: runtime_bootrom_single_bit_probe.tcl <psu_init.tcl> <bitfile>"
  exit 2
}

set psu_init_tcl [lindex $argv 0]
set bit_file [lindex $argv 1]

step "check inputs" {
  if {![file exists $psu_init_tcl]} { error "missing psu_init.tcl: $psu_init_tcl" }
  if {![file exists $bit_file]} { error "missing bit file: $bit_file" }
  puts "PSU_INIT=$psu_init_tcl"
  puts "BIT_FILE=$bit_file"
}

step "connect" {
  connect -url tcp:127.0.0.1:3121
  configparams force-mem-accesses 1
}

step "por recover" {
  select_ps_tap_or_psu
  rst -por
  after 2500
}

step "select psu" {
  select_psu
}

step "source psu_init" {
  source $psu_init_tcl
}

step "run psu_init" {
  psu_init
}

step "program bit" {
  fpga $bit_file
}

step "release isolation" {
  after 1000
  select_psu
  psu_ps_pl_isolation_removal
  after 1000
  psu_ps_pl_reset_config
}

step "read bootrom head" {
  select_psu
  puts "BOOTROM_10000=[mrd -force 0x00010000 4]"
  puts "BOOTROM_10020=[mrd -force 0x00010020 4]"
}

catch {disconnect}
exit
