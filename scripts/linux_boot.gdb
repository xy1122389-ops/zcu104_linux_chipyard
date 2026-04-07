# linux_boot.gdb — ZCU104 Rocket Minimal Linux Boot (Phase 1: no binary patches)
#
# Prerequisites:
#   1. run_ps_ddr_init.sh — PS DDR init + bitstream download
#   2. J-Link GDB Server running (port 2331)
#
# What this script does:
#   Phase 1: Zero uninitialized DDR regions via Rocket core
#   Phase 2: Restore fw_payload.bin (15MB) + DTB via SBA
#   Phase 3: L2 cache invalidation for restored regions
#   Phase 4: L2 flush + fence.i
#   Phase 5: Boot OpenSBI -> mret -> Linux
#   Phase 6: Clear dcsr ebreak bits
#   Phase 7: Run kernel 600s, halt, dump dmesg
#
# Key addresses (minimal kernel rebuild #5 - no SYSFS/CGROUPS):
#   OpenSBI _start:      0x80000000
#   Linux _start:        0x80200000
#   Linux start_kernel:  0x80600818 (VA 0xffffffff80400818)
#   OpenSBI mret:        0x8000b2b2
#   DTB:                 0x84000000
#   Firmware end:        0x80EC6008
#   __log_buf:           0x80ed6060 (VA 0xffffffff80cd6060)
#   log_buf (ptr):       0x80ec4d88 (VA 0xffffffff80cc4d88)
#   log_buf_len:         0x80ec4d80 (VA 0xffffffff80cc4d80)
#   _end:                0x80f04000 (VA 0xffffffff80d04000)
#   strlen:              0x805c8a40 (VA 0xffffffff803c8a40)
#   L2 Flush64 MMIO:     0x2010200

set pagination off
set confirm off
set breakpoint auto-hw off
set remotetimeout 600

file /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf

python
import subprocess, gdb, time
host = "172.19.128.1"  # Windows host via relay
relay_port = 12331
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
end

monitor halt
echo --- Initial state ---\n
info reg pc


# ============================================================
# Phase 1: Zero DDR via Rocket core
# ============================================================
echo \n=== Phase 1: Zero DDR via Rocket core ===\n


python
import os, gdb
cfg_name = os.environ.get("CHIPYARD_ZCU104_CFG", "")
skip_l2 = 1 if "NoL2" in cfg_name else 0
gdb.execute(f"set $skip_l2 = {skip_l2}")
if cfg_name:
    gdb.write(f"[cfg] CHIPYARD_ZCU104_CFG={cfg_name}\n")
if skip_l2:
    gdb.write("[cfg] No-L2 config detected; skipping Phase 3 L2 invalidation\n")
end

monitor WriteCSR 0x180 0
monitor WriteCSR 0x7b0 0x4000F0C3

# Write zero_loop at 0x80036100
#   sd zero,0(a0); c.addi a0,8; blt a0,a1,loop; c.ebreak
set *(unsigned int*)0x80036100 = 0x00053023
set *(unsigned short*)0x80036104 = 0x0521
set *(unsigned int*)0x80036106 = 0xFEB54DE3
set *(unsigned short*)0x8003610A = 0x9002

# fence.i trampoline at 0x80036200
set *(unsigned int*)0x80036200 = 0x0000100f
set *(unsigned short*)0x80036204 = 0x9002

# Flush L2 for trampoline addresses
if $skip_l2 == 0
set *(unsigned long long*)0x2010200 = 0x80036100
set *(unsigned long long*)0x2010200 = 0x80036140
set *(unsigned long long*)0x2010200 = 0x80036200
else
echo [L2flush] Skipped Phase 1 trampoline flush for no-L2 config\n
end

set $pc = 0x80036200
stepi
echo [ok] fence.i\n

delete breakpoints
hbreak *0x8003610a

