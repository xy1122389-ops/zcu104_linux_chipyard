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

echo --- Clearing all triggers and debug state ---\n
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

echo \n=== Phase 1: Restore fw_payload.bin (interleaved SBA + L2 copyback) ===\n
python
import os, gdb, time

COPYBACK_ADDR = 0x81200000
SUB_CHUNK = 256 * 1024

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

# ===== L2 Cache Flush =====
# Evict all stale dirty L2 lines from previous boot by reading+writing
# a scratch region >= L2 capacity (1MB covers up to 1MB L2).
# This ensures CPU reads after SBA writes go to DDR, not stale L2.
L2_FLUSH_BASE = 0x85000000
L2_FLUSH_SIZE = 1024 * 1024  # 1MB
gdb.write(f"[flush] Flushing L2 cache ({L2_FLUSH_SIZE // 1024}KB thrash at 0x{L2_FLUSH_BASE:x})...\n")
gdb.execute(f"set $a0 = 0x{L2_FLUSH_BASE:x}")
gdb.execute(f"set $a1 = 0x{L2_FLUSH_BASE + L2_FLUSH_SIZE:x}")
gdb.execute(f"set $pc = 0x{COPYBACK_ADDR + 4:x}")
gdb.execute(f"hbreak *0x{COPYBACK_ADDR + 0x14:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")
gdb.write("[flush] L2 flush complete\n")

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

        if sub_idx % 4 == 0 or sub_idx == total_sub:
            gdb.write(f"[restore+cb] {sub_idx}/{total_sub}: 0x{mem_addr:08x}+{sub_len//1024}KB  SBA {dt:.1f}s\n")

elapsed_total = time.time() - t_global
gdb.write(f"[ok] fw_payload.bin restored+dirtied in {elapsed_total:.1f}s\n")
end

python
import gdb, os
dtb_default = "/root/chipyard/fpga/linux-bringup/demo-assets/dtb/chipyard-zcu104-linux-withinit.dtb"
dtb_path = os.environ.get("DTB_PATH", dtb_default)
gdb.execute(f"restore {dtb_path} binary 0x84000000")

COPYBACK_ADDR = 0x81200000
dtb_size = os.path.getsize(dtb_path)
dtb_end = (0x84000000 + dtb_size + 63) & ~63
gdb.execute(f"set $a0 = 0x84000000")
gdb.execute(f"set $a1 = 0x{dtb_end:x}")
gdb.execute(f"set $pc = 0x{COPYBACK_ADDR + 4:x}")
gdb.execute(f"hbreak *0x{COPYBACK_ADDR + 0x14:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")
gdb.write(f"[ok] DTB restored+dirtied at 0x84000000\n")
end

python
import gdb
linux_w0 = int(gdb.parse_and_eval("*(unsigned int*)0x80200000"))
osbi_w0 = int(gdb.parse_and_eval("*(unsigned int*)0x80000000"))
dtb_magic = int(gdb.parse_and_eval("*(unsigned int*)0x84000000"))
gdb.write(f"[verify] OpenSBI: 0x{osbi_w0:08x}  Linux: 0x{linux_w0:08x}  DTB: 0x{dtb_magic:08x}\n")
end

echo \n=== Phase 2: Boot OpenSBI -> Linux _start ===\n
set $a0 = 0
set $a1 = 0x84000000
set $a2 = 0
set $pc = 0x80000000

delete breakpoints
hbreak *0x8000ad3c
echo [boot] Running OpenSBI to mret...\n
continue

python
import gdb, re
pc = int(gdb.parse_and_eval("$pc"))
if pc != 0x8000ad3c:
    gdb.write(f"[FAIL] Expected mret at 0x8000ad3c, got 0x{pc:x}\n")
    raise gdb.GdbError("OpenSBI did not reach mret")
gdb.write("[OK] OpenSBI reached mret\n")
gdb.execute("delete breakpoints")
gdb.execute("set $a1 = 0x84000000")
out = gdb.execute("monitor ReadCSR 0x7b0", to_string=True)
m = re.search(r'(?:0x)?([0-9A-Fa-f]{8})', out)
if m:
    old_dcsr = int(m.group(1), 16)
    new_dcsr = old_dcsr & ~((1 << 15) | (1 << 13) | (1 << 12) | (1 << 2))
    gdb.execute(f"monitor WriteCSR 0x7b0 0x{new_dcsr:08X}")
