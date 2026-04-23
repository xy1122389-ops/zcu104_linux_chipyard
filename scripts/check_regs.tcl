connect -url tcp:127.0.0.1:3121

set psu_found 0
if {![catch {targets -set -nocase -filter {name =~ "*PSU*"}}]} {
    set psu_found 1
}

if {!$psu_found} {
    puts "PSU target not found"
    targets
    disconnect
    exit 1
}

proc read32 {addr name} {
    set v [mrd -force $addr 1]
    puts [format "%-16s %s" $name $v]
}

puts "=== PS SDIO1 / LPD Register Check ==="
read32 0xFF5E0238 "RST_LPD_IOU2"
read32 0xFF5E0070 "SDIO1_REF_CTRL"
read32 0xFF9B0000 "AFIFM6_RDCTRL"
read32 0xFF9B0014 "AFIFM6_WRCTRL"
read32 0xFF1700FC "HOST_VERSION"
read32 0xFF170040 "CAPABILITIES"
read32 0xFF170024 "PRESENT_STATE"
disconnect
exit
