# All-in-one: POR → psu_init → bitstream → test
# Run everything in a single XSDB session

connect -url tcp:127.0.0.1:3121

puts "=== Step 1: POR Reset ==="
targets -set -nocase -filter {name =~ "PS TAP"}
rst -por
after 5000

puts "=== Step 2: Check targets ==="
targets

puts "=== Step 3: Select PSU ==="
targets -set -nocase -filter {name =~ "*PSU*"}

puts "=== Step 4: Source psu_init.tcl ==="
set psu_init_path {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig\obj\ip\zcu104ps\psu_init.tcl}
source $psu_init_path

puts "=== Step 5: Run psu_init ==="
psu_init

puts "=== Step 6: Test DDR (pre-bitstream) ==="
catch {
    set ddr_pre [mrd -force 0x80000000 2]
    puts "DDR pre-bitstream: $ddr_pre"
} err
if {$err ne ""} { puts "DDR pre-bitstream FAIL: $err" }

puts "=== Step 7: Program bitstream ==="
set bit_file {\\wsl.localhost\Ubuntu-22.04\root\chipyard\fpga\generated-src\chipyard.fpga.zcu104.ZCU104FPGATestHarness.RocketZCU104LinuxBringupConfig\obj\ZCU104FPGATestHarness.bit}
targets -set -nocase -filter {name =~ "*PL*"}
fpga $bit_file
after 3000

puts "=== Step 8: Select PSU again ==="
targets -set -nocase -filter {name =~ "*PSU*"}

puts "=== Step 9: Remove PS-PL isolation ==="
psu_ps_pl_isolation_removal
after 2000

puts "=== Step 10: PS-PL reset config ==="
psu_ps_pl_reset_config

puts "=== Step 11: Test DDR (post-bitstream) ==="
catch {
    set ddr_post [mrd -force 0x80000000 2]
    puts "DDR post-bitstream: $ddr_post"
} err2
if {$err2 ne ""} { puts "DDR post-bitstream FAIL: $err2" }

puts "=== Step 12: Test AFIFM6 ==="
catch {
    set r1 [mrd -force 0xFF9B0000 1]
    puts "AFIFM6_RDCTRL: $r1"
    set r2 [mrd -force 0xFF9B0014 1]
    puts "AFIFM6_WRCTRL: $r2"
} err3
if {$err3 ne ""} { puts "AFIFM6 FAIL: $err3" }

puts "=== Step 13: Test SDIO1 ==="
catch {
    set ver [mrd -force 0xFF1700FC 1]
    puts "SDIO1_VER: $ver"
    set caps [mrd -force 0xFF170040 1]
    puts "SDIO1_CAPS: $caps"
} err4
if {$err4 ne ""} { puts "SDIO1 FAIL: $err4" }

puts "\n=== ALL DONE ==="
disconnect
exit
