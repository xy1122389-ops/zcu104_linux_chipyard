# linux_boot.gdb — ZCU104 Rocket Linux bring-up (DDR zero + boot + dcsr fix)
#
# Prerequisites (must be done in order before running this script):
#   1. run_ps_ddr_init.sh — PS DDR init + bitstream download
#   2. xsdb_load_ddr.sh  — fresh XSDB load of fw_payload.bin + DTB
#   3. J-Link GDB Server running (start_jlink_gdb_server.bat, port 2331)
#
# What this script does:
#   Phase 1: Zero uninitialized DDR regions via Rocket core (~30s)
#   Phase 2: Patch CMDLINE to add init_on_alloc=1
#   Phase 3: L2 cache flush (eliminate stale cache lines after zero+patch)
#   Phase 4: Restore pristine OpenSBI + DTB + fence.i
#   Phase 5: Boot OpenSBI -> mret -> Linux _start -> _start_kernel
#   Phase 6: Clear dcsr ebreak bits so kernel WARN/ebreak is handled by
#            kernel's own trap handler, not by J-Link debug mode
#   Phase 7: Continue kernel, detach
#
# After this script completes, the kernel is running unattended.
# Use dump_klog.sh (60-120s later) to halt and read the kernel ring buffer.
#
# KNOWN CONSTRAINTS:
#   - NEVER use "monitor go" -- crashes hart to 0xdeadbeef
#   - GDB batch "continue &" + "interrupt" does NOT work reliably
#   - J-Link does NOT detect ebreak halts -- always use hbreak
#   - OpenSBI _relocate_lottery in .data persists across boots -- MUST restore
#   - OpenSBI fdt_open_into expands DTB in place -- MUST restore original DTB
#   - SBA writes bypass L2 cache; program-buffer writes are L2-coherent
#
# Key addresses (see also linux-bringup/ADDRESS_PLAN.md):
#   OpenSBI _start:      0x80000000
#   Linux _start:        0x80200000
#   Linux _start_kernel: 0x802010d0
#   OpenSBI mret:        0x8000b2b2
#   DTB:                 0x84000000 (4201 bytes)
#   Kernel log buffer:   0x830e7108 (PA)
#   L2 Flush64:          0x2010200

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

# Ensure M-mode bare (no address translation)
monitor WriteCSR 0x180 0
monitor WriteCSR 0x7b0 0x4000F0C3

# Write zero_loop at 0x80036100 (inside OpenSBI reserved region)
#   0x80036100: sd zero,0(a0)       # 0x00053023
#   0x80036104: c.addi a0,8         # 0x0521
#   0x80036106: blt a0,a1,loop      # 0xFEB54DE3
#   0x8003610a: c.ebreak            # 0x9002
set *(unsigned int*)0x80036100 = 0x00053023
set *(unsigned short*)0x80036104 = 0x0521
set *(unsigned int*)0x80036106 = 0xFEB54DE3
set *(unsigned short*)0x8003610A = 0x9002

# fence.i trampoline at 0x80036200
set *(unsigned int*)0x80036200 = 0x0000100f
set *(unsigned short*)0x80036204 = 0x9002
set $pc = 0x80036200
stepi
echo [ok] fence.i\n

delete breakpoints
hbreak *0x8003610a

# Pass 0: OpenSBI overflow (0x80040000-0x80200000, ~1.75MB)
echo [zero0] 0x80040000-0x80200000...\n
set $a0 = 0x80040000
set $a1 = 0x80200000
set $pc = 0x80036100
continue
echo [zero0] done\n

# Pass 1: Gap between firmware end and DTB (0x830D4808-0x84000000)
echo [zero1] 0x830D4808-0x84000000...\n
set $a0 = 0x830D4808
set $a1 = 0x84000000
set $pc = 0x80036100
continue
echo [zero1] done\n

# Pass 1b: After DTB to 0x84100000 (~1MB)
echo [zero1b] 0x84001070-0x84100000...\n
set $a0 = 0x84001070
set $a1 = 0x84100000
set $pc = 0x80036100
continue
echo [zero1b] done\n

# Pass 2-4: Everything above DTB (~1.94GB)
echo [zero2] 0x84100000-0xA0000000...\n
set $a0 = 0x84100000
set $a1 = 0xA0000000
set $pc = 0x80036100
continue
echo [zero2] done\n

echo [zero3] 0xA0000000-0xC0000000...\n
set $a0 = 0xA0000000
set $a1 = 0xC0000000
set $pc = 0x80036100
continue
echo [zero3] done\n

echo [zero4] 0xC0000000-0x100000000...\n
set $a0 = 0xC0000000
set $a1 = 0x100000000
set $pc = 0x80036100
continue
echo [zero4] done\n
echo [ALL DDR ZEROED]\n

# ============================================================
# Phase 2: Patch CMDLINE (all 3 copies -- .rodata is the effective one)
# ============================================================
echo \n=== Phase 2: Patch CMDLINE ===\n
restore /tmp/cmdline_rodata_patch.bin binary 0x82CDCD88
restore /tmp/cmdline_rodata_patch.bin binary 0x82B4B600
restore /tmp/cmdline_rodata_patch.bin binary 0x80A0F8E8
echo [ok] CMDLINE patched: \n
x/1s 0x82CDCD88

