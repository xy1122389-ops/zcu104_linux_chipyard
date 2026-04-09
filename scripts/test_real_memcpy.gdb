set confirm off
set pagination off
python
import os, struct

port = os.environ.get("JLINK_PORT", "12331")
gdb.execute(f"target remote localhost:{port}")
inf = gdb.selected_inferior()

print("\n=== Test kernel's actual memcpy + memset (correct PA) ===\n")

PA_MEMCPY = 0x804fd6bc  # memcpy entry (c.mv t6,a0)
PA_MEMSET = 0x804fd938  # memset entry (c.mv t0,a0)

# Verify memcpy entry
data = bytes(inf.read_memory(PA_MEMCPY, 8))
insn_bytes = ' '.join(f'{b:02x}' for b in data[:6])
print(f"memcpy at PA 0x{PA_MEMCPY:08x}: {insn_bytes}")
# Should be: aa 8f 93 36 06 08 (c.mv t6,a0 + sltiu a3,a2,128)
if data[:2] == bytes([0xaa, 0x8f]):
    print("  ✓ c.mv t6,a0 confirmed")
else:
    print("  ✗ MISMATCH!")

# Verify memset entry
data2 = bytes(inf.read_memory(PA_MEMSET, 8))
insn_bytes2 = ' '.join(f'{b:02x}' for b in data2[:6])
print(f"memset at PA 0x{PA_MEMSET:08x}: {insn_bytes2}")
if data2[:2] == bytes([0xaa, 0x82]):
    print("  ✓ c.mv t0,a0 confirmed")
else:
    print("  ✗ MISMATCH!")

# Setup test
SRC = 0x82008000
DST = 0x82010000
EBREAK_ADDR = 0x82030000

# Write ebreak at return address
gdb.execute(f"set *(unsigned int*){EBREAK_ADDR} = 0x00100073")

# Write banner source text
banner = b"Linux version 6.6.0-fpga-min-g67bc4513761f-dirty (root@YXY) (riscv64-unknown-linux-gnu-gcc (gc891d8dc23e) 13.2.0, GNU ld (GNU Binutils) 2.42) #26 Thu Apr  9 05:34:01 CST 2026\n"
print(f"\nSource text: {len(banner)} bytes")

for i in range(0, len(banner) + 8, 8):
    chunk = banner[i:i+8] if i < len(banner) else b'\x00' * 8
    if len(chunk) < 8:
        chunk = chunk + b'\x00' * (8 - len(chunk))
    val = int.from_bytes(chunk, 'little')
    gdb.execute(f"set *(unsigned long long*){SRC + i} = {val}")

# Fill dest with 0xDE sentinel
for i in range(0, 256, 8):
    gdb.execute(f"set *(unsigned long long*){DST + i} = 0xDEDEDEDEDEDEDEDE")

# Save sp - we need a valid stack for function calls (sb uses no stack, but just in case)
save_sp = int(gdb.parse_and_eval("$sp"))
# Use our own stack
gdb.execute(f"set $sp = 0x82040000")

# ===== Test 1: memcpy(dst, src, 174) =====
print(f"\n--- Test 1: memcpy(dst, src, 174) ---")
gdb.execute(f"set $a0 = {DST}")
gdb.execute(f"set $a1 = {SRC}")
gdb.execute(f"set $a2 = 174")
gdb.execute(f"set $pc = {PA_MEMCPY}")
gdb.execute(f"set $ra = {EBREAK_ADDR}")
gdb.execute("delete breakpoints")
gdb.execute(f"hbreak *{EBREAK_ADDR}")

gdb.execute("continue")
pc = int(gdb.parse_and_eval("$pc"))
if pc != EBREAK_ADDR:
    print(f"  ERROR: PC=0x{pc:08x}, expected 0x{EBREAK_ADDR:08x}")
    gdb.execute("disconnect")
    import sys; sys.exit(1)

print("  memcpy returned OK")

# Read result
dst_data = bytes(inf.read_memory(DST, 192))
print(f"  Dest[168:184]: {' '.join(f'{b:02x}' for b in dst_data[168:184])}")
ascii_tail = ''.join(chr(b) if 32<=b<127 else f'\\x{b:02x}' for b in dst_data[168:184])
print(f"  ASCII:          {ascii_tail}")

