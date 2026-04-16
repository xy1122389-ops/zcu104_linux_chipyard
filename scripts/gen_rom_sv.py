#!/usr/bin/env python3
"""Generate TLROM.sv array content from sdboot.bin"""
import sys, struct

if len(sys.argv) < 2:
    print("Usage: gen_rom_sv.py sdboot.bin [num_entries=1024]")
    sys.exit(1)

binfile = sys.argv[1]
n_entries = int(sys.argv[2]) if len(sys.argv) > 2 else 1024

with open(binfile, 'rb') as f:
    data = f.read()

# Pad to 8-byte boundary
while len(data) % 8:
    data += b'\x00'

# Convert to 64-bit words (little-endian)
words = []
for i in range(0, len(data), 8):
    val = struct.unpack('<Q', data[i:i+8])[0]
    words.append(val)

# Pad to n_entries with zeros
while len(words) < n_entries:
    words.append(0)

# Output in REVERSE order (SystemVerilog packed array: index 1023 first, index 0 last)
# This matches the existing TLROM.sv format
lines = []
for i in range(n_entries - 1, -1, -1):
    prefix = "    '{"  if i == n_entries - 1 else "      "
    suffix = "};" if i == 0 else ","
    val = words[i]
    if val == 0:
        lines.append(f"{prefix}64'h0{suffix}")
    else:
        lines.append(f"{prefix}64'h{val:X}{suffix}")

for line in lines:
    print(line)
