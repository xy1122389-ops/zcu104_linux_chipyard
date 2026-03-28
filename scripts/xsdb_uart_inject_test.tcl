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

set uart_base 0x64000000
set txdata   [expr {$uart_base + 0x0}]
set rxdata   [expr {$uart_base + 0x4}]
set txctrl   [expr {$uart_base + 0x8}]
set ie       [expr {$uart_base + 0x10}]
set ip       [expr {$uart_base + 0x14}]
set divreg   [expr {$uart_base + 0x18}]
set baud_div 433
set msg "UART_TEST_ZCU104_115200\\r\\n"

proc mrd_word {addr} {
  set out [mrd $addr]
  foreach line [split $out "\n"] {
    if {[regexp {:\s+([0-9A-Fa-f]+)} $line -> w]} {
      scan $w %x v
      return $v
    }
  }
  error "unable to parse mrd output for 0x[format %08x $addr]: $out"
}

proc wait_tx_ready {addr} {
  for {set i 0} {$i < 200} {incr i} {
    set v [mrd_word $addr]
    if {($v & 0x80000000) == 0} {
      return
    }
    after 1
  }
  error "uart tx full timeout"
}

step "connect hw_server" {
  connect -url tcp:127.0.0.1:3121
}

step "select PSU" {
  select_psu_target
  puts [targets]
}

step "configure uart" {
  mwr $ie 0x0
  mwr $divreg $baud_div
  mwr $txctrl 0x1
  puts "UART_TXCTRL=[mrd $txctrl]"
  puts "UART_DIV=[mrd $divreg]"
  puts "UART_TXDATA_BEFORE=[mrd $txdata]"
  puts "UART_RXDATA_BEFORE=[mrd $rxdata]"
  puts "UART_IP_BEFORE=[mrd $ip]"
}

step "write test string" {
  binary scan $msg c* bytes
  foreach b $bytes {
    set v [expr {$b & 0xff}]
    wait_tx_ready $txdata
    mwr $txdata $v
    after 10
  }
  puts "UART_TXDATA_AFTER=[mrd $txdata]"
  puts "UART_IP_AFTER=[mrd $ip]"
}

step "disconnect" {
  disconnect
}

exit