# Check correctness
correct_174 = banner[:174]
actual_174 = dst_data[:174]
if actual_174 == correct_174:
    print("  174 bytes: CORRECT")
else:
    diffs = [(i, correct_174[i], actual_174[i]) for i in range(174) if actual_174[i] != correct_174[i]]
    print(f"  174 bytes: {len(diffs)} diffs!")

# Check bytes beyond 174
print(f"  Byte 174: 0x{dst_data[174]:02x} (expect 0xDE sentinel)")
print(f"  Byte 175: 0x{dst_data[175]:02x} (expect 0xDE sentinel)")
if dst_data[174:176] == b'\xde\xde':
    print("  Beyond 174: clean (sentinel preserved)")
elif dst_data[174:176] == banner[172:174]:
    print(f"  Beyond 174: DUPLICATED! ('{banner[172:174].decode()}' = last 2 chars)")
else:
    print(f"  Beyond 174: unexpected ({dst_data[174:176]!r})")

# ===== Test 2: memset(dst+174, 0, 10) =====
print(f"\n--- Test 2: memset(dst+174, 0, 10) ---")
gdb.execute(f"set $a0 = {DST + 174}")
gdb.execute(f"set $a1 = 0")
gdb.execute(f"set $a2 = 10")
gdb.execute(f"set $pc = {PA_MEMSET}")
gdb.execute(f"set $ra = {EBREAK_ADDR}")
gdb.execute("continue")

pc2 = int(gdb.parse_and_eval("$pc"))
if pc2 != EBREAK_ADDR:
    print(f"  ERROR: PC=0x{pc2:08x}")
else:
    print("  memset returned OK")
    dst_data2 = bytes(inf.read_memory(DST, 192))
    print(f"  Dest[168:184]: {' '.join(f'{b:02x}' for b in dst_data2[168:184])}")
    print(f"  Byte 174: 0x{dst_data2[174]:02x} (expect 0x00)")
    print(f"  Byte 175: 0x{dst_data2[175]:02x} (expect 0x00)")

# ===== Test 3: Combined memcpy_and_pad pattern =====
# Re-fill dest with 0xDE
print(f"\n--- Test 3: memcpy(174) + memset pad (simulating memcpy_and_pad) ---")
for i in range(0, 256, 8):
    gdb.execute(f"set *(unsigned long long*){DST + i} = 0xDEDEDEDEDEDEDEDE")

# Call memcpy(dst, src, 174)
gdb.execute(f"set $a0 = {DST}")
gdb.execute(f"set $a1 = {SRC}")
gdb.execute(f"set $a2 = 174")
gdb.execute(f"set $pc = {PA_MEMCPY}")
gdb.execute(f"set $ra = {EBREAK_ADDR}")
gdb.execute("continue")
assert int(gdb.parse_and_eval("$pc")) == EBREAK_ADDR

# Call memset(dst+174, 0, 10) 
gdb.execute(f"set $a0 = {DST + 174}")
gdb.execute(f"set $a1 = 0")
gdb.execute(f"set $a2 = 10")
gdb.execute(f"set $pc = {PA_MEMSET}")
gdb.execute(f"set $ra = {EBREAK_ADDR}")
gdb.execute("continue")
assert int(gdb.parse_and_eval("$pc")) == EBREAK_ADDR

# Check result
dst_final = bytes(inf.read_memory(DST, 192))
print(f"  Dest[168:184]: {' '.join(f'{b:02x}' for b in dst_final[168:184])}")
ascii_final = ''.join(chr(b) if 32<=b<127 else f'\\x{b:02x}' for b in dst_final[168:184])
print(f"  ASCII: {ascii_final}")

if dst_final[:174] == banner[:174]:
    print("  First 174 bytes: CORRECT")
else:
    print("  First 174 bytes: WRONG!")

if dst_final[174:184] == b'\x00' * 10:
    print("  Bytes 174-183: all zero (CORRECT - no duplication)")
elif dst_final[174:176] == banner[172:174]:
    print(f"  Bytes 174-175: DUPLICATED! '{banner[172:174].decode()}'")
else:
    print(f"  Bytes 174-183: {' '.join(f'{b:02x}' for b in dst_final[174:184])}")

# Restore
gdb.execute(f"set $sp = {save_sp}")
gdb.execute("delete breakpoints")
gdb.execute("disconnect")

print("\n=== Done ===")
end
quit