# Pass 0: OpenSBI overflow (0x80040000-0x80200000)
echo [zero0] 0x80040000-0x80200000...\n
set $a0 = 0x80040000
set $a1 = 0x80200000
set $pc = 0x80036100
continue
echo [zero0] done\n

# Pass 1: Gap between firmware end and DTB (0x80EC4000 -> 0x84000000)
echo [zero1] 0x80EC4000-0x84000000...\n
set $a0 = 0x80EC4000
set $a1 = 0x84000000
set $pc = 0x80036100
continue
echo [zero1] done\n

# Pass 1b: After DTB to 0x84100000
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
# Phase 2: Restore fw_payload.bin (17MB) + DTB via SBA
# ============================================================
echo === Phase 2: Restore fw_payload.bin (15MB via SBA) ===\n

monitor WriteCSR 0x180 0
monitor WriteCSR 0x7b0 0x4000F0C3

# Re-establish fence.i trampoline
set *(unsigned int*)0x80036200 = 0x0000100f
set *(unsigned short*)0x80036204 = 0x9002
if $skip_l2 == 0
set *(unsigned long long*)0x2010200 = 0x80036200
else
echo [L2flush] Skipped Phase 2 trampoline flush for no-L2 config\n
end
set $pc = 0x80036200
stepi
echo [ok] fence.i\n

# Restore fw_payload.bin in 4MB chunks
python
import subprocess, os, gdb, time

chunk_dir = "/tmp/fw_chunks_new"
base_addr = 0x80000000
chunk_size = 4194304  # 4MB
reconnect_every = 4
_host = "172.19.128.1"
_port = 12331

chunks = sorted([f for f in os.listdir(chunk_dir) if f.startswith("chunk_") and f.endswith(".bin")])
total = len(chunks)
gdb.write(f"[restore] Loading fw_payload.bin in {total} chunks (4MB each)...\n")

for i, fname in enumerate(chunks):
    if i > 0 and i % reconnect_every == 0:
        gdb.write(f"[reconnect] Cycling J-Link connection after {i} chunks...\n")
        gdb.execute("disconnect")
        time.sleep(3)
        gdb.execute(f"target remote {_host}:{_port}")
        gdb.execute("monitor halt")
        gdb.write(f"[reconnect] OK\n")

    addr = base_addr + i * chunk_size
    fpath = os.path.join(chunk_dir, fname)
    fsize = os.path.getsize(fpath)
    gdb.write(f"[restore {i+1}/{total}] {fname} -> 0x{addr:08x} ({fsize} bytes)...\n")
    gdb.execute(f"restore {fpath} binary 0x{addr:x}")
    gdb.write(f"[restore {i+1}/{total}] done\n")

gdb.write("[ok] fw_payload.bin restored (15MB in chunks)\n")
end

# Restore DTB
restore /root/chipyard/fpga/linux-bringup/demo-assets/dtb/chipyard-zcu104-linux.dtb binary 0x84000000
echo [ok] DTB restored at 0x84000000\n
# External DTB at 0x84000000 already contains:
#   bootargs = "console=ttyS0,115200n8 initramfs_async=0"
#   linux,initrd-start = <0x00 0x8080f1a8>
#   linux,initrd-end   = <0x00 0x809ca3d8>
# OpenSBI overrides a1 with its embedded DTB at 0x82400000;
# we redirect a1 -> 0x84000000 at mret (Phase 5) so Linux uses external DTB.
echo [dtb] External DTB has bootargs + initrd props; will redirect a1 at mret\n

# ============================================================
# Phase 3: L2 cache invalidation after SBA restore
# ============================================================
echo \n=== Phase 3: Invalidate L2 cache for firmware region ===\n

if $skip_l2 == 0
# Re-install L2 flush loop: sd a0, 0(a2); addi a0, a0, 64; blt a0, a1, loop; c.ret
set *(unsigned int*)0x80036100 = 0x00A63023
set *(unsigned int*)0x80036104 = 0x04050513
set *(unsigned int*)0x80036108 = 0xFEB54CE3
set *(unsigned short*)0x8003610C = 0x9002

