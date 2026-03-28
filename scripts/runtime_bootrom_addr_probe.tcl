proc step {label body} {
  puts "\n==== $label ===="
  flush stdout
  if {[catch {uplevel 1 $body} err opts]} {
    puts "STEP_ERR_LABEL=$label"
    puts "STEP_ERR_VALUE=$err"
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

if {$argc != 4} {
  puts stderr "usage: runtime_bootrom_addr_probe.tcl <psu_init.tcl> <bitfile> <baseaddr-hex> <words>"
  exit 2
}

set psu_init_tcl [lindex $argv 0]
set bit_file [lindex $argv 1]
scan [lindex $argv 2] %llx baseaddr
set words [lindex $argv 3]

step "check inputs" {
  if {![file exists $psu_init_tcl]} { error "missing psu_init.tcl: $psu_init_tcl" }
  if {![file exists $bit_file]} { error "missing bit file: $bit_file" }
  puts "PSU_INIT=$psu_init_tcl"
  puts "BIT_FILE=$bit_file"
  puts [format "BASEADDR=0x%X" $baseaddr]
  puts "WORDS=$words"
}

step "connect and recover" {
  connect -url tcp:127.0.0.1:3121
  configparams force-mem-accesses 1
  select_ps_tap_or_psu
  rst -por
  after 2500
}

step "psu init and fpga" {
  select_psu
  source $psu_init_tcl
  psu_init
  fpga $bit_file
  after 1000
  select_psu
  psu_ps_pl_isolation_removal
  after 1000
  psu_ps_pl_reset_config
}

step "read bootrom region" {
  select_psu
  puts [mrd -force $baseaddr $words]
}

catch {disconnect}
exit
