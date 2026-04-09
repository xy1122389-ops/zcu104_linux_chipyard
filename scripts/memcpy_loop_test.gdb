# Test memcpy loop running on hart to detect store buffer 2-byte duplication
set confirm off
set pagination off

python
import os, struct

port = os.environ.get("JLINK_PORT", "12331")
gdb.execute(f"target remote localhost:{port}")
inf = gdb.selected_inferior()

print("\n=== Memcpy Loop Test on Hart ===\n")

# Save CPU state
save_pc = int(gdb.parse_and_eval("$pc"))
save_regs = {}
for r in ['a0','a1','a2','a3','a4','a5','ra','t0','t1']:
    save_regs[r] = int(gdb.parse_and_eval(f"${r}"))

# Use 0x80300000 as code space, 0x80310000 as source, 0x80320000 as dest
CODE_ADDR = 0x80300000
SRC_ADDR  = 0x80310000
DST_ADDR  = 0x80320000

# Write source data: "0123456789ABCDEF" (16 bytes)
src_data = b"0123456789ABCDEF"
for i in range(0, 16, 8):
    val = int.from_bytes(src_data[i:i+8], 'little')
    gdb.execute(f"set *(unsigned long long*){SRC_ADDR + i} = {val}")

# Clear destination
for i in range(0, 32, 8):
    gdb.execute(f"set *(unsigned long long*){DST_ADDR + i} = 0")

# Assemble memcpy loop in machine code:
# a0 = dst, a1 = src, a2 = count
#
# loop:
#   lb a3, 0(a1)       # 0x0005c583   (load byte from src)
#   sb a3, 0(a0)       # 0x00d50023   (store byte to dst)
#   addi a0, a0, 1     # 0x00150513
#   addi a1, a1, 1     # 0x00158593
#   addi a2, a2, -1    # 0xfff60613
#   bnez a2, loop      # bne a2, zero, -16 = 0xfe061ae3
#   ebreak             # 0x00100073
#
code = [
    0x0005c583,  # lb a3, 0(a1)
    0x00d50023,  # sb a3, 0(a0)
    0x00150513,  # addi a0, a0, 1
    0x00158593,  # addi a1, a1, 1
    0xfff60613,  # addi a2, a2, -1
    0xfe061ae3,  # bne a2, x0, -12  (back to lb)  -- WAIT offset calc
]
# Actually, bne offset: target = lb at CODE_ADDR, current = CODE_ADDR+20
# offset = CODE_ADDR - (CODE_ADDR+20) = -20
# BNE encoding: imm[12|10:5] rs2 rs1 funct3 imm[4:1|11] opcode
# offset = -20 = 0xFFFFFFEC, bits: [12]=1, [11]=1, [10:5]=111110, [4:1]=1110  
# Hmm let me recalculate more carefully
# bne a2, x0, offset=-20
# imm[12|10:5] = 1_111110 = 0x7E with sign
# rs2 = x0 = 00000
# rs1 = a2 = x12 = 01100
# funct3 = 001
# imm[4:1|11] = 1110_1
# opcode = 1100011
# Full: 1 111111 00000 01100 001 1110 1 1100011
# = 0xFE061663 ... let me use an assembler

# Let me just brute-force assemble using known encodings
# 6 instructions, last one loops back to first (offset = -6*4 = -24? No, RVC...)
# Since these are all 32-bit, offset from bne to lb = -(5*4) = -20
# But wait we have 6 insns: lb, sb, addi, addi, addi, bne
# bne is at offset 5*4=20. Target is offset 0. So offset = 0 - 20 = -20.
# -20 in 13-bit signed: 
# -20 = 0x...FFFFFFEC
# imm bits: [12]=1, [11]=1, [10:5]=111110, [4:1]=0110, 
# Wait: -20 = -0x14
# Binary: 1_1111_1110_1100 (13 bits of -20)
# imm[12] = 1
# imm[11] = 1  
# imm[10:5] = 111011
# imm[4:1] = 0110
# Hmm, this is getting complex. Let me use a different approach.

# Actually I'll use a different loop structure with just 4 instructions:
# loop:
#   lb a3, 0(a1)       # 4 bytes
#   sb a3, 0(a0)       # 4 bytes  
#   addi a0, a0, 1     # 4 bytes  (can use c.addi but let's stay 32-bit)
#   addi a1, a1, 1     # 4 bytes
#   addi a2, a2, -1    # 4 bytes
#   bne a2, x0, -20    # 4 bytes, offset = -20 from this insn to lb

