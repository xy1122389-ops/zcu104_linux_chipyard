set confirm off
set pagination off
python
import os, struct

port = os.environ.get("JLINK_PORT", "12331")
gdb.execute(f"target remote localhost:{port}")
inf = gdb.selected_inferior()

print("=== Initramfs deep analysis ===\n")

# Check DTB at 0x84000000 for initrd properties
dtb_data = bytes(inf.read_memory(0x84000000, 4096))
# Search for "initrd" string in DTB
idx = dtb_data.find(b'linux,initrd')
if idx >= 0:
    print(f"DTB has 'linux,initrd' at offset {idx}")
    print(f"  context: {dtb_data[idx-8:idx+32]}")
else:
    print("DTB does NOT have 'linux,initrd' property (good)")

idx2 = dtb_data.find(b'initrd')
if idx2 >= 0 and idx2 != idx:
    print(f"DTB has 'initrd' reference at offset {idx2}")

# Check __initramfs_start data in DDR
# VA 0xffffffff8060f188 → PA 0x8080f188
initramfs_pa = 0x8080f188
data = bytes(inf.read_memory(initramfs_pa, 64))
print(f"\ninitramfs at PA 0x{initramfs_pa:08x}:")
print(f"  first 64 bytes: {data[:32].hex()}")
print(f"  ascii: {''.join(chr(b) if 32<=b<127 else '.' for b in data[:32])}")
print(f"  CPIO magic check: {'OK' if data[:6] == b'070701' else 'FAIL: '+data[:6].hex()}")

# Check __initramfs_size
# VA 0xffffffff807ca598 → PA 0x809ca598
size_pa = 0x809ca598
size_data = bytes(inf.read_memory(size_pa, 8))
size_val = struct.unpack_from('<I', size_data, 0)[0]  # .long = 4 bytes
size_val_64 = struct.unpack_from('<Q', size_data, 0)[0]
print(f"\n__initramfs_size at PA 0x{size_pa:08x}:")
print(f"  raw: {size_data.hex()}")
print(f"  as .long (4 bytes): {size_val} (0x{size_val:x})")
print(f"  as .quad (8 bytes): {size_val_64} (0x{size_val_64:x})")
print(f"  expected: 1815564 (0x1bb40c)")
print(f"  match: {size_val == 1815564}")

# Verify initramfs data integrity by checking checksum of first 1KB and last 1KB
import hashlib

# First 1KB
first_1k = bytes(inf.read_memory(initramfs_pa, 1024))
first_hash = hashlib.md5(first_1k).hexdigest()
print(f"\nFirst 1KB MD5: {first_hash}")

# Also check CPIO header fields
# CPIO SVR4 header is 110 bytes of hex ASCII
# Format: "070701" + 8-char hex fields
if data[:6] == b'070701':
    fields = {
        'magic': data[0:6],
        'ino': data[6:14],
        'mode': data[14:22],
        'uid': data[22:30],
        'gid': data[30:38],
        'nlink': data[38:46],
        'mtime': data[46:54],
        'filesize': data[54:62],
    }
    for name, val in fields.items():
        print(f"  {name}: {val.decode('ascii', errors='replace')}")

# Check some data in the middle of initramfs (to verify copyback worked)
mid_offset = 1815564 // 2  # middle of initramfs
mid_pa = initramfs_pa + mid_offset
mid_ddr = bytes(inf.read_memory(mid_pa, 16))
print(f"\nMiddle of initramfs (offset {mid_offset}, PA 0x{mid_pa:08x}):")
print(f"  DDR: {mid_ddr.hex()}")

# Compare with payload file
try:
    chunk_idx = (0x80f188 + mid_offset) // (4*1024*1024)
    chunk_off = (0x80f188 + mid_offset) % (4*1024*1024)
    fname = f'/tmp/fw_chunks_allpatch/chunk_{chunk_idx:02d}.bin'
    with open(fname, 'rb') as f:
        f.seek(chunk_off)
        file_data = f.read(16)
    print(f"  File: {file_data.hex()}")
    print(f"  Match: {mid_ddr == file_data}")
except Exception as e:
    print(f"  File comparison error: {e}")

# Check: is initrd_start set in kernel? 
# initrd_start is a kernel variable. Find its PA from the running kernel
# Actually, let me check if kernel CONFIG_BLK_DEV_INITRD is enabled
# by checking if initrd_start symbol exists
# For now, let's check a few addresses

gdb.execute("disconnect")
end
quit
