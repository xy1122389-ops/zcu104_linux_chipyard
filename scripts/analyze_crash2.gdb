set confirm off
set pagination off
python
import os, struct

port = os.environ.get("JLINK_PORT", "12331")
gdb.execute(f"target remote localhost:{port}")
inf = gdb.selected_inferior()

print("=== Deep crash analysis ===\n")

# From klog crash register dump:
# t0=0x0000000000000000  t1=0xffffff8000000007  t2=0xffffffff80850937
# s0=0xffffffff80868bf0  s1=0xffffffd8010522d4  s2=0xffffffff808509e0
# a0=0xffffffd8010522d4  a1=0xffffffff80850938  a2=0x0000000000000000
# a3=0xffffffff80868a88  a4=0x0000000000000037  a5=0xffffff8000000007
# a6=0x0000000000000063  a7=0x0000000000000000
# s3=0xffffffd80100ee00  s4=0x0000000000000000  s5=0xffffffff80863e98
# s6=0xffffffd807e00000  s7=0xffffffff808509d8  s8=0x0000000000000001
# s9=0xffffffd8010522d9  s10=0x0000000000000011 s11=0xffffffd8010522a0
# ra=0xffffffff80032060

# KEY: a5 = 0xffffff8000000007 = same as badaddr!
# t1 = 0xffffff8000000007 = same as badaddr!
# t2 = 0xffffffff80850937 = a1 - 1

# Read actual strlen code from DDR
# strlen VA = 0xffffffff802fda58, PA = 0x804fda58
strlen_pa = 0x804fda58
print(f"strlen code at PA 0x{strlen_pa:08x}:")
strlen_code = bytes(inf.read_memory(strlen_pa, 32))
print(f"  hex: {' '.join(f'{b:02x}' for b in strlen_code[:32])}")

# Disassemble as RISC-V instructions
i = 0
while i < 28:
    hw = struct.unpack_from('<H', strlen_code, i)[0]
    if (hw & 3) == 3:  # 32-bit instruction
        if i+2 < 32:
            hw2 = struct.unpack_from('<H', strlen_code, i+2)[0]
            insn = (hw2 << 16) | hw
            print(f"  +0x{i:02x}: 0x{insn:08x} (32-bit)")
            i += 4
        else:
            break
    else:
        print(f"  +0x{i:02x}: 0x{hw:04x}     (16-bit C-ext)")
        i += 2

# Now look at parameq code
# parameq VA = 0xffffffff80032042, PA = 0x80232042
parameq_pa = 0x80232042
print(f"\nparameq code at PA 0x{parameq_pa:08x}:")
parameq_code = bytes(inf.read_memory(parameq_pa, 80))
print(f"  hex: {' '.join(f'{b:02x}' for b in parameq_code[:80])}")

# Disassemble
i = 0
while i < 76:
    hw = struct.unpack_from('<H', parameq_code, i)[0]
    if (hw & 3) == 3:
        if i+2 < 80:
            hw2 = struct.unpack_from('<H', parameq_code, i+2)[0]
            insn = (hw2 << 16) | hw
            print(f"  +0x{i:02x}: 0x{insn:08x} (32-bit)")
            i += 4
        else:
            break
    else:
        print(f"  +0x{i:02x}: 0x{hw:04x}     (16-bit C-ext)")
        i += 2

# Also read parse_args around offset +0xe8
# parse_args VA = 0xffffffff80031f78 (= 0xffffffff80032060 - 0xe8)
parse_args_va = 0xffffffff80032060 - 0xe8
parse_args_pa = parse_args_va - 0xffffffff80000000 + 0x80200000
print(f"\nparse_args at PA 0x{parse_args_pa:08x} (VA 0x{parse_args_va:016x}):")
pa_code = bytes(inf.read_memory(parse_args_pa, 32))
# Just show the area around +0xe8
pa_area_pa = parse_args_pa + 0xe0
pa_area = bytes(inf.read_memory(pa_area_pa, 32))
print(f"  parse_args+0xe0 area hex: {' '.join(f'{b:02x}' for b in pa_area[:32])}")

