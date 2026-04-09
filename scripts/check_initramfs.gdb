set confirm off
set pagination off
python
import os, struct

port = os.environ.get("JLINK_PORT", "12331")
gdb.execute(f"target remote localhost:{port}")
inf = gdb.selected_inferior()

print("=== Initramfs data verification ===\n")

# From System.Map: __initramfs_start VA = 0xffffffff8060f1a8
# PA = VA - 0xffffffff80000000 + 0x80200000 = 0x8080f1a8
initramfs_pa = 0x8080f1a8

# Read first 32 bytes
data = bytes(inf.read_memory(initramfs_pa, 32))
print(f"initramfs data at PA 0x{initramfs_pa:08x} (from System.Map):")
print(f"  hex: {' '.join(f'{b:02x}' for b in data)}")
print(f"  ascii: {''.join(chr(b) if 32 <= b < 127 else '.' for b in data)}")

# Check CPIO magic "070701"
if data[:6] == b'070701':
    print("  *** CPIO MAGIC OK ***")
else:
    print(f"  CPIO magic MISMATCH: expected '070701', got '{data[:6]}'")

# Also search for CPIO magic in nearby addresses (System.Map offset might be wrong)
# Search the payload for "070701" pattern
print("\n--- Searching for CPIO magic '070701' in payload ---")
SEARCH_STEP = 4096
found_addrs = []
for search_base in range(0x80600000, 0x80C00000, SEARCH_STEP):
    try:
        chunk = bytes(inf.read_memory(search_base, SEARCH_STEP))
        idx = 0
        while True:
            pos = chunk.find(b'070701', idx)
            if pos < 0:
                break
            addr = search_base + pos
            # Verify it's really the start of a CPIO archive (not in the middle)
            # Check that the next field (inode) is reasonable
            found_addrs.append(addr)
            idx = pos + 1
    except:
        pass
    if len(found_addrs) > 20:
        break

print(f"Found {len(found_addrs)} occurrences of CPIO magic")
for addr in found_addrs[:10]:
    data = bytes(inf.read_memory(addr, 32))
    print(f"  0x{addr:08x}: {data[:16].decode('ascii', errors='replace')}")

# Also check the initramfs data from the actual payload file
# Read from the chunk file to compare
print("\n--- Payload binary comparison ---")
chunk_2_start = 0x80800000  # chunk_02 covers 8-12MB of payload (PA 0x80800000-0x80C00000)
initramfs_offset_in_chunk2 = initramfs_pa - chunk_2_start
print(f"initramfs offset in chunk_02: 0x{initramfs_offset_in_chunk2:x}")

# Read the payload file bytes at the corresponding offset
try:
    with open('/tmp/fw_chunks_allpatch/chunk_02.bin', 'rb') as f:
        f.seek(initramfs_offset_in_chunk2)
        file_data = f.read(32)
    print(f"From chunk file: {' '.join(f'{b:02x}' for b in file_data)}")
    print(f"       ascii:    {''.join(chr(b) if 32 <= b < 127 else '.' for b in file_data)}")
    print(f"From DDR:        {' '.join(f'{b:02x}' for b in data[:32] if data)}")
except Exception as e:
    print(f"Error: {e}")

gdb.execute("disconnect")
end
quit