gdb.execute("hbreak *0x80200000")
gdb.write("[boot] Continuing to Linux _start...\n")
gdb.execute("continue")
pc2 = int(gdb.parse_and_eval("$pc"))
gdb.write(f"[boot] Stopped at PC = 0x{pc2:x}\n")
end

echo \n=== Phase 3: Run kernel (long run, no halting) ===\n

python
import gdb, time, os, re, struct

run_secs = int(os.environ.get("KERNEL_RUN_SECS", "1800"))
run_tag = os.environ.get("RUN_TAG", time.strftime("longrun_%Y%m%d_%H%M%S"))

# Clear triggers
for i in range(2):
    gdb.execute(f"monitor WriteCSR 0x7a0 {i}")
    gdb.execute("monitor WriteCSR 0x7a1 0")
    gdb.execute("monitor WriteCSR 0x7a2 0")

gdb.execute("delete breakpoints")
gdb.execute("monitor go")
gdb.write(f"[run] Kernel running for {run_secs}s...\n")

for i in range(0, run_secs, 60):
    chunk = min(60, run_secs - i)
    time.sleep(chunk)
    elapsed = i + chunk
    gdb.write(f"[wait] {elapsed}/{run_secs}s\n")

gdb.write(f"[halt] Halting...\n")
gdb.execute("monitor halt")
time.sleep(2)
try:
    gdb.execute("maintenance flush register-cache")
except:
    pass

pc = int(gdb.parse_and_eval("$pc")) & 0xFFFFFFFFFFFFFFFF
gdb.write(f"[state] PC = 0x{pc:016x}\n")

# Read CSRs
gdb.write("\n=== CSRs ===\n")
csrs = {}
for name, num in [("sepc", 0x141), ("scause", 0x142), ("stval", 0x143),
                  ("satp", 0x180), ("mepc", 0x341), ("mcause", 0x342),
                  ("mtval", 0x343), ("mstatus", 0x300), ("medeleg", 0x302)]:
    out = gdb.execute(f"monitor ReadCSR 0x{num:x}", to_string=True).strip()
    m = re.search(r'(?:0x)?([0-9A-Fa-f]{8,16})', out)
    csrs[name] = int(m.group(1), 16) if m else 0
    gdb.write(f"  {name:10s} = {out}\n")

gdb.write("\n=== GPRs ===\n")
gdb.execute("info reg pc ra sp gp tp a0 a1 a2 s0 s1")

# === Read kernel data via CPU ld (PA-based, goes through D-cache/L2) ===
gdb.write("\n=== Reading kernel data via CPU ld (PA-based) ===\n")

READER = 0x80038000
code = [0x0000100f, 0x00053583, 0x00100073]
for i, insn in enumerate(code):
    gdb.execute(f"set *(unsigned int*)0x{READER + i*4:x} = 0x{insn:08x}")

# Execute fence.i once
gdb.execute(f"set $a0 = 0x{READER:x}")
gdb.execute(f"set $pc = 0x{READER:x}")
gdb.execute(f"hbreak *0x{READER + 8:x}")
gdb.execute("continue")
gdb.execute("delete breakpoints")

def cpu_ld(pa):
    gdb.execute(f"set $a0 = 0x{pa:x}")
    gdb.execute(f"set $pc = 0x{READER + 4:x}")
    gdb.execute(f"hbreak *0x{READER + 8:x}")
    gdb.execute("continue")
    val = int(gdb.parse_and_eval("$a1")) & 0xFFFFFFFFFFFFFFFF
    gdb.execute("delete breakpoints")
    return val

# Compare SBA vs CPU ld for verification
gdb.write("\n--- SBA vs CPU comparison ---\n")
for name, pa in [("OpenSBI", 0x80000000), ("Image", 0x80200000), ("DTB", 0x84000000)]:
    tmp = "/tmp/_cmp.bin"
    gdb.execute(f"dump binary memory {tmp} 0x{pa:x} 0x{pa+8:x}", to_string=True)
    with open(tmp, "rb") as f:
        sba = struct.unpack("<Q", f.read(8))[0]
    cpu = cpu_ld(pa)
    eq = "==" if sba == cpu else "!="
    gdb.write(f"  {name:10s} SBA=0x{sba:016x} CPU=0x{cpu:016x} {eq}\n")

