proc section {label} {
  puts ""
  puts "==== $label ===="
  flush stdout
}

proc emit {key value} {
  puts "$key=$value"
  flush stdout
}

proc step {label body} {
  section $label
  if {[catch {uplevel 1 $body} err opts]} {
    emit "STEP_ERR_LABEL" $label
    emit "STEP_ERR_VALUE" $err
    if {[dict exists $opts -errorinfo]} {
      puts [dict get $opts -errorinfo]
    }
    flush stdout
    exit 1
  }
}

proc select_ps_tap_or_psu {} {
  if {![catch {targets 1}]} { return }
  if {![catch {targets -set -nocase -filter {name == "PS TAP"}}]} { return }
  if {![catch {targets -set -nocase -filter {name =~ "*PSU*"}}]} { return }
  error "unable to select PS TAP or PSU"
}

proc select_psu {} {
  if {![catch {targets -set -nocase -filter {name =~ "*PSU*"}}]} { return }
  error "unable to select PSU"
}

proc select_apu {} {
  if {![catch {targets -set -nocase -filter {name == "APU (L2 Cache Reset)"}}]} { return }
  if {![catch {targets -set -nocase -filter {name == "APU"}}]} { return }
  if {![catch {targets 8}]} { return }
  error "unable to select APU"
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

proc state_reason_a53_0 {} {
  set rc [catch {targets -target-properties -filter {name =~ "*Cortex-A53 #0*"}} tprops]
  if {$rc} {
    return "ERR:[string trim $tprops]"
  }
  if {[catch {set tprop0 [lindex $tprops 0]; set reason [dict get $tprop0 state_reason]}]} {
    return "NA"
  }
  return $reason
}

proc pc_to_hex {pcraw} {
  if {[regexp -nocase {pc:\s*([0-9a-f]+)} $pcraw -> hx]} { return [string toupper $hx] }
  if {[regexp -nocase {0x([0-9a-f]+)} $pcraw -> hx2]} { return [string toupper $hx2] }
  return ""
}

proc probe_bp_addr {addr} {
  select_a53_0
  catch {stop}
  catch {bpremove -all}
  bpadd -type hw -addr $addr
  rst -processor
  after 100
  catch {con}
  after 300
  catch {stop}
  set reason [state_reason_a53_0]
  set pcraw [rr pc]
  set cpsr [rr cpsr]
  set pchex [pc_to_hex $pcraw]
  set addrhex [format %016llX $addr]
  set exact_hit NO
  if {$pchex eq $addrhex || $pchex eq [format %X $addr]} {
    set exact_hit YES
  }
  emit [format "BP_ADDR_0x%X_REASON" $addr] $reason
  emit [format "BP_ADDR_0x%X_PC" $addr] $pcraw
  emit [format "BP_ADDR_0x%X_CPSR" $addr] $cpsr
  emit [format "BP_ADDR_0x%X_EXACT_HIT" $addr] $exact_hit
  catch {bpremove -all}
}

set ladder_addrs {0x1F0 0x1F8 0x1FC 0x200 0x204 0x208 0x20C 0x210 0x220}

step "connect and baseline recover" {
  connect -url tcp:127.0.0.1:3121
  configparams force-mem-accesses 1
}

step "ladder" {
  foreach addr $ladder_addrs {
    probe_bp_addr $addr
  }
}

catch {bpremove -all}
catch {disconnect}
exit
