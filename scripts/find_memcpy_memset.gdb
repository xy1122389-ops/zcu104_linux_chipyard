set confirm off
set pagination off
python
import os, struct

port = os.environ.get("JLINK_PORT", "12331")
gdb.execute(f"target remote localhost:{port}")
inf = gdb.selected_inferior()

print("\n=== Find actual __memcpy in DDR ===\n")

# memcpy.S first 2 instructions:
# mv t6, a0     = addi x31, x10, 0 = 0x00050f93
# sltiu a3, a2, 128 = 0x08063693
pattern = struct.pack('<II', 0x00050f93, 0x08063693)

# Search kernel text region: PA 0x80200000 - 0x80800000
found = []
CHUNK = 0x10000  # 64KB chunks
for base in range(0x80200000, 0x80800000, CHUNK):
    try:
        data = bytes(inf.read_memory(base, CHUNK))
    except:
        continue
    
    pos = 0
    while True:
        pos = data.find(pattern, pos)
        if pos < 0:
            break
        pa = base + pos
        # Also check 3rd instruction: bnez a3, 4f = some bne variant
        insn3 = struct.unpack_from('<I', data, pos+8)[0] if pos+12 <= len(data) else 0
        # bnez a3, offset → bne x13, x0, offset
        # opcode = 0x63, funct3 = 001, rs1 = x13, rs2 = x0
        # [6:0] = 1100011, [14:12] = 001, [19:15] = 01101, [24:20] = 00000
        is_bnez_a3 = (insn3 & 0x00707F) == 0x069063  # == bne a3, x0
        found.append((pa, insn3, is_bnez_a3))
        print(f"  Found pattern at PA 0x{pa:08x} (3rd insn: 0x{insn3:08x}, bnez_a3={is_bnez_a3})")
        pos += 4

# Also search for memset pattern:
# mv t0, a0 = addi x5, x10, 0 = 0x00050293
# sltiu a3, a2, 16 = 0x01063693
memset_pattern = struct.pack('<II', 0x00050293, 0x01063693)
print(f"\n=== Find actual __memset in DDR ===")
for base in range(0x80200000, 0x80800000, CHUNK):
    try:
        data = bytes(inf.read_memory(base, CHUNK))
    except:
        continue
    pos = 0
    while True:
        pos = data.find(memset_pattern, pos)
        if pos < 0:
            break
        pa = base + pos
        print(f"  Found memset pattern at PA 0x{pa:08x}")
        pos += 4

gdb.execute("disconnect")
end
quit
