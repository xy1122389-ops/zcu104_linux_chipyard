# Check if FPGA is properly configured
connect -url tcp:127.0.0.1:3121

puts "=== Check FPGA Config Status ==="
# Select PL target
targets -set -nocase -filter {name =~ "*PL*"}
puts "PL target selected"

# Check FPGA config status
catch {
    # Read FPGA status 
    set device [lindex [jtag targets] 0]
    puts "JTAG device info: $device"
} err

# Try to read PL JTAG  
catch {
    jtag targets
} jt
puts "JTAG: $jt"

# Check status via PSU
targets -set -nocase -filter {name =~ "*PSU*"}

# Read PCAP STATUS register
set pcap_status [mrd -force 0xFFCA3008 1]
puts "PCAP_STATUS (0xFFCA3008): $pcap_status"

# Read PCAP CTRL
set pcap_ctrl [mrd -force 0xFFCA3008 1]
puts "PCAP_CTRL: $pcap_ctrl"

# Check if PL is DONE  
# CSU_PCAP_STATUS: bit 2 = PL_INIT, bit 1 = PL_DONE
set r [mrd -force 0xFFCA0010 1]
puts "CSU_MULTI_BOOT (0xFFCA0010): $r"

# CSU status
set r2 [mrd -force 0xFFCA0044 1]
puts "CSU_ISR (0xFFCA0044): $r2"

# FPGA PL done signal
set r3 [mrd -force 0xFFCA3000 1]
puts "PCAP_CTRL (0xFFCA3000): $r3"

puts "\n=== Try direct PL register access ==="
# Try writing to PL via LPD - write to BRAM at 0x60000000 range 
# First check if we can read DDR
catch {
    set ddr [mrd -force 0x80000000 4]
    puts "DDR read: $ddr"
} derr
if {$derr ne ""} { puts "DDR read error: $derr" }

puts "\n=== Full Target List ==="
targets

disconnect
exit