# Check the __param section entries
# s2 = 0xffffffff808509e0 - might be a __param entry pointer
# s7 = 0xffffffff808509d8 - might be another entry or offset
# Let's read the __param entry that s2 points to
s2_pa = 0xffffffff808509e0 - 0xffffffff80000000 + 0x80200000
print(f"\n--- __param entry at s2 PA 0x{s2_pa:08x} ---")
param_data = bytes(inf.read_memory(s2_pa, 80))
for j in range(0, 80, 8):
    val = struct.unpack_from('<Q', param_data, j)[0]
    print(f"  +{j:2d}: 0x{val:016x}")

# The first field should be the 'name' pointer
name_ptr = struct.unpack_from('<Q', param_data, 0)[0]
print(f"\n  name ptr: 0x{name_ptr:016x}")
if 0xffffffff80000000 <= name_ptr <= 0xffffffffffffffff:
    name_pa = name_ptr - 0xffffffff80000000 + 0x80200000
    try:
        name_str = bytes(inf.read_memory(name_pa, 64)).split(b'\x00')[0].decode('ascii', errors='replace')
        print(f"  name string: \"{name_str}\"")
    except:
        print(f"  cannot read name at PA 0x{name_pa:08x}")
elif name_ptr == 0xffffff8000000007:
    print("  *** BAD NAME POINTER - matches badaddr! ***")

# Also check the entry BEFORE s2 (might be the one that crashed)
# __param entries are typically 3 x 8 = 24 bytes each  
# But struct kernel_param is larger. Let me check...
# struct kernel_param {
#     const char *name;           // +0
#     struct module *mod;         // +8
#     const struct kernel_param_ops *ops; // +16
#     const u16 perm;             // +24
#     s8 level;                   // +26
#     u8 flags;                   // +27
#     union { void *arg; ... };   // +32
# }; // size = 40 bytes on rv64 (with alignment)

# Actually, s7 = 0xffffffff808509d8 = s2 - 8
# That doesn't match a 40-byte stride. Let's check if s5 has __stop___param
s5_val = 0xffffffff80863e98
print(f"\ns5 (possible __stop___param?) = 0x{s5_val:016x}")

# Check range: s2 to s5
range_bytes = s5_val - 0xffffffff808509e0
n_entries = range_bytes // 40
print(f"  Range: {range_bytes} bytes = {n_entries} entries (if stride=40)")

# Let me also check s7 as possibly pointing to the CURRENT entry being processed
s7_pa = 0xffffffff808509d8 - 0xffffffff80000000 + 0x80200000
print(f"\n--- Entry at s7 PA 0x{s7_pa:08x} ---")
s7_data = bytes(inf.read_memory(s7_pa, 48))
for j in range(0, 48, 8):
    val = struct.unpack_from('<Q', s7_data, j)[0]
    print(f"  +{j:2d}: 0x{val:016x}")

# Check a1 area - read more context around the parameter string
print(f"\n--- Area around a1 = 0xffffffff80850938 (PA 0x80A50938) ---")
area_before = bytes(inf.read_memory(0x80A50900, 128))
for j in range(0, 128, 8):
    val = struct.unpack_from('<Q', area_before, j)[0]
    ascii_bytes = area_before[j:j+8]
    ascii_str = ''.join(chr(b) if 32 <= b < 127 else '.' for b in ascii_bytes)
    print(f"  +{j:3d} (0x{0x80A50900+j:08x}): 0x{val:016x}  {ascii_str}")

# Check if the bad address 0xffffff8000000007 appears anywhere in the __param section
# Read from s2 backwards to find it
search_start = s2_pa - 200
search_data = bytes(inf.read_memory(search_start, 400))
print(f"\n--- Scanning for 0xffffff8000000007 near __param ---")
target = struct.pack('<Q', 0xffffff8000000007)
pos = 0
while pos < len(search_data):
    idx = search_data.find(target, pos)
    if idx < 0:
        break
    print(f"  Found at offset {idx} (PA 0x{search_start+idx:08x})")
    pos = idx + 1

gdb.execute("disconnect")
end
quit
