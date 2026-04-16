# Quick A2 route test: read SDIO1 via PL->PS path
set confirm off
set pagination off

# Connect to J-Link
target remote 172.19.128.1:2331
monitor halt
monitor reset

# Disable MMU (satp=0)
set $satp = 0

# Test A2 route: Rocket 0x6017xxxx -> PS 0xFF17xxxx via S_AXI_LPD
printf "=== A2 Route Test (PL->PS LPD) ===\n"

printf "Reading SDIO1 VERSION (0x601700FC)...\n"
set $ver = *(unsigned int*)0x601700FC
printf "SDIO1_VER = 0x%08x\n", $ver

printf "Reading SDIO1 CAPS_LO (0x60170040)...\n"
set $caps = *(unsigned int*)0x60170040
printf "SDIO1_CAPS = 0x%08x\n", $caps

printf "Reading SDIO1 BASE (0x60170000)...\n"
set $base = *(unsigned int*)0x60170000
printf "SDIO1_BASE = 0x%08x\n", $base

printf "Reading UART0 STATUS (0x60000004)...\n"  
set $uart = *(unsigned int*)0x60000004
printf "UART0_STATUS = 0x%08x\n", $uart

printf "\n=== All A2 reads completed ===\n"
disconnect
quit
