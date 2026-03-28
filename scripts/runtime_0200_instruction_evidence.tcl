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

proc pc_to_hex {pcraw} {
  if {[regexp -nocase {pc:\s*([0-9a-f]+)} $pcraw -> hx]} { return [string toupper $hx] }
  if {[regexp -nocase {0x([0-9a-f]+)} $pcraw -> hx2]} { return [string toupper $hx2] }
  return ""
}

proc normalize_word {value} {
  scan $value %x intval
  return [format %08X $intval]
}

proc target_window_words {base words} {
  set out {}
  if {[catch {set raw [mrd $base $words]} err]} {
    error "mrd_failed:$err"
  }
  foreach line [split $raw "\n"] {
    if {[regexp {^\s*([0-9A-Fa-f]+):\s+([0-9A-Fa-f]+)} $line -> addr value]} {
      lappend out [normalize_word $value]
    }
  }
  if {[llength $out] != $words} {
    error "mrd_parse_failed:base=[format 0x%X $base] words=$words got=[llength $out]"
  }
  return $out
}

proc file_word_at {fh offset} {
  seek $fh $offset start
  set bytes [read $fh 4]
  if {[string length $bytes] != 4} {
    error "short_read:file_offset=[format 0x%X $offset]"
  }
  binary scan $bytes H8 hex
  set b0 [string range $hex 0 1]
  set b1 [string range $hex 2 3]
  set b2 [string range $hex 4 5]
  set b3 [string range $hex 6 7]
  return [string toupper "${b3}${b2}${b1}${b0}"]
}

proc file_window_words {fh base words} {
  set out {}
  for {set i 0} {$i < $words} {incr i} {
    lappend out [file_word_at $fh [expr {$base + (4 * $i)}]]
  }
  return $out
}

proc current_state_reason {} {
  set rc [catch {targets -target-properties -filter {name =~ "*Cortex-A53 #0*"}} tprops]
  if {$rc} {
    return "ERR:[string trim $tprops]"
  }
  if {[catch {set tprop0 [lindex $tprops 0]; set reason [dict get $tprop0 state_reason]}]} {
    return "NA"
  }
  return $reason
}

proc emit_step_snapshot {tag} {
  select_a53_0
  emit "${tag}_STATE_REASON" [current_state_reason]
  emit "${tag}_PC" [rr pc]
  emit "${tag}_CPSR" [rr cpsr]
  emit "${tag}_R0" [rr r0]
  emit "${tag}_SP" [rr sp]
  select_apu
  if {[catch {set raw [mrd 0x1fc 4]} err]} {
    emit "${tag}_NEIGHBOR_WORDS" "ERR:$err"
  } else {
    emit "${tag}_NEIGHBOR_WORDS" [string trim $raw]
  }
  select_a53_0
}

if {$argc != 1} {
  puts stderr "usage: runtime_0200_instruction_evidence.tcl <fw_payload-flat-path>"
  exit 2
}

set flat_file [lindex $argv 0]
set payload_psddr_addr 0x00000000
set bootaddr 0x80000000
set bootaddr_reg_lo 0x1000
set bootaddr_reg_hi 0x1004
set msip_addr 0x2000000
set flat_size [file size $flat_file]
set flat_size_aligned [expr {($flat_size + 0xfff) & ~0xfff}]
set target_window_base 0x1c0
set target_window_words_count 32
set payload_window_base 0x21c0
set neighbor_window_base 0x1fc
set neighbor_window_words_count 4

set linux_psu_init "/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/obj/ip/zcu104ps/psu_init.tcl"
set linux_bit "/root/chipyard/fpga/generated-src/chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig/obj/ZCU104FPGATestHarness.bit"
set windows_psu_init {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig\obj\ip\zcu104ps\psu_init.tcl}
set windows_bit {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig\obj\ZCU104FPGATestHarness.bit}

if {$tcl_platform(platform) eq "windows"} {
  set psu_init_tcl $windows_psu_init
  set bit_file $windows_bit
} else {
  set psu_init_tcl $linux_psu_init
  set bit_file $linux_bit
}

