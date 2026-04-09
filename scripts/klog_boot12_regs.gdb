set confirm off
set pagination off
python
import os, struct

port = os.environ.get("JLINK_PORT", "12331")
gdb.execute(f"target remote localhost:{port}")
inf = gdb.selected_inferior()

# Read records with register dumps (records around the crash)
INFO_PA = 0x80E15EF0
STRIDE = 88
DATA_PA = 0x80ED0060

# First, build offset table
data_offset = 0
record_offsets = []
for idx in range(120):
    info_addr = INFO_PA + idx * STRIDE
    try:
        info_data = bytes(inf.read_memory(info_addr, 24))
    except:
        break
    seq = struct.unpack_from('<Q', info_data, 0)[0]
    text_len = struct.unpack_from('<H', info_data, 16)[0]
    if seq != idx or text_len == 0 or text_len > 2000:
        break
    record_offsets.append((idx, text_len, data_offset))
    data_size = (text_len + 7) & ~7
    data_offset += 8 + data_size

print(f"Total records: {len(record_offsets)}")

# Find records containing register info (look for "t1" "t0" "epc" etc.)
for idx, text_len, d_off in record_offsets:
    text_addr = DATA_PA + d_off + 8
    try:
        raw = bytes(inf.read_memory(text_addr, min(text_len, 512)))
        text = raw[:text_len].decode('ascii', errors='replace').replace('\x00', '')
    except:
        continue
    
    # Print records that contain register info or crash info
    if any(k in text for k in ['t0 :', 't1 :', 'epc :', 'badaddr', 'strlen', 'Unable to handle', 'ra :', 'Oops']):
        ts_addr = INFO_PA + idx * STRIDE + 8
        ts_data = bytes(inf.read_memory(ts_addr, 8))
        ts = struct.unpack_from('<Q', ts_data, 0)[0]
        ts_sec = ts / 1e9 if ts > 0 else 0.0
        print(f"[{ts_sec:12.6f}] R{idx:3d}: {text}")

gdb.execute("disconnect")
end
quit
