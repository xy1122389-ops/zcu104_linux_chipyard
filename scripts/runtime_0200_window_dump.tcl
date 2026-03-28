proc try_select_a53_0 {} {
  if {![catch {targets 9}]} { return }
  if {![catch {targets -set -nocase -filter {name =~ "*Cortex-A53 #0*"}}]} { return }
  error "unable to select Cortex-A53 #0"
}

proc try_select_apu {} {
  if {![catch {targets -set -nocase -filter {name == "APU (L2 Cache Reset)"}}]} { return }
  if {![catch {targets -set -nocase -filter {name == "APU"}}]} { return }
  if {![catch {targets 8}]} { return }
  error "unable to select APU"
}

connect -url tcp:127.0.0.1:3121
configparams force-mem-accesses 1
try_select_a53_0
catch {stop}
after 100
puts "==== A53 TARGET AFTER STOP ===="
puts [targets]
try_select_apu
puts "==== MRD 0x1C0 32 ===="
puts [mrd 0x1c0 32]
catch {disconnect}
exit
