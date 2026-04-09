set pagination off
set confirm off
set breakpoint auto-hw off
set remotetimeout 600

file /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf

python
import gdb, os, time
host = os.environ.get("JLINK_HOST", "172.19.128.1")
port = int(os.environ.get("JLINK_PORT", "12331"))
gdb.write(f"[info] Connecting to J-Link at {host}:{port}\n")
for attempt in range(1, 4):
    try:
        gdb.execute(f"target remote {host}:{port}")
        gdb.write(f"[info] Connected on attempt {attempt}\n")
        break
    except gdb.error as err:
        gdb.write(f"[warn] Attempt {attempt} failed: {err}\n")
        if attempt == 3: raise
        time.sleep(2)
end

monitor halt
echo --- Initial state ---\n
info reg pc

echo --- Clearing triggers ---\n
monitor WriteCSR 0x7a0 0
monitor WriteCSR 0x7a1 0
monitor WriteCSR 0x7a2 0
monitor WriteCSR 0x7a0 1
monitor WriteCSR 0x7a1 0
monitor WriteCSR 0x7a2 0
monitor WriteCSR 0x7a0 2
monitor WriteCSR 0x7a1 0
monitor WriteCSR 0x7a2 0
monitor WriteCSR 0x7a0 3
monitor WriteCSR 0x7a1 0
monitor WriteCSR 0x7a2 0
monitor WriteCSR 0x180 0
monitor WriteCSR 0x300 0
monitor WriteCSR 0x7b0 0x4000F003

echo \n=== Phase 1: Load payload ===\n
python
import os, gdb, time

COPYBACK_ADDR = 0x81200000
SUB_CHUNK = 256 * 1024

# Install copyback routine: fence.i; ld a1,0(a0); sd a1,0(a0); addi a0,64; blt a0,a1,-12; ebreak
instrs = [
    (COPYBACK_ADDR + 0x00, 0x0000100f),
    (COPYBACK_ADDR + 0x04, 0x00053283),
    (COPYBACK_ADDR + 0x08, 0x00553023),
    (COPYBACK_ADDR + 0x0C, 0x04050513),
    (COPYBACK_ADDR + 0x10, 0xFEB54AE3),
    (COPYBACK_ADDR + 0x14, 0x00100073),
]
for addr, val in instrs:
    gdb.execute(f"set *(unsigned int*)0x{addr:x} = 0x{val:08x}")

# Test copyback
gdb.execute(f"set $a0 = 0x{COPYBACK_ADDR:x}")
gdb.execute(f"set $a1 = 0x{COPYBACK_ADDR + 64:x}")
gdb.execute(f"set $pc = 0x{COPYBACK_ADDR:x}")
gdb.execute(f"hbreak *0x{COPYBACK_ADDR + 0x14:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")

first_copyback = [True]
def run_copyback(start, end_aligned):
    entry = COPYBACK_ADDR if first_copyback[0] else COPYBACK_ADDR + 4
    first_copyback[0] = False
    gdb.execute(f"set $a0 = 0x{start:x}")
    gdb.execute(f"set $a1 = 0x{end_aligned:x}")
    gdb.execute(f"set $pc = 0x{entry:x}")
    gdb.execute(f"hbreak *0x{COPYBACK_ADDR + 0x14:x}")
    gdb.execute("continue")
    gdb.execute("delete breakpoints")

# L2 flush: 1MB thrash
L2_FLUSH_BASE = 0x85000000
L2_FLUSH_SIZE = 1024 * 1024
gdb.write(f"[flush] Flushing L2 cache...\n")
gdb.execute(f"set $a0 = 0x{L2_FLUSH_BASE:x}")
gdb.execute(f"set $a1 = 0x{L2_FLUSH_BASE + L2_FLUSH_SIZE:x}")
gdb.execute(f"set $pc = 0x{COPYBACK_ADDR + 4:x}")
gdb.execute(f"hbreak *0x{COPYBACK_ADDR + 0x14:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")
gdb.write("[flush] Done\n")

# Load payload
chunk_dir = "/tmp/fw_chunks_allpatch"
base_addr = 0x80000000
chunk_size = 4194304
chunks = sorted([f for f in os.listdir(chunk_dir) if f.startswith("chunk_") and f.endswith(".bin")])
total_size = sum(os.path.getsize(os.path.join(chunk_dir, f)) for f in chunks)
total_sub = 0
for f in chunks:
    total_sub += (os.path.getsize(os.path.join(chunk_dir, f)) + SUB_CHUNK - 1) // SUB_CHUNK
