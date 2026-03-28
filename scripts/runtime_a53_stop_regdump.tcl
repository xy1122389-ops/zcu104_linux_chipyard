proc try_select_a53_0 {} {
  if {![catch {targets 9}]} { return }
  if {![catch {targets -set -nocase -filter {name =~ "*Cortex-A53 #0*"}}]} { return }
  error "unable to select Cortex-A53 #0"
}

connect -url tcp:127.0.0.1:3121
try_select_a53_0
puts "==== BEFORE STOP ===="
puts [targets]
catch {stop}
after 100
puts "==== AFTER STOP ===="
puts [targets]
puts "==== A53_0 RRD ALL AFTER STOP ===="
puts [rrd]
catch {disconnect}
exit
