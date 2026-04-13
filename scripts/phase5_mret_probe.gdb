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
        gdb.write(f"[warn] Connect attempt {attempt} failed: {err}\n")
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

# Phase 1 zero trampoline above _fw_end to avoid clobbering OpenSBI .bss
set *(unsigned int*)0x80038000 = 0x00053023
set *(unsigned short*)0x80038004 = 0x0521
set *(unsigned int*)0x80038006 = 0xFEB54DE3
set *(unsigned short*)0x8003800A = 0x9002
set *(unsigned int*)0x80038100 = 0x0000100f
set *(unsigned short*)0x80038104 = 0x9002
set *(unsigned long long*)0x2010200 = 0x80038000
set *(unsigned long long*)0x2010200 = 0x80038040
set *(unsigned long long*)0x2010200 = 0x80038100
set $pc = 0x80038100
stepi
echo [ok] fence.i phase1\n
delete breakpoints
hbreak *0x8003800a

echo [zero0]\n
set $a0 = 0x80040000
set $a1 = 0x80200000
set $pc = 0x80038000
continue

echo [zero1]\n
set $a0 = 0x80EC4000
set $a1 = 0x84000000
set $pc = 0x80038000
continue

echo [zero1b]\n
set $a0 = 0x84001070
set $a1 = 0x84100000
set $pc = 0x80038000
continue

echo [zero2]\n
set $a0 = 0x84100000
set $a1 = 0xA0000000
set $pc = 0x80038000
continue

echo [zero3]\n
set $a0 = 0xA0000000
set $a1 = 0xC0000000
set $pc = 0x80038000
continue

echo [zero4]\n
set $a0 = 0xC0000000
set $a1 = 0x100000000
set $pc = 0x80038000
continue

echo [ALL DDR ZEROED]\n

# Phase 2 restore
monitor WriteCSR 0x180 0
monitor WriteCSR 0x7b0 0x4000F0C3
set *(unsigned int*)0x80038100 = 0x0000100f
set *(unsigned short*)0x80038104 = 0x9002
set *(unsigned long long*)0x2010200 = 0x80038100
set $pc = 0x80038100
stepi
echo [ok] fence.i phase2\n
python
import os, gdb, time

chunk_dir = "/tmp/fw_chunks_new"
base_addr = 0x80000000
chunk_size = 4194304
host = os.environ.get("JLINK_HOST", "172.19.128.1")
port = int(os.environ.get("JLINK_PORT", "2331"))
chunks = sorted([f for f in os.listdir(chunk_dir) if f.startswith("chunk_") and f.endswith(".bin")])
for index, fname in enumerate(chunks):
    if index > 0 and index % 4 == 0:
        gdb.write(f"[reconnect] after {index} chunks\n")
        gdb.execute("disconnect")
        time.sleep(2)
        gdb.execute(f"target remote {host}:{port}")
        gdb.execute("monitor halt")
    addr = base_addr + index * chunk_size
    gdb.write(f"[restore] {fname} -> 0x{addr:x}\n")
    gdb.execute(f"restore {os.path.join(chunk_dir, fname)} binary 0x{addr:x}")
end

restore /root/chipyard/fpga/linux-bringup/demo-assets/dtb/chipyard-zcu104-linux.dtb binary 0x84000000
echo [ok] DTB restored\n

# Phase 3 invalidate
monitor WriteCSR 0x180 0
set *(unsigned int*)0x80038000 = 0x00A63023
set *(unsigned int*)0x80038004 = 0x04050513
set *(unsigned int*)0x80038008 = 0xFEB54CE3
set *(unsigned short*)0x8003800C = 0x9002
set *(unsigned int*)0x80038100 = 0x0000100f
set *(unsigned short*)0x80038104 = 0x9002
set *(unsigned long long*)0x2010200 = 0x80038000
set *(unsigned long long*)0x2010200 = 0x80038040
set *(unsigned long long*)0x2010200 = 0x80038100
set $pc = 0x80038100
stepi
delete breakpoints
hbreak *0x8003800c
set $a0 = 0x80000000
set $a1 = 0x810cb608
set $a2 = 0x2010200
set $pc = 0x80038000
continue
set $a0 = 0x84000000
set $a1 = 0x8400105e
set $a2 = 0x2010200
set $pc = 0x80038000
continue
echo [ok] L2 invalidate done\n

# Phase 4 fence.i
set *(unsigned int*)0x80038100 = 0x0000100f
set *(unsigned short*)0x80038104 = 0x9002
set *(unsigned long long*)0x2010200 = 0x80038100
set $pc = 0x80038100
stepi
echo [ok] fence.i phase4\n

# Phase 5 probe: run briefly instead of waiting forever on mret breakpoint
echo \n=== Phase 5 Probe ===\n
set $a0 = 0
set $a1 = 0x84000000
set $a2 = 0
set $pc = 0x80000000

python
import gdb, time, re

gdb.write("[probe] monitor go for 2s from OpenSBI entry\n")
gdb.execute("monitor go")
time.sleep(2)
gdb.execute("monitor halt")
time.sleep(1)
gdb.execute("maintenance flush register-cache")

try:
    pc = int(gdb.parse_and_eval("$pc")) & 0xFFFFFFFFFFFFFFFF
    gdb.write(f"[probe] halted PC = 0x{pc:016x}\n")
except Exception as err:
    gdb.write(f"[probe] PC read failed: {err}\n")

for name, csr in [("satp", 0x180), ("mepc", 0x341), ("mcause", 0x342), ("sepc", 0x141), ("scause", 0x142), ("dpc", 0x7b1), ("dcsr", 0x7b0)]:
    try:
        out = gdb.execute(f"monitor ReadCSR 0x{csr:x}", to_string=True).strip()
        gdb.write(f"[probe] {name:6s} = {out}\n")
    except Exception as err:
        gdb.write(f"[probe] {name:6s} read failed: {err}\n")
end

detach
quit