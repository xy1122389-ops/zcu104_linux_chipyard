# Search for linux_banner string in kernel rodata
# Kernel loaded at PA 0x80200000 (VA 0xffffffff80000000)
set confirm off
set pagination off

python
import os
port = os.environ.get("JLINK_PORT", "12331")
gdb.execute(f"target remote localhost:{port}")
end

echo \n=== Search for linux_banner in kernel image ===\n

# Search for "CST 2026" in rodata area (approx PA 0x80500000-0x80700000)
# The banner should contain "CST 2026\n" without duplication

python
import struct

# Search for "CST 2026" pattern in kernel rodata
target = b"CST 2026"
target_dup = b"CST 202626"

# Kernel rodata is typically after text. Read in chunks.
# Text ~3105K = ~0x300000, so rodata starts around 0x80200000 + 0x300000 = 0x80500000
# rodata ~2048K = ~0x200000
found = []
for base in range(0x80500000, 0x80700000, 0x1000):
    try:
        inf = gdb.selected_inferior()
        data = bytes(inf.read_memory(base, 0x1000))
        idx = 0
        while True:
            pos = data.find(b"CST 20", idx)
            if pos < 0:
                break
            # Read context around match
            ctx_start = max(0, pos - 4)
            ctx_end = min(len(data), pos + 20)
            ctx = data[ctx_start:ctx_end]
            addr = base + pos
            found.append((addr, ctx))
            idx = pos + 1
    except:
        pass

if not found:
    # Try broader range
    for base in range(0x80200000, 0x80400000, 0x1000):
        try:
            inf = gdb.selected_inferior()
            data = bytes(inf.read_memory(base, 0x1000))
            idx = 0
            while True:
                pos = data.find(b"CST 20", idx)
                if pos < 0:
                    break
                ctx_start = max(0, pos - 4)
                ctx_end = min(len(data), pos + 20)
                ctx = data[ctx_start:ctx_end]
                addr = base + pos
                found.append((addr, ctx))
                idx = pos + 1
        except:
            pass

print(f"\nFound {len(found)} matches for 'CST 20':")
for addr, ctx in found:
    # Show hex and ASCII
    hex_str = ' '.join(f'{b:02x}' for b in ctx)
    ascii_str = ''.join(chr(b) if 32 <= b < 127 else '.' for b in ctx)
    dup = "DUP!" if b"202626" in ctx else "OK"
    print(f"  0x{addr:08x}: {hex_str}")
    print(f"  ASCII: {ascii_str}  [{dup}]")
end

# Also search for known short string to verify: "detected" vs "detecteded"
python
target_ok = b"detected\n"
target_bad = b"detecteded"

for base in range(0x80500000, 0x80700000, 0x1000):
    try:
        inf = gdb.selected_inferior()
        data = bytes(inf.read_memory(base, 0x1000))
        for pat, label in [(target_ok, "OK"), (target_bad, "DUP")]:
            pos = data.find(pat)
            if pos >= 0:
                addr = base + pos
                ctx = data[max(0,pos-10):pos+len(pat)+4]
                print(f"  [{label}] 0x{addr:08x}: {ctx}")
    except:
        pass
end

echo \n=== Done ===\n
disconnect
quit
