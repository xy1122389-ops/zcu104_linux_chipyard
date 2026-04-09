set confirm off
set pagination off
python
import os, struct, time

port = os.environ.get("JLINK_PORT", "12331")
gdb.execute(f"target remote localhost:{port}")
inf = gdb.selected_inferior()

print("\n=== Memcpy Loop Test (stepi-based) ===\n")

# Save CPU state
save_pc = int(gdb.parse_and_eval("$pc"))
save_regs = {}
for r in ['a0','a1','a2','a3','a4','a5','t0','t1','t2']:
    save_regs[r] = int(gdb.parse_and_eval(f"${r}"))

SRC_ADDR  = 0x82000000   # well outside kernel text
DST_ADDR  = 0x82010000
CODE_ADDR = 0x82020000   # for verify only

# ===== Test 1: Byte-by-byte memcpy via stepi (16 bytes) =====
print("--- Test 1: byte-by-byte memcpy (16 bytes, stepi loop) ---")
src_data = b"0123456789ABCDEF"

# Write source via SBA
for i in range(0, 16, 8):
    val = int.from_bytes(src_data[i:i+8], 'little')
    gdb.execute(f"set *(unsigned long long*){SRC_ADDR + i} = {val}")

# Clear dest
for i in range(0, 32, 8):
    gdb.execute(f"set *(unsigned long long*){DST_ADDR + i} = 0")

# Set regs
gdb.execute(f"set $a0 = {DST_ADDR}")
gdb.execute(f"set $a1 = {SRC_ADDR}")

# Run memcpy byte by byte using stepi
# For each byte: lb a2, 0(a1); sb a2, 0(a0); addi a0,a0,1; addi a1,a1,1
for i in range(16):
    # lb a2, 0(a1) = 0x0005c603
    gdb.execute(f"set $pc = {save_pc}")
    gdb.execute(f"set *(unsigned int*){save_pc} = 0x0005c603")
    gdb.execute("stepi")
    
    # sb a2, 0(a0) = 0x00c50023
    gdb.execute(f"set *(unsigned int*){save_pc} = 0x00c50023")
    gdb.execute("stepi")
    
    # addi a0, a0, 1 = 0x00150513
    gdb.execute(f"set *(unsigned int*){save_pc} = 0x00150513")
    gdb.execute("stepi")
    
    # addi a1, a1, 1 = 0x00158593
    gdb.execute(f"set *(unsigned int*){save_pc} = 0x00158593")
    gdb.execute("stepi")

# Readback via SBA
dst = bytes(inf.read_memory(DST_ADDR, 24))
print(f"  Source:   {src_data}")
print(f"  Dest:     {dst[:16]}")
print(f"  Dest hex: {' '.join(f'{b:02x}' for b in dst[:24])}")
if dst[:16] == src_data and dst[16:24] == b'\x00'*8:
    print("  RESULT: PASS!")
else:
    print("  RESULT: FAIL!")
    for i in range(20):
        exp = src_data[i] if i < 16 else 0
        act = dst[i]
        if act != exp:
            print(f"    [{i:2d}] exp=0x{exp:02x} act=0x{act:02x}")

# ===== Test 2: Word (sd) memcpy via stepi (64 bytes) =====
print("\n--- Test 2: sd-based memcpy (64 bytes) ---")
SRC2 = SRC_ADDR + 0x100
DST2 = DST_ADDR + 0x100
src64 = b"The quick brown fox jumps over the lazy dog. ABCDEFGHIJKLMNOP!@#"
assert len(src64) == 64

for i in range(0, 64, 8):
    val = int.from_bytes(src64[i:i+8], 'little')
    gdb.execute(f"set *(unsigned long long*){SRC2 + i} = {val}")
for i in range(0, 80, 8):
    gdb.execute(f"set *(unsigned long long*){DST2 + i} = 0")

gdb.execute(f"set $a0 = {DST2}")
gdb.execute(f"set $a1 = {SRC2}")

for i in range(8):  # 8 doublewords
    # ld a2, 0(a1)  = 0x0005b603
    gdb.execute(f"set $pc = {save_pc}")
    gdb.execute(f"set *(unsigned int*){save_pc} = 0x0005b603")
    gdb.execute("stepi")
    
    # sd a2, 0(a0)  = 0x00c53023
    gdb.execute(f"set *(unsigned int*){save_pc} = 0x00c53023")
    gdb.execute("stepi")
    
    # addi a0, a0, 8 = 0x00850513
    gdb.execute(f"set *(unsigned int*){save_pc} = 0x00850513")
    gdb.execute("stepi")
    
    # addi a1, a1, 8 = 0x00858593
    gdb.execute(f"set *(unsigned int*){save_pc} = 0x00858593")
    gdb.execute("stepi")