# fence.i trampoline
set *(unsigned int*)0x80036200 = 0x0000100f
set *(unsigned short*)0x80036204 = 0x9002
set *(unsigned long long*)0x2010200 = 0x80036100
set *(unsigned long long*)0x2010200 = 0x80036140
set *(unsigned long long*)0x2010200 = 0x80036200
set $pc = 0x80036200
stepi
echo [ok] fence.i for L2 invalidation\n

# Invalidate firmware region (15MB: 0x80000000 - 0x80EC7000)
delete breakpoints
hbreak *0x8003610C
set $a0 = 0x80000000
set $a1 = 0x80EC4000
set $a2 = 0x2010200
set $pc = 0x80036100
echo [L2inv] Invalidating L2 for firmware region (17MB)...\n
continue

else
echo [L2inv] Skipped for no-L2 config\n
end

echo [L2inv] done\n

# Invalidate DTB region
delete breakpoints
hbreak *0x8003610C
set $a0 = 0x84000000
set $a1 = 0x84002000
set $a2 = 0x2010200
set $pc = 0x80036100
echo [L2inv] Invalidating L2 for DTB region...\n
continue
echo [L2inv] done\n

# Verify SBA write integrity
echo [verify] Checking SBA write integrity...\n
x/2wx 0x80200000
x/2wx 0x81000000
x/2wx 0x80EC2800

# Verify initramfs magic (CPIO "070701" at PA 0x8080f1a8)
python
import gdb
def read_u32(addr):
    return int(gdb.parse_and_eval(f"*(unsigned int*)0x{addr:x}"))

# Initramfs CPIO magic at 0x8080f1a8 should be 0x37303730 (LE "0707")
cpio_w0 = read_u32(0x8080f1a8)
cpio_w1 = read_u32(0x8080f1ac)
gdb.write(f"[verify] Initramfs magic @ 0x8080f1a8: 0x{cpio_w0:08x} 0x{cpio_w1:08x}\n")
if cpio_w0 == 0x37303730 and cpio_w1 == 0x30303130:
    gdb.write("[verify] Initramfs magic: OK (cpio 070701)\n")
else:
    gdb.write("[FAIL] Initramfs magic MISMATCH! Expected 0x37303730 0x30303130\n")
    gdb.write("[FAIL] This will cause 'invalid magic at start of compressed archive' panic\n")

# Linux _start at 0x80200000 should be 0x106f5a4d
linux_w0 = read_u32(0x80200000)
if linux_w0 == 0x106f5a4d:
    gdb.write("[verify] Linux _start: OK\n")
else:
    gdb.write(f"[FAIL] Linux _start: 0x{linux_w0:08x} (expected 0x106f5a4d)\n")

# OpenSBI entry at 0x80000000 should be 0x0e976f05
osbi_w0 = read_u32(0x80000000)
if osbi_w0 == 0x0e976f05:
    gdb.write("[verify] OpenSBI entry: OK\n")
else:
    gdb.write(f"[FAIL] OpenSBI entry: 0x{osbi_w0:08x} (expected 0x0e976f05)\n")

# Quick spot-check: sample 16 words across firmware and count mismatches
import struct
fw_data = open("/root/chipyard/fpga/linux-bringup/payload/fw_payload.bin", "rb").read()
spots = [0x0, 0x10000, 0x40000, 0x80000, 0x100000, 0x200000, 0x400000,
         0x600000, 0x80f1a8, 0x80f200, 0x900000, 0xa00000, 0xb00000, 0xc00000, 0xec0000, 0xec3200]
mismatches = 0
for off in spots:
    if off + 4 > len(fw_data):
        continue
    expected = struct.unpack('<I', fw_data[off:off+4])[0]
    actual = read_u32(0x80000000 + off)
    if actual != expected:
        gdb.write(f"[FAIL] Mismatch @ 0x{0x80000000+off:08x}: got 0x{actual:08x} expected 0x{expected:08x}\n")
        mismatches += 1
