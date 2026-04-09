set confirm off
set pagination off
python
import os, struct, time

port = os.environ.get("JLINK_PORT", "12331")
gdb.execute(f"target remote localhost:{port}")
inf = gdb.selected_inferior()

print("\n=== Correct Klog Dump (using printk_info text_len) ===\n")

INFO_PA = 0x80E15EF0      # _printk_rb_static_infos
INFO_STRIDE = 88           # sizeof(printk_info) with alignment
DATA_PA = 0x80ED0060       # start of text data ring (__log_buf)

# Read entire data ring (128KB = default LOG_BUF_LEN for CONFIG_LOG_BUF_SHIFT=17)
DATA_SIZE = 128 * 1024
try:
    data_ring = bytes(inf.read_memory(DATA_PA, DATA_SIZE))
except:
    # Try smaller if 128KB fails
    DATA_SIZE = 32 * 1024
    data_ring = bytes(inf.read_memory(DATA_PA, DATA_SIZE))

# Find all data blocks by scanning for headers
blocks = []
off = 0
while off < len(data_ring) - 16:
    b = data_ring[off:off+8]
    # Pattern: XX f0 ff ff 00 00 00 00 (data block header)
    if b[1] == 0xf0 and b[2] == 0xff and b[3] == 0xff and b[4:8] == b'\x00\x00\x00\x00':
        block_seq = b[0]
        text_start = off + 8
        blocks.append((off, block_seq, text_start))
        # Find next block (scan for next header pattern or \0 padding)
        scan = text_start
        while scan < len(data_ring) - 8:
            if (data_ring[scan+1] == 0xf0 and data_ring[scan+2] == 0xff and 
                data_ring[scan+3] == 0xff and data_ring[scan+4:scan+8] == b'\x00\x00\x00\x00'):
                break
            scan += 8
        off = scan
    else:
        off += 8

print(f"Found {len(blocks)} data blocks in ring buffer")

# Level names
LEVELS = ['EMERG', 'ALERT', 'CRIT', 'ERR', 'WARNING', 'NOTICE', 'INFO', 'DEBUG']

# Read info and output clean log
output_lines = []
for i in range(min(len(blocks), 500)):
    info_addr = INFO_PA + i * INFO_STRIDE
    try:
        info_data = bytes(inf.read_memory(info_addr, 24))
    except:
        break
    
    seq = struct.unpack_from('<Q', info_data, 0)[0]
    ts = struct.unpack_from('<Q', info_data, 8)[0]
    text_len = struct.unpack_from('<H', info_data, 16)[0]
    facility = info_data[18]
    flags = info_data[19]
    level = info_data[20]
    
    if seq != i:
        # Sequence mismatch - might have wrapped or ended
        break
    
    if text_len == 0:
        continue
    
    # Get text from data block
    if i < len(blocks):
        _, _, text_start = blocks[i]
        text = data_ring[text_start:text_start + text_len]
    else:
        break
    
    text_str = text.decode('ascii', errors='replace')
    ts_sec = ts / 1e9
    level_str = LEVELS[level] if level < 8 else f'L{level}'
    
    line = f"[{ts_sec:12.6f}] {text_str}"
    output_lines.append(line)

print(f"\nTotal records: {len(output_lines)}")

# Save to file
tag = os.environ.get("RUN_TAG", "corrected")
outfile = f"/tmp/klog_{tag}_{time.strftime('%Y%m%d_%H%M%S')}.txt"
with open(outfile, 'w') as f:
    for line in output_lines:
        f.write(line + '\n')
print(f"Saved to {outfile}")

# Print first 50 lines
print("\n--- First 50 lines ---")
for line in output_lines[:50]:
    print(line)

# Print last 20 lines
if len(output_lines) > 50:
    print(f"\n--- Last 20 lines (of {len(output_lines)}) ---")
    for line in output_lines[-20:]:
        print(line)

# Check for any crash/oops info
print("\n--- Crash/Oops scan ---")
for i, line in enumerate(output_lines):
    if any(k in line.lower() for k in ['oops', 'panic', 'bug:', 'unable to', 'killed', 'segfault']):
        # Print context
        for j in range(max(0, i-2), min(len(output_lines), i+5)):
            marker = ">>>" if j == i else "   "
            print(f"{marker} {output_lines[j]}")
        print()

gdb.execute("disconnect")
end
quit
