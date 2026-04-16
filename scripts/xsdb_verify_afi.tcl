# Verify AFI FM6 and PS-PL state after initialization
connect -url tcp:127.0.0.1:3121
targets -set -nocase -filter {name =~ "*PSU*"}

puts "=== AFI FM6 Registers (S_AXI_LPD) ==="

# AFIFM6 RDCTRL at 0xFF9B0000
set r1 [mrd -force 0xFF9B0000 1]
puts "AFIFM6_RDCTRL (0xFF9B0000): $r1"

# AFIFM6 WRCTRL at 0xFF9B0014
set r2 [mrd -force 0xFF9B0014 1]
puts "AFIFM6_WRCTRL (0xFF9B0014): $r2"

# RST_LPD_TOP at 0xFF5E023C - bit 19 for AFI FM6 reset
set r3 [mrd -force 0xFF5E023C 1]
puts "RST_LPD_TOP (0xFF5E023C): $r3"

puts "\n=== PS-PL Isolation ==="
# LPD isolation: 0xFFD80118
set r4 [mrd -force 0xFFD80118 1]
puts "REQ_PWRUP_INT_EN (0xFFD80118): $r4"

# PS-PL isolation control: PMU_GLOBAL requests
# PMU_GLOBAL_REQ_PWRUP_STATUS at 0xFFD80110
set r5 [mrd -force 0xFFD80110 1]
puts "REQ_PWRUP_STATUS (0xFFD80110): $r5"

# LPD_SLCR SLCR_INTF control
# 0xFF41A000 - PS-PL interface isolation
set r6 [mrd -force 0xFF41A000 1]
puts "LPD_SLCR_INTF (0xFF41A000): $r6"

# More isolation registers
# 0xFF41A040 - LPD power island isolation
set r7 [mrd -force 0xFF41A040 1]
puts "AFC_LPD_ISO (0xFF41A040): $r7"

puts "\n=== S_AXI_LPD Port Config ==="
# Check if S_AXI_LPD is actually connected
# LPD_SLCR: 0xFF410000 region
set r8 [mrd -force 0xFF410000 8]
puts "LPD_SLCR base: $r8"

puts "\n=== GPIO Reset State (PS-PL fabric resets) ==="
# GPIO Bank 5 DATA - used for fabric reset
set r9 [mrd -force 0xFF0A0048 1]
puts "GPIO_DATA_5 (0xFF0A0048): $r9"

# GPIO Bank 5 Direction
set r10 [mrd -force 0xFF0A0344 1]
puts "GPIO_DIRM_5 (0xFF0A0344): $r10"

# GPIO Bank 5 Output Enable  
set r11 [mrd -force 0xFF0A0348 1]
puts "GPIO_OEN_5 (0xFF0A0348): $r11"

puts "\n=== Test direct PS SDIO1 access (sanity) ==="
set r12 [mrd -force 0xFF1700FC 1]
puts "SDIO1_VER (direct): $r12"

puts "\n=== Done ==="
disconnect
exit
