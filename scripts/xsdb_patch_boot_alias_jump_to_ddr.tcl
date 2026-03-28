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
set insn0 0x800002B7
set insn1 0x00028067
set insn2 0x00000013
set insn3 0x00000013

step "connect hw_server" {
  connect -url tcp:127.0.0.1:3121
}

step "select PSU" {
  select_psu_target
}

step "show before" {
  puts [mrd $patch_base 4]
}

step "apply patch" {
  mwr $patch_base $insn0
  mwr [expr {$patch_base + 4}] $insn1
  mwr [expr {$patch_base + 8}] $insn2
  mwr [expr {$patch_base + 12}] $insn3
}

step "show after" {
  puts [mrd $patch_base 4]
}

step "disconnect" {
  disconnect
}

exit
