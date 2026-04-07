# linux_reboot_dump.gdb — Quick reboot for minimal kernel
# Assumes DDR already has valid fw_payload.bin from previous full boot.
# Re-restores OpenSBI + key kernel sections, boots, waits, dumps dmesg.

set pagination off
set confirm off
set breakpoint auto-hw off
set remotetimeout 600

file /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf

python
import subprocess, gdb
host = subprocess.check_output(
    ["bash", "-lc", "ip route | awk '/default/ {print $3; exit}'"], text=True
).strip() or "172.19.128.1"
gdb.write(f"[info] Connecting to J-Link at {host}:2331\n")
gdb.execute(f"target remote {host}:2331")
end

monitor halt
echo --- Quick Reboot (minimal kernel) ---\n
info reg pc

monitor WriteCSR 0x180 0
monitor WriteCSR 0x7b0 0x4000F0C3

# fence.i trampoline
set *(unsigned int*)0x80036200 = 0x0000100f
set *(unsigned short*)0x80036204 = 0x9002
set $pc = 0x80036200
stepi
echo [ok] fence.i\n

# Re-restore all chunks (17MB total, only 5 chunks)
python
import os, gdb, time

chunk_dir = "/tmp/fw_chunks_new"
base_addr = 0x80000000
chunk_size = 4194304

chunks = sorted([f for f in os.listdir(chunk_dir) if f.startswith("chunk_") and f.endswith(".bin")])
total = len(chunks)
gdb.write(f"[restore] Re-loading fw_payload.bin in {total} chunks...\n")

for i, fname in enumerate(chunks):
    if i > 0 and i % 4 == 0:
        gdb.write(f"[reconnect] Cycling J-Link...\n")
        gdb.execute("disconnect")
        time.sleep(3)
        gdb.execute("target remote 172.19.128.1:2331")
        gdb.execute("monitor halt")

    addr = base_addr + i * chunk_size
    fpath = os.path.join(chunk_dir, fname)
    fsize = os.path.getsize(fpath)
    gdb.write(f"[restore {i+1}/{total}] {fname} -> 0x{addr:08x} ({fsize} bytes)...\n")
    gdb.execute(f"restore {fpath} binary 0x{addr:x}")

gdb.write("[ok] fw_payload.bin restored\n")
end

restore /root/chipyard/fpga/linux-bringup/demo-assets/dtb/chipyard-zcu104-linux.dtb binary 0x84000000
echo [ok] DTB restored\n

# L2 invalidation for restored region
set *(unsigned int*)0x80036100 = 0x00A63023
set *(unsigned int*)0x80036104 = 0x04050513
set *(unsigned int*)0x80036108 = 0xFEB54CE3
set *(unsigned short*)0x8003610C = 0x9002

set *(unsigned int*)0x80036200 = 0x0000100f
set *(unsigned short*)0x80036204 = 0x9002
set *(unsigned long long*)0x2010200 = 0x80036100
set *(unsigned long long*)0x2010200 = 0x80036140
set *(unsigned long long*)0x2010200 = 0x80036200
set $pc = 0x80036200
stepi

delete breakpoints
hbreak *0x8003610C
set $a0 = 0x80000000
set $a1 = 0x810E0000
set $a2 = 0x2010200
set $pc = 0x80036100
echo [L2inv] Invalidating firmware region...\n
continue
echo [L2inv] done\n

delete breakpoints
hbreak *0x8003610C
set $a0 = 0x84000000
set $a1 = 0x84002000
set $a2 = 0x2010200
set $pc = 0x80036100
continue
echo [L2inv] DTB done\n

# fence.i
set *(unsigned int*)0x80036200 = 0x0000100f
set *(unsigned short*)0x80036204 = 0x9002
set *(unsigned long long*)0x2010200 = 0x80036200
set $pc = 0x80036200
stepi
echo [ok] fence.i\n

# Boot
set $a0 = 0
set $a1 = 0x84000000
set $a2 = 0
set $pc = 0x80000000

delete breakpoints
hbreak *0x8000b2b2
echo [boot] Running OpenSBI to mret...\n
continue

python
import gdb, re, time

pc = int(gdb.parse_and_eval("$pc"))
if pc != 0x8000b2b2:
    gdb.write(f"[FAIL] Expected mret, got 0x{pc:x}\n")
    raise gdb.GdbError("OpenSBI did not reach mret")

gdb.write("[OK] mret reached\n")
gdb.execute("delete breakpoints")
gdb.execute("hbreak *0x80200000")
gdb.execute("continue")
gdb.write(f"[OK] Linux _start\n")
gdb.execute("delete breakpoints")

# Clear dcsr ebreak bits
read_out = gdb.execute("monitor ReadCSR 0x7b0", to_string=True)
m = re.search(r'(?:0x)?([0-9A-Fa-f]{8})', read_out)
old_dcsr = int(m.group(1), 16)
new_dcsr = old_dcsr & ~((1<<15)|(1<<13)|(1<<12))
gdb.execute(f"monitor WriteCSR 0x7b0 0x{new_dcsr:08X}")
gdb.write(f"[dcsr] 0x{old_dcsr:08X} -> 0x{new_dcsr:08X}\n")

# Run kernel
gdb.execute("continue &")
time.sleep(1)
gdb.execute("disconnect")
gdb.write("[boot] Disconnected. Waiting 600s...\n")
time.sleep(600)

gdb.write("[halt] Reconnecting...\n")
gdb.execute("target remote 172.19.128.1:2331")
time.sleep(2)

try:
    pc_val = int(gdb.parse_and_eval("$pc"))
    gdb.write(f"[state] PC = 0x{pc_val & 0xFFFFFFFFFFFFFFFF:016x}\n")
except:
    pass

try:
    gdb.execute("set $satp = 0")
except:
    pass

# Dump dmesg
try:
    log_buf_val = int(gdb.parse_and_eval("*(unsigned long long*)0x810d58f8"))
    log_buf_len = int(gdb.parse_and_eval("*(unsigned int*)0x810d58f0"))
    gdb.write(f"[log] log_buf=0x{log_buf_val:016x} len={log_buf_len}\n")
except:
    log_buf_val = 0
    log_buf_len = 0

if log_buf_val == 0xffffffff80eee348:
    log_pa = 0x810e8348
elif (log_buf_val >> 32) in (0xffffffd8, 0xffffffff):
    log_pa = (log_buf_val - 0xffffffff80000000 + 0x80200000) & 0xFFFFFFFFFFFFFFFF
    if not (0x80000000 <= log_pa <= 0xFFFFFFFF):
        log_pa = 0x810e8348
else:
    log_pa = 0x810e8348

dump_sz = 0x20000
if 0 < log_buf_len <= 0x200000:
    dump_sz = log_buf_len

gdb.execute(f"dump binary memory /tmp/klog_latest.bin {log_pa} {log_pa + dump_sz}")
gdb.write(f"[dump] Saved /tmp/klog_latest.bin ({dump_sz} bytes from 0x{log_pa:x})\n")

gdb.write("[DONE] Reboot complete.\n")
gdb.execute("disconnect")
end

quit
