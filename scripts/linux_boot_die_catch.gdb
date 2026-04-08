set pagination off
set confirm off
set breakpoint auto-hw off
set remotetimeout 600

file /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf

python
import gdb, os, time
host = os.environ.get("JLINK_HOST", "172.19.128.1")
port = int(os.environ.get("JLINK_PORT", "2331"))
gdb.write(f"[info] Connecting to J-Link at {host}:{port}\n")
last_error = None
for attempt in range(1, 4):
    try:
        gdb.execute(f"target remote {host}:{port}")
        gdb.write(f"[info] Connected on attempt {attempt}\n")
        last_error = None
        break
    except gdb.error as err:
        last_error = err
        gdb.write(f"[warn] Attempt {attempt} failed: {err}\n")
        if attempt < 3:
            time.sleep(2)
if last_error is not None:
    raise last_error
end

monitor halt
echo --- Initial state ---\n
info reg pc
monitor WriteCSR 0x180 0
monitor WriteCSR 0x7b0 0x4000F0C3

echo \n=== Phase 1: Restore fw_payload.bin (interleaved SBA + L2 copyback) ===\n
python
import os, gdb, time

# --- L2 cache parameters ---
# SiFive InclusiveCache: 512KB, 8-way, 1024 sets, 64B lines = 8192 lines total
# SBA writes create CLEAN L2 lines lost on eviction.
# Strategy: write 256KB via SBA, then immediately copyback (ld+sd) to make dirty.
# 256KB = 4096 lines = 4 lines/set (out of 8 ways), safe from self-eviction.

COPYBACK_ADDR = 0x80F00000
SUB_CHUNK = 256 * 1024  # 256KB sub-chunks for interleaved write+copyback

# Write the copyback routine via SBA (6 instructions = 24 bytes)
instrs = [
    (COPYBACK_ADDR + 0x00, 0x0000100f),  # fence.i
    (COPYBACK_ADDR + 0x04, 0x00053283),  # ld t0, 0(a0)
    (COPYBACK_ADDR + 0x08, 0x00553023),  # sd t0, 0(a0)
    (COPYBACK_ADDR + 0x0C, 0x04050513),  # addi a0, a0, 64
    (COPYBACK_ADDR + 0x10, 0xFEB54AE3),  # blt a0, a1, -12
    (COPYBACK_ADDR + 0x14, 0x00100073),  # ebreak
]
for addr, val in instrs:
    gdb.execute(f"set *(unsigned int*)0x{addr:x} = 0x{val:08x}")

# Copyback the routine itself (1 cache line) so it survives
gdb.execute(f"set $a0 = 0x{COPYBACK_ADDR:x}")
gdb.execute(f"set $a1 = 0x{COPYBACK_ADDR + 64:x}")
gdb.execute(f"set $pc = 0x{COPYBACK_ADDR:x}")   # starts with fence.i
gdb.execute(f"hbreak *0x{COPYBACK_ADDR + 0x14:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")
gdb.write("[copyback] Routine at 0x{:08x} written and dirtied\n".format(COPYBACK_ADDR))

# Helper: run copyback on [start_addr, end_addr_aligned)
first_copyback = [True]  # use fence.i only on first call
def run_copyback(start, end_aligned):
    n = (end_aligned - start) // 64
    entry = COPYBACK_ADDR if first_copyback[0] else COPYBACK_ADDR + 4
    first_copyback[0] = False
    gdb.execute(f"set $a0 = 0x{start:x}")
    gdb.execute(f"set $a1 = 0x{end_aligned:x}")
    gdb.execute(f"set $pc = 0x{entry:x}")
    gdb.execute(f"hbreak *0x{COPYBACK_ADDR + 0x14:x}")
    gdb.execute("continue")
    a0_after = int(gdb.parse_and_eval("$a0")) & 0xFFFFFFFFFFFFFFFF
    gdb.execute("delete breakpoints")
    if a0_after < end_aligned:
        gdb.write(f"[WARN] copyback incomplete: a0=0x{a0_after:x} expected 0x{end_aligned:x}\n")

# --- Load payload with interleaved copyback ---
chunk_dir = "/tmp/fw_chunks_new"
base_addr = 0x80000000
chunk_size = 4194304  # 4MB per file chunk
chunks = sorted([f for f in os.listdir(chunk_dir) if f.startswith("chunk_") and f.endswith(".bin")])

total_size = sum(os.path.getsize(os.path.join(chunk_dir, f)) for f in chunks)
total_sub = 0
for f in chunks:
    total_sub += (os.path.getsize(os.path.join(chunk_dir, f)) + SUB_CHUNK - 1) // SUB_CHUNK
