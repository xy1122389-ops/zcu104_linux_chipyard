# xsdb_diag_after_program.tcl — Post-FPGA-program diagnostic checks via XSDB
#
# Run AFTER run_ps_ddr_init.sh has completed.
# Verifies: PL configuration status, DDR access, AFIFM6 config.
#
# Usage:  xsdb.bat -eval "source {<path>/xsdb_diag_after_program.tcl}"

proc step {label body} {
  puts "\n==== $label ===="
  flush stdout
  if {[catch {uplevel 1 $body} err]} {
    puts "  FAIL: $err"
    flush stdout
    return 0
  }
  return 1
}

proc hex {val} {
  return [format "0x%08X" $val]
}

# Robust mrd parser: mrd returns "ADDR:   VALUE\n"
# e.g. "FFCA3010:   00010002" or "80100000:   DEADBEEF"
proc read32 {addr} {
  set raw [mrd -force $addr 1]
  set raw [string trim $raw]
  # Split on ":" and take the last part
  set parts [split $raw ":"]
  set valstr [string trim [lindex $parts end]]
  # mrd returns hex without 0x prefix. Parse as hex.
  return [scan $valstr "%x"]
}

set pass_count 0
set fail_count 0
set test_results {}

connect -url tcp:127.0.0.1:3121
after 2000

# ---- Select PSU target (with fallback) ----
if {[catch {targets -set -nocase -filter {name =~ "*PSU*"}}]} {
  puts "PSU not found, trying alternative targets..."
  if {[catch {targets -set -nocase -filter {name =~ "*Cortex*#0*"}}]} {
    if {[catch {targets -set -nocase -filter {name =~ "*PS TAP*"}}]} {
      puts "WARNING: No suitable PS target found."
      puts "Available targets:"
      targets
    }
  }
}
puts "Target selected:"
targets

# ---- Test 1: PCAP STATUS (PL configuration status) ----
step "Test 1: PCAP STATUS (PL done?)" {
  set pcap [read32 0xFFCA3010]
  puts "  PCAP_STATUS = [hex $pcap]"
  set pl_done [expr {($pcap >> 1) & 1}]
  set pl_init [expr {($pcap >> 2) & 1}]
  puts "  PL_DONE = $pl_done, PL_INIT = $pl_init"
  if {$pl_done} {
    puts "  PASS: PL is configured (bitstream loaded)"
    incr pass_count
    lappend test_results "PCAP_STATUS: PASS (PL_DONE=1)"
  } else {
    puts "  FAIL: PL_DONE is not set — bitstream NOT loaded!"
    incr fail_count
    lappend test_results "PCAP_STATUS: FAIL (PL_DONE=0, pcap=[hex $pcap])"
  }
}

# ---- Test 2: PL clock status ----
step "Test 2: PL clock config (PL_CLK0)" {
  set pl_clk0 [read32 0xFF5E00C0]
  puts "  PL0_REF_CTRL = [hex $pl_clk0]"
  set clkact [expr {($pl_clk0 >> 24) & 1}]
  set div0 [expr {$pl_clk0 & 0x3F}]
  set div1 [expr {($pl_clk0 >> 8) & 0x3F}]
  puts "  CLKACT = $clkact, DIV0 = $div0, DIV1 = $div1"
  if {$clkact} {
    puts "  PASS: PL clock 0 is active"
    incr pass_count
    lappend test_results "PL_CLK0: PASS (active, div0=$div0, div1=$div1)"
  } else {
    puts "  INFO: PL clock 0 not active (design uses board oscillator sys_clock)"
    lappend test_results "PL_CLK0: INFO (not active, design uses sys_clock 125MHz)"
  }
}

# ---- Test 3: DDR read/write test ----
# Note: From the PS side, DDR is at 0x00000000-0x7FFFFFFF.
# 0x80000000+ is PL address space (M_AXI_HPM0_FPD), NOT DDR!
# The Rocket core sees DDR at 0x80000000 in its own map, but that's
# the PL-internal view, not the PS view.
step "Test 3: DDR read/write (0x00100000 — PS-side DDR)" {
  set test_addr 0x00100000
  set test_val 0xDEADBEEF
  mwr -force $test_addr $test_val
  after 100
  set rb [read32 $test_addr]
  puts "  Write [hex $test_val] -> [hex $test_addr]"
  puts "  Read  [hex $rb]      <- [hex $test_addr]"
  if {$rb == $test_val} {
    puts "  PASS: DDR read/write OK"
    incr pass_count
    lappend test_results "DDR_RW: PASS"
  } else {
    puts "  FAIL: DDR read/write mismatch!"
    incr fail_count
    lappend test_results "DDR_RW: FAIL (wrote [hex $test_val], read [hex $rb])"
  }
  mwr -force $test_addr 0x00000000
}