gdb.write(f"[restore] Loading {total_size} bytes in {len(chunks)} files, {total_sub} sub-chunks\n")

t_global = time.time()
sub_idx = 0
for i, fname in enumerate(chunks):
    fpath = os.path.join(chunk_dir, fname)
    fsize = os.path.getsize(fpath)
    file_base = base_addr + i * chunk_size
    for offset in range(0, fsize, SUB_CHUNK):
        sub_end = min(offset + SUB_CHUNK, fsize)
        sub_len = sub_end - offset
        mem_addr = file_base + offset
        sub_idx += 1
        t0 = time.time()
        gdb.execute(f"restore {fpath} binary 0x{file_base:x} 0x{offset:x} 0x{sub_end:x}")
        dt = time.time() - t0
        cb_end = (mem_addr + sub_len + 63) & ~63
        run_copyback(mem_addr, cb_end)
        if sub_idx % 8 == 0 or sub_idx == total_sub:
            gdb.write(f"[restore+cb] {sub_idx}/{total_sub}: 0x{mem_addr:08x}+{sub_len//1024}KB  SBA {dt:.1f}s\n")

elapsed_total = time.time() - t_global
gdb.write(f"[ok] Payload loaded in {elapsed_total:.1f}s\n")

# Load DTB
dtb_path = "/root/chipyard/fpga/linux-bringup/demo-assets/dtb/chipyard-zcu104-linux-withinit.dtb"
gdb.execute(f"restore {dtb_path} binary 0x84000000")
dtb_size = os.path.getsize(dtb_path)
dtb_end = (0x84000000 + dtb_size + 63) & ~63
gdb.execute(f"set $a0 = 0x84000000")
gdb.execute(f"set $a1 = 0x{dtb_end:x}")
gdb.execute(f"set $pc = 0x{COPYBACK_ADDR + 4:x}")
gdb.execute(f"hbreak *0x{COPYBACK_ADDR + 0x14:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")
gdb.write("[ok] DTB loaded\n")
end

echo \n=== Phase 2: Boot ===\n
set $a0 = 0
set $a1 = 0x84000000
set $a2 = 0
set $pc = 0x80000000

delete breakpoints
hbreak *0x8000ad3c
echo [boot] OpenSBI...\n
continue

python
import gdb, re
pc = int(gdb.parse_and_eval("$pc"))
if pc != 0x8000ad3c:
    gdb.write(f"[FAIL] mret not reached, PC=0x{pc:x}\n")
    raise gdb.GdbError("Failed")
gdb.write("[OK] mret reached\n")
gdb.execute("delete breakpoints")
gdb.execute("set $a1 = 0x84000000")
out = gdb.execute("monitor ReadCSR 0x7b0", to_string=True)
m = re.search(r'(?:0x)?([0-9A-Fa-f]{8})', out)
if m:
    old = int(m.group(1), 16)
    new = old & ~((1 << 15) | (1 << 13) | (1 << 12) | (1 << 2))
    gdb.execute(f"monitor WriteCSR 0x7b0 0x{new:08X}")
gdb.execute("hbreak *0x80200000")
gdb.execute("continue")
pc2 = int(gdb.parse_and_eval("$pc"))
gdb.write(f"[boot] Linux _start at 0x{pc2:x}\n")
end

echo \n=== Phase 3: Run kernel 120s ===\n
python
import gdb, time

# Clear triggers
for i in range(2):
    gdb.execute(f"monitor WriteCSR 0x7a0 {i}")
    gdb.execute("monitor WriteCSR 0x7a1 0")
    gdb.execute("monitor WriteCSR 0x7a2 0")
gdb.execute("delete breakpoints")
gdb.execute("monitor go")

run_secs = 120
gdb.write(f"[run] Kernel running for {run_secs}s...\n")
for i in range(0, run_secs, 30):
    chunk = min(30, run_secs - i)
    time.sleep(chunk)
    gdb.write(f"[wait] {i+chunk}/{run_secs}s\n")

gdb.write("[halt] Halting...\n")
gdb.execute("monitor halt")
time.sleep(2)

pc = int(gdb.parse_and_eval("$pc")) & 0xFFFFFFFFFFFFFFFF
gdb.write(f"[state] PC=0x{pc:016x}\n")

