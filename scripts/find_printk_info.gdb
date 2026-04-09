set confirm off
set pagination off
python
import os, struct

port = os.environ.get("JLINK_PORT", "12331")
gdb.execute(f"target remote localhost:{port}")
inf = gdb.selected_inferior()

print("\n=== Printk Descriptor Scan ===\n")

# From System.map (linux-bringup/kernel):
# _printk_rb_static_infos: VA 0xffffffff80c15ef0 → PA = 0x80200000 + 0xc15ef0 = 0x80E15EF0
# _printk_rb_static_descs: VA 0xffffffff80c6def0 → PA = 0x80200000 + 0xc6def0 = 0x80E6DEF0
# __log_buf: VA 0xffffffff80cd4060 → PA 0x80ED4060
#
# But System.map may not match. Let's try scanning near these areas.

# First: we KNOW the text data is at PA 0x80ED0060 (first record header).
# The printk_info struct layout (rv64):
# +0:  u64 seq
# +8:  u64 ts_nsec
# +16: u16 text_len
# +18: u8 facility
# +19: u8 flags
# +20: u8 level
# +21: 3 bytes padding
# +24: u32 caller_id
# +28: struct dev_printk_info (subsystem[16] + device[48]) = 64 bytes
# +92: ... end
# Total size: 88 bytes? Let me compute more carefully.
# Actually: sizeof(printk_info) depends on dev_printk_info size.
# dev_printk_info has: char subsystem[16]; char device[48]; = 64 bytes.
# So printk_info = 8 + 8 + 2 + 1 + 1 + 1 + 3 + 4 + 64 = 92 bytes.
# With padding to next 8-byte boundary: 96 bytes.

# Let's search for printk_info[0] pattern: seq=0 (8 zero bytes), then ts_nsec (nonzero)
# Scan a region around the System.map addresses, +/- 64KB

scan_base = 0x80E00000  # Start scanning from here
scan_size = 0x100000    # 1MB

print(f"Scanning PA 0x{scan_base:08x} - 0x{scan_base+scan_size:08x} for printk_info[0]...")

# Read in 4KB chunks
CHUNK = 4096
found_candidates = []

for offset in range(0, scan_size, CHUNK):
    pa = scan_base + offset
    try:
        data = bytes(inf.read_memory(pa, CHUNK))
    except:
        continue
    
    # Search for pattern: 8 zero bytes (seq=0) + nonzero 8 bytes (ts_nsec) + 
    # text_len around 170-180 + facility=0 + level around 0-7
    for i in range(0, len(data) - 32, 8):  # 8-byte aligned
        # seq = 0
        seq = struct.unpack_from('<Q', data, i)[0]
        if seq != 0:
            continue
        
        # ts_nsec > 0 and reasonable (< 10^18 ns = 10^9 seconds = ~30 years)
        ts = struct.unpack_from('<Q', data, i+8)[0]
        if ts == 0 or ts > 10**18:
            continue
        
        # text_len: plausible values 100-250 (banner is 174 or 176)
        text_len = struct.unpack_from('<H', data, i+16)[0]
        if text_len < 100 or text_len > 250:
            continue
        
        # facility = 0 (kern)
        facility = data[i+18]
        if facility != 0:
            continue
        
        # level in range 0-7
        level = data[i+20]
        if level > 7:
            continue
        
        addr = pa + i
        found_candidates.append((addr, ts, text_len, facility, level))
        print(f"  Candidate at PA 0x{addr:08x}: seq=0 ts={ts} text_len={text_len} facility={facility} level={level}")

if not found_candidates:
    print("  No candidates found in scan range!")
else:
    print(f"\nFound {len(found_candidates)} candidates")
    
    # For each candidate, check seq=1 at next record (offset + printk_info_size)
    # Try sizes: 88, 96, 104
    for info_size in [88, 96, 104, 80, 72]:
        for cand_addr, ts, text_len, fac, lvl in found_candidates:
            next_addr = cand_addr + info_size
            try:
                next_data = bytes(inf.read_memory(next_addr, 32))
                next_seq = struct.unpack_from('<Q', next_data, 0)[0]
                next_ts = struct.unpack_from('<Q', next_data, 8)[0]
                next_text_len = struct.unpack_from('<H', next_data, 16)[0]
                
                if next_seq == 1 and next_ts > ts and 10 < next_text_len < 200:
                    print(f"\n  *** FOUND printk_info array at PA 0x{cand_addr:08x} (info_size={info_size}) ***")
                    print(f"  Record 0: seq=0 ts={ts} text_len={text_len} level={lvl}")
                    print(f"  Record 1: seq=1 ts={next_ts} text_len={next_text_len}")
                    
                    # Read a few more records
                    for rec_idx in range(2, 12):
                        rec_addr = cand_addr + rec_idx * info_size
                        try:
                            rd = bytes(inf.read_memory(rec_addr, 24))
                            rseq = struct.unpack_from('<Q', rd, 0)[0]
                            rts = struct.unpack_from('<Q', rd, 8)[0]
                            rtl = struct.unpack_from('<H', rd, 16)[0]
                            rlvl = rd[20]
                            print(f"  Record {rec_idx}: seq={rseq} text_len={rtl} level={rlvl}")
                        except:
                            break
                    
                    # Compare text_len with known correct/dup values
                    print(f"\n  KEY: text_len for record 0:")
                    print(f"    Stored in descriptor: {text_len}")
                    print(f"    Correct (no dup, no \\n): 174")
                    print(f"    With 2-byte dup (no \\n): 176")
                    print(f"    Correct (with \\n): 175")
                    print(f"    With dup (with \\n): 177")
                    if text_len == 174:
                        print(f"    ==> text_len is CORRECT (174) → memcpy is the bug!")
                    elif text_len == 176:
                        print(f"    ==> text_len is 176 (with dup, \\n stripped) → vsnprintf/strlen returns wrong len!")
                    elif text_len == 175:
                        print(f"    ==> text_len is 175 (correct with \\n) → \\n NOT stripped, then memcpy issue")
                    elif text_len == 177:
                        print(f"    ==> text_len is 177 (dup + \\n) → vsnprintf returns wrong len!")
                    else:
                        print(f"    ==> unexpected value {text_len}")
            except:
                pass

gdb.execute("disconnect")
end
quit
