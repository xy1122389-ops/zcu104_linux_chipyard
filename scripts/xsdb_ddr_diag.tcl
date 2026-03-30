# xsdb_ddr_diag.tcl — Diagnostic: test DDR read/write from ARM core
# Tests if dow -data actually writes correct data to DDR

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

step "connect hw_server" {
  connect -url tcp:127.0.0.1:3121
  configparams force-mem-accesses 1
  puts "Memory access checks bypassed."
}

step "select and prepare A53 #0" {
  targets -set -nocase -filter {name =~ "*A53*#0*"}
  rst -processor -clear-registers
  catch {stop}
  after 500
}

step "Test 1: mwr/mrd at DDR 0x01000000 (safely above any OCM alias)" {
  mwr 0x01000000 0xDEADCAFE
  set v [mrd -value 0x01000000]
  puts [format "  wrote 0xDEADCAFE, read back 0x%08x => %s" $v [expr {$v == 0xDEADCAFE ? "PASS" : "FAIL"}]]
}

step "Test 2: mwr/mrd at DDR 0x00000000 (might be OCM alias)" {
  mwr 0x00000000 0xBAADF00D
  set v [mrd -value 0x00000000]
  puts [format "  wrote 0xBAADF00D, read back 0x%08x => %s" $v [expr {$v == 0xBAADF00D ? "PASS" : "FAIL"}]]
}

step "Test 3: mwr/mrd at DDR 0x00200000 (above OCM, inside firmware range)" {
  mwr 0x00200000 0x12345678
  set v [mrd -value 0x00200000]
  puts [format "  wrote 0x12345678, read back 0x%08x => %s" $v [expr {$v == 0x12345678 ? "PASS" : "FAIL"}]]
}

step "Test 4: dow -data small test file -> 0x01000000" {
  # Create a 16-byte test file with known content
  set testfile [file join [file dirname [info script]] _ddr_test.bin]
  if {$tcl_platform(platform) eq "windows"} {
    set testfile "C:/Windows/Temp/_ddr_test.bin"
  }
  set fd [open $testfile wb]
  # Write 0xCAFEBABE 0x12345678 0xDEADBEEF 0xFEEDFACE (little-endian)
  puts -nonewline $fd [binary format iu4 {0xCAFEBABE 0x12345678 0xDEADBEEF 0xFEEDFACE}]
  close $fd
  
  dow -data $testfile 0x01000000
  
  set v0 [mrd -value 0x01000000]
  set v1 [mrd -value 0x01000004]
  set v2 [mrd -value 0x01000008]
  set v3 [mrd -value 0x0100000c]
  puts [format "  Expected: CAFEBABE 12345678 DEADBEEF FEEDFACE"]
  puts [format "  Got:      %08x %08x %08x %08x" $v0 $v1 $v2 $v3]
  set allok [expr {$v0 == 0xCAFEBABE && $v1 == 0x12345678 && $v2 == 0xDEADBEEF && $v3 == 0xFEEDFACE}]
  puts [format "  dow -data verify: %s" [expr {$allok ? "PASS" : "FAIL"}]]
}

step "Test 5: dow -data firmware 4 bytes -> 0x01100000 and verify" {
  # Load just first 4 bytes of fw_payload.bin to a test address
  if {$tcl_platform(platform) eq "windows"} {
    set fw_bin {\\wsl.localhost\Ubuntu-22.04\root\chipyard\software\firemarshal\boards\default\firmware\opensbi\build\platform\generic\firmware\fw_payload.bin}
  } else {
    set fw_bin /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.bin
  }
  
  dow -data $fw_bin 0x01100000
  
  set v0 [mrd -value 0x01100000]
  set v1 [mrd -value 0x01100004]
  set v2 [mrd -value 0x01300000]
  puts [format "  fw_payload at 0x01100000: 0x%08x (expect 0x0e976f05)" $v0]
  puts [format "  fw_payload at 0x01100004: 0x%08x" $v1]
  puts [format "  fw_payload at 0x01300000 (Linux entry): 0x%08x (expect 0x106f5a4d)" $v2]
}

step "disconnect" {
  disconnect
}
exit