dst64 = bytes(inf.read_memory(DST2, 72))
print(f"  Source: {src64}")
print(f"  Dest:   {dst64[:64]}")
if dst64[:64] == src64:
    print("  RESULT: PASS!")
else:
    print("  RESULT: FAIL!")
    for i in range(68):
        exp = src64[i] if i < 64 else 0
        act = dst64[i]
        if act != exp:
            print(f"    [{i:2d}] exp=0x{exp:02x}({chr(exp) if 32<=exp<127 else '.'}) act=0x{act:02x}({chr(act) if 32<=act<127 else '.'})")

# ===== Test 3: Simulate vsnprintf pattern =====
# printk's vsnprintf does byte-by-byte (%s copy). Let's test with the exact
# banner text that shows duplication
print("\n--- Test 3: banner text memcpy (175 bytes, sb-based) ---")
SRC3 = SRC_ADDR + 0x200
DST3 = DST_ADDR + 0x200

banner = b"Linux version 6.6.0-fpga-min-g67bc4513761f-dirty (root@YXY) (riscv64-unknown-linux-gnu-gcc (gc891d8dc23e) 13.2.0, GNU ld (GNU Binutils) 2.42) #26 Thu Apr  9 05:34:01 CST 2026\n"
blen = len(banner)
print(f"  Banner length: {blen} bytes")

# Write source
for i in range(0, blen, 8):
    chunk = banner[i:i+8].ljust(8, b'\x00')
    val = int.from_bytes(chunk, 'little')
    gdb.execute(f"set *(unsigned long long*){SRC3 + i} = {val}")

# Clear dest (rounded up)
for i in range(0, blen + 32, 8):
    gdb.execute(f"set *(unsigned long long*){DST3 + i} = 0")

# Do byte-by-byte copy
gdb.execute(f"set $a0 = {DST3}")
gdb.execute(f"set $a1 = {SRC3}")
print(f"  Copying {blen} bytes via lb/sb stepi loop...")

for i in range(blen):
    gdb.execute(f"set $pc = {save_pc}")
    gdb.execute(f"set *(unsigned int*){save_pc} = 0x0005c603")  # lb a2, 0(a1)
    gdb.execute("stepi")
    gdb.execute(f"set *(unsigned int*){save_pc} = 0x00c50023")  # sb a2, 0(a0)
    gdb.execute("stepi")
    gdb.execute(f"set *(unsigned int*){save_pc} = 0x00150513")  # addi a0,a0,1
    gdb.execute("stepi")
    gdb.execute(f"set *(unsigned int*){save_pc} = 0x00158593")  # addi a1,a1,1
    gdb.execute("stepi")
    if (i+1) % 50 == 0:
        print(f"    ... {i+1}/{blen} bytes")

# Readback
dst_banner = bytes(inf.read_memory(DST3, blen + 8))
print(f"  Last 20 bytes of dest: {' '.join(f'{b:02x}' for b in dst_banner[blen-10:blen+8])}")
last20_ascii = ''.join(chr(b) if 32<=b<127 else f'\\x{b:02x}' for b in dst_banner[blen-10:blen+8])
print(f"  ASCII: {last20_ascii}")

if dst_banner[:blen] == banner:
    print("  RESULT: PASS - no duplication!")
else:
    print("  RESULT: FAIL - data mismatch!")
    # Find first difference
    for i in range(blen + 4):
        exp = banner[i] if i < blen else 0
        act = dst_banner[i]
        if act != exp:
            ctx_start = max(0, i-5)
            ctx_exp = banner[ctx_start:min(len(banner), i+5)]
            ctx_act = dst_banner[ctx_start:i+5]
            print(f"    First diff at byte {i}: exp=0x{exp:02x}({chr(exp) if 32<=exp<127 else '.'}) act=0x{act:02x}({chr(act) if 32<=act<127 else '.'})")
            print(f"    Context exp: {ctx_exp}")
            print(f"    Context act: {ctx_act}")
            break

# Restore
for r, v in save_regs.items():
    gdb.execute(f"set ${r} = {v}")
gdb.execute(f"set $pc = {save_pc}")

print("\n=== All Tests Complete ===")
gdb.execute("disconnect")
end
quit