# ============================================================
# Phase 3: L2 cache flush (2GB)
# ============================================================
echo \n=== Phase 3: L2 cache flush ===\n

monitor WriteCSR 0x180 0
monitor WriteCSR 0x7b0 0x4000F0C3

# Write flush loop at 0x80036100:
#   sd a0, 0(a2)            # trigger Flush64
#   addi a0, a0, 64         # next cache line
#   blt a0, a1, -8          # loop
#   c.ebreak
set *(unsigned int*)0x80036100 = 0x00A63023
set *(unsigned int*)0x80036104 = 0x04050513
set *(unsigned int*)0x80036108 = 0xFEB54CE3
set *(unsigned short*)0x8003610C = 0x9002

set *(unsigned int*)0x80036200 = 0x0000100f
set *(unsigned short*)0x80036204 = 0x9002
set $pc = 0x80036200
stepi
echo [ok] fence.i for flush\n

delete breakpoints
hbreak *0x8003610C
set $a0 = 0x80000000
set $a1 = 0x100000000
set $a2 = 0x2010200
set $pc = 0x80036100
echo [l2flush] Flushing 2GB...\n
continue
echo [l2flush] done\n

# ============================================================
# Phase 4: Restore pristine OpenSBI + DTB + fence.i
# ============================================================
echo \n=== Phase 4: Restore pristine OpenSBI + DTB ===\n

monitor WriteCSR 0x180 0
monitor WriteCSR 0x7b0 0x4000F0C3

# Re-establish fence.i trampoline (may have been evicted)
set *(unsigned int*)0x80036200 = 0x0000100f
set *(unsigned short*)0x80036204 = 0x9002
set $pc = 0x80036200
stepi
echo [ok] fence.i\n

# Restore pristine OpenSBI 256KB (fixes _relocate_lottery, _boot_status, all .data)
restore /tmp/opensbi_region.bin binary 0x80000000
echo [ok] OpenSBI 256KB restored\n

# Restore original DTB (4201 bytes, before fdt_open_into expansion)
restore /root/chipyard/fpga/linux-bringup/demo-assets/dtb/chipyard-zcu104-linux.dtb binary 0x84000000
echo [ok] DTB restored\n

# ============================================================
# Phase 5: Boot OpenSBI -> mret -> Linux _start -> _start_kernel
# ============================================================
echo \n=== Phase 5: Boot to _start_kernel ===\n

# Set up OpenSBI entry: a0=hartid=0, a1=DTB address
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
    gdb.execute("info reg pc ra sp a0 a1")
    gdb.execute("x/8i $pc")
    raise gdb.GdbError("OpenSBI did not reach mret")

gdb.write("[OK] OpenSBI reached mret\n")
gdb.execute("delete breakpoints")
gdb.execute("stepi")

pc2 = int(gdb.parse_and_eval("$pc"))
gdb.write(f"[OK] After mret: pc=0x{pc2:x}\n")

gdb.execute("hbreak *0x802010d0")
gdb.execute("continue")

pc3 = int(gdb.parse_and_eval("$pc"))
if pc3 != 0x802010d0:
    gdb.write(f"\n[FAIL] Expected _start_kernel at 0x802010d0, got 0x{pc3:x}\n")
    gdb.execute("info reg pc ra sp")
    gdb.execute("x/8i $pc")
    raise gdb.GdbError("Kernel did not reach _start_kernel")

gdb.write("[OK] Linux _start_kernel reached\n")
gdb.execute("delete breakpoints")

# ==========================================================
# Phase 6: Clear dcsr ebreak bits (THE KEY FIX)
# ==========================================================
# Current dcsr = 0x4000F0C3:
#   bit [15] ebreakm = 1  -> M-mode ebreak enters debug mode
#   bit [13] ebreaks = 1  -> S-mode ebreak enters debug mode  <- PROBLEM
#   bit [12] ebreaku = 1  -> U-mode ebreak enters debug mode  <- PROBLEM
#   bit [1:0] prv    = 3  -> M-mode privilege
#
# The kernel uses ebreak for WARN_ON guards (e.g. stack_depot_early_init).
# With ebreaks=1, these kernel ebreaks halt the CPU in debug mode instead
# of being handled by the kernel's own exception handler.
#
# Fix: clear bits 15,13,12 -> new value = 0x400040C3
# (xdebugver and cause are read-only, hardware ignores writes to them)

gdb.write("\n=== Phase 6: Clear dcsr ebreak bits ===\n")

# Read current dcsr
gdb.write("[dcsr] Before: ")
gdb.execute("monitor ReadCSR 0x7b0")

# Clear ebreakm/ebreaks/ebreaku (bits 15, 13, 12)
gdb.execute("monitor WriteCSR 0x7b0 0x400040C3")

# Verify
gdb.write("[dcsr] After:  ")
gdb.execute("monitor ReadCSR 0x7b0")

gdb.write("[OK] dcsr ebreak bits cleared\n")

# ==========================================================
# Phase 7: Continue kernel and detach
# ==========================================================
gdb.write("\n=== Phase 7: Launching kernel ===\n")
gdb.write("Kernel will run unattended. Use dump_klog.sh after 60-120s.\n")
gdb.execute("continue &")

import time
time.sleep(2)
gdb.execute("detach")
gdb.write("\n[DONE] Kernel running. GDB detached.\n")
end

quit
