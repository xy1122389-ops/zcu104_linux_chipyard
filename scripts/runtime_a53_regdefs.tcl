proc try_select_a53_0 {} {
  if {![catch {targets 9}]} { return }
  if {![catch {targets -set -nocase -filter {name =~ "*Cortex-A53 #0*"}}]} { return }
  error "unable to select Cortex-A53 #0"
}

connect -url tcp:127.0.0.1:3121
try_select_a53_0
catch {stop}
after 100
puts "==== TARGET ===="
puts [targets]
puts "==== RRD_DEFS ===="
catch {puts [rrd -defs]} err
if {$err ne ""} { puts "RRD_DEFS_ERR=$err" }
catch {disconnect}
exit
