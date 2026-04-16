# Check PL clocks and reset state
connect -url tcp:127.0.0.1:3121
targets -set -nocase -filter {name =~ "*PSU*"}

puts "=== PL Fabric Clocks ==="
# FCLK0 control at CRL_APB
set r1 [mrd -force 0xFF5E0070 1]
puts "SDIO1_REF_CTRL (0xFF5E0070): $r1"

# PL clock 0: CRL_APB PL0_REF_CTRL at 0xFF5E00C0
set r2 [mrd -force 0xFF5E00C0 1]
puts "PL0_REF_CTRL (0xFF5E00C0): $r2"

# PL clock 1
set r3 [mrd -force 0xFF5E00C4 1]
puts "PL1_REF_CTRL (0xFF5E00C4): $r3"

# PL clock 2
set r4 [mrd -force 0xFF5E00C8 1]
puts "PL2_REF_CTRL (0xFF5E00C8): $r4"

# PL clock 3
set r5 [mrd -force 0xFF5E00CC 1]
puts "PL3_REF_CTRL (0xFF5E00CC): $r5"

puts "\n=== GPIO DATA_5 (0xFF0A0054) - fabric reset ==="
set r6 [mrd -force 0xFF0A0054 1]
puts "GPIO_DATA_5  (0xFF0A0054): $r6"

# Also read DATA_RO_5 (actual pin value)
set r7 [mrd -force 0xFF0A0074 1]
puts "GPIO_DATARO_5 (0xFF0A0074): $r7"

puts "\n=== PS-PL AXI GPIO & Level Shifter ==="
# LPD_SLCR for PS-PL interface
set r8 [mrd -force 0xFF41A000 4]
puts "LPD_SLCR_INTF: $r8"

# Check if fabric reset is de-asserted
# RST_LPD_TOP includes fabric resets
set r9 [mrd -force 0xFF5E023C 1]
puts "\nRST_LPD_TOP (0xFF5E023C): $r9"

# RST_FPD_TOP
set r10 [mrd -force 0xFD1A0100 1]
puts "RST_FPD_TOP (0xFD1A0100): $r10"

puts "\n=== PMU Power Status ==="
# Check PL power status
set r11 [mrd -force 0xFFD80104 1]
puts "GLOBAL_CNTRL (0xFFD80104): $r11"

set r12 [mrd -force 0xFFD80110 1]
puts "REQ_PWRUP_STATUS (0xFFD80110): $r12"

# PL power state
set r13 [mrd -force 0xFFD80200 1]
puts "PWR_STATE (0xFFD80200): $r13"

puts "\n=== Done ==="
disconnect
exit
