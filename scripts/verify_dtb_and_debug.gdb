# verify_dtb_and_debug.gdb — Verify DTB and set breakpoints for crash debugging
# Usage: riscv64-unknown-linux-gnu-gdb -x scripts/verify_dtb_and_debug.gdb

set pagination off
set confirm off

target extended-remote 172.19.128.1:2331

# Load symbols
file /root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux

echo \n=== Phase 1: Verify DTB in FPGA memory ===\n
# DTB was loaded at PA 0x84000000, size ~4201 bytes
dump binary memory /tmp/verify_dtb.bin 0x84000000 0x84001800

echo \n=== Phase 2: Verify key .rodata area ===\n
# Check the "bus\0" string at PA 0x80D02CA0
dump binary memory /tmp/verify_bus_string.bin 0x80D02CA0 0x80D02CB0

echo \n=== Phase 3: Check BSS region ===\n
# .bss at VA 0xffffffff80ec2000 → PA 0x810C2000
# Check if BSS was properly zeroed
dump binary memory /tmp/verify_bss_start.bin 0x810C2000 0x810C2100

echo \n=== Phase 4: Restart from OpenSBI with breakpoints ===\n
# Reset CPU to OpenSBI entry point
# Memory is still intact, just re-run from scratch
set $pc = 0x80000000
set $a0 = 0
# a1 will be set by OpenSBI to point to DTB

# KEY: Set hardware breakpoints at crash-related functions
# platform_bus_init = 0xffffffff8061f308 → PA 0x80821308(?)
# Actually we need VA breakpoints since PC will be at VA after MMU enable

# Break at platform_bus_init (called once, safe)
hbreak *0xffffffff8061f308
# Break at OpenSBI mret (to verify boot starts)
hbreak *0x8000b2b2

echo [ok] Breakpoints set, continuing from OpenSBI...\n
continue

# Should hit mret first
echo \n=== Hit mret, OpenSBI → Kernel transition ===\n
info registers a0 a1 mepc
# Delete mret breakpoint and continue to platform_bus_init
delete 2
continue

# Should hit platform_bus_init
echo \n=== Hit platform_bus_init ===\n
info registers pc ra sp
# Inspect the bus_kset and platform_bus that will be registered

# Step into bus_register and inspect the kset
echo [stepping] Into bus_register...\n
# Set breakpoint at kobject_get_path (where strlen is called with the name)
hbreak *0xffffffff80438270
continue

# Should hit kobject_get_path
echo \n=== Hit kobject_get_path ===\n
echo [args] a0 = kobj pointer:\n
info registers a0 a1
# Inspect the kobject
echo [kobj] Dumping kobject at a0:\n
# kobject.name is the first pointer field (offset 0 or 8 depending on layout)
# Let's just print the kobject memory
x/16xg $a0

# Continue to strlen
hbreak *0xffffffff80451c4c
continue
echo \n=== Hit strlen ===\n
echo [args] a0 = string pointer:\n
info registers a0
echo [string] Content at a0:\n
x/4s $a0

echo \n[done] Manual inspection complete\n
quit