# CSRs
import re
for name, num in [("satp", 0x180), ("scause", 0x142)]:
    out = gdb.execute(f"monitor ReadCSR 0x{num:x}", to_string=True).strip()
    gdb.write(f"  {name}={out}\n")

gdb.write("\n=== Phase 4: Read kernel log via block copy ===\n")

# Install block copy at 0x81400000 (NOT 0x81200000 which is L2-cached from Phase 1 copyback)
# fence.i; ld a3,0(a0); sd a3,0(a2); addi a0,8; addi a2,8; blt a0,a1,-16; ebreak
BLKCOPY = 0x81400000
for addr, val in [
    (BLKCOPY+0x00, 0x0000100f),
    (BLKCOPY+0x04, 0x00053683),
    (BLKCOPY+0x08, 0x00d63023),
    (BLKCOPY+0x0c, 0x00850513),
    (BLKCOPY+0x10, 0x00860613),
    (BLKCOPY+0x14, 0xFEB548E3),
    (BLKCOPY+0x18, 0x00100073),
]:
    gdb.execute(f"set *(unsigned int*)0x{addr:x} = 0x{val:08x}")

# Read a single 8-byte word via CPU (at uncached address, 2 cache lines after BLKCOPY)
def cpu_ld_one(pa):
    READER = BLKCOPY + 0x80
    gdb.execute(f"set *(unsigned int*)0x{READER:x} = 0x0000100f")
    gdb.execute(f"set *(unsigned int*)0x{READER+4:x} = 0x00053583")
    gdb.execute(f"set *(unsigned int*)0x{READER+8:x} = 0x00100073")
    gdb.execute(f"set $a0 = 0x{pa:x}")
    gdb.execute(f"set $pc = 0x{READER:x}")
    gdb.execute(f"hbreak *0x{READER+8:x}")
    gdb.execute("continue")
    val = int(gdb.parse_and_eval("$a1")) & 0xFFFFFFFFFFFFFFFF
    gdb.execute("delete breakpoints")
    return val

def va2pa(va):
    return (va - 0xffffffff80000000 + 0x80200000) & 0xFFFFFFFFFFFFFFFF

# Read key variables
import subprocess, struct
nm = subprocess.run(["/opt/conda/envs/firemarshal/riscv-tools/bin/riscv64-unknown-linux-gnu-nm",
                     "/root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux"],
                    capture_output=True, text=True)
sym_vas = {}
for line in nm.stdout.split('\n'):
    parts = line.split()
    if len(parts) >= 3:
        sym_vas[parts[2]] = int(parts[0], 16)

# Read just oops_count and system_state (2 CPU ld operations, safe)
for sym in ["oops_count", "system_state"]:
    if sym in sym_vas:
        va = sym_vas[sym]
        pa = va2pa(va)
        try:
            val = cpu_ld_one(pa)
            gdb.write(f"  {sym} = {val} (VA=0x{va:x} PA=0x{pa:x})\n")
        except Exception as e:
            gdb.write(f"  {sym} ERROR: {e}\n")

# Block copy __log_buf (16KB) to buffer then SBA dump
log_buf_pa = va2pa(sym_vas.get("__log_buf", 0))
gdb.write(f"\n[blkcopy] Reading __log_buf at PA 0x{log_buf_pa:x}...\n")
SRC = log_buf_pa
SIZE = 16384
DST = 0x81500000

gdb.execute(f"set $a0 = 0x{SRC:x}")
gdb.execute(f"set $a1 = 0x{SRC + SIZE:x}")
gdb.execute(f"set $a2 = 0x{DST:x}")
gdb.execute(f"set $pc = 0x{BLKCOPY:x}")
gdb.execute(f"hbreak *0x{BLKCOPY + 0x18:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")

outfile = "/tmp/klog_boot7.bin"
gdb.execute(f"dump binary memory {outfile} 0x{DST:x} 0x{DST + SIZE:x}")
gdb.write(f"[ok] Log dumped to {outfile}\n")

# Print first 512 bytes as hex+ascii
with open(outfile, "rb") as f:
    data = f.read(512)
for i in range(0, len(data), 16):
    c = data[i:i+16]
    h = " ".join(f"{b:02x}" for b in c)
    a = "".join(chr(b) if 32 <= b < 127 else "." for b in c)
    gdb.write(f"  {i:04x}: {h:48s} |{a}|\n")

gdb.write("\n[done] Diagnostics complete.\n")
end

quit