# bne a2, x0, -20:
# -20 decimal = -0x14
# In B-type format for RISC-V:
# offset bits [12:1] = -20 >> 1 ... hmm offset is in multiples of 2
# offset = -20, offset[12:1] = -20 bits
# offset = 1_1111_1110_1100 (binary of -20 as 13-bit signed)
# imm[12] = 1
# imm[11] = 1
# imm[10:5] = 111011
# imm[4:1] = 0110
#
# Encoding: imm[12] imm[10:5] rs2 rs1 funct3 imm[4:1] imm[11] opcode
# =         1       111011    00000 01100 001    0110     1      1100011
# Let me compute byte by byte:
# [6:0] = 1100011 = 0x63
# [11:7] = 0110_1 = 0x0D
# [14:12] = 001
# [19:15] = 01100 = 12 (a2)
# [24:20] = 00000 = 0 (x0)
# [31:25] = 1_111011 = 0xFB (but sign-extended)

# Let me just compute: imm = -20
# B-type: [31] imm[12], [30:25] imm[10:5], [24:20] rs2, [19:15] rs1, 
#         [14:12] funct3, [11:8] imm[4:1], [7] imm[11], [6:0] opcode
# 
# -20 = 0b 1_1_111011_0110_0  (13 bits including bit 0 which is always 0)
# imm[12] = 1
# imm[11] = 1  
# imm[10:5] = 111011
# imm[4:1] = 0110
#
# [31:25] = imm[12] imm[10:5] = 1_111011 = 0xFB → but as 7 bits = 1111011 = 0x7B? 
# Wait: [31] = imm[12] = 1
# [30:25] = imm[10:5] = 111011
# So [31:25] = 1_111011 = 0xFB (but only 7 bits) → binary 1111011
#
# [24:20] = rs2 = x0 = 00000
# [19:15] = rs1 = x12 = 01100
# [14:12] = funct3 = 001 (bne)
# [11:8] = imm[4:1] = 0110
# [7] = imm[11] = 1
# [6:0] = opcode = 1100011
#
# Full 32-bit: 1111011_00000_01100_001_0110_1_1100011
# = 1111 0110 0000 0110 0001 0110 1110 0011
# = 0xF6061663 ... hmm
# Actually let me be more careful:
# bit 31: 1
# bits 30-25: 111011
# bits 24-20: 00000
# bits 19-15: 01100
# bits 14-12: 001  
# bits 11-8: 0110
# bit 7: 1
# bits 6-0: 1100011
#
# 1_111011_00000_01100_001_0110_1_1100011
# Grouping into hex (left to right = MSB):
# 1111 0110 0000 0110 0001 0110 1100 0011
#  F    6    0    6    1    6    E    3
# Wait, let me recount:
# bit31 bit30-25 bit24-20 bit19-15 bit14-12 bit11-8 bit7 bit6-0
# 1     111011   00000    01100    001      0110    1    1100011
#
# Concatenating: 1_111011_00000_01100_001_0110_1_1100011
# = 1111 0110 0000 0110 0001 0110 1110 0011
# Wait: 1 111011 00000 01100 001 01101 1100011
# Let me count bits: 1 + 6 + 5 + 5 + 3 + 4 + 1 + 7 = 32 ✓
# 
# Binary: 1|111011|00000|01100|001|0110|1|1100011
# Group as 4-bit nibbles from MSB:
# 1111 0110 0000 0110 0001 0110 1110 0011
# Hmm: 111|1011|0000|0011|0000|1011|0111|00011
# Let me redo grouping from bit 31 to bit 0:
# Bit 31: 1
# Bits 30-28: 111
# Bits 27-24: 0110  → byte[31:24] = 1111 0110 = 0xF6 ... no wait
#
# I keep making mistakes. Let me just compute it programmatically.

import struct

