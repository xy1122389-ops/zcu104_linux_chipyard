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
gdb.write("[copyback] Routine at 0x{:08x} written and dirtied\n".format(COPYBACK_ADDR))

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

chunk_dir = "/tmp/fw_chunks_slip"
base_addr = 0x80000000
chunk_size = 4194304
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
dtb_default = "/root/chipyard/fpga/linux-bringup/dtb/chipyard-zcu104-linux-slip.dtb"
dtb_path = os.environ.get("DTB_PATH", dtb_default)
gdb.write(f"[dtb] Using: {dtb_path}\n")
gdb.execute(f"restore {dtb_path} binary 0x84000000")

COPYBACK_ADDR = 0x81200000
dtb_size = os.path.getsize(dtb_path)
dtb_end = (0x84000000 + dtb_size + 63) & ~63
gdb.execute("set $a0 = 0x84000000")
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

echo \n=== Phase 2: Direct timed run ===\n
set $a0 = 0
set $a1 = 0x84000000
set $a2 = 0
set $pc = 0x80000000
symbol-file /root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux

python
import gdb, os, time
run_secs = int(os.environ.get("KERNEL_RUN_SECS", "20"))
run_tag = os.environ.get("RUN_TAG", time.strftime("timedrun_%Y%m%d_%H%M%S"))
gdb.write(f"[boot] Running target freely for {run_secs}s\n")
gdb.execute("monitor go")
time.sleep(run_secs)
gdb.execute("monitor halt")
try:
    gdb.execute("maintenance flush register-cache")
except gdb.error:
    pass
pc = int(gdb.parse_and_eval("$pc")) & 0xFFFFFFFFFFFFFFFF
gdb.write(f"[halt] PC = 0x{pc:016x}\n")
klog_file = f"/tmp/{run_tag}_klog.bin"
logbuf_va = int(gdb.parse_and_eval("(unsigned long)&__log_buf")) & 0xFFFFFFFFFFFFFFFF
logbuf_pa = (logbuf_va - 0xffffffff80000000 + 0x80200000) & 0xFFFFFFFFFFFFFFFF
gdb.write(f"[klog] __log_buf VA = 0x{logbuf_va:016x}, PA = 0x{logbuf_pa:016x}\n")
gdb.write(f"[klog] Dumping to {klog_file}\n")
gdb.execute(f"dump binary memory {klog_file} 0x{logbuf_pa:x} 0x{logbuf_pa + 0x20000:x}")
gdb.write(f"[klog] Dumped 0x{logbuf_pa:x} - 0x{logbuf_pa + 0x20000:x}\n")
end

quit