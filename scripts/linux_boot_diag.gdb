# linux_boot_diag.gdb — Diagnostic: boot + halt at sched_init to inspect SLUB state
# Based on linux_boot.gdb but stops at sched_init entry instead of running kernel
#
# Usage: bash scripts/start_linux_boot.sh (ensure prereqs), then:
#   riscv64-unknown-linux-gnu-gdb -batch -x scripts/linux_boot_diag.gdb

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
echo --- Initial state ---\n
info reg pc

# ============================================================
# Phase 1: Zero DDR via Rocket core
# ============================================================
echo \n=== Phase 1: Zero DDR via Rocket core ===\n

monitor WriteCSR 0x180 0
monitor WriteCSR 0x7b0 0x4000F0C3

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
echo [ok] fence.i\n

delete breakpoints
hbreak *0x8003800a

echo [zero0] 0x80040000-0x80200000...\n
set $a0 = 0x80040000
set $a1 = 0x80200000
set $pc = 0x80038000
continue
echo [zero0] done\n

echo [zero1] 0x80EC4000-0x84000000...\n
set $a0 = 0x80EC4000
set $a1 = 0x84000000
set $pc = 0x80038000
continue
echo [zero1] done\n

echo [zero1b] 0x84001070-0x84100000...\n
set $a0 = 0x84001070
set $a1 = 0x84100000
set $pc = 0x80038000
continue
echo [zero1b] done\n

echo [zero2] 0x84100000-0xA0000000...\n
set $a0 = 0x84100000
set $a1 = 0xA0000000
set $pc = 0x80038000
continue
echo [zero2] done\n

echo [zero3] 0xA0000000-0xC0000000...\n
set $a0 = 0xA0000000
set $a1 = 0xC0000000
set $pc = 0x80038000
continue
echo [zero3] done\n

echo [zero4] 0xC0000000-0x100000000...\n
set $a0 = 0xC0000000
set $a1 = 0x100000000
set $pc = 0x80038000
continue
echo [zero4] done\n
echo [ALL DDR ZEROED]\n

# ============================================================
# Phase 2: Patch CMDLINE
# ============================================================
echo \n=== Phase 2: Patch CMDLINE ===\n
restore /tmp/cmdline_rodata_patch.bin binary 0x82CDCD88
restore /tmp/cmdline_rodata_patch.bin binary 0x82B4B600
restore /tmp/cmdline_rodata_patch.bin binary 0x80A0F8E8
echo [ok] CMDLINE patched\n

# ============================================================
# Phase 3: L2 cache flush (2GB)
# ============================================================
echo \n=== Phase 3: L2 cache flush ===\n

monitor WriteCSR 0x180 0
monitor WriteCSR 0x7b0 0x4000F0C3

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
echo [ok] fence.i for flush\n

delete breakpoints
hbreak *0x8003800C
set $a0 = 0x80000000
set $a1 = 0x100000000
set $a2 = 0x2010200
set $pc = 0x80038000
echo [l2flush] Flushing 2GB...\n
continue
echo [l2flush] done\n

# ============================================================
# Phase 4: Restore pristine OpenSBI + DTB + sections
# ============================================================
echo \n=== Phase 4: Restore pristine data ===\n

monitor WriteCSR 0x180 0
monitor WriteCSR 0x7b0 0x4000F0C3

set *(unsigned int*)0x80038100 = 0x0000100f
set *(unsigned short*)0x80038104 = 0x9002
set *(unsigned long long*)0x2010200 = 0x80038100
set $pc = 0x80038100
stepi
echo [ok] fence.i\n

restore /tmp/opensbi_region.bin binary 0x80000000
echo [ok] OpenSBI 256KB restored\n

restore /tmp/kernel_data_section.bin binary 0x83000000
echo [ok] Kernel .data 850KB restored\n

restore /tmp/kernel_initdata_section.bin binary 0x80a00000
echo [ok] Kernel .init.data 80KB restored\n

restore /tmp/kernel_percpu_section.bin binary 0x8314e000
echo [ok] Kernel .percpu 40KB restored\n

restore /root/chipyard/fpga/linux-bringup/demo-assets/dtb/chipyard-zcu104-linux.dtb binary 0x84000000
echo [ok] DTB restored\n

# Phase 4b: skipped (second L2 flush removed - too slow and may interfere)

# ============================================================
# Phase 5: Boot OpenSBI -> mret -> Linux _start -> _start_kernel
# ============================================================
echo \n=== Phase 5: Boot to _start_kernel ===\n

set $a0 = 0
set $a1 = 0x84000000
set $a2 = 0
set $pc = 0x80000000

delete breakpoints
hbreak *0x8000b2b2
echo [boot] Running OpenSBI to mret...\n
continue

python
import gdb

pc = int(gdb.parse_and_eval("$pc"))
if pc != 0x8000b2b2:
    gdb.write(f"\n[FAIL] Expected mret at 0x8000b2b2, got 0x{pc:x}\n")
    raise gdb.GdbError("OpenSBI did not reach mret")