gdb.write(f"[verify] Spot-check: {len(spots)} locations, {mismatches} mismatches\n")
end

# ============================================================
# Phase 4: fence.i
# ============================================================
echo \n=== Phase 4: fence.i ===\n

set *(unsigned int*)0x80036200 = 0x0000100f
set *(unsigned short*)0x80036204 = 0x9002
if $skip_l2 == 0
set *(unsigned long long*)0x2010200 = 0x80036200
else
echo [L2flush] Skipped Phase 4 trampoline flush for no-L2 config\n
end
set $pc = 0x80036200
stepi
echo [ok] fence.i\n

# ============================================================
# Phase 5: Boot OpenSBI -> mret -> Linux _start
# ============================================================
echo \n=== Phase 5: Boot to Linux _start ===\n

set $a0 = 0
set $a1 = 0x84000000
set $a2 = 0
set $pc = 0x80000000

delete breakpoints
hbreak *0x8000b2b2
echo [boot] Running OpenSBI to mret...\n
continue

python
import gdb, subprocess, time
_host = "172.19.128.1"
_port = 12331

pc = int(gdb.parse_and_eval("$pc"))
if pc != 0x8000b2b2:
    gdb.write(f"\n[FAIL] Expected mret at 0x8000b2b2, got 0x{pc:x}\n")
    gdb.execute("info reg pc ra sp a0 a1")
    gdb.execute("x/8i $pc")
    raise gdb.GdbError("OpenSBI did not reach mret")

gdb.write("[OK] OpenSBI reached mret\n")
gdb.execute("delete breakpoints")

# Log a1 (DTB address from OpenSBI)
a1_val = int(gdb.parse_and_eval("$a1"))
gdb.write(f"[dtb] a1 = 0x{a1_val:x} (DTB addr from OpenSBI)\n")

# Verify DTB magic
dtb_magic = int(gdb.parse_and_eval(f"*(unsigned int*)0x{a1_val:x}"))
gdb.write(f"[dtb] DTB magic: 0x{dtb_magic:08x}")
if dtb_magic == 0xedfe0dd0:  # LE read of BE 0xd00dfeed
    gdb.write(" (valid)\n")
else:
    gdb.write(" (INVALID!)\n")

# Use stepi for mret -> Linux _start (hbreak + continue unreliable through relay)
gdb.execute("stepi")
pc2 = int(gdb.parse_and_eval("$pc"))
gdb.write(f"[OK] Linux _start: pc=0x{pc2:x}\n")
if pc2 != 0x80200000:
    gdb.write(f"[WARN] Expected 0x80200000, got 0x{pc2:x}\n")

# ==========================================================
# Phase 5.5: GDB patches DISABLED - System.map does not match kernel binary!
# The System.map addresses are offset by ~0x1a72f0 from the actual binary.
# All previous patches were corrupting random kernel code/data.
# ==========================================================
gdb.write("\n=== Phase 5.5: GDB patches SKIPPED (System.map mismatch) ===\n")

# ==========================================================
# Phase 6: Clear dcsr ebreak bits
# ==========================================================
gdb.write("\n=== Phase 6: Clear dcsr ebreak bits ===\n")

read_out = gdb.execute("monitor ReadCSR 0x7b0", to_string=True)
gdb.write(f"[dcsr] Before: {read_out.strip()}\n")

import re
m = re.search(r'(?:0x)?([0-9A-Fa-f]{8})', read_out)
if not m:
    raise gdb.GdbError(f"Cannot parse dcsr from: {read_out.strip()}")
old_dcsr = int(m.group(1), 16)

