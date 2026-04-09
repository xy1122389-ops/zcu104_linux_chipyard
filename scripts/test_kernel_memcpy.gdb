set confirm off
set pagination off
python
import os, struct

port = os.environ.get("JLINK_PORT", "12331")
gdb.execute(f"target remote localhost:{port}")
inf = gdb.selected_inferior()

print("\n=== Verify kernel memcpy/memset/memcpy_and_pad ===\n")

# System.map (linux-bringup/kernel):
# __memcpy: VA 0xffffffff803b7b04 → PA = 0x805b7b04
# memset:   need to find

# First verify __memcpy matches by checking first instructions
# memcpy.S starts with: move t6, a0 (= addi t6, a0, 0 = 0x00050f13)
pa_memcpy = 0x805b7b04

data = bytes(inf.read_memory(pa_memcpy, 32))
insns = [struct.unpack_from('<I', data, i)[0] for i in range(0, 32, 4)]
print(f"PA 0x{pa_memcpy:08x} (__memcpy from System.map):")
for i, insn in enumerate(insns):
    print(f"  +{i*4:2d}: 0x{insn:08x}")

# Check if first instruction is "move t6, a0" = addi x31, x10, 0 = 0x00050f93
# Actually: move is pseudo for addi rd, rs, 0
# t6 = x31, a0 = x10
# addi x31, x10, 0 = imm[11:0] | rs1 | funct3 | rd | opcode
# = 000000000000 | 01010 | 000 | 11111 | 0010011
# = 0000_0000_0000_0101_0000_1111_1001_0011
# = 0x00050F93
if insns[0] == 0x00050f93:
    print("  → First instruction matches 'mv t6, a0' ✓")
else:
    print(f"  → First instruction 0x{insns[0]:08x} does NOT match expected 0x00050f93")
    # Try nearby offsets (maybe padding/alignment)
    for delta in range(-16, 32, 4):
        test_pa = pa_memcpy + delta
        test_data = bytes(inf.read_memory(test_pa, 4))
        test_insn = struct.unpack_from('<I', test_data, 0)[0]
        if test_insn == 0x00050f93:
            print(f"  → Found 'mv t6, a0' at PA 0x{test_pa:08x} (offset {delta})")
            pa_memcpy = test_pa
            break

# Also find __memset
# memset.S starts with: move t0, a0 (= addi x5, x10, 0 = 0x00050293)
# From System.map, need to grep for __memset
# Let me search for memset's entry by scanning near memcpy
# Actually let me just check a known System.map address
# grep __memset from System.map shows... let me check

# For now, let's search for the pattern 0x00050293 near memcpy
print(f"\nSearching for memset near memcpy...")
for offset in range(0, 2048, 4):
    search_pa = pa_memcpy + offset
    search_data = bytes(inf.read_memory(search_pa, 4))
    search_insn = struct.unpack_from('<I', search_data, 0)[0]
    if search_insn == 0x00050293:
        # Check next instruction: sltiu a3, a2, 16 = 0x01063693
        next_data = bytes(inf.read_memory(search_pa + 4, 4))
        next_insn = struct.unpack_from('<I', next_data, 0)[0]
        if next_insn == 0x01063693:  # sltiu a3, a2, 16
            print(f"  Found __memset at PA 0x{search_pa:08x}")
            pa_memset = search_pa
            break

# Now let's actually test: call kernel's memcpy+memset with known data
# We'll set up the call in-memory and use continue/hbreak

print("\n\n=== Testing kernel memcpy(dst, src, 174) + memset(dst+174, 0, 8) ===")
SRC = 0x82008000
DST = 0x82010000

# Write 180 bytes of source pattern: "ABCD...+last 2 bytes are 'XY'"  
import string
src_text = "Linux version 6.6.0-fpga-min-g67bc4513761f-dirty (root@YXY) (riscv64-unknown-linux-gnu-gcc (gc891d8dc23e) 13.2.0, GNU ld (GNU Binutils) 2.42) #26 Thu Apr  9 05:34:01 CST 2026\n"
src_bytes = src_text.encode('ascii')
print(f"Source text length: {len(src_bytes)} bytes (including \\n)")
# This matches the actual linux_banner

# Write source to DDR
for i in range(0, len(src_bytes), 8):
    chunk = src_bytes[i:i+8]
    if len(chunk) < 8:
        chunk = chunk + b'\x00' * (8 - len(chunk))
    val = int.from_bytes(chunk, 'little')
    gdb.execute(f"set *(unsigned long long*){SRC + i} = {val}")

# Fill dest with sentinel pattern (0xDE) so we can see what's overwritten
for i in range(0, 256, 8):
    gdb.execute(f"set *(unsigned long long*){DST + i} = 0xDEDEDEDEDEDEDEDE")

# Write a small program to call memcpy then memset:
# a0 = dst, a1 = src, a2 = 174
# call __memcpy (jalr ra, memcpy_addr)
# a0 = dst+174, a1 = 0, a2 = 8  
# call __memset
# ebreak

CODE = 0x82020000

# Using auipc + jalr for calls to PA addresses
# For memcpy at pa_memcpy:
# offset = pa_memcpy - CODE
# For memset at pa_memset
# This is complex. Let me use a simpler approach:
# Write the addresses as data and use absolute jalr

