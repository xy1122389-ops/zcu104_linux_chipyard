# Test CPU write path vs SBA write path
# CPU writes go through L1→L2→DDR
# SBA writes bypass caches
set confirm off
set pagination off

python
import os
port = os.environ.get("JLINK_PORT", "12331")
gdb.execute(f"target remote localhost:{port}")
end

echo \n=== CPU vs SBA Write Path Test ===\n

# First, SBA write test (baseline - already proven to work)
echo \n--- SBA Write (via GDB set) ---\n
set *(unsigned long long*)0x80100000 = 0x4142434445464748
printf "SBA wrote 0x4142434445464748 to 0x80100000\n"
printf "SBA read: 0x%016llx\n", *(unsigned long long*)0x80100000

# Now test CPU write path
# Save all state
echo \n--- CPU Write Test (using hart to execute sd) ---\n

# Save original registers
set $save_pc = $pc
set $save_a0 = $a0
set $save_a1 = $a1
set $save_a2 = $a2
set $save_t0 = $t0

# Set up: write 0x5152535455565758 to 0x80100100 via CPU sd instruction
# a0 = address, a1 = value
set $a0 = 0x80100100
set $a1 = 0x5152535455565758

# Write sd instruction at a scratch location and execute it
# sd a1, 0(a0) = 0x00b53023
# We'll use the current PC area - save the instruction there first
set $save_insn = *(unsigned int*)$pc
set *(unsigned int*)$pc = 0x00b53023
# fence.i to sync icache
set $save_insn2 = *(unsigned int*)($pc+4)
set *(unsigned int*)($pc+4) = 0x0000100f

# Execute: sd a1, 0(a0)
stepi
# Execute: fence.i (for completeness)
stepi

# Restore original instructions
set *(unsigned int*)($save_pc) = $save_insn
set *(unsigned int*)($save_pc+4) = $save_insn2

# Now, fence to ensure store is visible
# fence = 0x0ff0000f
set *(unsigned int*)$pc = 0x0ff0000f
set $save_insn3 = *(unsigned int*)($pc+4)
set *(unsigned int*)($pc+4) = 0x0000100f
stepi
stepi

# Read via SBA to see what the CPU actually stored
printf "CPU wrote 0x5152535455565758 to 0x80100100\n"
printf "SBA readback: 0x%016llx\n", *(unsigned long long*)0x80100100

# Also test: CPU write at 0x80100200, multiple values
set $a0 = 0x80100200
set $a1 = 0x0807060504030201
set *(unsigned int*)$pc = 0x00b53023
stepi
set $a0 = 0x80100208
set $a1 = 0x100F0E0D0C0B0A09
set *(unsigned int*)$pc = 0x00b53023
stepi
# Fence
set *(unsigned int*)$pc = 0x0ff0000f
stepi

printf "CPU wrote 0x0807060504030201 to 0x80100200\n"
printf "SBA readback: 0x%016llx\n", *(unsigned long long*)0x80100200
printf "CPU wrote 0x100F0E0D0C0B0A09 to 0x80100208\n" 
printf "SBA readback: 0x%016llx\n", *(unsigned long long*)0x80100208

# Byte-level check
printf "Bytes at 0x80100200:\n"
printf "  [0]=0x%02x [1]=0x%02x [2]=0x%02x [3]=0x%02x\n", *(unsigned char*)0x80100200, *(unsigned char*)0x80100201, *(unsigned char*)0x80100202, *(unsigned char*)0x80100203
printf "  [4]=0x%02x [5]=0x%02x [6]=0x%02x [7]=0x%02x\n", *(unsigned char*)0x80100204, *(unsigned char*)0x80100205, *(unsigned char*)0x80100206, *(unsigned char*)0x80100207

# Restore registers
set $pc = $save_pc
set $a0 = $save_a0
set $a1 = $save_a1
set $a2 = $save_a2
set $t0 = $save_t0

echo \n=== Test Complete ===\n
disconnect
quit
