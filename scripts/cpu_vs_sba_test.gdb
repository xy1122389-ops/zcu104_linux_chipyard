# Test: read __log_buf via CPU (hart ld) vs SBA path
# If data matches, the corruption is in the stored data
# If data differs, SBA read path is corrupting
set confirm off
set pagination off

python
import os
port = os.environ.get("JLINK_PORT", "12331")
gdb.execute(f"target remote localhost:{port}")
end

echo \n=== CPU Read vs SBA Read Test ===\n

# __log_buf PA = 0x80ED0060 (from klog dump)
# Read first 64 bytes of the first printk record text via SBA
echo --- SBA read of __log_buf+8 (first record text) ---\n
printf "SBA[0x80ED0068]: 0x%016llx\n", *(unsigned long long*)0x80ED0068
printf "SBA[0x80ED0070]: 0x%016llx\n", *(unsigned long long*)0x80ED0070
printf "SBA[0x80ED0078]: 0x%016llx\n", *(unsigned long long*)0x80ED0078
printf "SBA[0x80ED0080]: 0x%016llx\n", *(unsigned long long*)0x80ED0080

# Now read same data via CPU hart
echo \n--- CPU read of same addresses (via hart ld) ---\n
# Save registers
set $save_pc = $pc
set $save_a0 = $a0
set $save_a1 = $a1

# Read 0x80ED0068 via CPU ld
set $a0 = 0x80ED0068
# Patch current instruction to: ld a1, 0(a0) = 0x00053583
set $save_insn0 = *(unsigned int*)$pc
set *(unsigned int*)$pc = 0x00053583
# fence.i
set $save_insn1 = *(unsigned int*)($pc+4)
set *(unsigned int*)($pc+4) = 0x0000100f
stepi
stepi
printf "CPU[0x80ED0068]: 0x%016llx\n", $a1

set $a0 = 0x80ED0070
set *(unsigned int*)$save_pc = 0x00053583
set *(unsigned int*)($save_pc+4) = 0x0000100f
set $pc = $save_pc
stepi
stepi
printf "CPU[0x80ED0070]: 0x%016llx\n", $a1

set $a0 = 0x80ED0078
set *(unsigned int*)$save_pc = 0x00053583
set *(unsigned int*)($save_pc+4) = 0x0000100f
set $pc = $save_pc
stepi
stepi
printf "CPU[0x80ED0078]: 0x%016llx\n", $a1

set $a0 = 0x80ED0080
set *(unsigned int*)$save_pc = 0x00053583
set *(unsigned int*)($save_pc+4) = 0x0000100f
set $pc = $save_pc
stepi
stepi
printf "CPU[0x80ED0080]: 0x%016llx\n", $a1

# Now test: CPU write then SBA read
echo \n--- CPU write test: sd then SBA readback ---\n
set $a0 = 0x80200000
set $a1 = 0x4847464544434241
# sd a1, 0(a0) = 0x00b53023
set *(unsigned int*)$save_pc = 0x00b53023
set *(unsigned int*)($save_pc+4) = 0x0000100f
set $pc = $save_pc
stepi
stepi

# fence to push store
set *(unsigned int*)$save_pc = 0x0ff0000f
set *(unsigned int*)($save_pc+4) = 0x0000100f
set $pc = $save_pc
stepi
stepi

printf "CPU wrote  0x4847464544434241 to 0x80200000\n"
printf "SBA read:  0x%016llx\n", *(unsigned long long*)0x80200000

# Test with different pattern
set $a0 = 0x80200008
set $a1 = 0x0102030405060708
set *(unsigned int*)$save_pc = 0x00b53023
set *(unsigned int*)($save_pc+4) = 0x0000100f
set $pc = $save_pc
stepi
stepi
set *(unsigned int*)$save_pc = 0x0ff0000f
set *(unsigned int*)($save_pc+4) = 0x0000100f
set $pc = $save_pc
stepi
stepi

printf "CPU wrote  0x0102030405060708 to 0x80200008\n"
printf "SBA read:  0x%016llx\n", *(unsigned long long*)0x80200008

# Byte-level readback
printf "\nByte-level at 0x80200008:\n"
printf "  [0]=0x%02x [1]=0x%02x [2]=0x%02x [3]=0x%02x\n", *(unsigned char*)0x80200008, *(unsigned char*)0x80200009, *(unsigned char*)0x8020000a, *(unsigned char*)0x8020000b
printf "  [4]=0x%02x [5]=0x%02x [6]=0x%02x [7]=0x%02x\n", *(unsigned char*)0x8020000c, *(unsigned char*)0x8020000d, *(unsigned char*)0x8020000e, *(unsigned char*)0x8020000f

# Restore
set $pc = $save_pc
set $a0 = $save_a0
set $a1 = $save_a1

echo \n=== Test Complete ===\n
disconnect
quit