def encode_bne(rs1, rs2, offset):
    """Encode BNE instruction. offset is in bytes, must be even."""
    assert offset % 2 == 0
    imm = offset
    # Sign-extend to 13 bits
    imm12 = (imm >> 12) & 1
    imm11 = (imm >> 11) & 1
    imm10_5 = (imm >> 5) & 0x3F
    imm4_1 = (imm >> 1) & 0xF
    
    opcode = 0x63  # BRANCH
    funct3 = 0x1   # BNE
    
    insn = (imm12 << 31) | (imm10_5 << 25) | (rs2 << 20) | (rs1 << 15) | \
           (funct3 << 12) | (imm4_1 << 8) | (imm11 << 7) | opcode
    return insn & 0xFFFFFFFF

bne_insn = encode_bne(12, 0, -20)  # bne a2(x12), x0, -20
print(f"bne a2, x0, -20 = 0x{bne_insn:08x}")

code = [
    0x0005c583,  # lb a3, 0(a1)
    0x00d50023,  # sb a3, 0(a0)
    0x00150513,  # addi a0, a0, 1
    0x00158593,  # addi a1, a1, 1
    0xfff60613,  # addi a2, a2, -1
    bne_insn,    # bne a2, x0, -20
    0x00100073,  # ebreak
]

# Write code to CODE_ADDR
for i, insn in enumerate(code):
    addr = CODE_ADDR + i * 4
    gdb.execute(f"set *(unsigned int*){addr} = {insn}")

# Verify source data
print(f"\nSource data at 0x{SRC_ADDR:08x}:")
src_read = bytes(inf.read_memory(SRC_ADDR, 16))
print(f"  {src_read}")

# Set up registers and run
gdb.execute(f"set $a0 = {DST_ADDR}")
gdb.execute(f"set $a1 = {SRC_ADDR}")
gdb.execute(f"set $a2 = 16")
gdb.execute(f"set $pc = {CODE_ADDR}")

# Set a hardware breakpoint at ebreak location
ebreak_addr = CODE_ADDR + len(code) * 4 - 4  # last instruction
print(f"Running memcpy loop (16 bytes)...")
print(f"  code={CODE_ADDR:#x}, ebreak at {ebreak_addr:#x}")

# Run with continue until ebreak
gdb.execute(f"hbreak *{ebreak_addr}")
gdb.execute("continue")

# Read destination via SBA
print(f"\nDestination data at 0x{DST_ADDR:08x} (SBA read):")
dst_data = bytes(inf.read_memory(DST_ADDR, 24))
hex_str = ' '.join(f'{b:02x}' for b in dst_data)
ascii_str = ''.join(chr(b) if 32<=b<127 else '.' for b in dst_data)
print(f"  Hex:   {hex_str}")
print(f"  ASCII: {ascii_str}")
print(f"  Expected: {' '.join(f'{b:02x}' for b in src_data)} 00 00 00 00 00 00 00 00")

# Check for duplication
if dst_data[:16] == src_data:
    print("\n  RESULT: PASS - memcpy loop produces correct data!")
else:
    print(f"\n  RESULT: FAIL!")
    for i in range(20):
        exp = src_data[i] if i < 16 else 0
        act = dst_data[i]
        marker = " <-- MISMATCH" if act != exp else ""
        print(f"    [{i:2d}] exp=0x{exp:02x}({chr(exp) if 32<=exp<127 else '.'}) act=0x{act:02x}({chr(act) if 32<=act<127 else '.'}){marker}")

# Now test with LONGER string (64 bytes) to match a cache line
print("\n--- Test 2: 64-byte memcpy loop ---")
SRC2 = SRC_ADDR + 0x100
DST2 = DST_ADDR + 0x100
src64 = b"The quick brown fox jumps over the lazy dog. 0123456789ABCDEFGH"[:64]
for i in range(0, 64, 8):
    val = int.from_bytes(src64[i:i+8], 'little')
    gdb.execute(f"set *(unsigned long long*){SRC2 + i} = {val}")
for i in range(0, 80, 8):
    gdb.execute(f"set *(unsigned long long*){DST2 + i} = 0")

gdb.execute(f"set $a0 = {DST2}")
gdb.execute(f"set $a1 = {SRC2}")
gdb.execute(f"set $a2 = 64")
gdb.execute(f"set $pc = {CODE_ADDR}")
gdb.execute("continue")

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

# Cleanup
gdb.execute("delete breakpoints")

# Restore
for r, v in save_regs.items():
    gdb.execute(f"set ${r} = {v}")
gdb.execute(f"set $pc = {save_pc}")

print("\n=== Test Complete ===")
gdb.execute("disconnect")
end

quit
