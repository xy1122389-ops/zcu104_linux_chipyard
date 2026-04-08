# verify_memory.gdb — Read back FPGA memory regions and save for comparison
# Usage: riscv64-unknown-linux-gnu-gdb -x scripts/verify_memory.gdb

set pagination off
set confirm off

# Connect to J-Link
target extended-remote 172.19.128.1:2331

# The CPU should still be halted from the previous test
# Memory is still intact (no reset)

echo \n=== Memory Integrity Verification ===\n

# Payload starts at PA 0x80000000
# .rodata crash area: VA 0xffffffff80b02ca0 → PA 0x80D02CA0
# We'll dump several regions for comparison:

# Region 1: Around the crash address (256 bytes around 0x80D02CA0)
echo [1/5] Dumping crash area (PA 0x80D02C00, 512 bytes)...\n
dump binary memory /tmp/verify_crash_area.bin 0x80D02C00 0x80D02E00

# Region 2: Start of kernel .text (PA 0x80202000, 4KB)
echo [2/5] Dumping kernel .text start (PA 0x80202000, 4KB)...\n
dump binary memory /tmp/verify_text_start.bin 0x80202000 0x80203000

# Region 3: Start of .rodata (PA 0x80C00000, 4KB)
echo [3/5] Dumping .rodata start (PA 0x80C00000, 4KB)...\n
dump binary memory /tmp/verify_rodata_start.bin 0x80C00000 0x80C01000

# Region 4: OpenSBI area (PA 0x80000000, 4KB)
echo [4/5] Dumping OpenSBI start (PA 0x80000000, 4KB)...\n
dump binary memory /tmp/verify_opensbi_start.bin 0x80000000 0x80001000

# Region 5: A larger region covering the crash address (64KB around crash)
echo [5/5] Dumping 64KB around crash area (PA 0x80D00000)...\n
dump binary memory /tmp/verify_rodata_64k.bin 0x80D00000 0x80D10000

echo \n=== All regions dumped. Comparing... ===\n

quit
