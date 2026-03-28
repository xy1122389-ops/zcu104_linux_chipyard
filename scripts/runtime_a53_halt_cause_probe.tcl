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

proc pc_to_hex {pcraw} {
  if {[regexp -nocase {pc:\s*([0-9a-f]+)} $pcraw -> hx]} { return [string toupper $hx] }
  if {[regexp -nocase {0x([0-9a-f]+)} $pcraw -> hx2]} { return [string toupper $hx2] }
  return ""
}

proc dump_group {group_name} {
  section "rrd $group_name"
  if {[catch {set out [rrd $group_name]} err]} {
    puts "RRD_${group_name}_ERR=[string trim $err]"
  } else {
    puts [string trim $out]
  }
  flush stdout
}

proc emit_dbg_field {raw field} {
  if {[regexp [format {%s:\s+([0-9A-Fa-f]+)} $field] $raw -> value]} {
    puts "DBG_[string toupper $field]=$value"
  } else {
    puts "DBG_[string toupper $field]=NA"
  }
  flush stdout
}

connect -url tcp:127.0.0.1:3121
select_a53_0
catch {stop}
after 100

set pre_pc [rr pc]
set pre_cpsr [rr cpsr]
set recovery_used NO
section "pre state"
puts "PRE_PC=$pre_pc"
puts "PRE_CPSR=$pre_cpsr"

if {[pc_to_hex $pre_pc] eq ""} {
  set recovery_used YES
  catch {bpremove -all}
  catch {bpadd -type hw -addr 0x0000000000000200}
  catch {rst -processor}
  after 100
  catch {con}
  after 300
  catch {stop}
}

section "target"
puts [targets]
puts "RECOVERY_USED=$recovery_used"
set tprops_rc [catch {targets -target-properties -filter {name =~ "*Cortex-A53 #0*"}} tprops]
if {$tprops_rc} {
  puts "TARGET_PROPS_ERR=[string trim $tprops]"
} else {
  puts "TARGET_PROPS=$tprops"
  if {![catch {set tprop0 [lindex $tprops 0]; set reason [dict get $tprop0 state_reason]}]} {
    puts "TARGET_STATE_REASON=$reason"
  } else {
    puts "TARGET_STATE_REASON=NA"
  }
}

section "core regs"
puts "PC=[rr pc]"
puts "CPSR=[rr cpsr]"
puts "R0=[rr r0]"
puts "R14=[rr r14]"
puts "R30=[rr r30]"
puts "SP=[rr sp]"
puts "PC_HEX=[pc_to_hex [rr pc]]"

section "rrd defs"
if {[catch {set defs [rrd -defs]} err]} {
  puts "RRD_DEFS_ERR=[string trim $err]"
} else {
  puts [string trim $defs]
}

section "rrd defs sys"
if {[catch {set defs_sys [rrd -defs sys]} err]} {
  puts "RRD_DEFS_SYS_ERR=[string trim $err]"
} else {
  puts [string trim $defs_sys]
}

section "rrd defs dbg"
if {[catch {set defs_dbg [rrd -defs dbg]} err]} {
  puts "RRD_DEFS_DBG_ERR=[string trim $err]"
} else {
  puts [string trim $defs_dbg]
}

dump_group sys
if {[catch {set dbg_raw [rrd dbg]} err]} {
  section "rrd dbg"
  puts "RRD_dbg_ERR=[string trim $err]"
  set dbg_raw ""
} else {
  section "rrd dbg"
  puts [string trim $dbg_raw]
  emit_dbg_field $dbg_raw mdscr_el1
  emit_dbg_field $dbg_raw oseccr_el1
  emit_dbg_field $dbg_raw mdrar_el1
  emit_dbg_field $dbg_raw oslsr_el1
  emit_dbg_field $dbg_raw dbgprcr_el1
  emit_dbg_field $dbg_raw dbgclaimset_el1
  emit_dbg_field $dbg_raw dbgclaimclr_el1
  emit_dbg_field $dbg_raw dbgauthstatus_el1
  emit_dbg_field $dbg_raw dbgvcr32_el2
}
dump_group acpu_gic

catch {bpremove -all}
catch {disconnect}
exit
