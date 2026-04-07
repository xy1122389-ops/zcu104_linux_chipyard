# sba_verify.gdb — Read back DDR regions and dump for comparison with fw_payload.bin
# Usage: gdb -batch -x scripts/sba_verify.gdb
# After boot run completes (kernel panicked), connect and read back key regions.

set pagination off
set confirm off

python
import gdb, os, struct

gdb.write("\n=== SBA Upload Verification ===\n")

# Connect
gdb.execute("target remote 172.19.128.1:12331")
gdb.write("[OK] Connected\n")

# Halt if running
try:
    gdb.execute("monitor halt")
except:
    pass

FW_PATH = "/root/chipyard/fpga/linux-bringup/payload/fw_payload.bin"
fw_data = open(FW_PATH, "rb").read()
fw_len = len(fw_data)
BASE = 0x80000000

gdb.write(f"[info] fw_payload.bin: {fw_len} bytes\n")

# Verify strategy: sample blocks throughout the firmware image
# Each block = 256 bytes, check every 512KB offset + critical areas
mismatches = 0
total_checked = 0
mismatch_details = []

# Critical regions to check:
# 1. OpenSBI entry (0x80000000)
# 2. Linux _start (0x80200000) 
# 3. initramfs cpio (0x8080f1a8)
# 4. Kernel .rodata (strscpy lives here)
# 5. Kernel .data
# 6. End of firmware

check_offsets = []

# Every 256KB through the firmware
for off in range(0, fw_len, 256 * 1024):
    check_offsets.append(off)

# Critical specific offsets
for critical in [0x0, 0x200000, 0x60f1a8, 0x80f1a8, 0x80f1a8 + 1024, fw_len - 1024]:
    if 0 <= critical < fw_len - 256:
        check_offsets.append(critical)

# Deduplicate and sort
check_offsets = sorted(set(check_offsets))

BLOCK = 256  # bytes per check

for off in check_offsets:
    end = min(off + BLOCK, fw_len)
    actual_len = end - off
    pa = BASE + off
    
    # Read memory via GDB
    try:
        mem = gdb.selected_inferior().read_memory(pa, actual_len)
        mem_bytes = bytes(mem)
    except Exception as e:
        gdb.write(f"[ERROR] Read failed at PA 0x{pa:x}: {e}\n")
        mismatches += 1
        continue
    
    expected = fw_data[off:off+actual_len]
    total_checked += actual_len
    
    if mem_bytes != expected:
        mismatches += 1
        # Find first mismatch byte
        for i in range(actual_len):
            if mem_bytes[i] != expected[i]:
                mismatch_details.append({
                    'offset': off + i,
                    'pa': pa + i,
                    'expected': expected[i],
                    'got': mem_bytes[i],
                })
                gdb.write(f"[MISMATCH] offset=0x{off+i:x} PA=0x{pa+i:x} expected=0x{expected[i]:02x} got=0x{mem_bytes[i]:02x}\n")
                break

gdb.write(f"\n=== Verification Summary ===\n")
gdb.write(f"Checked: {len(check_offsets)} blocks, {total_checked} bytes total\n")
gdb.write(f"Mismatches: {mismatches} blocks\n")

if mismatches == 0:
    gdb.write("[PASS] All sampled blocks match fw_payload.bin\n")
else:
    gdb.write(f"[FAIL] {mismatches} mismatched blocks!\n")
    for d in mismatch_details[:20]:
        gdb.write(f"  offset=0x{d['offset']:x} PA=0x{d['pa']:x} exp=0x{d['expected']:02x} got=0x{d['got']:02x}\n")

# Also do a focused check on the strscpy crash area
# badaddr was 0x800200d8 - this is PA 0x800200d8 (kernel text near _start)
gdb.write(f"\n=== Focused check: PA 0x800200d8 (crash badaddr) ===\n")
try:
    mem = gdb.selected_inferior().read_memory(0x800200d0, 32)
    mem_bytes = bytes(mem)
    expected = fw_data[0x200d0:0x200f0]
    match = "MATCH" if mem_bytes == expected else "MISMATCH"
    gdb.write(f"[{match}] PA 0x800200d0..0x800200ef\n")
    if mem_bytes != expected:
        for i in range(32):
            if mem_bytes[i] != expected[i]:
                gdb.write(f"  byte+{i}: exp=0x{expected[i]:02x} got=0x{mem_bytes[i]:02x}\n")
except Exception as e:
    gdb.write(f"[ERROR] {e}\n")

# Check if DDR at the crash address region was modified by kernel at runtime
# Read the page table entry for VA 0xffffffff800200d8
gdb.write(f"\n=== Check: satp register ===\n")
try:
    satp = int(gdb.parse_and_eval("$satp" if True else "$x0"))
except:
    satp_out = gdb.execute("monitor ReadCSR 0x180", to_string=True)
    import re
    m = re.search(r'(?:0x)?([0-9A-Fa-f]+)', satp_out)
    satp = int(m.group(1), 16) if m else 0
gdb.write(f"satp = 0x{satp:016x}\n")
mode = (satp >> 60) & 0xF
ppn = satp & ((1 << 44) - 1)
gdb.write(f"Mode={mode} (8=Sv39), PPN=0x{ppn:x}, Root PT PA=0x{ppn*4096:x}\n")

gdb.execute("disconnect")
gdb.write("\n=== Done ===\n")
end
