set confirm off
set pagination off
python
import os, struct

port = os.environ.get("JLINK_PORT", "12331")
gdb.execute(f"target remote localhost:{port}")
inf = gdb.selected_inferior()

print("\n=== Analyze crash: strlen badaddr=0xffffff8000000007 ===\n")

# Crash context from klog:
# epc: strlen+0x6  (lbu t0, 0(t1))
# ra:  parameq+0x1e
# badaddr: 0xffffff8000000007
# cause: 0xd (load page fault)
# a0 = 0xffffffd8010522d4, a1 = 0xffffffff80850938
# s1 = 0xffffffd8010522d4, s9 = 0xffffffd8010522d9

# The stretch function was called with a pointer that reaches 0xffffff8000000007.
# Since strlen scans byte by byte from a0, the initial pointer might BE 0xffffff8000000007
# or nearby. But a0 = 0xffffffd8010522d4, which is in lowmem range.

# parameq(input, paramname) is called from parse_args.
# parameq compares characters from 'input' and 'paramname'.
# If parameq calls strlen, one of these pointers must be the bad one.

# a0 = 0xffffffd8010522d4 → this is the 'input' (kernel command line token)
# a1 = 0xffffffff80850938 → this is 'paramname' (from __param section)

# Let's check BOTH addresses

# a1 = 0xffffffff80850938 → kernel text/rodata
# PA = a1 - 0xffffffff80000000 + 0x80200000 = 0x80A50938
pa_a1 = 0x80A50938
try:
    data_a1 = bytes(inf.read_memory(pa_a1, 64))
    text_a1 = data_a1.split(b'\x00')[0].decode('ascii', errors='replace')
    print(f"a1 (paramname) PA 0x{pa_a1:08x}: \"{text_a1}\"")
except Exception as e:
    print(f"a1 read error: {e}")

# a0 = 0xffffffd8010522d4 → lowmem (dynamically allocated?)
# PA = a0 - 0xffffffd800000000 + 0x80000000 = 0x810522d4
pa_a0 = 0x810522d4
try:
    data_a0 = bytes(inf.read_memory(pa_a0, 64))
    text_a0 = data_a0.split(b'\x00')[0].decode('ascii', errors='replace')
    hex_a0 = ' '.join(f'{b:02x}' for b in data_a0[:32])
    print(f"a0 (input)     PA 0x{pa_a0:08x}: \"{text_a0}\"")
    print(f"  hex: {hex_a0}")
except Exception as e:
    print(f"a0 read error: {e}")

# The badaddr 0xffffff8000000007 doesn't match either a0 or a1 directly.
# It could be from a DIFFERENT call to strlen, or from a field accessed through
# a struct pointer.

# Let's check what parameq does. It iterates through __setup or __param entries.
# The __param entries are in the __param section. Each entry has:
# struct kernel_param {
#     const char *name;      // +0: 8 bytes on rv64
#     ...
# };
#
# If a param->name pointer is 0xffffff8000000007, that's our bad pointer.

# Let's find __param section boundaries
# From System.Map (linux-bringup/kernel):
# Search for __start___param and __stop___param
print("\n--- Checking __param section ---")

# Let's look at the __setup section instead
# struct obs_kernel_param {
#     const char *str;     // +0
#     int (*setup_func)(char *); // +8
#     int early;           // +16
# };
# Total: 24 bytes on rv64 (with padding to 8-byte alignment)

# The badaddr 0xffffff8000000007 looks like a str pointer
# Binary: 1111...11 1000 0000 0000 ... 0000 0111
# = 0xffffff8000000007
# This could be an address with just the 3 low bits set + all high bits set.
# Might be a struct with flags in the low bits reinterpreted as a pointer.

# Actually, let's check: does 0xffffff8000000007 look like it could be
# something else misinterpreted as a pointer?
# 0xffffff8000000007 =
#   top byte: 0xFF = -1
#   as signed: -549755813881
# Doesn't look like a valid kernel address (kernel is at 0xffffffff80000000+)

# Let's find the actual __param section. Search for __start___param:
print("\n--- Searching for parameter table ---")

# We know parameq at VA 0xffffffff80032042 (from crash backtrace)
# PA = 0x80232042
# Let me read and disassemble parameq to understand how it accesses the param name

pa_parameq = 0x80232042
print(f"\nparameq at PA 0x{pa_parameq:08x}:")
parameq_code = bytes(inf.read_memory(pa_parameq, 64))
for i in range(0, 64, 2):
    hw = struct.unpack_from('<H', parameq_code, i)[0]
    # Check if 32-bit insn
    if (hw & 3) == 3:  # 32-bit instruction
        if i+2 < 64:
            hw2 = struct.unpack_from('<H', parameq_code, i+2)[0]
            insn = (hw2 << 16) | hw
            print(f"  +{i:02x}: 0x{insn:08x}")
        break  # for simplicity
    else:
        print(f"  +{i:02x}: 0x{hw:04x} (C-ext)")

# Let me also check: read the a1 value as a pointer chain
# a1 = 0xffffffff80850938, which should be in kernel rodata
# This might be a kernel_param entry or obs_kernel_param entry
# Let me read the struct at that address
pa_struct = 0x80A50938
struct_data = bytes(inf.read_memory(pa_struct, 48))
print(f"\nStruct at a1 PA 0x{pa_struct:08x}:")
for i in range(0, 48, 8):
    val = struct.unpack_from('<Q', struct_data, i)[0]
    print(f"  +{i:2d}: 0x{val:016x}")

# Check the name pointer from this struct
name_ptr = struct.unpack_from('<Q', struct_data, 0)[0]
print(f"\nName pointer: 0x{name_ptr:016x}")
if name_ptr == 0xffffff8000000007:
    print("  *** THIS IS THE BAD POINTER! ***")
    print("  The kernel_param entry has a corrupted name pointer")
elif name_ptr > 0xffffffff80000000:
    # Try to read the name
    name_pa = name_ptr - 0xffffffff80000000 + 0x80200000
    try:
        name_data = bytes(inf.read_memory(name_pa, 32))
        name_str = name_data.split(b'\x00')[0].decode('ascii', errors='replace')
        print(f"  Name string: \"{name_str}\"")
    except:
        print(f"  Cannot read name at PA 0x{name_pa:08x}")

# Also check: what is the CURRENT parse_args input?
# From register state: a0 = 0xffffffd8010522d4
# This is the current token being compared
print(f"\nCurrent input token (a0=0xffffffd8010522d4, PA 0x810522d4):")
try:
    token_data = bytes(inf.read_memory(0x810522d4, 32))
    token_str = token_data.split(b'\x00')[0].decode('ascii', errors='replace')
    print(f"  \"{token_str}\"")
    print(f"  hex: {' '.join(f'{b:02x}' for b in token_data[:32])}")
except:
    print("  Cannot read")

gdb.execute("disconnect")
end
quit
