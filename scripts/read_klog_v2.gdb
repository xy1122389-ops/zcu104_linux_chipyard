set pagination off
set confirm off
set remotetimeout 60

target remote 172.19.128.1:12331
monitor halt

echo --- Reading kernel log ---\n

python
import gdb

# Block copy routine at UNCACHED address (not 0x81200000 which has L2 cached copyback)
BLKCOPY = 0x81400000
for addr, val in [
    (BLKCOPY+0x00, 0x0000100f),  # fence.i
    (BLKCOPY+0x04, 0x00053683),  # ld a3, 0(a0)
    (BLKCOPY+0x08, 0x00d63023),  # sd a3, 0(a2)
    (BLKCOPY+0x0c, 0x00850513),  # addi a0, a0, 8
    (BLKCOPY+0x10, 0x00860613),  # addi a2, a2, 8
    (BLKCOPY+0x14, 0xFEB548E3),  # blt a0, a1, -16
    (BLKCOPY+0x18, 0x00100073),  # ebreak
]:
    gdb.execute(f"set *(unsigned int*)0x{addr:x} = 0x{val:08x}")

# First, copyback the instruction area to ensure L2 has the new code
# Use the OLD copyback at 0x81200000 (which is still cached OK in L2)
# It does: fence.i, ld a1 0(a0), sd a1 0(a0), addi a0 64, blt, ebreak
gdb.execute(f"set $a0 = 0x{BLKCOPY:x}")
gdb.execute(f"set $a1 = 0x{BLKCOPY + 64:x}")
gdb.execute(f"set $pc = 0x81200004")  # skip fence.i (already cached)
gdb.execute(f"hbreak *0x81200014")
gdb.execute("continue")
gdb.execute("delete breakpoints")
gdb.write("[ok] Block copy code installed and cached in L2\n")

# Now block-copy 16KB from __log_buf (PA 0x80ed0060) to buffer (PA 0x81500000)
SRC = 0x80ed0060
SIZE = 16384
DST = 0x81500000

gdb.execute(f"set $a0 = 0x{SRC:x}")
gdb.execute(f"set $a1 = 0x{SRC + SIZE:x}")
gdb.execute(f"set $a2 = 0x{DST:x}")
gdb.execute(f"set $pc = 0x{BLKCOPY:x}")
gdb.execute(f"hbreak *0x{BLKCOPY + 0x18:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")
gdb.write("[ok] Block copy done\n")

# Now copyback destination to ensure SBA can read it
gdb.execute(f"set $a0 = 0x{DST:x}")
gdb.execute(f"set $a1 = 0x{DST + SIZE:x}")
gdb.execute("set $pc = 0x81200004")
gdb.execute("hbreak *0x81200014")
gdb.execute("continue")
gdb.execute("delete breakpoints")
gdb.write("[ok] Destination copybacked\n")

# SBA dump
outfile = "/tmp/klog_boot7.bin"
gdb.execute(f"dump binary memory {outfile} 0x{DST:x} 0x{DST + SIZE:x}")
gdb.write(f"[ok] Dumped to {outfile}\n")

# Print first 1024 bytes
with open(outfile, "rb") as f:
    data = f.read(1024)
for i in range(0, len(data), 16):
    c = data[i:i+16]
    h = " ".join(f"{b:02x}" for b in c)
    a = "".join(chr(b) if 32 <= b < 127 else "." for b in c)
    gdb.write(f"  {i:04x}: {h:48s} |{a}|\n")

gdb.write("[done]\n")
end

quit
