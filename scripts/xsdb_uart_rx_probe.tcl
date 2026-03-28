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

set uart_base 0x64000000
set rxdata [expr {$uart_base + 0x4}]
set txctrl [expr {$uart_base + 0x8}]
set rxctrl [expr {$uart_base + 0xC}]
set ie     [expr {$uart_base + 0x10}]
set divreg [expr {$uart_base + 0x18}]

step "connect hw_server" {
  connect -url tcp:127.0.0.1:3121
}

step "select PSU" {
  select_psu_target
}

step "configure uart" {
  mwr $ie 0x0
  mwr $divreg 0x1B1
  mwr $txctrl 0x1
  mwr $rxctrl 0x1
  puts "RXDATA_BEFORE=[mrd $rxdata]"
}

step "poll rxdata" {
  set got -1
  for {set i 0} {$i < 200} {incr i} {
    set v [mrd_word $rxdata]
    if {($v & 0x80000000) == 0} {
      set got $v
      break
    }
    after 10
  }
  if {$got >= 0} {
    puts [format "RXDATA_WORD=0x%08X" $got]
    puts [format "RXDATA_BYTE=0x%02X" [expr {$got & 0xff}]]
  } else {
    puts "RXDATA_WORD=EMPTY"
  }
}

step "disconnect" {
  disconnect
}

exit
