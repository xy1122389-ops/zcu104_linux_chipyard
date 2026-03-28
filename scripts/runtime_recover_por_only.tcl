proc emit {msg} {
  puts $msg
  flush stdout
}

proc select_reset_root {} {
  if {![catch {targets 1}]} { return "PS TAP" }
  if {![catch {targets -set -nocase -filter {name == "PS TAP"}}]} { return "PS TAP" }
  if {![catch {targets -set -nocase -filter {name =~ "*PSU*"}}]} { return "PSU" }
  error "unable to select PS TAP or PSU for rst -por"
}

connect -url tcp:127.0.0.1:3121
set root [select_reset_root]
emit "RECOVER_POR_ROOT=$root"
if {[catch {rst -por} out]} {
  emit "RECOVER_POR_OK=NO"
  emit "RECOVER_POR_VALUE=[string trim $out]"
} else {
  emit "RECOVER_POR_OK=YES"
  emit "RECOVER_POR_VALUE=[string trim $out]"
}
after 2500
catch {disconnect}
exit
