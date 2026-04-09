set confirm off
set pagination off
python
import os, struct, time

port = os.environ.get("JLINK_PORT", "12331")
gdb.execute(f"target remote localhost:{port}")
inf = gdb.selected_inferior()

print("=== Boot 12 klog dump (correct method) ===\n")

INFO_PA = 0x80E15EF0
STRIDE = 88
DATA_PA = 0x80ED0060

# Read up to 100 records
records = []
for idx in range(100):
    info_addr = INFO_PA + idx * STRIDE
    try:
        info_data = bytes(inf.read_memory(info_addr, 88))
    except:
        break
    seq = struct.unpack_from('<Q', info_data, 0)[0]
    ts = struct.unpack_from('<Q', info_data, 8)[0]
    text_len = struct.unpack_from('<H', info_data, 16)[0]
    
    if seq != idx:
        break
    if text_len == 0 or text_len > 2000:
        break
    
    # Find the data block for this record
    # Scan for data block header with matching ID
    # text data starts at DATA_PA + some offset
    # For simplicity, scan sequentially
    records.append((idx, seq, ts, text_len))

print(f"Found {len(records)} records\n")

# Now read text data
# The text data ring has prb_data_blk_hdr (8 bytes) before each data block
# We scan starting from DATA_PA
data_offset = 0
output_lines = []
for rec_idx, (idx, seq, ts, text_len) in enumerate(records):
    # Read the data block header
    hdr_addr = DATA_PA + data_offset
    try:
        hdr = bytes(inf.read_memory(hdr_addr, 8))
        blk_id = struct.unpack_from('<Q', hdr, 0)[0]
    except:
        break
    
    # The data starts right after the header
    text_addr = hdr_addr + 8
    try:
        raw = bytes(inf.read_memory(text_addr, min(text_len, 512)))
        text = raw[:text_len].decode('ascii', errors='replace')
    except:
        text = f"<read error at 0x{text_addr:08x}>"
    
    ts_sec = ts / 1e9 if ts > 0 else 0.0
    text = text.replace('\x00', '')
    line = f"[{ts_sec:12.6f}] {text}"
    output_lines.append(line)
    
    # Advance data_offset: header(8) + data block size (round up to 8)
    data_size = (text_len + 7) & ~7
    data_offset += 8 + data_size

# Print all lines
for line in output_lines:
    print(line)

# Also print the last 20 lines which likely contain the crash
print(f"\n=== Total records: {len(output_lines)} ===")

# Check if crash registers are the SAME as Boot 11
print("\n=== Checking characteristic crash values ===")
for line in output_lines:
    if 't1' in line and '8000000000000007' in line:
        print(f"  FOUND t1=8000000000000007: {line.strip()}")
    if 'badaddr' in line:
        print(f"  FOUND badaddr: {line.strip()}")
    if 'strlen' in line:
        print(f"  FOUND strlen: {line.strip()}")

gdb.execute("disconnect")
end
quit
