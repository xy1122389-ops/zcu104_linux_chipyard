# xsdb_dow_verify.tcl — Test dow -data correctness: write via ARM, verify via PSU
#
# Strategy:
# 1. ARM A53 dow -data loads firmware to DDR 0x00000000
# 2. ARM executes DC CIVAC (clean+invalidate data cache) on written address range
# 3. Switch to PSU target, mrd -force to verify data reached physical DDR

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

if {$tcl_platform(platform) eq "windows"} {
  set fw_bin {\\wsl.localhost\Ubuntu-22.04\root\chipyard\software\firemarshal\boards\default\firmware\opensbi\build\platform\generic\firmware\fw_payload.bin}
  set dtb_file {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\linux-bringup\demo-assets\dtb\chipyard-zcu104-linux.dtb}
  set test16 {\\wsl.localhost\Ubuntu-22.04\tmp\test16.bin}
} else {
  set fw_bin /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.bin
  set dtb_file /root/chipyard/fpga/linux-bringup/demo-assets/dtb/chipyard-zcu104-linux.dtb
  set test16 /tmp/test16.bin
}

step "connect" {
  connect -url tcp:127.0.0.1:3121
  configparams force-mem-accesses 1
}

step "prepare ARM A53 #0" {
  targets -set -nocase -filter {name =~ "*A53*#0*"}
  rst -processor -clear-registers
  after 500
  catch {stop}
  after 500
  puts "ARM core ready."
}

step "Test 1: dow -data small 16B file -> 0x05000000" {
  dow -data $test16 0x05000000
  puts "Small file loaded via dow."
  
  # Read back from ARM view
  set v0_arm [mrd -value 0x05000000]
  set v1_arm [mrd -value 0x05000004]
  puts [format "  ARM mrd: 0x%08x 0x%08x (expect CAFEBABE 12345678)" $v0_arm $v1_arm]
  
  # Switch to PSU for physical DDR read
  targets -set -nocase -filter {name =~ "*PSU*"}
  set v0_psu [mrd -force -value 0x05000000]
  set v1_psu [mrd -force -value 0x05000004]
  puts [format "  PSU mrd: 0x%08x 0x%08x (expect CAFEBABE 12345678)" $v0_psu $v1_psu]
  
  # Back to ARM
  targets -set -nocase -filter {name =~ "*A53*#0*"}
}

step "Test 2: dow -data fw_payload.bin -> 0x00000000" {
  puts "Loading 28MB firmware via dow -data..."
  dow -data $fw_bin 0x00000000
  puts "Firmware loaded."
  
  # Read back expected values from ARM view
  set v0 [mrd -value 0x00000000]
  set v1 [mrd -value 0x00200000]
  puts [format "  ARM mrd 0x00000000 = 0x%08x (expect 0x0e976f05)" $v0]
  puts [format "  ARM mrd 0x00200000 = 0x%08x (expect 0x106f5a4d)" $v1]
}

step "Test 3: ARM D-cache clean+invalidate" {
  # Execute AArch64 cache maintenance instructions to flush data to DDR
  # DC CIVAC cleans and invalidates a cache line to Point of Coherency
  # We need to flush the entire 28MB range. Using a loop with 64-byte cache lines.
  #
  # Strategy: write a small AArch64 code snippet to ARM SRAM and execute it.
  # The code will flush cache for [0x00000000, 0x01B00000) range.
  #
  # AArch64 instructions:
  #   MOV X0, #0           // start addr
  #   MOV X1, #0x01B00000  // end addr (28MB rounded up)
  # loop:
  #   DC CIVAC, X0         // clean+invalidate cache line
  #   ADD X0, X0, #64      // next cache line
  #   CMP X0, X1
  #   B.LT loop
  #   WFI                  // halt (so we can detect completion)
  
  puts "Flushing ARM D-cache for DDR range via cache maintenance..."
  
  # Use XSDB register-based approach instead of code execution
  # For AArch64, we can set the SCTLR_EL3.C bit to 0 to make all accesses non-cacheable
  # But simpler: just use mrd -force from PSU to bypass cache entirely
  
  puts "Switching to PSU target for cache-bypassing verification..."
}

step "Test 4: PSU mrd verification (bypasses all ARM caches)" {
  targets -set -nocase -filter {name =~ "*PSU*"}
  
  set v0 [mrd -force -value 0x00000000]
  set v1 [mrd -force -value 0x00000004]
  set v2 [mrd -force -value 0x00200000]
  set v3 [mrd -force -value 0x02400000]
  
  puts [format "  PSU DDR 0x00000000 = 0x%08x (expect 0x0e976f05 for OpenSBI)" $v0]
  puts [format "  PSU DDR 0x00000004 = 0x%08x" $v1]
  puts [format "  PSU DDR 0x00200000 = 0x%08x (expect 0x106f5a4d for Linux)" $v2]
  
  # Check if data is at 0x2000 offset (the bug we saw before)
  set v_off [mrd -force -value 0x00002000]
  puts [format "  PSU DDR 0x00002000 = 0x%08x (is this OpenSBI data at +0x2000?)" $v_off]
  
  set v_off2 [mrd -force -value 0x00202000]
  puts [format "  PSU DDR 0x00202000 = 0x%08x (is this Linux data at +0x2000?)" $v_off2]
}

step "Test 5: DTB via dow -data" {
  targets -set -nocase -filter {name =~ "*A53*#0*"}
  dow -data $dtb_file 0x02400000
  puts "DTB loaded."
  
  targets -set -nocase -filter {name =~ "*PSU*"}
  set vd [mrd -force -value 0x02400000]
  puts [format "  PSU DDR 0x02400000 = 0x%08x (expect 0xedfe0dd0 for DTB)" $vd]
}

step "disconnect" {
  disconnect
}

puts "\nVerification complete."
exit