DEBUG_RESUME_MASK = (1 << 15) | (1 << 13) | (1 << 12) | (1 << 2)
new_dcsr = old_dcsr & ~DEBUG_RESUME_MASK
gdb.write(f"[dcsr] old=0x{old_dcsr:08X} -> new=0x{new_dcsr:08X} (cleared bits 15,13,12,2)\n")

gdb.execute(f"monitor WriteCSR 0x7b0 0x{new_dcsr:08X}")
verify_out = gdb.execute("monitor ReadCSR 0x7b0", to_string=True)
gdb.write(f"[dcsr] After:  {verify_out.strip()}\n")
gdb.write("[OK] dcsr ebreak bits cleared\n")

# Native continue from 0x80200000 is unreliable through this debug path.
# Step over the first two Linux entry instructions first, then run freely.
try:
    pc_before_run = int(gdb.parse_and_eval("$pc"))
    if pc_before_run == 0x80200000:
        gdb.write("[boot] Advancing past Linux entry stub with stepi x2...\n")
        gdb.execute("stepi")
        gdb.execute("stepi")
        pc_after_run = int(gdb.parse_and_eval("$pc"))
        gdb.write(f"[boot] PC after entry stepi = 0x{pc_after_run:x}\n")
except Exception as e:
    gdb.write(f"[boot] Entry stepi workaround failed: {e}\n")

# ==========================================================
# Phase 7: Launch kernel + auto-dump klog after timeout
# ==========================================================
import os, re, time

LOG_PA        = 0x80ed4060
LOG_LEN       = 0x20000
KERNEL_RUN_SECS = int(os.environ.get("KERNEL_RUN_SECS", "300"))

gdb.write(f"\n=== Phase 7: Launch kernel (run {KERNEL_RUN_SECS}s then dump klog) ===\n")

gdb.execute("delete breakpoints")

# Clear hardware triggers left by Phase 5 hbreak
gdb.write("[triggers] Clearing hardware trigger CSRs...\n")
for trig_idx in range(2):
    gdb.execute(f"monitor WriteCSR 0x7a0 {trig_idx}")  # tselect
    gdb.execute("monitor WriteCSR 0x7a1 0")             # tdata1 = 0 (disable)
    gdb.execute("monitor WriteCSR 0x7a2 0")             # tdata2 = 0 (clear addr)
gdb.write("[OK] Hardware triggers cleared (tselect 0 and 1)\n")

# Use async continue so we can sleep and then interrupt in same Python block
gdb.write(f"[boot] Launching kernel (async), will halt in {KERNEL_RUN_SECS}s...\n")

# Use J-Link monitor to resume execution (non-blocking)
gdb.execute("monitor go")
gdb.write("[boot] Kernel running (via monitor go)...\n")
time.sleep(KERNEL_RUN_SECS)
gdb.write(f"\n[boot] {KERNEL_RUN_SECS}s elapsed. Halting kernel...\n")
gdb.execute("monitor halt")
time.sleep(2)  # Give target time to halt

# Read PC to confirm halted
try:
    pc_test = int(gdb.parse_and_eval("$pc"))
    gdb.write(f"[boot] Target halted at PC = 0x{pc_test & 0xFFFFFFFFFFFFFFFF:016x}\n")
except:
    gdb.write("[boot] PC read failed, retrying halt...\n")
    gdb.execute("monitor halt")
    time.sleep(1)
    try:
        pc_test = int(gdb.parse_and_eval("$pc"))
        gdb.write(f"[boot] Target halted at PC = 0x{pc_test & 0xFFFFFFFFFFFFFFFF:016x}\n")
    except Exception as e:
        gdb.write(f"[boot] Halt failed: {e}\n")
end

python
import gdb, re, os, struct, time

gdb.write("\n=== Phase 8: Dump kernel log (same session) ===\n")

LOG_PA   = 0x80ed4060
LOG_LEN  = 0x20000
RUN_TAG  = os.environ.get("RUN_TAG", time.strftime("run_%Y%m%d_%H%M%S"))
KLOG_BIN = f"/tmp/klog_{RUN_TAG}.bin"
LOG_FILE = f"/tmp/boot_{RUN_TAG}.strings"

