# Test various memory regions to isolate the A2 route failure
set confirm off
set pagination off

target remote 172.19.128.1:2331
monitor halt
monitor reset

set $satp = 0

printf "=== Memory Region Access Test ===\n"

# Test DDR (should always work)
printf "DDR 0x80000000: "
set $ddr = *(unsigned int*)0x80000000
printf "0x%08x OK\n", $ddr

# Test boot ROM
printf "Boot ROM 0x10000: "
set $rom = *(unsigned int*)0x10000
printf "0x%08x OK\n", $rom

# Test on-chip SRAM if exists (CLINT/PLIC area)
printf "CLINT 0x02000000: "
set $clint = *(unsigned int*)0x02000000
printf "0x%08x OK\n", $clint

# Test ExtBus region 0x60000000 (A2 route)
printf "ExtBus 0x60000000: "
set $ext = *(unsigned int*)0x60000000
printf "0x%08x OK\n", $ext

disconnect
quit
