set confirm off
set pagination off
python
import os, struct

port = os.environ.get("JLINK_PORT", "12331")
gdb.execute(f"target remote localhost:{port}")
inf = gdb.selected_inferior()

print("\n=== Check printk_info at System.map address ===\n")

# From System.map: _printk_rb_static_infos at VA 0xffffffff80c15ef0
# PA = 0x80200000 + 0xc15ef0 = 0x80E15EF0
INFO_PA = 0x80E15EF0

# Read raw data at this address
data = bytes(inf.read_memory(INFO_PA, 512))
print(f"Raw hex at PA 0x{INFO_PA:08x}:")
for off in range(0, 256, 16):
    hex_part = ' '.join(f'{data[off+i]:02x}' for i in range(16))
    print(f"  +{off:03x}: {hex_part}")

# Try to interpret as printk_info with various sizes
for info_size in [72, 80, 88, 96, 104]:
    seq0 = struct.unpack_from('<Q', data, 0)[0]
    ts0 = struct.unpack_from('<Q', data, 8)[0]
    tl0 = struct.unpack_from('<H', data, 16)[0]
    fac0 = data[18]
    flags0 = data[19]
    lvl0 = data[20]
    
    if info_size < len(data):
        seq1 = struct.unpack_from('<Q', data, info_size)[0]
        ts1 = struct.unpack_from('<Q', data, info_size + 8)[0]
        tl1 = struct.unpack_from('<H', data, info_size + 16)[0]
    else:
        seq1, ts1, tl1 = -1, -1, -1
    
    print(f"\n  info_size={info_size}: R0(seq={seq0}, ts={ts0}, tl={tl0}, fac={fac0}, lvl={lvl0}) R1(seq={seq1}, tl={tl1})")

# Also, let me scan for seq=0 more aggressively near __log_buf
# __log_buf found at PA ~0x80ED0060 (ring buffer data)
# Descriptors are typically at lower addresses than the data

print("\n\n=== Scanning near known __log_buf for printk_info ===")
# Scan 0x80E00000 to 0x80ED0000 for pattern:
# 8 bytes = 0 (seq=0), then 8 bytes > 0 (ts), then 2 bytes in [150,200] (text_len)

for scan_pa in range(0x80E00000, 0x80ED0000, 0x1000):
    try:
        block = bytes(inf.read_memory(scan_pa, 0x1000))
    except:
        continue
    
    for off in range(0, len(block) - 128, 8):
        # Pattern: seq=0, ts>0&&ts<10^12, text_len in [150,200], fac=0, lvl=5
        vals = struct.unpack_from('<QQH', block, off)
        seq, ts, tl = vals
        if seq != 0 or ts == 0 or ts > 10**12:
            continue
        if tl < 150 or tl > 200:
            continue
        fac = block[off+18]
        lvl = block[off+20]
        if fac == 0 and lvl == 5:
            addr = scan_pa + off
            print(f"  Found at PA 0x{addr:08x}: seq=0 ts={ts} text_len={tl} fac={fac} lvl={lvl}")
            # Check next records at various stride
            for stride in [72, 80, 88, 96, 104]:
                next_off = off + stride
                if next_off + 24 < len(block):
                    ns = struct.unpack_from('<Q', block, next_off)[0]
                    if ns == 1:
                        nt = struct.unpack_from('<Q', block, next_off+8)[0]
                        ntl = struct.unpack_from('<H', block, next_off+16)[0]
                        print(f"    stride={stride}: next seq=1 ts={nt} text_len={ntl} ← MATCH!")

# Also try broader text_len range with level=5 (NOTICE) 
print("\n=== Broader scan: any text_len, level=5 ===")  
for scan_pa in range(0x80E00000, 0x80ED0000, 0x1000):
    try:
        block = bytes(inf.read_memory(scan_pa, 0x1000))
    except:
        continue
    
    for off in range(0, len(block) - 128, 8):
        vals = struct.unpack_from('<QQH', block, off)
        seq, ts, tl = vals
        if seq != 0 or ts == 0 or ts > 10**12:
            continue
        if tl < 50 or tl > 300:
            continue
        fac = block[off+18]
        lvl = block[off+20]
        if fac == 0 and lvl == 5:
            addr = scan_pa + off
            print(f"  Found at PA 0x{addr:08x}: seq=0 ts={ts} text_len={tl} lvl={lvl}")

gdb.execute("disconnect")
end
quit
