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

set uart_base 0xFF010000
set ctrl   [expr {$uart_base + 0x0}]
set mode   [expr {$uart_base + 0x4}]
set chstat [expr {$uart_base + 0x2C}]
set fifo   [expr {$uart_base + 0x30}]
set div    [expr {$uart_base + 0x34}]
set baud   [expr {$uart_base + 0x18}]
set msg "PS_UART1_TEST_115200\r\n"

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

proc wait_tx_room {addr} {
  for {set i 0} {$i < 500} {incr i} {
    set v [mrd_word $addr]
    if {($v & 0x10) == 0} {
      return
    }
    after 1
  }
  error "ps uart tx full timeout"
}

step "connect hw_server" {
  connect -url tcp:127.0.0.1:3121
}

step "select PSU" {
  select_psu_target
  puts [targets]
}

step "read uart1 config" {
  puts "UART1_CTRL=[mrd $ctrl]"
  puts "UART1_MODE=[mrd $mode]"
  puts "UART1_BAUD=[mrd $baud]"
  puts "UART1_DIV=[mrd $div]"
  puts "UART1_CHSTAT=[mrd $chstat]"
}

step "write test string" {
  binary scan $msg c* bytes
  foreach b $bytes {
    set v [expr {$b & 0xff}]
    wait_tx_room $chstat
    mwr $fifo $v
    after 1
  }
  puts "UART1_CHSTAT_AFTER=[mrd $chstat]"
}

step "disconnect" {
  disconnect
}

exit
