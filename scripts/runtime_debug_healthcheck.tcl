proc section {label} {
  puts ""
  puts "==== $label ===="
  flush stdout
}

proc emit_kv {key value} {
  puts "$key=$value"
  flush stdout
}

proc emit_cmd {key script} {
  if {[catch {uplevel 1 $script} out]} {
    emit_kv "${key}_OK" NO
    emit_kv "${key}_VALUE" [string trim $out]
  } else {
    emit_kv "${key}_OK" YES
    emit_kv "${key}_VALUE" [string trim $out]
  }
}

proc select_by_filter {filter} {
  if {[catch {targets -set -nocase -filter $filter} out]} {
    return [list NO [string trim $out]]
  }
  return [list YES [string trim $out]]
}

proc emit_select {prefix filter} {
  set res [select_by_filter $filter]
  emit_kv "${prefix}_SELECT_OK" [lindex $res 0]
  emit_kv "${prefix}_SELECT_VALUE" [lindex $res 1]
}

proc emit_targets_tree {prefix} {
  section "$prefix targets"
  if {[catch {targets} out]} {
    emit_kv "${prefix}_TARGETS_OK" NO
    emit_kv "${prefix}_TARGETS_VALUE" [string trim $out]
  } else {
    emit_kv "${prefix}_TARGETS_OK" YES
    puts [string trim $out]
    flush stdout
  }
}

proc emit_target_props {prefix filter} {
  if {[catch {targets -target-properties -filter $filter} out]} {
    emit_kv "${prefix}_PROPS_OK" NO
    emit_kv "${prefix}_PROPS_VALUE" [string trim $out]
  } else {
    emit_kv "${prefix}_PROPS_OK" YES
    emit_kv "${prefix}_PROPS_VALUE" [string trim $out]
  }
}

proc emit_reg_reads {prefix regs} {
  foreach reg $regs {
    emit_cmd "${prefix}_REG_[string toupper $reg]" [list rrd $reg]
  }
}

proc emit_mem_reads {prefix addr_words_list} {
  foreach item $addr_words_list {
    lassign $item addr words
    set addr_key [string map {0x ""} [string toupper $addr]]
    emit_cmd "${prefix}_MRD_${addr_key}" [list mrd $addr $words]
  }
}

section "connect"
emit_cmd "CONNECT" { connect -url tcp:127.0.0.1:3121 }
emit_cmd "FORCE_MEM_ACCESSES" { configparams force-mem-accesses 1 }

emit_targets_tree "INITIAL"

section "psu"
emit_select "PSU" {name =~ "*PSU*"}
emit_target_props "PSU" {name =~ "*PSU*"}
if {[lindex [select_by_filter {name =~ "*PSU*"}] 0] eq "YES"} {
  emit_mem_reads "PSU" {
    {0x1000 1}
    {0x1004 1}
    {0x2000000 1}
  }
}

section "apu"
emit_select "APU" {name =~ "*APU*"}
emit_target_props "APU" {name =~ "*APU*"}
if {[lindex [select_by_filter {name =~ "*APU*"}] 0] eq "YES"} {
  emit_reg_reads "APU" {pc dbgdscr}
  emit_mem_reads "APU" {
    {0x1e0 2}
    {0x200 2}
  }
}

section "a53_0"
emit_select "A53_0" {name =~ "*Cortex-A53 #0*"}
emit_target_props "A53_0" {name =~ "*Cortex-A53 #0*"}
if {[lindex [select_by_filter {name =~ "*Cortex-A53 #0*"}] 0] eq "YES"} {
  emit_reg_reads "A53_0" {pc cpsr r0 sp lr}
}

section "a53_1"
emit_select "A53_1" {name =~ "*Cortex-A53 #1*"}
emit_target_props "A53_1" {name =~ "*Cortex-A53 #1*"}
if {[lindex [select_by_filter {name =~ "*Cortex-A53 #1*"}] 0] eq "YES"} {
  emit_reg_reads "A53_1" {pc cpsr r0 sp lr}
}

section "disconnect"
emit_cmd "DISCONNECT" { disconnect }
exit
