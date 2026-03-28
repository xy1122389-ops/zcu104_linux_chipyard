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

proc select_psu_target {} {
  if {![catch {targets -set -nocase -filter {name =~ "*PSU*"}}]} {
    return
  }
  error "unable to select PSU target"
}

set clock_gater_addr 0x100000
set bootaddr_reg_lo 0x1000
set bootaddr_reg_hi 0x1004
set tile_reset_addr 0x110000
set msip_addr 0x2000000
set bootaddr 0x80000000

step "connect hw_server" {
  connect -url tcp:127.0.0.1:3121
}

step "select PSU" {
  select_psu_target
  puts [targets]
}

step "enable tile clock" {
  mwr $clock_gater_addr 0x1
}

step "pulse tile reset and retrigger boot" {
  mwr $bootaddr_reg_lo $bootaddr
  mwr $bootaddr_reg_hi 0x0
  mwr $tile_reset_addr 0x1
  after 50
  mwr $tile_reset_addr 0x0
  mwr $msip_addr 0x0
  after 50
  mwr $msip_addr 0x1
}

step "readback" {
  puts "CLOCK_GATER=[mrd $clock_gater_addr]"
  puts "BOOTADDR_LO=[mrd $bootaddr_reg_lo]"
  puts "BOOTADDR_HI=[mrd $bootaddr_reg_hi]"
  puts "TILE_RESET=[mrd $tile_reset_addr]"
  puts "MSIP=[mrd $msip_addr]"
}

step "disconnect" {
  disconnect
}

exit
