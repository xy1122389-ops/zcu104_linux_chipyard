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

proc compare_windows {base target_words same_words plus_words} {
  set same_match 0
  set plus_match 0
  set words [llength $target_words]
  set same_mismatch_addrs {}
  set plus_mismatch_addrs {}

  emit "WINDOW_BASE" [format 0x%X $base]
  emit "OFFSET_HYPOTHESIS" "+0x2000"
  emit "TARGET_WORDS" [join $target_words ","]
  emit "PAYLOAD_SAME_WORDS" [join $same_words ","]
  emit "PAYLOAD_PLUS2000_WORDS" [join $plus_words ","]

  for {set i 0} {$i < $words} {incr i} {
    set t [lindex $target_words $i]
    set s [lindex $same_words $i]
    set p [lindex $plus_words $i]
    if {$t eq $s} {
      incr same_match
    } else {
      lappend same_mismatch_addrs [format 0x%X [expr {$base + (4 * $i)}]]
    }
    if {$t eq $p} {
      incr plus_match
    } else {
      lappend plus_mismatch_addrs [format 0x%X [expr {$base + (4 * $i)}]]
    }
    emit [format "WORD_%d" $i] [format "target=%s same=%s plus2000=%s same_match=%s plus2000_match=%s" \
      $t $s $p [expr {$t eq $s ? "YES" : "NO"}] [expr {$t eq $p ? "YES" : "NO"}]]
  }

  emit "MATCH_SAME_OFFSET" [format "%d/%d" $same_match $words]
  emit "MATCH_PLUS_2000" [format "%d/%d" $plus_match $words]
  emit "FULL_MATCH_SAME_OFFSET" [expr {$same_match == $words ? "YES" : "NO"}]
  emit "FULL_MATCH_PLUS_2000" [expr {$plus_match == $words ? "YES" : "NO"}]
  emit "WINDOW_SUMMARY" [format "base=0x%X match_self=%s match_plus_0x2000=%s matched_words_self=%d/%d matched_words_plus_0x2000=%d/%d" \
    $base \
    [expr {$same_match == $words ? "yes" : "no"}] \
    [expr {$plus_match == $words ? "yes" : "no"}] \
    $same_match $words \
    $plus_match $words]
  emit "WINDOW_MISMATCH_ADDRS_SELF" [expr {[llength $same_mismatch_addrs] ? [join $same_mismatch_addrs ","] : "none"}]
  emit "WINDOW_MISMATCH_ADDRS_PLUS_0X2000" [expr {[llength $plus_mismatch_addrs] ? [join $plus_mismatch_addrs ","] : "none"}]

  return [list $same_match $plus_match $same_mismatch_addrs $plus_mismatch_addrs]
}

proc format_runs {bases step} {
  if {[llength $bases] == 0} {
    return ""
  }

  set runs {}
  set run_start [lindex $bases 0]
  set prev $run_start

  for {set i 1} {$i < [llength $bases]} {incr i} {
    set cur [lindex $bases $i]
    if {$cur != ($prev + $step)} {
      lappend runs [format "0x%X-0x%X" $run_start $prev]
      set run_start $cur
    }
    set prev $cur
  }

  lappend runs [format "0x%X-0x%X" $run_start $prev]
  return [join $runs ","]
}

if {$argc != 1} {
  puts stderr "usage: runtime_payload_offset_evidence.tcl <fw_payload-flat-path>"
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
set window_words 16
set sample_bases {}
for {set base 0} {$base <= 0x2000} {incr base 0x40} {
  lappend sample_bases $base
}

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
  emit "PAYLOAD_SIZE_ALIGNED" [format 0x%X $flat_size_aligned]
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
  emit "POST_BOOTADDR_HI" [string trim [mrd $bootaddr_reg_hi 1]]
  emit "POST_MSIP" [string trim [mrd $msip_addr 1]]
}

