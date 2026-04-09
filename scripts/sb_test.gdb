# Test sb (store byte) via CPU hart - detect 2-byte duplication in byte stores
set confirm off
set pagination off

python
import os, struct, time

port = os.environ.get("JLINK_PORT", "12331")
gdb.execute(f"target remote localhost:{port}")

print("\n=== Store Byte (sb) Test via CPU Hart ===\n")

# Save CPU state
inf = gdb.selected_inferior()
save_pc = int(gdb.parse_and_eval("$pc"))
save_a0 = int(gdb.parse_and_eval("$a0"))
save_a1 = int(gdb.parse_and_eval("$a1"))
save_ra = int(gdb.parse_and_eval("$ra"))

# dest = 0x80300000 (safe DDR area)
dest = 0x80300000

# First, zero 64 bytes at dest via SBA
for i in range(8):
    gdb.execute(f"set *(unsigned long long*){dest + i*8} = 0")

# Now write 16 bytes "ABCDEFGHIJKLMNOP" via CPU sb instructions
# sb a1, 0(a0) = 0x00b50023  (rs1=a0=x10, rs2=a1=x11, funct3=000=byte)
sb_insn = 0x00b50023  # sb a1, 0(a0)
fence_i = 0x0000100f  # fence.i

test_string = b"ABCDEFGHIJKLMNOP"
print(f"Writing {len(test_string)} bytes via CPU sb at 0x{dest:08x}")

for i, byte_val in enumerate(test_string):
    addr = dest + i
    # Set a0 = addr, a1 = byte value
    gdb.execute(f"set $a0 = {addr}")
    gdb.execute(f"set $a1 = {byte_val}")
    
    # Patch instruction: sb a1, 0(a0)
    gdb.execute(f"set $pc = {save_pc}")
    gdb.execute(f"set *(unsigned int*){save_pc} = {sb_insn}")
    gdb.execute(f"set *(unsigned int*){save_pc + 4} = {fence_i}")
    gdb.execute("stepi")  # execute sb
    gdb.execute("stepi")  # execute fence.i

# Fence to ensure all stores are visible
gdb.execute(f"set $pc = {save_pc}")
gdb.execute(f"set *(unsigned int*){save_pc} = 0x0ff0000f")  # fence
gdb.execute(f"set *(unsigned int*){save_pc + 4} = {fence_i}")
gdb.execute("stepi")
gdb.execute("stepi")

# Read back via SBA
print(f"\nSBA readback of 0x{dest:08x} (24 bytes):")
data = bytes(inf.read_memory(dest, 24))
hex_str = ' '.join(f'{b:02x}' for b in data)
ascii_str = ''.join(chr(b) if 32 <= b < 127 else '.' for b in data)
print(f"  Hex:   {hex_str}")
print(f"  ASCII: {ascii_str}")
print(f"  Expected: 41 42 43 44 45 46 47 48 49 4a 4b 4c 4d 4e 4f 50 00 00 00 00 00 00 00 00")
print(f"  Expected: ABCDEFGHIJKLMNOP........")

# Check for 2-byte duplication
if data[:16] == test_string:
    print("\n  RESULT: PASS - No 2-byte duplication in sb stores!")
else:
    print(f"\n  RESULT: FAIL - Data mismatch!")
    # Find where it diverges
    for i in range(min(24, len(test_string) + 4)):
        expected = test_string[i] if i < len(test_string) else 0
        actual = data[i]
        marker = " <-- MISMATCH" if actual != expected else ""
        print(f"    [{i:2d}] expected=0x{expected:02x} actual=0x{actual:02x}{marker}")

# Also test sd (store doubleword) with full 8-byte value
print("\n--- Test 2: CPU sd of 0x4142434445464748 ---")
dest2 = dest + 0x100
gdb.execute(f"set $a0 = {dest2}")
gdb.execute(f"set $a1 = 0x4142434445464748")
gdb.execute(f"set $pc = {save_pc}")
gdb.execute(f"set *(unsigned int*){save_pc} = 0x00b53023")  # sd a1, 0(a0)
gdb.execute(f"set *(unsigned int*){save_pc + 4} = {fence_i}")
gdb.execute("stepi")
gdb.execute("stepi")
gdb.execute(f"set *(unsigned int*){save_pc} = 0x0ff0000f")  # fence
gdb.execute(f"set *(unsigned int*){save_pc + 4} = {fence_i}")
gdb.execute("stepi")
gdb.execute("stepi")

data2 = bytes(inf.read_memory(dest2, 16))
hex2 = ' '.join(f'{b:02x}' for b in data2)
print(f"  SBA read: {hex2}")
print(f"  Expected: 48 47 46 45 44 43 42 41 00 00 00 00 00 00 00 00")

# Restore CPU state
gdb.execute(f"set $pc = {save_pc}")
gdb.execute(f"set $a0 = {save_a0}")
gdb.execute(f"set $a1 = {save_a1}")
gdb.execute(f"set $ra = {save_ra}")

print("\n=== Test Complete ===")
gdb.execute("disconnect")
end

quit