# Read kernel variables at their PAs
# PA = VA - 0xffffffff80000000 + 0x80200000
gdb.write("\n--- Kernel variables (CPU ld from PA) ---\n")

import subprocess
nm = subprocess.run(["/opt/conda/envs/firemarshal/riscv-tools/bin/riscv64-unknown-linux-gnu-nm",
                     "/root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux"],
                    capture_output=True, text=True)

sym_vas = {}
for line in nm.stdout.split('\n'):
    parts = line.split()
    if len(parts) >= 3:
        sym_vas[parts[2]] = int(parts[0], 16)

def va2pa(va):
    return (va - 0xffffffff80000000 + 0x80200000) & 0xFFFFFFFFFFFFFFFF

key_syms = ["log_buf", "log_buf_len", "__log_buf", "saved_command_line", 
            "oops_count", "jiffies_64", "system_state", "nr_threads",
            "init_task", "boot_cpu_data"]

for sym in key_syms:
    if sym in sym_vas:
        va = sym_vas[sym]
        pa = va2pa(va)
        try:
            val = cpu_ld(pa)
            bval = val.to_bytes(8, "little")
            asc = "".join(chr(b) if 32 <= b < 127 else "." for b in bval)
            gdb.write(f"  {sym:25s} VA=0x{va:x} PA=0x{pa:x} = 0x{val:016x} [{asc}]\n")
            
            # SBA comparison
            tmp = "/tmp/_cmp.bin"
            gdb.execute(f"dump binary memory {tmp} 0x{pa:x} 0x{pa+8:x}", to_string=True)
            with open(tmp, "rb") as f:
                sba = struct.unpack("<Q", f.read(8))[0]
            if sba != val:
                gdb.write(f"    ^^^ SBA=0x{sba:016x} DIFFERS from CPU!\n")
        except Exception as e:
            gdb.write(f"  {sym:25s} ERROR: {e}\n")

# Read __log_buf contents (first 256 bytes)
__log_buf_va = sym_vas.get("__log_buf", 0)
if __log_buf_va:
    __log_buf_pa = va2pa(__log_buf_va)
    gdb.write(f"\n--- __log_buf (PA=0x{__log_buf_pa:x}, first 256 bytes via CPU ld) ---\n")
    data = b""
    for off in range(0, 256, 8):
        try:
            w = cpu_ld(__log_buf_pa + off)
            data += w.to_bytes(8, "little")
        except:
            break
    for i in range(0, len(data), 16):
        c = data[i:i+16]
        h = " ".join(f"{b:02x}" for b in c)
        a = "".join(chr(b) if 32 <= b < 127 else "." for b in c)
        gdb.write(f"  {i:04x}: {h:48s} {a}\n")

# Follow log_buf pointer if valid
log_buf_val = None
if "log_buf" in sym_vas:
    try:
        log_buf_val = cpu_ld(va2pa(sym_vas["log_buf"]))
    except:
        pass

if log_buf_val and log_buf_val > 0xffffffc000000000:
    if log_buf_val >= 0xffffffff80000000:
        buf_pa = va2pa(log_buf_val)
    elif log_buf_val >= 0xffffffd800000000:
        buf_pa = log_buf_val - 0xffffffd800000000 + 0x80000000
    else:
        buf_pa = va2pa(log_buf_val)
    
    gdb.write(f"\n--- log_buf content (VA=0x{log_buf_val:x} PA=0x{buf_pa:x}) ---\n")
    data = b""
    for off in range(0, 512, 8):
        try:
            w = cpu_ld(buf_pa + off)
            data += w.to_bytes(8, "little")
        except:
            break
    for i in range(0, len(data), 16):
        c = data[i:i+16]
        h = " ".join(f"{b:02x}" for b in c)
        a = "".join(chr(b) if 32 <= b < 127 else "." for b in c)
        gdb.write(f"  {i:04x}: {h:48s} {a}\n")

# Save summary
summary = f"/tmp/{run_tag}_summary.txt"
with open(summary, "w") as f:
    f.write(f"PC=0x{pc:016x}\n")
    for n, v in csrs.items():
        f.write(f"{n}=0x{v:016x}\n")
gdb.write(f"\n[files] Summary: {summary}\n")
gdb.write("[done] Analysis complete. CPU state is left halted (do not resume).\n")
end

quit
