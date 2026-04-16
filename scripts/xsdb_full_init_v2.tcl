# Complete sequence: POR → psu_init → bitstream → test DDR → test SDIO
# All in ONE XSDB session. Add error handling to continue on failures.

connect -url tcp:127.0.0.1:3121

# ───────────────────────────────────────
# Phase 1: POR
# ───────────────────────────────────────
puts "\n══════ Phase 1: POR ══════"
targets -set -nocase -filter {name =~ "PS TAP"}
rst -por
after 5000
puts "POR done"
targets

# ───────────────────────────────────────
# Phase 2: Test pre-init PS register access
# ───────────────────────────────────────
puts "\n══════ Phase 2: Pre-init test ══════"
targets -set -nocase -filter {name =~ "*PSU*"}
puts "PSU target ok"

# Simple CRL_APB register
set p [mrd -force 0xFF5E0020 1]
puts "IOPLL_CTRL (pre-init): $p"

# ───────────────────────────────────────
# Phase 3: psu_init
# ───────────────────────────────────────
puts "\n══════ Phase 3: psu_init ══════"
set psu_file {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig\obj\ip\zcu104ps\psu_init.tcl}  
source $psu_file
psu_init
puts "psu_init done"

# Test after psu_init
set p2 [mrd -force 0xFF5E0020 1]
puts "IOPLL_CTRL (post-init): $p2"

# ───────────────────────────────────────
# Phase 4: Test DDR (before bitstream)
# ───────────────────────────────────────
puts "\n══════ Phase 4: Test DDR ══════"
catch {
    # Write a pattern to DDR
    mwr -force 0x80000000 0xDEADBEEF
    set d [mrd -force 0x80000000 1]
    puts "DDR write/read: $d"
} derr
if {[info exists derr] && $derr ne ""} {
    puts "DDR FAIL: $derr"
    puts "*** DDR NOT WORKING - psu_init may have wrong DDR config ***"
} else {
    puts "DDR OK!"
}

# ───────────────────────────────────────
# Phase 5: Program bitstream
# ───────────────────────────────────────
puts "\n══════ Phase 5: Program bitstream ══════"
targets -set -nocase -filter {name =~ "*PL*"}
set bit_file {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig\obj\ZCU104FPGATestHarness.bit}
fpga $bit_file
after 3000
puts "Bitstream programmed"

# ───────────────────────────────────────
# Phase 6: PS-PL isolation removal + reset
# ───────────────────────────────────────
puts "\n══════ Phase 6: PS-PL isolation + reset ══════"
targets -set -nocase -filter {name =~ "*PSU*"}
psu_ps_pl_isolation_removal
after 2000
psu_ps_pl_reset_config
puts "Isolation removed, reset toggled"

# ───────────────────────────────────────
# Phase 7: Post-bitstream tests
# ───────────────────────────────────────
puts "\n══════ Phase 7: Post-bitstream tests ══════"

# DDR
catch {
    set d2 [mrd -force 0x80000000 1]
    puts "DDR (post-bit): $d2"
} derr2
if {[info exists derr2] && $derr2 ne ""} { puts "DDR post-bit FAIL: $derr2" }

# AFI FM6
catch {
    set a1 [mrd -force 0xFF9B0000 1]
    set a2 [mrd -force 0xFF9B0014 1]
    puts "AFIFM6_RDCTRL: $a1"
    puts "AFIFM6_WRCTRL: $a2"
} aerr
if {[info exists aerr] && $aerr ne ""} { puts "AFIFM6 FAIL: $aerr" }

# SDIO1
catch {
    set ver [mrd -force 0xFF1700FC 1]
    set caps [mrd -force 0xFF170040 1]
    puts "SDIO1_VER: $ver"
    puts "SDIO1_CAPS: $caps"
} serr
if {[info exists serr] && $serr ne ""} { puts "SDIO1 FAIL: $serr" }

puts "\n══════ ALL DONE ══════"
disconnect
exit
