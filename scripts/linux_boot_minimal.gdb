# linux_boot_minimal.gdb — Minimal boot: restore all + boot (no DDR zeroing)
# Purpose: Test if DDR zeroing is causing cache coherency issues
#
# This script:
# 1. Restores ENTIRE kernel region from fw_payload.bin (no selective zeroing)
# 2. Patches CMDLINE
# 3. Flushes L2
# 4. Boots with dcsr fix
#
# ASSUMES fw_payload.bin was previously loaded via XSDB and DDR still has data.

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
# Phase 1: Restore entire fw_payload.bin (all segments)
# ============================================================
echo \n=== Phase 1: Restore ENTIRE fw_payload.bin ===\n

monitor WriteCSR 0x180 0
monitor WriteCSR 0x7b0 0x4000F0C3

# Restore the full fw_payload.bin to PA 0x80000000
# This includes OpenSBI + kernel text + init.data + rodata + data + initramfs
restore /root/chipyard/fpga/linux-bringup/payload/fw_payload.bin binary 0x80000000
echo [ok] Full fw_payload.bin restored\n

# Restore DTB
restore /root/chipyard/fpga/linux-bringup/demo-assets/dtb/chipyard-zcu104-linux.dtb binary 0x84000000
echo [ok] DTB restored\n

# ============================================================
# Phase 2: Patch CMDLINE (WITHOUT init_on_alloc=1)
# ============================================================
echo \n=== Phase 2: Patch CMDLINE (no init_on_alloc) ===\n
# Just use "console=ttySIF0 earlycon" without init_on_alloc
# We'll patch the rodata copy only
# Original: "console=ttySIF0 earlycon"
# No patching needed since the binary already has the base cmdline

# Actually, let's still patch for earlycon visibility
restore /tmp/cmdline_rodata_patch.bin binary 0x82CDCD88
restore /tmp/cmdline_rodata_patch.bin binary 0x82B4B600
restore /tmp/cmdline_rodata_patch.bin binary 0x80A0F8E8
echo [ok] CMDLINE patched\n

# ============================================================
# Phase 3: L2 cache flush (entire 2GB)
# ============================================================
echo \n=== Phase 3: L2 cache flush ===\n

# Write flush loop at 0x80036100
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
# Phase 4: Re-restore OpenSBI (flush loop corrupted it)
# ============================================================
echo \n=== Phase 4: Re-restore OpenSBI ===\n
monitor WriteCSR 0x180 0
monitor WriteCSR 0x7b0 0x4000F0C3

set *(unsigned int*)0x80036200 = 0x0000100f
set *(unsigned short*)0x80036204 = 0x9002
set $pc = 0x80036200
stepi

restore /tmp/opensbi_region.bin binary 0x80000000
echo [ok] OpenSBI re-restored after flush\n

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
gdb.execute("stepi")

pc2 = int(gdb.parse_and_eval("$pc"))
gdb.write(f"[OK] After mret: pc=0x{pc2:x}\n")

gdb.execute("hbreak *0x802010d0")
gdb.execute("continue")
end

python
import gdb

pc = int(gdb.parse_and_eval("$pc"))
if pc != 0x802010d0:
    gdb.write(f"\n[FAIL] Expected _start_kernel at 0x802010d0, got 0x{pc:x}\n")
    raise gdb.GdbError("Linux did not reach _start_kernel")

gdb.write("[OK] Linux _start_kernel reached\n")
gdb.execute("delete breakpoints")
end

# ============================================================
# Phase 6: Clear dcsr ebreak bits
# ============================================================
echo \n=== Phase 6: Clear dcsr ebreak bits ===\n

python
import gdb

# Read current dcsr
output = gdb.execute("monitor ReadCSR 0x7b0", to_string=True)
line = [l for l in output.strip().split('\n') if 'O.K.' in l or '0x' in l.lower()]
if line:
    val_str = line[0].split(':')[-1].strip()
    old_val = int(val_str, 16)
else:
    old_val = 0x4000F081

gdb.write(f"[dcsr] old=0x{old_val:08X}")

new_val = old_val & ~((1 << 15) | (1 << 13) | (1 << 12))
gdb.write(f" -> new=0x{new_val:08X} (cleared bits 15,13,12)\n")

prv = old_val & 0x3
gdb.write(f"[dcsr] prv preserved = {prv} (1=S-mode, 3=M-mode)\n")
gdb.execute(f"monitor WriteCSR 0x7b0 0x{new_val:X}")

# Verify
output2 = gdb.execute("monitor ReadCSR 0x7b0", to_string=True)
gdb.write(f"[dcsr] After:  {output2.strip()}\n")
gdb.write("[OK] dcsr ebreak bits cleared\n")
end

# ============================================================
# Phase 7: Launch kernel
# ============================================================
echo \n=== Phase 7: Launching kernel ===\n
echo Kernel will run unattended. Use dump_klog.sh after 60-120s.\n

python
import gdb
try:
    gdb.execute("continue &")
except:
    pass
try:
    gdb.execute("detach")
except:
    pass
end