gdb.write(f"[restore] Loading {total_size} bytes in {len(chunks)} files, {total_sub} sub-chunks of {SUB_CHUNK//1024}KB each\n")

t_global = time.time()
sub_idx = 0
for i, fname in enumerate(chunks):
    fpath = os.path.join(chunk_dir, fname)
    fsize = os.path.getsize(fpath)
    file_base = base_addr + i * chunk_size  # bias for restore command

    for offset in range(0, fsize, SUB_CHUNK):
        sub_end = min(offset + SUB_CHUNK, fsize)
        sub_len = sub_end - offset
        mem_addr = file_base + offset
        sub_idx += 1

        t0 = time.time()
        gdb.execute(f"restore {fpath} binary 0x{file_base:x} 0x{offset:x} 0x{sub_end:x}")
        dt = time.time() - t0

        # Immediately copyback this sub-chunk
        cb_end = (mem_addr + sub_len + 63) & ~63
        run_copyback(mem_addr, cb_end)

        if sub_idx % 4 == 0 or sub_idx == total_sub:
            gdb.write(f"[restore+cb] {sub_idx}/{total_sub}: 0x{mem_addr:08x}+{sub_len//1024}KB  SBA {dt:.1f}s\n")

elapsed_total = time.time() - t_global
gdb.write(f"[ok] fw_payload.bin restored+dirtied in {elapsed_total:.1f}s\n")
end

python
import gdb, os
dtb_default = "/root/chipyard/fpga/linux-bringup/demo-assets/dtb/chipyard-zcu104-linux-withinit.dtb"
dtb_path = os.environ.get("DTB_PATH", dtb_default)
gdb.write(f"[dtb] Using: {dtb_path}\n")
gdb.execute(f"restore {dtb_path} binary 0x84000000")

# Copyback DTB immediately (< 4KB = 66 cache lines, trivial)
COPYBACK_ADDR = 0x80F00000
dtb_size = os.path.getsize(dtb_path)
dtb_end = (0x84000000 + dtb_size + 63) & ~63
gdb.execute(f"set $a0 = 0x84000000")
gdb.execute(f"set $a1 = 0x{dtb_end:x}")
gdb.execute(f"set $pc = 0x{COPYBACK_ADDR + 4:x}")
gdb.execute(f"hbreak *0x{COPYBACK_ADDR + 0x14:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")
gdb.write(f"[ok] DTB restored+dirtied at 0x84000000 ({dtb_size} bytes)\n")
end

python
import gdb
linux_w0 = int(gdb.parse_and_eval("*(unsigned int*)0x80200000"))
osbi_w0 = int(gdb.parse_and_eval("*(unsigned int*)0x80000000"))
dtb_magic = int(gdb.parse_and_eval("*(unsigned int*)0x84000000"))
gdb.write(f"[verify] OpenSBI entry: 0x{osbi_w0:08x}\n")
gdb.write(f"[verify] Linux _start: 0x{linux_w0:08x}\n")
gdb.write(f"[verify] DTB magic: 0x{dtb_magic:08x}\n")
end

echo \n=== Phase 2: Boot OpenSBI -> Linux _start ===\n
set $a0 = 0
set $a1 = 0x84000000
set $a2 = 0
set $pc = 0x80000000

delete breakpoints
hbreak *0x8000b2b2
echo [boot] Running OpenSBI to mret...\n
continue

python
import gdb, re
pc = int(gdb.parse_and_eval("$pc"))
if pc != 0x8000b2b2:
    gdb.write(f"[FAIL] Expected mret at 0x8000b2b2, got 0x{pc:x}\n")
    gdb.execute("info reg pc ra sp a0 a1 a2")
    gdb.execute("x/8i $pc")
    raise gdb.GdbError("OpenSBI did not reach mret")
gdb.write("[OK] OpenSBI reached mret\n")
gdb.execute("delete breakpoints")
gdb.execute("set $a1 = 0x84000000")
out = gdb.execute("monitor ReadCSR 0x7b0", to_string=True)
m = re.search(r'(?:0x)?([0-9A-Fa-f]{8})', out)
if m:
    old_dcsr = int(m.group(1), 16)
    new_dcsr = old_dcsr & ~((1 << 15) | (1 << 13) | (1 << 12) | (1 << 2))
    gdb.write(f"[dcsr] old=0x{old_dcsr:08X} -> new=0x{new_dcsr:08X}\n")
    gdb.execute(f"monitor WriteCSR 0x7b0 0x{new_dcsr:08X}")