# Target is halted after interrupt
try:
    gdb.execute("set $satp = 0")
except:
    pass

# Read state
try:
    pc = int(gdb.parse_and_eval("$pc"))
    gdb.write(f"[state] PC = 0x{pc & 0xFFFFFFFFFFFFFFFF:016x}\n")
except:
    gdb.write("[state] PC read failed\n")

for name, reg in [("satp", "$satp"), ("scause", "$scause"), ("sepc", "$sepc"),
                   ("stval", "$stval"), ("sstatus", "$sstatus"), ("mcause", "$mcause")]:
    try:
        val = int(gdb.parse_and_eval(reg))
        gdb.write(f"[state] {name} = 0x{val & 0xFFFFFFFFFFFFFFFF:016x}\n")
    except:
        pass

# Dump klog binary
gdb.write(f"[dump] Dumping {LOG_LEN} bytes from PA 0x{LOG_PA:x} -> {KLOG_BIN}\n")
gdb.execute(f"dump binary memory {KLOG_BIN} {LOG_PA} {LOG_PA + LOG_LEN}")
gdb.write(f"[dump] Saved to {KLOG_BIN}\n")

# Also save to the standard location
gdb.execute(f"dump binary memory /tmp/klog_latest.bin {LOG_PA} {LOG_PA + LOG_LEN}")

# Read back and extract strings + check for key milestones
try:
    data = open(KLOG_BIN, "rb").read()
    strings = re.findall(rb'[\x20-\x7e]{8,}', data)
    gdb.write(f"\n[strings] Found {len(strings)} strings in klog\n")

    milestones = {
        "clocksource": False,
        "Freeing unused": False,
        "Run /init": False,
        "init_pipe_fs": False,
        "populate_rootfs": False,
        "Kernel panic": False,
        "Oops": False,
        "invalid magic": False,
        "Welcome": False,
        "busybox": False,
        "/bin/sh": False,
    }

    with open(LOG_FILE, "w") as f:
        for i, s in enumerate(strings):
            line = s.decode("ascii", errors="replace")
            f.write(f"{i:4d}: {line}\n")
            for key in milestones:
                if key.lower() in line.lower():
                    milestones[key] = True
            # Print first 60 and last 20 strings
            if i < 60 or i >= len(strings) - 20:
                gdb.write(f"  {i:4d}: {line[:120]}\n")
            elif i == 60:
                gdb.write(f"  ... ({len(strings) - 80} more strings) ...\n")

    gdb.write(f"\n[milestones]\n")
    for key, hit in milestones.items():
        status = "YES" if hit else "no"
        gdb.write(f"  {key:20s}: {status}\n")

    gdb.write(f"\n[files] klog binary: {KLOG_BIN}\n")
    gdb.write(f"[files] klog strings: {LOG_FILE}\n")

except Exception as e:
    gdb.write(f"[error] String extraction failed: {e}\n")

# Re-verify initramfs magic in DDR (check if it was corrupted during kernel run)
try:
    cpio_w0 = int(gdb.parse_and_eval("*(unsigned int*)0x8080f1a8"))
    cpio_w1 = int(gdb.parse_and_eval("*(unsigned int*)0x8080f1ac"))
    expected_cpio = (cpio_w0 == 0x37303730 and cpio_w1 == 0x30303130)
    gdb.write(f"\n[post-check] Initramfs magic @ PA 0x8080f1a8: 0x{cpio_w0:08x} 0x{cpio_w1:08x}")
    gdb.write(f" ({'OK' if expected_cpio else 'CORRUPTED!'})\n")
except Exception as e:
    gdb.write(f"[post-check] Initramfs read failed: {e}\n")

gdb.write("\n=== Boot + dump complete ===\n")
end
