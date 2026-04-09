set confirm off
set pagination off
python
import os

port = os.environ.get("JLINK_PORT", "12331")
gdb.execute(f"target remote localhost:{port}")
inf = gdb.selected_inferior()

print("\n=== Payload Binary vs DDR Comparison ===\n")

# Read source payload chunk_00 (PA 0x80000000) segments and compare with DDR
# Focus on kernel text area around parameq (PA 0x80231f38) and strlen (PA 0x804fda58)
# Also the banner area (PA 0x80A565EE)

import struct

check_regions = [
    # (name, PA, size, chunk_file, chunk_offset_in_payload)
    # chunk_00 starts at PA 0x80000000
    ("parameq area", 0x80231f00, 128, "/tmp/fw_chunks_allpatch/chunk_00.bin", 0x231f00),
    ("kernel_entry", 0x80200000, 128, "/tmp/fw_chunks_allpatch/chunk_00.bin", 0x200000),
    ("near parameq", 0x80231000, 128, "/tmp/fw_chunks_allpatch/chunk_00.bin", 0x231000),
    # chunk_01 starts at PA 0x80400000
    ("strlen area", 0x804fda00, 128, "/tmp/fw_chunks_allpatch/chunk_01.bin", 0x0fda00),
    # chunk_02 starts at PA 0x80800000
    ("banner area", 0x80A565D0, 64, "/tmp/fw_chunks_allpatch/chunk_02.bin", 0x2565D0),
]

any_mismatch = False

for name, pa, size, chunk_file, chunk_offset in check_regions:
    # Read from DDR via SBA
    try:
        ddr_data = bytes(inf.read_memory(pa, size))
    except:
        print(f"[{name}] FAILED to read DDR at PA 0x{pa:08x}")
        continue
    
    # Read from source file
    try:
        with open(chunk_file, "rb") as f:
            f.seek(chunk_offset)
            file_data = f.read(size)
    except:
        print(f"[{name}] FAILED to read {chunk_file} at offset 0x{chunk_offset:x}")
        continue
    
    if ddr_data == file_data:
        print(f"[{name}] PA 0x{pa:08x}: MATCH ({size} bytes)")
    else:
        any_mismatch = True
        # Find first difference
        diffs = []
        for i in range(min(len(ddr_data), len(file_data))):
            if ddr_data[i] != file_data[i]:
                diffs.append(i)
        print(f"[{name}] PA 0x{pa:08x}: MISMATCH! {len(diffs)} bytes differ")
        for d in diffs[:10]:
            print(f"    offset +{d}: file=0x{file_data[d]:02x} ddr=0x{ddr_data[d]:02x}")
        if len(diffs) > 10:
            print(f"    ... and {len(diffs)-10} more differences")

# Now do a LARGE comparison: read 4KB at several key regions
print("\n--- Large region comparisons (4KB each) ---")
large_regions = [
    ("chunk_00 start (OpenSBI)", 0x80000000, 4096, "/tmp/fw_chunks_allpatch/chunk_00.bin", 0),
    ("kernel text start", 0x80200000, 4096, "/tmp/fw_chunks_allpatch/chunk_00.bin", 0x200000),
    ("kernel text mid", 0x80280000, 4096, "/tmp/fw_chunks_allpatch/chunk_00.bin", 0x280000),
    ("chunk_00/01 boundary area", 0x803FF000, 4096, "/tmp/fw_chunks_allpatch/chunk_00.bin", 0x3FF000),
    ("chunk_01 start", 0x80400000, 4096, "/tmp/fw_chunks_allpatch/chunk_01.bin", 0),
    ("chunk_02 start", 0x80800000, 4096, "/tmp/fw_chunks_allpatch/chunk_02.bin", 0),
    ("chunk_02 mid (rodata)", 0x80A00000, 4096, "/tmp/fw_chunks_allpatch/chunk_02.bin", 0x200000),
    ("chunk_03 start", 0x80C00000, 4096, "/tmp/fw_chunks_allpatch/chunk_03.bin", 0),
]

total_checked = 0
total_mismatched = 0

for name, pa, size, chunk_file, chunk_offset in large_regions:
    try:
        ddr_data = bytes(inf.read_memory(pa, size))
        with open(chunk_file, "rb") as f:
            f.seek(chunk_offset)
            file_data = f.read(size)
    except Exception as e:
        print(f"[{name}] Error: {e}")
        continue
    
    total_checked += size
    diffs = [i for i in range(min(len(ddr_data), len(file_data))) if ddr_data[i] != file_data[i]]
    total_mismatched += len(diffs)
    
    if diffs:
        any_mismatch = True
        print(f"[{name}] PA 0x{pa:08x}: {len(diffs)} diffs in {size} bytes")
        for d in diffs[:5]:
            print(f"    +0x{d:03x}: file=0x{file_data[d]:02x} ddr=0x{ddr_data[d]:02x}")
    else:
        print(f"[{name}] PA 0x{pa:08x}: OK")

print(f"\nTotal: checked {total_checked} bytes, {total_mismatched} mismatches")

if not any_mismatch:
    print("\nAll checked regions MATCH - payload load is correct!")
    print("2-byte duplication is a RUNTIME issue (not loading)")
else:
    print(f"\nFOUND MISMATCHES - payload loading may be corrupting data!")

gdb.execute("disconnect")
end
quit