# Simpler: use sequential register setup + jalr
# Code layout at CODE:
# 0x00: sd ra, 0(sp)     ; save ra (need stack)
# Actually, let me use a custom approach. Put memcpy addr in t0, jalr t0.

# Even simpler: just do it in a flat sequence without sp:
# Use t5 as return address register
#
# Phase 1: call memcpy(dst, src, 174)
#   la a0, dst       → lui + addi
#   la a1, src       → lui + addi  
#   li a2, 174       → addi a2, x0, 174
#   load memcpy addr into t0
#   jalr ra, t0, 0    ; call memcpy
#   (returns here)
# Phase 2: call memset(dst+174, 0, 8)
#   la a0, dst+174   → lui + addi
#   li a1, 0         → addi a1, x0, 0
#   li a2, 8         → addi a2, x0, 8
#   load memset addr into t0
#   jalr ra, t0, 0    ; call memset
#   ebreak

# This requires putting the function addresses in memory and loading them

# Actually, the easiest approach: don't assemble code at all.
# Just set registers and use stepi to call the function.

# Plan:
# 1. Set a0=DST, a1=SRC, a2=174
# 2. Set pc=pa_memcpy
# 3. Set ra=some_ebreak_addr
# 4. hbreak *some_ebreak_addr
# 5. continue → memcpy runs to completion, returns to ebreak

EBREAK_ADDR = 0x82030000
gdb.execute(f"set *(unsigned int*){EBREAK_ADDR} = 0x00100073")  # ebreak

# Phase 1: call memcpy
gdb.execute(f"set $a0 = {DST}")
gdb.execute(f"set $a1 = {SRC}")
gdb.execute(f"set $a2 = 174")
gdb.execute(f"set $pc = {pa_memcpy}")
gdb.execute(f"set $ra = {EBREAK_ADDR}")
gdb.execute("delete breakpoints")
gdb.execute(f"hbreak *{EBREAK_ADDR}")

print(f"Calling __memcpy(0x{DST:x}, 0x{SRC:x}, 174)...")
gdb.execute("continue")
pc = int(gdb.parse_and_eval("$pc"))
if pc != EBREAK_ADDR:
    print(f"  ERROR: didn't return to ebreak (PC=0x{pc:08x})")
else:
    print(f"  memcpy returned OK")
    
    # Check dest after memcpy
    dst_data = bytes(inf.read_memory(DST, 192))
    print(f"  Dest[168:184] after memcpy: {' '.join(f'{b:02x}' for b in dst_data[168:184])}")
    ascii = ''.join(chr(b) if 32<=b<127 else '.' for b in dst_data[168:184])
    print(f"  ASCII: {ascii}")
    
    # Check if bytes 174-175 have data from STORE_BYTE_WORDWISE
    print(f"  Byte 174: 0x{dst_data[174]:02x} (expect 0xDE sentinel)")
    print(f"  Byte 175: 0x{dst_data[175]:02x} (expect 0xDE sentinel)")
    
    # Phase 2: call memset
    print(f"\nCalling __memset(0x{DST+174:x}, 0, 10)...")
    gdb.execute(f"set $a0 = {DST + 174}")
    gdb.execute(f"set $a1 = 0")
    gdb.execute(f"set $a2 = 10")
    try:
        pa_memset_val = pa_memset
    except:
        print("  __memset address not found, skipping memset test")
        pa_memset_val = None
    
    if pa_memset_val:
        gdb.execute(f"set $pc = {pa_memset_val}")
        gdb.execute(f"set $ra = {EBREAK_ADDR}")
        gdb.execute("continue")
        
        pc2 = int(gdb.parse_and_eval("$pc"))
        if pc2 != EBREAK_ADDR:
            print(f"  ERROR: didn't return (PC=0x{pc2:08x})")
        else:
            print(f"  memset returned OK")
            dst_data2 = bytes(inf.read_memory(DST, 192))
            print(f"  Dest[168:184] after memset: {' '.join(f'{b:02x}' for b in dst_data2[168:184])}")
            
            # Final check
            correct = src_bytes[:174]
            actual = dst_data2[:174]
            if actual == correct:
                print(f"\n  memcpy result: CORRECT (174 bytes match)")
            else:
                diffs = [(i, correct[i], actual[i]) for i in range(174) if actual[i] != correct[i]]
                print(f"\n  memcpy result: WRONG ({len(diffs)} diffs)")
                for idx, exp, act in diffs[:5]:
                    print(f"    [{idx}] exp=0x{exp:02x} act=0x{act:02x}")
            
            # Check beyond
            print(f"  Bytes 174-183: {' '.join(f'{b:02x}' for b in dst_data2[174:184])}")
            extra = dst_data2[174:176]
            if extra == b'\x00\x00':
                print(f"  Bytes 174-175: CLEAN (zeroed by memset)")
            elif extra == src_bytes[172:174]:
                print(f"  Bytes 174-175: DUPLICATED ('{extra.decode()}' = last 2 chars)!")
            else:
                print(f"  Bytes 174-175: unexpected ({extra!r})")

gdb.execute("delete breakpoints")
gdb.execute("disconnect")
end
quit