step "window compare" {
  select_apu
  set fh [open $flat_file rb]
  fconfigure $fh -translation binary -encoding binary

  set full_plus_bases {}
  set full_same_bases {}
  set partial_plus_bases {}
  set no_plus_bases {}

  foreach base $sample_bases {
    set target_words [target_window_words $base $window_words]
    set same_words [file_window_words $fh $base $window_words]
    set plus_words [file_window_words $fh [expr {$base + 0x2000}] $window_words]

    lassign [compare_windows $base $target_words $same_words $plus_words] same_match plus_match same_mismatch_addrs plus_mismatch_addrs

    if {$same_match == $window_words} { lappend full_same_bases $base }
    if {$plus_match == $window_words} {
      lappend full_plus_bases $base
    } elseif {$plus_match > 0} {
      lappend partial_plus_bases $base
      emit "PARTIAL_PLUS_WINDOW_DETAIL" [format "base=0x%X mismatch_addrs=%s" $base [join $plus_mismatch_addrs ","]]
    } else {
      lappend no_plus_bases $base
    }
  }

  close $fh

  section "summary"
  set full_plus_fmt {}
  foreach b $full_plus_bases { lappend full_plus_fmt [format 0x%X $b] }
  set partial_plus_fmt {}
  foreach b $partial_plus_bases { lappend partial_plus_fmt [format 0x%X $b] }
  set no_plus_fmt {}
  foreach b $no_plus_bases { lappend no_plus_fmt [format 0x%X $b] }
  set full_same_fmt {}
  foreach b $full_same_bases { lappend full_same_fmt [format 0x%X $b] }

  emit "FULL_MATCH_PLUS_2000_BASES" [join $full_plus_fmt ","]
  emit "PARTIAL_MATCH_PLUS_2000_BASES" [join $partial_plus_fmt ","]
  emit "NO_MATCH_PLUS_2000_BASES" [join $no_plus_fmt ","]
  emit "FULL_MATCH_SAME_OFFSET_BASES" [join $full_same_fmt ","]
  emit "FULL_MATCH_PLUS_2000_RUNS" [format_runs $full_plus_bases 0x40]
  emit "FULL_MATCH_SELF_RUNS" [format_runs $full_same_bases 0x40]
  if {[llength $full_plus_bases] > 0} {
    emit "LAST_FULL_PLUS_BASE" [format 0x%X [lindex $full_plus_bases end]]
  } else {
    emit "LAST_FULL_PLUS_BASE" NA
  }
  if {[llength $full_same_bases] > 0} {
    emit "FIRST_FULL_SELF_BASE" [format 0x%X [lindex $full_same_bases 0]]
  } else {
    emit "FIRST_FULL_SELF_BASE" NA
  }
  if {[llength $full_plus_bases] > 0 && [llength $full_same_bases] > 0} {
    emit "TRANSITION_INTERVAL" [format "between 0x%X and 0x%X" [lindex $full_plus_bases end] [lindex $full_same_bases 0]]
  } else {
    emit "TRANSITION_INTERVAL" NA
  }
  emit "FULL_PLUS_CONTIGUOUS_FROM_ZERO" [expr {[llength $full_plus_bases] > 0 && [lindex $full_plus_bases 0] == 0 && [format_runs $full_plus_bases 0x40] eq [format "0x0-0x%X" [lindex $full_plus_bases end]] ? "YES" : "NO"}]
  emit "IS_PLUS_2000_GLOBAL_ACROSS_SAMPLES" [expr {[llength $full_plus_bases] == [llength $sample_bases] ? "YES" : "NO"}]
  emit "PLUS_2000_MATCH_SCOPE" [expr {[llength $full_plus_bases] <= 3 ? "LOCALIZED" : "BROADER_THAN_SINGLE_WINDOW"}]
  emit "LIKELY_ALIAS_REMAP_WINDOW" [expr {[llength $full_plus_bases] > 0 && [lindex $full_plus_bases 0] == 0 && [llength $full_same_bases] > 0 ? "YES" : "UNCONFIRMED"}]
}

catch {disconnect}
exit
