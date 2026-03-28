proc step {name body} {
  puts ""
  puts "==== $name ===="
  uplevel 1 $body
}

proc show_targets {} {
  catch {puts [targets]} err
  if {$err ne ""} {
    puts $err
  }
}

if {$argc != 1} {
  error "usage: xsdb load_linux_fw_payload_psu.tcl <flat-binary>"
}

set flat_file [lindex $argv 0]
set payload_psddr_addr 0x00000000
set bootaddr 0x80000000
set bootaddr_reg_lo 0x1000
set bootaddr_reg_hi 0x1004
set msip_addr 0x2000000

step "check payload file" {
  if {![file exists $flat_file]} {
    error "flat payload not found: $flat_file"
  }
  set flat_size [file size $flat_file]
  set flat_size_aligned [expr {($flat_size + 0xfff) & ~0xfff}]
  puts [format "flat_file=%s" $flat_file]
  puts [format "flat_size=0x%x aligned=0x%x" $flat_size $flat_size_aligned]
  puts [format "payload_psddr_addr=0x%08x" $payload_psddr_addr]
  puts [format "bootaddr=0x%08x" $bootaddr]
}

step "connect hw_server" {
  connect -url tcp:127.0.0.1:3121
}

step "show all targets" {
  show_targets
}

step "force XSDB memory accesses" {
  configparams force-mem-accesses 1
}

step "select APU target for PS DDR payload access" {
  targets -set -nocase -filter {name == "APU (L2 Cache Reset)"}
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

step "reselect PSU target for boot-address-reg and MSIP" {
  targets -set -nocase -filter {name =~ "*PSU*"}
  show_targets
}

step "program boot-address-reg" {
  mwr $bootaddr_reg_lo 0x80000000
  mwr $bootaddr_reg_hi 0x00000000
  puts [mrd $bootaddr_reg_lo]
  puts [mrd $bootaddr_reg_hi]
}

step "trigger hart0 msip" {
  mwr $msip_addr 0x1
  puts [mrd $msip_addr]
}

step "disconnect" {
  disconnect
}
