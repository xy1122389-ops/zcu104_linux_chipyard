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

proc show_targets {} {
  catch {puts [targets]} err
  if {$err ne ""} {
    puts $err
  }
}

proc select_apu_target {} {
  if {![catch {targets -set -nocase -filter {name == "APU (L2 Cache Reset)"}}]} {
    return
  }
  if {![catch {targets -set -nocase -filter {name == "APU"}}]} {
    return
  }
  if {![catch {targets 8}]} {
    return
  }
  error "unable to select APU target by name or id"
}

if {$argc >= 1} {
  set flat_file [lindex $argv 0]
} elseif {[info exists ::env(FW_PAYLOAD_FLAT)]} {
  set flat_file $::env(FW_PAYLOAD_FLAT)
} else {
  puts stderr "ERROR: usage: xsdb load_linux_fw_payload.tcl <fw_payload-flat-path>"
  puts stderr "       or set FW_PAYLOAD_FLAT in the environment"
  exit 1
}

set payload_psddr_addr 0x00000000
set bootaddr 0x80000000
set bootaddr_reg_lo 0x1000
set bootaddr_reg_hi 0x1004
set msip_addr 0x2000000
set flat_size [file size $flat_file]
set flat_size_aligned [expr {($flat_size + 0xfff) & ~0xfff}]

if {$argc >= 2 && [lindex $argv 1] ne ""} {
  scan [lindex $argv 1] %llx bootaddr
}

step "check payload file" {
  if {![file exists $flat_file]} {
    error "payload file not found: $flat_file"
  }
  puts "flat payload = $flat_file"
  puts [format "flat_size = 0x%x aligned = 0x%x" $flat_size $flat_size_aligned]
  puts [format "payload_psddr_addr = 0x%08x" $payload_psddr_addr]
  puts [format "bootaddr = 0x%08x" $bootaddr]
}

step "connect hw_server" {
  connect -url tcp:127.0.0.1:3121
}

step "show targets" {
  show_targets
}

step "force XSDB memory accesses" {
  configparams force-mem-accesses 1
}

step "select APU target for PS DDR payload access" {
  select_apu_target
  show_targets
}

step "add XSDB memmap entry for PS DDR payload window" {
  memmap -addr $payload_psddr_addr -size $flat_size_aligned -flags 0x7
  puts [format "payload memmap: addr=0x%08x size=0x%x" $payload_psddr_addr $flat_size_aligned]
}

step "download flat payload to PS DDR physical 0x00000000" {
  dow -data $flat_file $payload_psddr_addr
  puts [mrd $payload_psddr_addr]
}

step "select PSU target for boot-address-reg and MSIP" {
  targets -set -nocase -filter {name =~ "*PSU*"}
  show_targets
}

step "program boot-address-reg for chip-visible DDR 0x80000000" {
  mwr $bootaddr_reg_lo $bootaddr
  mwr $bootaddr_reg_hi 0x00000000
  puts [mrd $bootaddr_reg_lo]
  puts [mrd $bootaddr_reg_hi]
}

step "trigger hart0 msip" {
  mwr $msip_addr 0x1
  puts [mrd $msip_addr]
}

step "final message" {
  puts "fw_payload loaded to PS DDR physical 0x00000000."
  puts [format "boot-address-reg points chip boot flow at 0x%08x and MSIP is asserted." $bootaddr]
  puts "Expected serial flow: bootrom banner -> OpenSBI -> Linux earlycon -> /#"
}

step "disconnect" {
  disconnect
}

exit