gdb.write("[OK] OpenSBI reached mret\n")
gdb.execute("delete breakpoints")
gdb.execute("set $a1 = 0x84000000")

# NOTE: Do NOT use stepi here! J-Link cannot single-step across
# mret (M-mode -> S-mode transition). Use hbreak at _start instead.
gdb.execute("hbreak *0x80200000")
gdb.execute("continue")

pc2 = int(gdb.parse_and_eval("$pc"))
gdb.write(f"[OK] Linux _start: pc=0x{pc2:x}\n")

gdb.execute("delete breakpoints")
# NOTE: _start_kernel runs at VA 0xffffffff802010d0 after MMU enable.
# Cannot use hbreak at PA 0x802010d0 — it would never fire.
# Clear dcsr here and continue; diag breakpoint uses VA.

# Phase 6: Clear dcsr ebreak bits
import re
gdb.write("\n=== Phase 6: Clear dcsr ebreak bits ===\n")
read_out = gdb.execute("monitor ReadCSR 0x7b0", to_string=True)
m = re.search(r'(?:0x)?([0-9A-Fa-f]{8})', read_out)
if not m:
    raise gdb.GdbError(f"Cannot parse dcsr from: {read_out.strip()}")
old_dcsr = int(m.group(1), 16)
EBREAK_MASK = (1 << 15) | (1 << 13) | (1 << 12)
new_dcsr = old_dcsr & ~EBREAK_MASK
gdb.write(f"[dcsr] 0x{old_dcsr:08X} -> 0x{new_dcsr:08X}\n")
gdb.execute(f"monitor WriteCSR 0x7b0 0x{new_dcsr:08X}")

# Phase 7: Set breakpoint at sched_init and run
gdb.write("\n=== Phase 7: Run to sched_init (diagnostic halt) ===\n")
gdb.execute("hbreak *0xffffffff8060944c")
gdb.execute("continue")

pc4 = int(gdb.parse_and_eval("$pc"))
gdb.write(f"[DIAG] Halted at 0x{pc4:x}\n")
if pc4 == 0xffffffff8060944c:
    gdb.write("[OK] At sched_init entry!\n")
    
    # Dump kmem_cache struct at PA 0x83401600 (kmalloc_caches[0][2])
    # Need bare-mode access: save satp, set satp=0, read, restore
    satp_out = gdb.execute("monitor ReadCSR 0x180", to_string=True)
    m2 = re.search(r'(?:0x)?([0-9A-Fa-f]+)', satp_out)
    old_satp = int(m2.group(1), 16) if m2 else 0
    gdb.write(f"[DIAG] Current satp = 0x{old_satp:016x}\n")
    
    # Switch to bare mode for PA reads
    gdb.execute("monitor WriteCSR 0x180 0")
    
    # Read kmem_cache struct at PA 0x83401600 (24 qwords = 192 bytes)
    gdb.write("\n[DIAG] kmalloc_caches[0][2] (kmalloc-192) at PA 0x83401600:\n")
    for i in range(0, 192, 8):
        addr = 0x83401600 + i
        val = int(gdb.parse_and_eval(f"*(unsigned long long*){addr}"))
        if val != 0:
            gdb.write(f"  +0x{i:02x}: 0x{val:016x}\n")
    
    # Also check a known-good cache: kmalloc-32 at PA 0x83401180
    gdb.write("\n[DIAG] kmalloc_caches[0][3] (kmalloc-32) at PA 0x83401180:\n")
    for i in range(0, 192, 8):
        addr = 0x83401180 + i
        val = int(gdb.parse_and_eval(f"*(unsigned long long*){addr}"))
        if val != 0:
            gdb.write(f"  +0x{i:02x}: 0x{val:016x}\n")
    
    # Check kmalloc_caches[0][1] (kmalloc-96) at PA 0x83401480
    gdb.write("\n[DIAG] kmalloc_caches[0][1] (kmalloc-96) at PA 0x83401480:\n")
    for i in range(0, 192, 8):
        addr = 0x83401480 + i
        val = int(gdb.parse_and_eval(f"*(unsigned long long*){addr}"))
        if val != 0:
            gdb.write(f"  +0x{i:02x}: 0x{val:016x}\n")
    
    # Restore satp
    gdb.execute(f"monitor WriteCSR 0x180 0x{old_satp:x}")
    
    gdb.write("\n[DIAG] Done. Check if caches are initialized.\n")
    gdb.write("If [2] and [1] are all-zero but [3] has data: init was incomplete.\n")
    gdb.write("If [2] and [1] also have data: data lost between sched_init and crash.\n")
else:
    gdb.write(f"[WARN] Not at sched_init, at 0x{pc4:x} instead\n")
    gdb.execute("info reg pc ra sp")

end

quit