step "check inputs" {
  if {![file exists $flat_file]} { error "missing payload file: $flat_file" }
  if {![file exists $psu_init_tcl]} { error "missing psu_init.tcl: $psu_init_tcl" }
  if {![file exists $bit_file]} { error "missing bitstream: $bit_file" }
  emit "PAYLOAD_FILE" $flat_file
  emit "BOOTADDR" [format 0x%X $bootaddr]
}

step "connect and recover" {
  connect -url tcp:127.0.0.1:3121
  configparams force-mem-accesses 1
  select_ps_tap_or_psu
  rst -por
  after 2500
}

step "psu init and fpga" {
  select_psu
  source $psu_init_tcl
  psu_init
  fpga $bit_file
  after 1000
  select_psu
  psu_ps_pl_isolation_removal
  after 1000
  psu_ps_pl_reset_config
}

step "payload download and bootaddr" {
  select_apu
  memmap -addr $payload_psddr_addr -size $flat_size_aligned -flags 0x7
  dow -data $flat_file $payload_psddr_addr
  select_psu
  mwr $bootaddr_reg_lo $bootaddr
  mwr $bootaddr_reg_hi 0x00000000
  mwr $msip_addr 0x1
  emit "POST_BOOTADDR_LO" [string trim [mrd $bootaddr_reg_lo 1]]
  emit "POST_MSIP" [string trim [mrd $msip_addr 1]]
}

step "target vs payload compare" {
  select_apu
  set target_words [target_window_words $target_window_base $target_window_words_count]
  set fh [open $flat_file rb]
  fconfigure $fh -translation binary -encoding binary
  set payload_words [file_window_words $fh $payload_window_base $target_window_words_count]
  close $fh

  emit "TARGET_WINDOW_BASE" [format 0x%X $target_window_base]
  emit "PAYLOAD_WINDOW_BASE" [format 0x%X $payload_window_base]
  emit "OFFSET_RELATION" [format "target +0x%X -> payload" [expr {$payload_window_base - $target_window_base}]]
  emit "TARGET_WINDOW_WORDS" [join $target_words ","]
  emit "PAYLOAD_WINDOW_WORDS" [join $payload_words ","]

  set match_count 0
  for {set i 0} {$i < $target_window_words_count} {incr i} {
    set t [lindex $target_words $i]
    set p [lindex $payload_words $i]
    if {$t eq $p} { incr match_count }
    emit [format "CMP_WORD_%02d" $i] [format "target=%s payload=%s match=%s" $t $p [expr {$t eq $p ? "YES" : "NO"}]]
  }
  emit "WINDOW_MATCH_COUNT" [format "%d/%d" $match_count $target_window_words_count]
  emit "WINDOW_FULL_MATCH" [expr {$match_count == $target_window_words_count ? "YES" : "NO"}]
}

step "park a53 at 0x200" {
  select_a53_0
  set pre_pc [rr pc]
  emit "PRE_PARK_PC" $pre_pc
  emit "PRE_PARK_STATE_REASON" [current_state_reason]
  if {[pc_to_hex $pre_pc] ne "0000000000000200" && [pc_to_hex $pre_pc] ne "200"} {
    emit "PARK_RECOVERY_USED" YES
    catch {stop}
    catch {bpremove -all}
    bpadd -type hw -addr 0x0000000000000200
    rst -processor
    after 100
    catch {con}
    after 300
    catch {stop}
  } else {
    emit "PARK_RECOVERY_USED" NO
  }
  emit "PARK_STATE_REASON" [current_state_reason]
  emit "PARK_PC" [rr pc]
  emit "PARK_CPSR" [rr cpsr]
}

step "single-step chain" {
  select_a53_0
  catch {bpremove -all}
  emit_step_snapshot STEP0
  for {set i 1} {$i <= 5} {incr i} {
    catch {stp}
    emit_step_snapshot [format "STEP%d" $i]
  }
}

catch {bpremove -all}
catch {disconnect}
exit
