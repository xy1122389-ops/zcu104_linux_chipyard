set pagination off
set confirm off
set remotetimeout 60

target remote 172.19.128.1:12331
monitor halt

python
import gdb, struct

READER = 0x80038000

def cpu_ld(pa):
    gdb.execute(f"set $a0 = 0x{pa:x}")
    gdb.execute(f"set $pc = 0x{READER + 4:x}")
    gdb.execute(f"hbreak *0x{READER + 8:x}")
    gdb.execute("continue")
    val = int(gdb.parse_and_eval("$a1")) & 0xFFFFFFFFFFFFFFFF
    gdb.execute("delete breakpoints")
    return val

# log_buf = 0xffffffff80ed0060 (runtime VA of __log_buf)
# This is a kernel IMAGE VA, PA = VA - 0xffffffff80000000 + 0x80200000
# PA = 0xed0060 + 0x80200000 = 0x810d0060
LOG_BUF_PA = 0x810d0060
LOG_BUF_LEN = 0x20000  # 128KB

gdb.write(f"Reading kernel log buffer at PA=0x{LOG_BUF_PA:x}, len={LOG_BUF_LEN}\n\n")

# Read first 4KB of log buffer
READ_SIZE = 4096
data = b""
for off in range(0, READ_SIZE, 8):
    try:
        w = cpu_ld(LOG_BUF_PA + off)
        data += w.to_bytes(8, "little")
    except Exception as e:
        gdb.write(f"Error at offset 0x{off:x}: {e}\n")
        break

# Save raw data to file
with open("/tmp/klog_raw.bin", "wb") as f:
    f.write(data)

# Print hex + ASCII dump of first 512 bytes
gdb.write("First 512 bytes (hex dump):\n")
for i in range(0, min(512, len(data)), 16):
    c = data[i:i+16]
    h = " ".join(f"{b:02x}" for b in c)
    a = "".join(chr(b) if 32 <= b < 127 else "." for b in c)
    gdb.write(f"  {i:04x}: {h:48s} {a}\n")

# Try to find printk log entries (printk_log format):
# struct printk_log { u64 ts_nsec; u16 len; u16 text_len; u16 dict_len; u8 facility; u8 flags; }
# Followed by text, then dict
gdb.write("\n\nSearching for printk log entries...\n")
offset = 0
entry_count = 0
while offset < len(data) - 16 and entry_count < 50:
    # Read printk_log header
    ts_nsec = int.from_bytes(data[offset:offset+8], "little")
    if offset + 12 > len(data):
        break
    total_len = int.from_bytes(data[offset+8:offset+10], "little")
    text_len = int.from_bytes(data[offset+10:offset+12], "little")
    dict_len = int.from_bytes(data[offset+12:offset+14], "little")
    facility = data[offset+14] if offset+14 < len(data) else 0
    flags = data[offset+15] if offset+15 < len(data) else 0
    
    if total_len == 0:
        break
    if total_len > 4096 or text_len > total_len:
        gdb.write(f"  Invalid entry at offset 0x{offset:x}: len={total_len} text_len={text_len}\n")
        break
    
    # Extract text
    text_start = offset + 16  # after the header
    text_end = text_start + text_len
    if text_end <= len(data):
        text = data[text_start:text_end].decode("ascii", errors="replace")
    else:
        text = "<truncated>"
    
    ts_sec = ts_nsec / 1e9
    gdb.write(f"  [{ts_sec:12.6f}] {text}\n")
    
    offset += total_len
    entry_count += 1

# Also read some data from further in the buffer to check
gdb.write(f"\nTotal entries found: {entry_count}\n")

# Read saved_command_line properly
# saved_command_line = 0xffffffff8005444c (value read from runtime VA)
# This looks like a kernel TEXT VA. Hmm.
# Let me try reading boot_command_line as a char array
# boot_command_line runtime VA = 0xffffffff80b18460
# But the value we read (0xffffffff8005445c) suggests it's NOT an array
# Let me try reading 128 bytes from both PAs to see content

gdb.write("\n\nChecking boot_command_line area:\n")
BOOT_CL_PA = 0x80d18460  # PA of boot_command_line (runtime)
data_cl = b""
for off in range(0, 128, 8):
    w = cpu_ld(BOOT_CL_PA + off)
    data_cl += w.to_bytes(8, "little")

for i in range(0, len(data_cl), 16):
    c = data_cl[i:i+16]
    h = " ".join(f"{b:02x}" for b in c)
    a = "".join(chr(b) if 32 <= b < 127 else "." for b in c)
    gdb.write(f"  {i:04x}: {h:48s} {a}\n")

# Also check saved_command_line pointer destination
# The value 0xffffffff8005444c might need PIE correction
# If it was a relocatable pointer, the linker set it to some VA
# After PIE relocation by +0x200000, the pointer should be:
# 0xffffffff8005444c + 0x200000 = 0xffffffff8007444c
# PA = 0xffffffff8007444c - 0xffffffff80000000 + 0x80200000 = 0x80274060+...
# Actually: PA = 0x7444c + 0x80200000 = 0x8027444c
# Hmm, that's in the OpenSBI region, doesn't seem right.
# The value might already be the PIE-adjusted VA.
# PA = 0xffffffff8005444c - 0xffffffff80000000 + 0x80200000 = 0x8025444c
saved_ptr = 0xffffffff8005444c
saved_ptr_pa = (saved_ptr - 0xffffffff80000000 + 0x80200000) & 0xFFFFFFFFFFFFFFFF
gdb.write(f"\nsaved_command_line points to: VA=0x{saved_ptr:x} PA=0x{saved_ptr_pa:x}\n")
data_saved = b""
for off in range(0, 128, 8):
    w = cpu_ld(saved_ptr_pa + off)
    data_saved += w.to_bytes(8, "little")

null_idx = data_saved.find(b'\x00')
if null_idx > 0:
    text = data_saved[:null_idx].decode("ascii", errors="replace")
    gdb.write(f"saved_command_line string: {text}\n")
else:
    for i in range(0, min(64, len(data_saved)), 16):
        c = data_saved[i:i+16]
        h = " ".join(f"{b:02x}" for b in c)
        a = "".join(chr(b) if 32 <= b < 127 else "." for b in c)
        gdb.write(f"  {i:04x}: {h:48s} {a}\n")

gdb.write("\n[done]\n")
end

quit
