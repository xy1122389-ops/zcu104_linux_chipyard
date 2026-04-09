set confirm off
set pagination off
python
import os, struct

port = os.environ.get("JLINK_PORT", "12331")
gdb.execute(f"target remote localhost:{port}")
inf = gdb.selected_inferior()

print("\n=== Verify: 2-byte duplication is a klog reading artifact ===\n")

# Theory: printk_sprint() does vscnprintf() directly into ring buffer text_buf,
# then memmove() to strip KERN_LEVEL prefix (2 bytes: "\001" + digit).
# The memmove shifts text left by 2 bytes, leaving the LAST 2 bytes of the
# original text un-overwritten. These appear as "duplication" when reading raw data.
#
# To prove this: read the ring buffer text using text_len from printk_info,
# and verify the text is CORRECT (no duplication).

# From System.Map: _printk_rb_static_infos at PA 0x80E15EF0
# printk_info struct (rv64):
#   +0:  u64 seq
#   +8:  u64 ts_nsec
#   +16: u16 text_len
#   +18: u8 facility
#   +19: u8 flags
#   +20: u8 level
#   +21: 3 bytes padding
#   +24: u32 caller_id
#   +28: struct dev_printk_info (64 bytes)
#   Total: 92 → padded to 96 (8-byte aligned)
# Note: stride was confirmed as 88 (seq=1 at offset 88)

INFO_PA = 0x80E15EF0
INFO_STRIDE = 88  # from earlier scan: next record at offset 88

# Ring buffer text data starts at PA 0x80ED0060 (data ring)
DATA_PA = 0x80ED0060

# Read text data ring (first 4KB)
data_ring = bytes(inf.read_memory(DATA_PA, 4096))

# For each record, read printk_info and extract text using text_len
print("Record | text_len | Raw_end_4 | Clean text (last 30 chars)")
print("-------+----------+-----------+---------------------------")

# Find data blocks by scanning for headers (incrementing IDs)
blocks = []
off = 0
while off < len(data_ring) - 16:
    # Check for data block header pattern: XX f0 ff ff 00 00 00 00
    if data_ring[off+1:off+4] == b'\xf0\xff\xff' and data_ring[off+4:off+8] == b'\x00\x00\x00\x00':
        block_id = data_ring[off]
        text_start = off + 8  # after 8-byte header
        # Find end of text (look for \n or \0 or next header)
        text_end = text_start
        while text_end < len(data_ring) and data_ring[text_end] != 0x00:
            text_end += 1
        raw_text = data_ring[text_start:text_end]
        blocks.append((off, block_id, text_start, raw_text))
        # Skip to next aligned position
        off = (text_end + 8) & ~7
    else:
        off += 8

# Now read printk_info for each block
for i, (blk_off, blk_id, text_start, raw_text) in enumerate(blocks[:15]):
    # Read printk_info for this record
    info_addr = INFO_PA + i * INFO_STRIDE
    try:
        info_data = bytes(inf.read_memory(info_addr, 24))
        seq = struct.unpack_from('<Q', info_data, 0)[0]
        ts = struct.unpack_from('<Q', info_data, 8)[0]
        text_len = struct.unpack_from('<H', info_data, 16)[0]
        facility = info_data[18]
        flags = info_data[19]
        level = info_data[20]
    except:
        print(f"R{i:2d} | ERROR reading info at PA 0x{info_addr:08x}")
        continue
    
    # Extract clean text (using text_len) from ring buffer data
    clean_text = data_ring[text_start:text_start + text_len]
    raw_tail = raw_text[-4:] if len(raw_text) >= 4 else raw_text
    clean_tail = clean_text[-30:] if len(clean_text) >= 30 else clean_text

    # Check for duplication in raw vs clean
    raw_str = raw_text.decode('ascii', errors='replace')
    clean_str = clean_text.decode('ascii', errors='replace')
    
    raw_has_dup = len(raw_text) > text_len
    dup_bytes = raw_text[text_len:text_len+2] if raw_has_dup else b''
    last2_clean = clean_text[-2:] if len(clean_text) >= 2 else b''
    
    dup_marker = ""
    if raw_has_dup and dup_bytes == last2_clean:
        dup_marker = f" ← RAW has +{len(raw_text)-text_len}B (last2='{dup_bytes.decode('ascii','replace')}' MATCHES)"
    elif raw_has_dup:
        dup_marker = f" ← RAW has +{len(raw_text)-text_len}B"
    
    clean_tail_str = clean_str[-40:] if len(clean_str) >= 40 else clean_str
    print(f"R{i:2d} | tl={text_len:3d} seq={seq} | {clean_tail_str}{dup_marker}")

print(f"\n=== Key verification ===")
print("If text_len correctly limits the records, there should be NO duplication")
print("in the 'Clean text' column above.")
print()

# Detailed check for record 0 (linux_banner)
info0 = bytes(inf.read_memory(INFO_PA, 24))
tl0 = struct.unpack_from('<H', info0, 16)[0]
print(f"Record 0: text_len={tl0}")
text0 = data_ring[8:8+tl0]  # skip 8-byte header
text0_str = text0.decode('ascii', errors='replace')
print(f"  Clean text ends with: ...{text0_str[-20:]}")
if text0_str.endswith("CST 2026"):
    print(f"  ✓ CORRECT! No duplication when using text_len!")
elif "202626" in text0_str:
    print(f"  ✗ Still has duplication even with text_len")
else:
    print(f"  ? Unexpected ending")

# Check raw text at same position
raw0 = data_ring[8:8+tl0+4]
print(f"  Raw bytes beyond text_len: {' '.join(f'{b:02x}' for b in raw0[tl0:tl0+4])}")
print(f"  These are STALE bytes from memmove prefix stripping")

gdb.execute("disconnect")
end
quit
