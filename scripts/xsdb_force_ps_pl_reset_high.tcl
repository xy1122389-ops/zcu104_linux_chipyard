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

set gpio_dirm_5        0xFF0A0344
set gpio_oen_5         0xFF0A0348
set gpio_mask_data_5_m 0xFF0A002C
set gpio_data_5_ro     0xFF0A0074
set high_mask          0xF0000000
set high_data_word     0x0FFFF000

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

step "connect hw_server" {
  connect -url tcp:127.0.0.1:3121
}

step "select PSU" {
  select_psu_target
}

step "show before" {
  puts "GPIO_DIRM_5_BEFORE=[mrd $gpio_dirm_5]"
  puts "GPIO_OEN_5_BEFORE=[mrd $gpio_oen_5]"
  puts "GPIO_DATA_5_RO_BEFORE=[mrd $gpio_data_5_ro]"
}

step "force high" {
  set dirm [mrd_word $gpio_dirm_5]
  set oen  [mrd_word $gpio_oen_5]
  mwr $gpio_dirm_5 [expr {$dirm | $high_mask}]
  mwr $gpio_oen_5  [expr {$oen  | $high_mask}]
  mwr $gpio_mask_data_5_m $high_data_word
}

step "show after" {
  puts "GPIO_DIRM_5_AFTER=[mrd $gpio_dirm_5]"
  puts "GPIO_OEN_5_AFTER=[mrd $gpio_oen_5]"
  puts "GPIO_DATA_5_RO_AFTER=[mrd $gpio_data_5_ro]"
}

step "disconnect" {
  disconnect
}

exit
