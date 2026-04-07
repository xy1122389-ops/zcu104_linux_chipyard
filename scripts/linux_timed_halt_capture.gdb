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

echo \n=== Phase 1: Restore fw_payload.bin ===\n
python
import os, gdb, time
chunk_dir = "/tmp/fw_chunks_new"
base_addr = 0x80000000
chunk_size = 4194304
chunks = sorted([f for f in os.listdir(chunk_dir) if f.startswith("chunk_") and f.endswith(".bin")])
gdb.write(f"[restore] Loading fw_payload.bin in {len(chunks)} chunks...\n")
for i, fname in enumerate(chunks):
    addr = base_addr + i * chunk_size
    fpath = os.path.join(chunk_dir, fname)
    fsize = os.path.getsize(fpath)
    gdb.write(f"[restore {i+1}/{len(chunks)}] {fname} -> 0x{addr:08x} ({fsize} bytes)...\n")
    t0 = time.time()
    gdb.execute(f"restore {fpath} binary 0x{addr:x}")
    elapsed = time.time() - t0
    gdb.write(f"[restore {i+1}/{len(chunks)}] done in {elapsed:.1f}s\n")
    if i + 1 < len(chunks):
        time.sleep(0.2)
gdb.write("[ok] fw_payload.bin restored\n")
end

python
import gdb, os
dtb_default = "/root/chipyard/fpga/linux-bringup/demo-assets/dtb/chipyard-zcu104-linux-withinit.dtb"
dtb_path = os.environ.get("DTB_PATH", dtb_default)
gdb.write(f"[dtb] Using: {dtb_path}\n")
gdb.execute(f"restore {dtb_path} binary 0x84000000")
end

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

echo \n=== Phase 3: Run kernel for a short window, then halt ===\n
symbol-file /root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux

python
import gdb, time, os, re
run_secs = int(os.environ.get("KERNEL_RUN_SECS", "20"))
run_tag = os.environ.get("RUN_TAG", time.strftime("timedcap_%Y%m%d_%H%M%S"))
summary = f"/tmp/{run_tag}_timed_capture.txt"

for trig_idx in range(2):
    gdb.execute(f"monitor WriteCSR 0x7a0 {trig_idx}")
    gdb.execute("monitor WriteCSR 0x7a1 0")
    gdb.execute("monitor WriteCSR 0x7a2 0")
gdb.write("[OK] Hardware triggers cleared\n")

gdb.execute("monitor go")
gdb.write(f"[run] Kernel running for {run_secs}s...\n")
time.sleep(run_secs)
gdb.write(f"[run] {run_secs}s elapsed, halting target...\n")
gdb.execute("monitor halt")
time.sleep(2)
try:
    gdb.execute("maintenance flush register-cache")
except gdb.error:
    pass

def read_csr(csr_num):
    out = gdb.execute(f"monitor ReadCSR 0x{csr_num:x}", to_string=True)
    m = re.search(r'(?:0x)?([0-9A-Fa-f]{8,16})', out)
    return (int(m.group(1), 16) if m else None, out.strip())

pc = int(gdb.parse_and_eval("$pc")) & 0xFFFFFFFFFFFFFFFF
sepc, sepc_raw = read_csr(0x141)
scause, scause_raw = read_csr(0x142)
stval, stval_raw = read_csr(0x143)
satp, satp_raw = read_csr(0x180)

with open(summary, "w") as f:
    f.write(f"pc=0x{pc:016x}\n")
    f.write(f"sepc={sepc_raw}\n")
    f.write(f"scause={scause_raw}\n")
    f.write(f"stval={stval_raw}\n")
    f.write(f"satp={satp_raw}\n")

gdb.write(f"[stop] PC = 0x{pc:016x}\n")
gdb.write(f"[csr] sepc  = {sepc_raw}\n")
gdb.write(f"[csr] scause= {scause_raw}\n")
gdb.write(f"[csr] stval = {stval_raw}\n")
gdb.write(f"[csr] satp  = {satp_raw}\n")
gdb.write(f"[files] Summary: {summary}\n")

gdb.execute("info reg pc ra sp gp tp t0 t1 t2 s0 s1 a0 a1 a2 a3 a4 a5 a6 a7")
try:
    gdb.execute("info symbol $pc")
    gdb.execute("x/12i $pc")
except gdb.error as err:
    gdb.write(f"[pc] symbol/disasm unavailable: {err}\n")
if sepc is not None:
    try:
        gdb.write(f"[fault] Disassembly at sepc=0x{sepc:016x}\n")
        gdb.execute(f"info symbol 0x{sepc:x}")
        gdb.execute(f"x/12i 0x{sepc:x}")
    except gdb.error as err:
        gdb.write(f"[fault] Could not inspect sepc: {err}\n")
try:
    gdb.execute("bt")
except gdb.error as err:
    gdb.write(f"[bt] unavailable: {err}\n")
end

quit
