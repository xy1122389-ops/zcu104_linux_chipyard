set confirm off
set pagination off
python
import os, struct

port = os.environ.get("JLINK_PORT", "12331")
gdb.execute(f"target remote localhost:{port}")
inf = gdb.selected_inferior()

print("\n=== Memcpy Loop Test (continue mode, cold I-cache address) ===\n")

save_pc = int(gdb.parse_and_eval("$pc"))
print(f"Current PC: 0x{save_pc:08x}")

# Use address 0x82000000 - 32MB into DDR, never touched by CPU (payload is ~15MB)
CODE = 0x82000000
SRC  = 0x82008000
DST  = 0x82010000

def encode_btype(funct3, rs1, rs2, offset):
    """Encode B-type instruction (BEQ/BNE/BLT/BGE/BLTU/BGEU)"""
    imm = offset & 0x1FFF  # 13-bit signed
    if offset < 0:
        imm = offset & 0x1FFF
    bit12 = (offset >> 12) & 1
    bit11 = (offset >> 11) & 1
    bits10_5 = (offset >> 5) & 0x3F
    bits4_1 = (offset >> 1) & 0xF
    insn = (bit12 << 31) | (bits10_5 << 25) | (rs2 << 20) | (rs1 << 15) | \
           (funct3 << 12) | (bits4_1 << 8) | (bit11 << 7) | 0x63
    return insn & 0xFFFFFFFF

# Assemble memcpy loop:
# 0x00: lb  a3, 0(a1)    ; 0x0005c683
# 0x04: sb  a3, 0(a0)    ; 0x00d50023
# 0x08: addi a0, a0, 1   ; 0x00150513
# 0x0c: addi a1, a1, 1   ; 0x00158593
# 0x10: addi a2, a2, -1  ; 0xfff60613
# 0x14: bne  a2, x0, -20 ; offset = -20 (back to 0x00)
# 0x18: ebreak            ; 0x00100073

bne_insn = encode_btype(1, 12, 0, -20)  # bne a2(x12), x0, -20
print(f"BNE encoding: 0x{bne_insn:08x}")

code_insns = [
    0x0005c683,  # lb a3, 0(a1)
    0x00d50023,  # sb a3, 0(a0)
    0x00150513,  # addi a0, a0, 1
    0x00158593,  # addi a1, a1, 1
    0xfff60613,  # addi a2, a2, -1
    bne_insn,    # bne a2, x0, -20
    0x00100073,  # ebreak
]

# First, let's verify our bne encoding by checking offset
# bne is at address CODE+0x14, target is CODE+0x00, offset = -0x14 = -20
print(f"Code at 0x{CODE:08x}, ebreak at 0x{CODE + 0x18:08x}")

# Write code
for i, insn in enumerate(code_insns):
    gdb.execute(f"set *(unsigned int*){CODE + i*4} = {insn}")

# Verify code was written
print("Written code:")
for i, insn in enumerate(code_insns):
    readback = int(gdb.parse_and_eval(f"*(unsigned int*){CODE + i*4}")) & 0xFFFFFFFF
    match = "OK" if readback == insn else f"MISMATCH (read 0x{readback:08x})"
    print(f"  0x{CODE + i*4:08x}: 0x{insn:08x} {match}")

# Write source data
src_data = b"0123456789ABCDEF"
for i in range(0, 16, 8):
    val = int.from_bytes(src_data[i:i+8], 'little')
    gdb.execute(f"set *(unsigned long long*){SRC + i} = {val}")

# Clear dest
for i in range(0, 32, 8):
    gdb.execute(f"set *(unsigned long long*){DST + i} = 0")

# Set up hart regs
gdb.execute(f"set $a0 = {DST}")
gdb.execute(f"set $a1 = {SRC}")
gdb.execute(f"set $a2 = 16")
gdb.execute(f"set $pc = {CODE}")

# Set hw breakpoint at ebreak
ebreak_addr = CODE + 6*4  # 0x82000018
gdb.execute(f"delete breakpoints")
gdb.execute(f"hbreak *{ebreak_addr}")

print(f"\nRunning lb/sb memcpy loop (16 bytes, continue)...")
gdb.execute("continue")

# Check PC
new_pc = int(gdb.parse_and_eval("$pc"))
print(f"Stopped at PC: 0x{new_pc:08x}")

