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

set patch_base 0x10020
set insn0 0x640022B7
set insn1 0x00100313
set insn2 0x0062A423
set insn3 0x0002A623
set insn4 0x0000006F

step "connect hw_server" {
  connect -url tcp:127.0.0.1:3121
}

step "select PSU" {
  select_psu_target
}

step "show before" {
  puts [mrd $patch_base 5]
}

step "apply patch" {
  mwr $patch_base $insn0
  mwr [expr {$patch_base + 4}] $insn1
  mwr [expr {$patch_base + 8}] $insn2
  mwr [expr {$patch_base + 12}] $insn3
  mwr [expr {$patch_base + 16}] $insn4
}

step "show after" {
  puts [mrd $patch_base 5]
}

step "disconnect" {
  disconnect
}

exit
