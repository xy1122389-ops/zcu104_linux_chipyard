proc section {label} {
  puts ""
  puts "==== $label ===="
  flush stdout
}

proc select_a53_0 {} {
  if {![catch {targets 9}]} { return }
  if {![catch {targets -set -nocase -filter {name =~ "*Cortex-A53 #0*"}}]} { return }
  error "unable to select Cortex-A53 #0"
}

proc rr {name} {
  if {[catch {rrd $name} out]} {
    return "ERR:[string trim $out]"
  }
  return [string trim $out]
}

proc reason {} {
  set rc [catch {targets -target-properties -filter {name =~ "*Cortex-A53 #0*"}} tprops]
  if {$rc} { return "ERR:[string trim $tprops]" }
  if {[catch {set tprop0 [lindex $tprops 0]; set r [dict get $tprop0 state_reason]}]} {
    return "NA"
  }
  return $r
}

proc snapshot {tag} {
  puts "${tag}_REASON=[reason]"
  puts "${tag}_PC=[rr pc]"
  puts "${tag}_CPSR=[rr cpsr]"
  puts "${tag}_R0=[rr r0]"
  puts "${tag}_SP=[rr sp]"
  if {[catch {set disout [dis pc 4]} err]} {
    puts "${tag}_DIS_ERR=[string trim $err]"
  } else {
    puts "${tag}_DIS=[string trim $disout]"
  }
  flush stdout
}

connect -url tcp:127.0.0.1:3121
select_a53_0
catch {stop}
after 100

section "initial"
puts [targets]
snapshot STABLE

section "stpi chain"
for {set i 1} {$i <= 3} {incr i} {
  catch {stpi}
  after 50
  snapshot [format "STPI_%d_RUNNING" $i]
  catch {stop}
  after 50
  snapshot [format "STPI_%d_STOPPED" $i]
}

section "reset back to 0x200"
catch {bpremove -all}
catch {bpadd -type hw -addr 0x0000000000000200}
catch {rst -processor}
after 100
catch {con}
after 300
catch {stop}
snapshot RESET_BACK

section "nxti chain"
catch {bpremove -all}
for {set i 1} {$i <= 3} {incr i} {
  catch {nxti}
  after 50
  snapshot [format "NXTI_%d_RUNNING" $i]
  catch {stop}
  after 50
  snapshot [format "NXTI_%d_STOPPED" $i]
}

catch {bpremove -all}
catch {disconnect}
exit
