set pagination off
set confirm off
set breakpoint auto-hw off
set remotetimeout 600

file /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf

python
import gdb, os, time
host = "172.19.128.1"
relay_port = 12331
cfg_name = os.environ.get("CHIPYARD_ZCU104_CFG", "")
gdb.write(f"[info] Connecting to J-Link at {host}:{relay_port}\n")
last_error = None
for attempt in range(1, 4):
    try:
        gdb.execute(f"target remote {host}:{relay_port}")
        gdb.write(f"[info] J-Link connected on attempt {attempt}\n")
        last_error = None
        break
    except gdb.error as err:
        last_error = err
        gdb.write(f"[warn] J-Link connect attempt {attempt} failed: {err}\n")
        if attempt < 3:
            time.sleep(2)
if last_error is not None:
    raise last_error
if cfg_name:
    gdb.write(f"[cfg] CHIPYARD_ZCU104_CFG={cfg_name}\n")
end

monitor halt
echo --- Initial state ---\n
info reg pc

monitor WriteCSR 0x180 0
monitor WriteCSR 0x7b0 0x4000F0C3

echo \n=== Phase 1: Restore fw_payload.bin (15MB via SBA) ===\n
python
import os, gdb
chunk_dir = "/tmp/fw_chunks_new"
base_addr = 0x80000000
chunk_size = 4194304
chunks = sorted([f for f in os.listdir(chunk_dir) if f.startswith("chunk_") and f.endswith(".bin")])
gdb.write(f"[restore] Loading fw_payload.bin in {len(chunks)} chunks (4MB each)...\n")
for i, fname in enumerate(chunks):
    addr = base_addr + i * chunk_size
    fpath = os.path.join(chunk_dir, fname)
    fsize = os.path.getsize(fpath)
    gdb.write(f"[restore {i+1}/{len(chunks)}] {fname} -> 0x{addr:08x} ({fsize} bytes)...\n")
    gdb.execute(f"restore {fpath} binary 0x{addr:x}")
    gdb.write(f"[restore {i+1}/{len(chunks)}] done\n")
gdb.write("[ok] fw_payload.bin restored\n")
end

restore /root/chipyard/fpga/linux-bringup/demo-assets/dtb/chipyard-zcu104-linux.dtb binary 0x84000000
echo [ok] DTB restored at 0x84000000\n
python
import gdb
linux_w0 = int(gdb.parse_and_eval("*(unsigned int*)0x80200000"))
osbi_w0 = int(gdb.parse_and_eval("*(unsigned int*)0x80000000"))
dtb_magic = int(gdb.parse_and_eval("*(unsigned int*)0x84000000"))
gdb.write(f"[verify] OpenSBI entry: 0x{osbi_w0:08x}\n")
gdb.write(f"[verify] Linux _start: 0x{linux_w0:08x}\n")
gdb.write(f"[verify] DTB magic: 0x{dtb_magic:08x}\n")
end

echo \n=== Phase 2: Boot OpenSBI -> Linux ===\n
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
gdb.execute("hbreak *0x80200000")
gdb.write("[boot] Continuing from mret to Linux _start...\n")
gdb.execute("continue")
pc2 = int(gdb.parse_and_eval("$pc"))
gdb.write(f"[boot] Stopped at PC = 0x{pc2:x}\n")
if pc2 != 0x80200000:
    gdb.write("[WARN] Did not stop at Linux _start as expected\n")
end

python
import gdb
gdb.write("\n=== Phase 3: Repair initramfs at do_populate_rootfs ===\n")
gdb.execute("delete breakpoints")
gdb.execute("hbreak *0x80402c0c")
gdb.write("[boot] Running to do_populate_rootfs...\n")
gdb.execute("continue")
pc = int(gdb.parse_and_eval("$pc"))
gdb.write(f"[boot] Stopped at PC = 0x{pc & 0xFFFFFFFFFFFFFFFF:016x}\n")
if pc != 0x80402c0c:
    gdb.write("[WARN] Did not stop at do_populate_rootfs as expected\n")
else:
    gdb.execute("delete breakpoints")
    gdb.execute("restore /tmp/initramfs_region.bin binary 0x8080f1a8")
    cpio_w0 = int(gdb.parse_and_eval("*(unsigned int*)0x8080f1a8"))
    cpio_w1 = int(gdb.parse_and_eval("*(unsigned int*)0x8080f1ac"))
    gdb.write(f"[repair] Initramfs magic after restore: 0x{cpio_w0:08x} 0x{cpio_w1:08x}\n")
end

python
import gdb, os, time
KERNEL_RUN_SECS = int(os.environ.get("KERNEL_RUN_SECS", "120"))
gdb.write(f"\n=== Phase 4: Launch kernel (run {KERNEL_RUN_SECS}s then dump klog) ===\n")
for trig_idx in range(2):
    gdb.execute(f"monitor WriteCSR 0x7a0 {trig_idx}")
    gdb.execute("monitor WriteCSR 0x7a1 0")
    gdb.execute("monitor WriteCSR 0x7a2 0")
gdb.write("[OK] Hardware triggers cleared\n")
gdb.execute("monitor go")
gdb.write("[boot] Kernel running (via monitor go)...\n")
time.sleep(KERNEL_RUN_SECS)
gdb.write(f"[boot] {KERNEL_RUN_SECS}s elapsed. Halting kernel...\n")
gdb.execute("monitor halt")
time.sleep(2)
try:
    pc = int(gdb.parse_and_eval("$pc"))
    gdb.write(f"[boot] Target halted at PC = 0x{pc & 0xFFFFFFFFFFFFFFFF:016x}\n")
except Exception as err:
    gdb.write(f"[boot] PC read failed: {err}\n")
end

python
import gdb, re, os, time
LOG_PA = 0x80ed4060
LOG_LEN = 0x20000
RUN_TAG = os.environ.get("RUN_TAG", time.strftime("run_%Y%m%d_%H%M%S"))
KLOG_BIN = f"/tmp/klog_{RUN_TAG}.bin"
LOG_FILE = f"/tmp/boot_{RUN_TAG}.strings"
gdb.write("\n=== Phase 5: Dump kernel log ===\n")
try:
    gdb.execute("set $satp = 0")
except:
    pass
gdb.execute(f"dump binary memory {KLOG_BIN} {LOG_PA} {LOG_PA + LOG_LEN}")
gdb.execute(f"dump binary memory /tmp/klog_latest.bin {LOG_PA} {LOG_PA + LOG_LEN}")
data = open(KLOG_BIN, "rb").read()
strings = re.findall(rb'[\x20-\x7e]{8,}', data)
with open(LOG_FILE, "w") as f:
    for i, s in enumerate(strings):
        line = s.decode("ascii", errors="replace")
        f.write(f"{i:4d}: {line}\n")
        if i < 80 or i >= max(len(strings) - 20, 80):
            gdb.write(f"  {i:4d}: {line[:120]}\n")
gdb.write(f"[strings] Found {len(strings)} strings\n")
gdb.write(f"[files] klog binary: {KLOG_BIN}\n")
gdb.write(f"[files] klog strings: {LOG_FILE}\n")
end
