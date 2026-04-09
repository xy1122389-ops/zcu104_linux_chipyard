set pagination off
set confirm off
set remotetimeout 120

target remote 172.19.128.1:12331
monitor halt

python
import gdb, struct, os

# Block copy routine at 0x81200000:
# a0 = source PA start
# a1 = source PA end (exclusive)
# a2 = dest PA start
# Copies 8 bytes at a time from [a0,a1) to a2+
#
# 0x81200000: fence.i
# 0x81200004: ld   a3, 0(a0)     # 0x00053683
# 0x81200008: sd   a3, 0(a2)     # 0x00d63023
# 0x8120000c: addi a0, a0, 8     # 0x00850513
# 0x81200010: addi a2, a2, 8     # 0x00860613
# 0x81200014: blt  a0, a1, -16   # 0xFEB54CE3  (back to ld)
# 0x81200018: ebreak              # 0x00100073

BLOCK_COPY = 0x81200000
DEST_BUF   = 0x81300000  # destination buffer

instrs = [
    (BLOCK_COPY + 0x00, 0x0000100f),  # fence.i
    (BLOCK_COPY + 0x04, 0x00053683),  # ld a3, 0(a0)
    (BLOCK_COPY + 0x08, 0x00d63023),  # sd a3, 0(a2)
    (BLOCK_COPY + 0x0C, 0x00850513),  # addi a0, a0, 8
    (BLOCK_COPY + 0x10, 0x00860613),  # addi a2, a2, 8
    (BLOCK_COPY + 0x14, 0xFEB54CE3),  # blt a0, a1, -16
    (BLOCK_COPY + 0x18, 0x00100073),  # ebreak
]

for addr, val in instrs:
    gdb.execute(f"set *(unsigned int*)0x{addr:x} = 0x{val:08x}")

# Run fence.i first (single step past it)
gdb.execute(f"set $pc = 0x{BLOCK_COPY:x}")
gdb.execute(f"set $a0 = 0x{BLOCK_COPY:x}")
gdb.execute(f"set $a1 = 0x{BLOCK_COPY + 8:x}")
gdb.execute(f"set $a2 = 0x{DEST_BUF:x}")
gdb.execute(f"hbreak *0x{BLOCK_COPY + 0x18:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")
gdb.write("[ok] Block copy routine installed and tested\n")

def block_copy(src_pa, size):
    """Copy `size` bytes from src_pa to DEST_BUF using CPU ld/sd"""
    gdb.execute(f"set $a0 = 0x{src_pa:x}")
    gdb.execute(f"set $a1 = 0x{src_pa + size:x}")
    gdb.execute(f"set $a2 = 0x{DEST_BUF:x}")
    gdb.execute(f"set $pc = 0x{BLOCK_COPY + 4:x}")  # skip fence.i
    gdb.execute(f"hbreak *0x{BLOCK_COPY + 0x18:x}")
    gdb.execute("continue")
    gdb.execute("delete breakpoints")
    # Now read dest buffer via SBA (fast!)
    tmp = f"/tmp/_blockcopy.bin"
    gdb.execute(f"dump binary memory {tmp} 0x{DEST_BUF:x} 0x{DEST_BUF + size:x}", to_string=True)
    with open(tmp, "rb") as f:
        return f.read()

# === Read kernel log buffer ===
# log_buf = 0xffffffff80ed0060 (runtime VA)
# PA = 0xffffffff80ed0060 - 0xffffffff80000000 + 0x80200000 = 0x810d0060
LOG_BUF_PA = 0x810d0060

gdb.write(f"\n=== Reading kernel log at PA=0x{LOG_BUF_PA:x} ===\n")

# Read 8KB of log buffer
CHUNK = 8192
data = block_copy(LOG_BUF_PA, CHUNK)
gdb.write(f"Read {len(data)} bytes\n")

# Save raw
with open("/tmp/klog_raw_8k.bin", "wb") as f:
    f.write(data)

# Parse printk_log entries
# Linux 6.x log format (struct printk_log):
# u64 ts_nsec; u16 len; u16 text_len; u16 dict_len; u8 facility; u8 flags;
# For newer kernels (6.x with printk_ringbuffer), format is different!
# Let's check the raw data first

gdb.write("\nFirst 256 bytes (hex dump):\n")
for i in range(0, min(256, len(data)), 16):
    c = data[i:i+16]
    h = " ".join(f"{b:02x}" for b in c)
    a = "".join(chr(b) if 32 <= b < 127 else "." for b in c)
    gdb.write(f"  {i:04x}: {h:48s} {a}\n")

# Try to find readable ASCII strings
gdb.write("\n\nSearching for ASCII strings (len >= 8):\n")
import re
ascii_strings = re.findall(b'[\x20-\x7e]{8,}', data)
for s in ascii_strings[:30]:
    gdb.write(f"  {s.decode('ascii')}\n")

# Also read first 4KB from a point 4KB into the buffer
data2 = block_copy(LOG_BUF_PA + 4096, CHUNK)
with open("/tmp/klog_raw_8k_p2.bin", "wb") as f:
    f.write(data2)

gdb.write("\n\nStrings from offset 4096:\n")
ascii_strings2 = re.findall(b'[\x20-\x7e]{8,}', data2)
for s in ascii_strings2[:30]:
    gdb.write(f"  {s.decode('ascii')}\n")

# Read saved_command_line string
# saved_command_line value = 0xffffffff8005444c (from previous read)
# This is a runtime VA in kernel text region
# PA = 0xffffffff8005444c - 0xffffffff80000000 + 0x80200000 = 0x8025444c
SAVED_CL_PA = 0x8025444c
gdb.write(f"\n=== saved_command_line at PA=0x{SAVED_CL_PA:x} ===\n")
cl_data = block_copy(SAVED_CL_PA, 512)
null_idx = cl_data.find(b'\x00')
if null_idx > 0:
    gdb.write(f"Command line: {cl_data[:null_idx].decode('ascii', errors='replace')}\n")
else:
    gdb.write("No null terminator found, raw:\n")
    for i in range(0, min(128, len(cl_data)), 16):
        c = cl_data[i:i+16]
        h = " ".join(f"{b:02x}" for b in c)
        a = "".join(chr(b) if 32 <= b < 127 else "." for b in c)
        gdb.write(f"  {i:04x}: {h:48s} {a}\n")

gdb.write("\n[done]\n")
end

quit
