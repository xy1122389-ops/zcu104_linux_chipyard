# Check SDIO1 clock and reset status  
connect -url tcp:127.0.0.1:3121
targets -set -nocase -filter {name =~ "*PSU*"}

puts "=== SDIO1 Clock & Reset Diagnostic ==="

# CRL_APB registers
# SDIO1_REF_CTRL at 0xFF5E0070
set r1 [mrd -force 0xFF5E0070 1]
puts "SDIO1_REF_CTRL: $r1"

# RST_LPD_IOU2 at 0xFF5E0238 (SDIO resets)
set r2 [mrd -force 0xFF5E0238 1]
puts "RST_LPD_IOU2:   $r2"

# IOU_SLCR SDIO_CLK_CTRL at 0xFF180320
set r3 [mrd -force 0xFF180320 1]
puts "SDIO_CLK_CTRL:   $r3"

# Also check SDIO0 at 0xFF160000 to compare
puts ""
puts "=== Checking SDIO0 for comparison ==="
catch {
    set s0 [mrd -force 0xFF1600FC 1]
    puts "SDIO0_VER:       $s0"
} err
if {$err ne ""} {
    puts "SDIO0_VER: FAILED - $err"
}

# Check CRL_APB RST_LPD_IOU0 bit
set r4 [mrd -force 0xFF5E0230 1]
puts "RST_LPD_IOU0:   $r4"

# Check IOPLL (typical SDIO clock source)
set r5 [mrd -force 0xFF5E0020 1]
puts "IOPLL_CTRL:      $r5"

# Check all resets
set r6 [mrd -force 0xFF5E023C 1]
puts "RST_LPD_TOP:     $r6"

puts "=== Done ==="
disconnect
exit
