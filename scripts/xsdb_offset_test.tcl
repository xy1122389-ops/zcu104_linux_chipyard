# xsdb_offset_test.tcl — Diagnose if mwr -force -bin -file introduces a byte offset
#
# Tests:
# 1. mwr single word to baseline address, verify
# 2. mwr -force -bin -file with 16-byte test file, read back at multiple offsets
# 3. mwr -force -bin -file with first 32 bytes of fw_payload.bin, read back

proc step {label body} {
  puts "\n==== $label ===="
  flush stdout
  if {[catch {uplevel 1 $body} err opts]} {
    puts stderr "ERROR in $label: $err"
    if {[dict exists $opts -errorinfo]} {
      puts stderr [dict get $opts -errorinfo]
    }
    flush stderr
    exit 1
  }
}

step "connect" {
  connect -url tcp:127.0.0.1:3121
  configparams force-mem-accesses 1
}

step "select PSU" {
  targets -set -nocase -filter {name =~ "*PSU*"}
}

step "Test A: single mwr + mrd baseline" {
  # Clear test area
  for {set i 0} {$i < 16} {incr i} {
    mwr -force [expr {0x04000000 + $i * 4}] 0x00000000
  }
  # Write known value
  mwr -force 0x04000000 0xAAAABBBB
  set v [mrd -force -value 0x04000000]
  puts [format "  mwr 0xAAAABBBB -> mrd = 0x%08x  %s" $v [expr {$v == 0xAAAABBBB ? "PASS" : "FAIL"}]]
}

step "Test B: mwr -force -bin -file with 16-byte test file" {
  set testfile {\\wsl.localhost\Ubuntu-22.04\tmp\test16.bin}
  
  # Clear area from 0x04000000 to 0x04004000 (16 KB ahead)
  for {set i 0} {$i < 32} {incr i} {
    mwr -force [expr {0x04000000 + $i * 4}] 0x00000000
  }
  
  # Write test file: 4 words (16 bytes) starting at 0x04000000
  puts "  Writing test16.bin (4 words) to 0x04000000..."
  mwr -force -bin -file $testfile 0x04000000 4
  
  # Read back at multiple offsets
  puts "  Expected: CAFEBABE 12345678 DEADBEEF FEEDFACE"
  puts ""
  puts "  Reading back from 0x04000000 to 0x04002020:"
  for {set off 0} {$off <= 0x2020} {incr off 0x1000} {
    set addr [expr {0x04000000 + $off}]
    set v0 [mrd -force -value $addr]
    set v1 [mrd -force -value [expr {$addr + 4}]]
    set v2 [mrd -force -value [expr {$addr + 8}]]
    set v3 [mrd -force -value [expr {$addr + 12}]]
    set match [expr {$v0 == 0xCAFEBABE && $v1 == 0x12345678}]
    puts [format "    0x%08x: %08x %08x %08x %08x  %s" $addr $v0 $v1 $v2 $v3 [expr {$match ? "<-- MATCH!" : ""}]]
  }
  # Also check exact 0x2000 offset
  set addr 0x04002000
  set v0 [mrd -force -value $addr]
  set v1 [mrd -force -value [expr {$addr + 4}]]
  set v2 [mrd -force -value [expr {$addr + 8}]]
  set v3 [mrd -force -value [expr {$addr + 12}]]
  set match [expr {$v0 == 0xCAFEBABE && $v1 == 0x12345678}]
  puts [format "    0x%08x: %08x %08x %08x %08x  %s" $addr $v0 $v1 $v2 $v3 [expr {$match ? "<-- MATCH at +0x2000!" : ""}]]
}

step "Test C: read DDR 0x00000000 area (after previous fw_payload load)" {
  puts "  fw_payload.bin first word should be 0x0e976f05"
  puts "  Scanning DDR 0x00000000 to 0x00003000:"
  for {set off 0} {$off <= 0x3000} {incr off 0x800} {
    set v [mrd -force -value $off]
    set match ""
    if {$v == 0x0E976F05} { set match "<-- OPENSBI FIRST WORD!" }
    puts [format "    0x%08x: 0x%08x  %s" $off $v $match]
  }
}

step "Test D: try dow -data with PSU target" {
  puts "  Attempting dow -data on PSU target..."
  if {[catch {dow -data {\\wsl.localhost\Ubuntu-22.04\tmp\test16.bin} 0x05000000} err]} {
    puts "  dow -data failed on PSU: $err"
    puts "  Switching to A53 #0 for dow -data test..."
    targets -set -nocase -filter {name =~ "*A53*#0*"}
    rst -processor -clear-registers
    after 500
    catch {stop}
    after 500
    dow -data {\\wsl.localhost\Ubuntu-22.04\tmp\test16.bin} 0x05000000
    
    # Switch back to PSU for mrd
    targets -set -nocase -filter {name =~ "*PSU*"}
    set v0 [mrd -force -value 0x05000000]
    set v1 [mrd -force -value 0x05000004]
    puts [format "  dow -data -> PSU mrd: 0x%08x 0x%08x (expect CAFEBABE 12345678)" $v0 $v1]
    
    # Also check +0x2000 offset  
    set v0b [mrd -force -value 0x05002000]
    set v1b [mrd -force -value 0x05002004]
    puts [format "  dow -data -> PSU mrd at +0x2000: 0x%08x 0x%08x" $v0b $v1b]
  }
}

step "disconnect" {
  disconnect
}

puts "\nDiagnostic complete."
exit