# ---- Test 3b: PL fabric access test (through M_AXI_HPM0_FPD) ----
# 0x80000000 maps to PL. If PL clock is running and the Rocket
# core's TL interconnect responds, we get data back. Timeout = PL dead.
step "Test 3b: PL fabric probe (0x80000000)" {
  if {[catch {set plval [read32 0x80000000]} err]} {
    puts "  PL access TIMEOUT or ERROR: $err"
    puts "  This suggests PL fabric (Rocket core interconnect) is not responding."
    puts "  Possible cause: MMCM not locked, core clock not running."
    incr fail_count
    lappend test_results "PL_PROBE: FAIL (timeout — core clock may be dead)"
  } else {
    puts "  PL read 0x80000000 = [hex $plval]"
    puts "  PASS: PL fabric responds"
    incr pass_count
    lappend test_results "PL_PROBE: PASS (PL fabric accessible)"
  }
}

# ---- Test 4: AFIFM6 config (S_AXI_LPD fabric width) ----
step "Test 4: AFIFM6 S_AXI_LPD config" {
  set rdctrl [read32 0xFF9B0000]
  set wrctrl [read32 0xFF9B0014]
  puts "  AFIFM6_RDCTRL (0xFF9B0000) = [hex $rdctrl]"
  puts "  AFIFM6_WRCTRL (0xFF9B0014) = [hex $wrctrl]"
  set rd_width [expr {$rdctrl & 0x3}]
  set wr_width [expr {$wrctrl & 0x3}]
  puts "  RD fabric width = $rd_width (expect 2=128-bit)"
  puts "  WR fabric width = $wr_width (expect 2=128-bit)"
  if {$rd_width == 2 && $wr_width == 2} {
    puts "  PASS: AFIFM6 128-bit fabric width set"
    incr pass_count
    lappend test_results "AFIFM6: PASS (128-bit)"
  } else {
    puts "  FAIL: AFIFM6 fabric width NOT 128-bit!"
    incr fail_count
    lappend test_results "AFIFM6: FAIL (rd=$rd_width, wr=$wr_width)"
  }
}

# ---- Test 5: DDR controller status ----
step "Test 5: DDR controller status" {
  set ddrc_stat [read32 0xFD070004]
  puts "  DDRC_STAT = [hex $ddrc_stat]"
  set op_mode [expr {$ddrc_stat & 0x7}]
  puts "  Operating mode = $op_mode (1=normal)"
  if {$op_mode == 1} {
    puts "  PASS: DDR controller in normal mode"
    incr pass_count
    lappend test_results "DDRC: PASS (normal mode)"
  } else {
    puts "  FAIL: DDR controller NOT in normal mode (mode=$op_mode)"
    incr fail_count
    lappend test_results "DDRC: FAIL (mode=$op_mode)"
  }
}

# ---- Test 6: PS-PL reset status ----
step "Test 6: PS-PL reset status" {
  # GPIO EMIO - check reset output state
  # DATA_5 register at 0xFF0A0054 controls PL resets via EMIO
  set data5 [read32 0xFF0A0054]
  puts "  GPIO_DATA_5 (EMIO) = [hex $data5]"
  # Also read PS-PL isolation status
  catch {
    set iso [read32 0xFF41A110]
    puts "  REQ_PWRUP_STATUS = [hex $iso]"
  }
  lappend test_results "PL_RESET: GPIO_DATA5=[hex $data5]"
}

# ---- Test 7: JTAG targets list ----
step "Test 7: JTAG targets" {
  set tgt_list [targets]
  puts "$tgt_list"
  lappend test_results "JTAG_TARGETS: listed"
}

# ---- Summary ----
puts "\n============================================"
puts "  DIAGNOSTIC SUMMARY"
puts "============================================"
puts "  Passed: $pass_count"
puts "  Failed: $fail_count"
puts ""
foreach r $test_results {
  puts "  $r"
}
puts "============================================"

disconnect
exit