else:
    gdb.write(f"[dcsr] parse failed: {out.strip()}\n")
gdb.execute("hbreak *0x80200000")
gdb.write("[boot] Continuing from mret to Linux _start...\n")
gdb.execute("continue")
pc2 = int(gdb.parse_and_eval("$pc"))
gdb.write(f"[boot] Stopped at PC = 0x{pc2:x}\n")
if pc2 != 0x80200000:
    gdb.write("[WARN] Did not stop at Linux _start as expected\n")
end

echo \n=== Phase 3: Set hbreak at die(), continue, catch crash ===\n
symbol-file /root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux

python
import gdb, re

# Clear hardware triggers first
for trig_idx in range(2):
    gdb.execute(f"monitor WriteCSR 0x7a0 {trig_idx}")
    gdb.execute("monitor WriteCSR 0x7a1 0")
    gdb.execute("monitor WriteCSR 0x7a2 0")
gdb.write("[OK] Hardware triggers cleared\n")
end

# Set hbreak at die() VA - will fire once MMU is on and kernel hits die()
delete breakpoints
hbreak *0xffffffff8000480e
echo [boot] hbreak at die() set, continuing kernel boot...\n
continue

echo \n=== Caught die() - dumping full state ===\n

python
import gdb, re, time

def read_csr(csr_num):
    out = gdb.execute(f"monitor ReadCSR 0x{csr_num:x}", to_string=True)
    m = re.search(r'(?:0x)?([0-9A-Fa-f]{8,16})', out)
    return (int(m.group(1), 16) if m else None, out.strip())

pc = int(gdb.parse_and_eval("$pc")) & 0xFFFFFFFFFFFFFFFF
gdb.write(f"[die] PC = 0x{pc:016x}\n")

# Check if we actually stopped at die
if pc != 0xffffffff8000480e:
    gdb.write(f"[WARN] PC is NOT at die() - unexpected stop\n")

# Dump all GPRs
gdb.execute("info reg pc ra sp gp tp t0 t1 t2 s0 s1 a0 a1 a2 a3 a4 a5 a6 a7 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 t3 t4 t5 t6")

# Dump critical CSRs
for name, num in [("sepc", 0x141), ("scause", 0x142), ("stval", 0x143), 
                  ("satp", 0x180), ("sstatus", 0x100), ("stvec", 0x105),
                  ("sscratch", 0x140), ("mepc", 0x341), ("mcause", 0x342),
                  ("mtval", 0x343), ("mstatus", 0x300)]:
    val, raw = read_csr(num)
    gdb.write(f"[csr] {name:10s} = {raw}\n")

# Try backtrace
gdb.write("\n[die] Backtrace:\n")
try:
    gdb.execute("bt 20")
except gdb.error as err:
    gdb.write(f"[bt] unavailable: {err}\n")

# Disassemble at PC
gdb.write("\n[die] Disassembly at PC:\n")
try:
    gdb.execute("x/8i $pc")
except gdb.error as err:
    gdb.write(f"[disasm] error: {err}\n")

# Inspect die() arguments: a0 = struct pt_regs*, a1 = const char *msg
gdb.write("\n[die] Arguments:\n")
try:
    regs_ptr = int(gdb.parse_and_eval("$a0")) & 0xFFFFFFFFFFFFFFFF
    msg_ptr = int(gdb.parse_and_eval("$a1")) & 0xFFFFFFFFFFFFFFFF
    gdb.write(f"  a0 (pt_regs*) = 0x{regs_ptr:016x}\n")
    gdb.write(f"  a1 (msg)      = 0x{msg_ptr:016x}\n")
    # Try to read the message string
    gdb.execute(f"x/s 0x{msg_ptr:x}")
    # Dump pt_regs: 32 GPRs + sepc + sstatus = 34 entries × 8 bytes
    gdb.write("\n[die] pt_regs dump (saved regs at exception time):\n")
    reg_names = ["zero/epc", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
                 "s0/fp", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
                 "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
                 "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6",
                 "sepc", "sstatus", "badaddr", "cause"]
    for j in range(min(36, len(reg_names))):
        val = int(gdb.parse_and_eval(f"*(unsigned long long*)(0x{regs_ptr:x} + {j*8})")) & 0xFFFFFFFFFFFFFFFF
        gdb.write(f"  pt_regs[{j:2d}] {reg_names[j]:10s} = 0x{val:016x}\n")
except gdb.error as err:
    gdb.write(f"  [error reading die args: {err}]\n")

gdb.write("\n[die] Done. CPU halted at die() entry.\n")
end

quit
