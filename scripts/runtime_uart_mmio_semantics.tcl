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

proc select_psu_target {} {
  if {![catch {targets -set -nocase -filter {name =~ "*PSU*"}}]} { return }
  error "unable to select PSU target"
}

proc mrd_line {addr} {
  return [string trim [mrd $addr]]
}

proc emit_reg {tag addr} {
  puts [format "%s_0x%08X=%s" $tag $addr [mrd_line $addr]]
  flush stdout
}

set uart_base 0x64000000
set txdata   [expr {$uart_base + 0x0}]
set rxdata   [expr {$uart_base + 0x4}]
set txctrl   [expr {$uart_base + 0x8}]
set rxctrl   [expr {$uart_base + 0xC}]
set ie       [expr {$uart_base + 0x10}]
set ip       [expr {$uart_base + 0x14}]
set divreg   [expr {$uart_base + 0x18}]
set probe_addrs [list $txdata $rxdata $txctrl $rxctrl $ie $ip $divreg]

step "connect" {
  connect -url tcp:127.0.0.1:3121
  configparams force-mem-accesses 1
}

step "select PSU" {
  select_psu_target
}

step "baseline reads" {
  foreach addr $probe_addrs {
    emit_reg BASE $addr
  }
}

step "program control regs" {
  mwr $ie 0x0
  mwr $divreg 0x1B1
  mwr $txctrl 0x1
  mwr $rxctrl 0x1
  foreach addr $probe_addrs {
    emit_reg POSTCFG $addr
  }
}

step "write txdata pattern" {
  foreach value {0x41 0x42 0x43 0x55} {
    mwr $txdata $value
    puts [format "WRITE_TXDATA=0x%02X" $value]
    emit_reg TXSNAP $txdata
    emit_reg TXSNAP $ip
    after 10
  }
}

step "stability rereads" {
  for {set round 0} {$round < 5} {incr round} {
    puts "REREAD_ROUND=$round"
    foreach addr $probe_addrs {
      emit_reg REREAD $addr
    }
    after 20
  }
}

step "disconnect" {
  disconnect
}

exit