if new_pc == ebreak_addr:
    # Read result
    dst_read = bytes(inf.read_memory(DST, 24))
    hex_str = ' '.join(f'{b:02x}' for b in dst_read)
    ascii_str = ''.join(chr(b) if 32<=b<127 else '.' for b in dst_read[:16])
    print(f"  Dest hex:   {hex_str}")
    print(f"  Dest ASCII: {ascii_str}")
    print(f"  Expected:   {' '.join(f'{b:02x}' for b in src_data)} 00 00 00 00 00 00 00 00")
    
    if dst_read[:16] == src_data and dst_read[16:24] == b'\x00'*8:
        print("  RESULT: PASS (16 bytes) - no duplication!")
    else:
        print("  RESULT: FAIL!")
        for i in range(20):
            exp = src_data[i] if i < 16 else 0
            act = dst_read[i]
            if act != exp:
                print(f"    [{i:2d}] exp=0x{exp:02x} act=0x{act:02x}")
    
    # === Test 2: 64-byte memcpy ===
    print(f"\n--- Test 2: 64-byte lb/sb loop ---")
    SRC2 = SRC + 0x100
    DST2 = DST + 0x100
    src64 = bytes(range(64))  # 0x00 to 0x3F
    
    for i in range(0, 64, 8):
        val = int.from_bytes(src64[i:i+8], 'little')
        gdb.execute(f"set *(unsigned long long*){SRC2 + i} = {val}")
    for i in range(0, 80, 8):
        gdb.execute(f"set *(unsigned long long*){DST2 + i} = 0xDEADBEEFDEADBEEF")
    
    gdb.execute(f"set $a0 = {DST2}")
    gdb.execute(f"set $a1 = {SRC2}")
    gdb.execute(f"set $a2 = 64")
    gdb.execute(f"set $pc = {CODE}")
    gdb.execute("continue")
    
    new_pc2 = int(gdb.parse_and_eval("$pc"))
    if new_pc2 == ebreak_addr:
        dst64 = bytes(inf.read_memory(DST2, 72))
        if dst64[:64] == src64:
            print("  RESULT: PASS (64 bytes)")
        else:
            print("  RESULT: FAIL!")
            for i in range(68):
                exp = src64[i] if i < 64 else 0xEF  # DEADBEEF fill
                act = dst64[i]
                if act != exp:
                    print(f"    [{i:2d}] exp=0x{exp:02x} act=0x{act:02x}")
        
        # Show last 8 bytes of dst + 4 beyond
        print(f"  Last 12 bytes: {' '.join(f'{b:02x}' for b in dst64[56:72])}")
    else:
        print(f"  Did not stop at ebreak (PC=0x{new_pc2:08x})")

    # === Test 3: 175-byte banner-sized memcpy ===
    print(f"\n--- Test 3: 175-byte lb/sb loop (banner size) ---")
    SRC3 = SRC + 0x200
    DST3 = DST + 0x200
    # Generate test pattern
    src175 = bytes([i & 0xFF for i in range(175)])

    for i in range(0, 176, 8):
        chunk = src175[i:i+8]
        if len(chunk) < 8:
            chunk = chunk + b'\x00' * (8 - len(chunk))
        val = int.from_bytes(chunk, 'little')
        gdb.execute(f"set *(unsigned long long*){SRC3 + i} = {val}")
    for i in range(0, 192, 8):
        gdb.execute(f"set *(unsigned long long*){DST3 + i} = 0xDEADBEEFDEADBEEF")
    
    gdb.execute(f"set $a0 = {DST3}")
    gdb.execute(f"set $a1 = {SRC3}")
    gdb.execute(f"set $a2 = 175")
    gdb.execute(f"set $pc = {CODE}")
    gdb.execute("continue")
    
    new_pc3 = int(gdb.parse_and_eval("$pc"))
    if new_pc3 == ebreak_addr:
        dst175 = bytes(inf.read_memory(DST3, 184))
        if dst175[:175] == src175:
            print(f"  RESULT: PASS (175 bytes)")
            # Check bytes 175-183 (should be DEADBEEF fill)
            trail = dst175[175:183]
            trail_hex = ' '.join(f'{b:02x}' for b in trail)
            print(f"  Trailing bytes [175:183]: {trail_hex}")
            # Check if last 2 src bytes are duplicated at [175:177]
            if dst175[175:177] == src175[173:175]:
                print("  WARNING: last 2 bytes duplicated in trailing area!")
            else:
                print("  Trailing area clean (no duplication)")
        else:
            print("  RESULT: FAIL!")
            diffs = [(i, src175[i], dst175[i]) for i in range(175) if dst175[i] != src175[i]]
            for idx, exp, act in diffs[:10]:
                print(f"    [{idx:3d}] exp=0x{exp:02x} act=0x{act:02x}")
            if len(diffs) > 10:
                print(f"    ... {len(diffs)-10} more diffs")
            print(f"  Last 12 bytes (169-183): {' '.join(f'{b:02x}' for b in dst175[169:183])}")
    else:
        print(f"  Did not stop at ebreak (PC=0x{new_pc3:08x})")

else:
    print(f"Did not stop at ebreak! PC=0x{new_pc:08x}")
    # Check scause
    scause = int(gdb.parse_and_eval("$a5"))
    print(f"  Check if trap occurred...")

# Cleanup
gdb.execute("delete breakpoints")
gdb.execute(f"set $pc = {save_pc}")
gdb.execute("disconnect")

print("\n=== Done ===")
end
quit
