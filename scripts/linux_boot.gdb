# linux_boot.gdb — ZCU104 Rocket Minimal Linux Boot (Phase 1: no binary patches)
#
# Prerequisites:
#   1. run_ps_ddr_init.sh — PS DDR init + bitstream download
#   2. J-Link GDB Server / relay running
#
# What this script does:
#   Phase 1: Zero uninitialized DDR regions via Rocket core
#   Phase 2: Restore fw_payload.bin (15MB) + DTB via SBA
#   Phase 3: L2 cache invalidation for restored regions
#   Phase 4: fence.i
#   Phase 5: Boot OpenSBI -> mret -> Linux
#   Phase 6: Clear dcsr ebreak bits
#   Phase 7: Run kernel for a timed interval
#   Phase 8: Dump printk ring buffer in the same session

set pagination off
set confirm off
set breakpoint auto-hw off
set remotetimeout 600

file /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf

python
import os, gdb, time

host = os.environ.get("JLINK_HOST", "172.19.128.1")
relay_port = int(os.environ.get("JLINK_PORT", "12331"))
cfg_name = os.environ.get("CHIPYARD_ZCU104_CFG", "")
skip_l2_env = os.environ.get("SKIP_L2")
if skip_l2_env is None:
    skip_l2 = 1 if "NoL2" in cfg_name else 0
else:
    skip_l2 = int(skip_l2_env)

gdb.execute(f"set $skip_l2 = {skip_l2}")
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
        gdb.write(f"[warn] Connect attempt {attempt} failed: {err}\n")
        if attempt < 3:
            time.sleep(2)
if last_error is not None:
    raise last_error
if cfg_name:
    gdb.write(f"[cfg] CHIPYARD_ZCU104_CFG={cfg_name}\n")
gdb.write(f"[cfg] skip_l2={skip_l2}\n")
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

# Safe scratch region above OpenSBI _fw_end (0x80037000)
# zero_loop: sd zero,0(a0); c.addi a0,8; blt a0,a1,loop; c.ebreak
set *(unsigned int*)0x80038000 = 0x00053023
set *(unsigned short*)0x80038004 = 0x0521
set *(unsigned int*)0x80038006 = 0xFEB54DE3
set *(unsigned short*)0x8003800A = 0x9002

# fence.i trampoline
set *(unsigned int*)0x80038100 = 0x0000100f
set *(unsigned short*)0x80038104 = 0x9002

if $skip_l2 == 0
set *(unsigned long long*)0x2010200 = 0x80038000
set *(unsigned long long*)0x2010200 = 0x80038040
set *(unsigned long long*)0x2010200 = 0x80038100
else
echo [L2flush] Skipped Phase 1 trampoline flush for no-L2 config\n
end

set $pc = 0x80038100
stepi
echo [ok] fence.i\n

delete breakpoints
hbreak *0x8003800A

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
# Phase 2: Restore fw_payload.bin + DTB via SBA
# ============================================================
echo \n=== Phase 2: Restore fw_payload.bin (15MB via SBA) ===\n

monitor WriteCSR 0x180 0
monitor WriteCSR 0x7b0 0x4000F0C3

set *(unsigned int*)0x80038100 = 0x0000100f
set *(unsigned short*)0x80038104 = 0x9002
if $skip_l2 == 0
set *(unsigned long long*)0x2010200 = 0x80038100
else
echo [L2flush] Skipped Phase 2 trampoline flush for no-L2 config\n
end
set $pc = 0x80038100
stepi
echo [ok] fence.i\n

python
import os, gdb, time

chunk_dir = "/tmp/fw_chunks_new"
base_addr = 0x80000000
chunk_size = 4194304
reconnect_every = 4
_host = os.environ.get("JLINK_HOST", "172.19.128.1")
_port = int(os.environ.get("JLINK_PORT", "12331"))

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
        gdb.write("[reconnect] OK\n")

    addr = base_addr + i * chunk_size
    fpath = os.path.join(chunk_dir, fname)
    fsize = os.path.getsize(fpath)
    gdb.write(f"[restore {i+1}/{total}] {fname} -> 0x{addr:08x} ({fsize} bytes)...\n")
    gdb.execute(f"restore {fpath} binary 0x{addr:x}")
    gdb.write(f"[restore {i+1}/{total}] done\n")

gdb.write("[ok] fw_payload.bin restored (15MB in chunks)\n")
end

restore /root/chipyard/fpga/linux-bringup/dtb/chipyard-zcu104-linux-slip.dtb binary 0x84000000
echo [ok] DTB restored at 0x84000000\n

# External DTB at 0x84000000 carries bootargs overrides.
# OpenSBI overwrites a1 with its embedded DTB; Phase 5 redirects a1 back.
echo [dtb] External DTB provides chosen bootargs; will redirect a1 at mret\n

# ============================================================
# Phase 3: L2 cache invalidation after SBA restore
# ============================================================
echo \n=== Phase 3: Invalidate L2 cache for firmware region ===\n

if $skip_l2 == 0
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
echo [ok] fence.i for L2 invalidation\n

delete breakpoints
hbreak *0x8003800C
set $a0 = 0x80000000
set $a1 = 0x80EC4000
set $a2 = 0x2010200
set $pc = 0x80038000
echo [L2inv] Invalidating L2 for firmware region (17MB)...\n
continue
echo [L2inv] Firmware region done\n

delete breakpoints
hbreak *0x8003800C
set $a0 = 0x84000000
set $a1 = 0x84002000
set $a2 = 0x2010200
set $pc = 0x80038000
echo [L2inv] Invalidating L2 for DTB region...\n
continue
echo [L2inv] DTB region done\n
else
echo [L2inv] Skipped for no-L2 config\n
end


# Verify SBA write integrity
echo [verify] Checking SBA write integrity...\n
python
import gdb
import struct

def read_u32(addr):
    return int(gdb.parse_and_eval(f"*(unsigned int*)0x{addr:x}"))

fw_path = "/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.bin"
fw_data = open(fw_path, "rb").read()
cpio_off = fw_data.find(b"070701")
if cpio_off < 0:
    gdb.write("[FAIL] Could not find CPIO magic in fw_payload.bin\n")
    cpio_pa = None
else:
    cpio_pa = 0x80000000 + cpio_off
    gdb.write(f"[verify] First CPIO header in fw_payload.bin: off=0x{cpio_off:x} pa=0x{cpio_pa:x}\n")

if cpio_pa is not None:
    cpio_w0 = read_u32(cpio_pa)
    cpio_w1 = read_u32(cpio_pa + 4)
    gdb.write(f"[verify] Initramfs magic @ 0x{cpio_pa:x}: 0x{cpio_w0:08x} 0x{cpio_w1:08x}\n")
    if cpio_w0 == 0x37303730 and (cpio_w1 & 0xFFFF) == 0x3130:
        gdb.write("[verify] Initramfs magic: OK (cpio 070701)\n")
    else:
        gdb.write("[FAIL] Initramfs magic MISMATCH at derived CPIO location\n")

linux_w0 = read_u32(0x80200000)
if linux_w0 == 0x106f5a4d:
    gdb.write("[verify] Linux _start: OK\n")
else:
    gdb.write(f"[FAIL] Linux _start: 0x{linux_w0:08x} (expected 0x106f5a4d)\n")

osbi_w0 = read_u32(0x80000000)
if osbi_w0 == 0x0e976f05:
    gdb.write("[verify] OpenSBI entry: OK\n")
else:
    gdb.write(f"[FAIL] OpenSBI entry: 0x{osbi_w0:08x} (expected 0x0e976f05)\n")

spots = [
    0x0, 0x10000, 0x40000, 0x80000, 0x100000, 0x200000, 0x400000,
    0x600000, 0x80f1a8, 0x80f200, 0x900000, 0xa00000, 0xb00000,
    0xc00000, 0xec0000, 0xec3200,
]
mismatches = 0
for off in spots:
    if off + 4 > len(fw_data):
        continue
    expected = struct.unpack("<I", fw_data[off:off + 4])[0]
    actual = read_u32(0x80000000 + off)
    if actual != expected:
        gdb.write(
            f"[FAIL] Mismatch @ 0x{0x80000000 + off:08x}: got 0x{actual:08x} expected 0x{expected:08x}\n"
        )
        mismatches += 1
gdb.write(f"[verify] Spot-check: {len(spots)} locations, {mismatches} mismatches\n")
end


# ============================================================
# Phase 4: fence.i
# ============================================================
echo \n=== Phase 4: fence.i ===\n

set *(unsigned int*)0x80038100 = 0x0000100f
set *(unsigned short*)0x80038104 = 0x9002
if $skip_l2 == 0
set *(unsigned long long*)0x2010200 = 0x80038100
else
echo [L2flush] Skipped Phase 4 trampoline flush for no-L2 config\n
end
set $pc = 0x80038100
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
hbreak *0x8000b1d2
echo [boot] Running OpenSBI to mret...\n
continue

python
import gdb, re

pc = int(gdb.parse_and_eval("$pc"))
if pc != 0x8000b1d2:
    gdb.write(f"\n[FAIL] Expected mret at 0x8000b1d2, got 0x{pc:x}\n")
    gdb.execute("info reg pc ra sp a0 a1 a2")
    gdb.execute("x/8i $pc")
    raise gdb.GdbError("OpenSBI did not reach mret")

gdb.write("[OK] OpenSBI reached mret\n")
gdb.execute("delete breakpoints")

a1_val = int(gdb.parse_and_eval("$a1"))
gdb.write(f"[dtb] a1 from OpenSBI = 0x{a1_val:x}\n")
try:
    dtb_magic = int(gdb.parse_and_eval(f"*(unsigned int*)0x{a1_val:x}"))
    gdb.write(f"[dtb] DTB magic at a1: 0x{dtb_magic:08x}")
    if dtb_magic == 0xedfe0dd0:
        gdb.write(" (valid)\n")
    else:
        gdb.write(" (INVALID!)\n")
except Exception as err:
    gdb.write(f"[dtb] DTB probe failed: {err}\n")

gdb.execute("set $a1 = 0x84000000")
gdb.write("[dtb] Redirected a1 -> 0x84000000 for external DTB\n")

gdb.execute("hbreak *0x80200000")
gdb.write("[boot] Continuing from mret to Linux _start...\n")
gdb.execute("continue")

pc2 = int(gdb.parse_and_eval("$pc"))
gdb.write(f"[OK] Linux _start: pc=0x{pc2:x}\n")
if pc2 != 0x80200000:
    gdb.write(f"[WARN] Expected 0x80200000, got 0x{pc2:x}\n")

gdb.execute("delete breakpoints")

gdb.write("\n=== Phase 5.5: GDB patches SKIPPED (System.map mismatch) ===\n")
gdb.write("\n=== Phase 6: Clear dcsr ebreak bits ===\n")

read_out = gdb.execute("monitor ReadCSR 0x7b0", to_string=True)
gdb.write(f"[dcsr] Before: {read_out.strip()}\n")

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

try:
    pc_before_run = int(gdb.parse_and_eval("$pc"))
    if pc_before_run == 0x80200000:
        gdb.write("[boot] Advancing past Linux entry stub with stepi x2...\n")
        gdb.execute("stepi")
        gdb.execute("stepi")
        pc_after_run = int(gdb.parse_and_eval("$pc"))
        gdb.write(f"[boot] PC after entry stepi = 0x{pc_after_run:x}\n")
except Exception as err:
    gdb.write(f"[boot] Entry stepi workaround failed: {err}\n")
end


# ==========================================================
# Phase 7: Launch kernel + auto-dump klog after timeout
# ==========================================================
python
import os, time, gdb

KERNEL_RUN_SECS = int(os.environ.get("KERNEL_RUN_SECS", "300"))

gdb.write(f"\n=== Phase 7: Launch kernel (run {KERNEL_RUN_SECS}s then dump klog) ===\n")
gdb.execute("delete breakpoints")

gdb.write("[triggers] Clearing hardware trigger CSRs...\n")
for trig_idx in range(2):
    gdb.execute(f"monitor WriteCSR 0x7a0 {trig_idx}")
    gdb.execute("monitor WriteCSR 0x7a1 0")
    gdb.execute("monitor WriteCSR 0x7a2 0")
gdb.write("[OK] Hardware triggers cleared (tselect 0 and 1)\n")

gdb.write(f"[boot] Launching kernel (async), will halt in {KERNEL_RUN_SECS}s...\n")
gdb.execute("monitor go")
gdb.write("[boot] Kernel running (via monitor go)...\n")
time.sleep(KERNEL_RUN_SECS)
gdb.write(f"\n[boot] {KERNEL_RUN_SECS}s elapsed. Halting kernel...\n")
gdb.execute("monitor halt")
time.sleep(2)

try:
    pc_test = int(gdb.parse_and_eval("$pc"))
    gdb.write(f"[boot] Target halted at PC = 0x{pc_test & 0xFFFFFFFFFFFFFFFF:016x}\n")
except Exception as err:
    gdb.write(f"[boot] PC read after halt failed: {err}\n")
end


python
import gdb, re, os, struct, time, subprocess

gdb.write("\n=== Phase 8: Dump kernel log (same session) ===\n")

VMLINUX = "/root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux"
NM = "/root/chipyard/.oclaw-env/riscv-tools/bin/riscv64-unknown-elf-nm"
RUN_TAG = os.environ.get("RUN_TAG", time.strftime("run_%Y%m%d_%H%M%S"))
KLOG_BIN = f"/tmp/klog_{RUN_TAG}.bin"
LOG_FILE = f"/tmp/boot_{RUN_TAG}.strings"
SYMBOL_CACHE = None

def load_symbols():
    global SYMBOL_CACHE
    if SYMBOL_CACHE is None:
        text = subprocess.check_output([NM, "-n", VMLINUX], text=True)
        SYMBOL_CACHE = {}
        for line in text.splitlines():
            parts = line.split()
            if len(parts) == 3:
                try:
                    SYMBOL_CACHE[parts[2]] = int(parts[0], 16)
                except ValueError:
                    pass
    return SYMBOL_CACHE

def lookup_symbol(name):
    return load_symbols().get(name)

def kernel_va_to_pa(addr):
    if addr is None:
        return None
    if 0xffffffd800000000 <= addr < 0xffffffd900000000:
        return addr - 0xffffffd800000000 + 0x80000000
    if addr >= 0xffffffff80000000:
        return (addr - 0xffffffff80000000 + 0x80200000) & 0xFFFFFFFFFFFFFFFF
    return addr

def read_pa_u32(pa):
    tmp = f"/tmp/_phase8_rd32_{pa:x}.bin"
    gdb.execute(f"dump binary memory {tmp} 0x{pa:x} 0x{pa + 4:x}", to_string=True)
    with open(tmp, "rb") as f:
        return struct.unpack("<I", f.read(4))[0]

def read_pa_u64(pa):
    tmp = f"/tmp/_phase8_rd64_{pa:x}.bin"
    gdb.execute(f"dump binary memory {tmp} 0x{pa:x} 0x{pa + 8:x}", to_string=True)
    with open(tmp, "rb") as f:
        return struct.unpack("<Q", f.read(8))[0]

def read_csr(name, csr_num):
    try:
        out = gdb.execute(f"monitor ReadCSR 0x{csr_num:x}", to_string=True)
        m = re.search(r'(?:0x)?([0-9A-Fa-f]{1,16})', out)
        if m:
            val = int(m.group(1), 16)
            gdb.write(f"[state] {name} = 0x{val & 0xFFFFFFFFFFFFFFFF:016x}\n")
            return val
    except Exception as err:
        gdb.write(f"[state] {name} read failed: {err}\n")
    return None

try:
    pc = int(gdb.parse_and_eval("$pc"))
    gdb.write(f"[state] PC = 0x{pc & 0xFFFFFFFFFFFFFFFF:016x}\n")
except Exception:
    gdb.write("[state] PC read failed\n")

satp_val = read_csr("satp", 0x180)
read_csr("scause", 0x142)
read_csr("sepc", 0x141)
read_csr("stval", 0x143)
read_csr("mcause", 0x342)
read_csr("mepc", 0x341)
read_csr("mtval", 0x343)
read_csr("dcsr", 0x7b0)
read_csr("dpc", 0x7b1)

log_buf_len_va = lookup_symbol("log_buf_len")
log_buf_va_var = lookup_symbol("log_buf")
static_log_buf_va = lookup_symbol("__log_buf")

if log_buf_len_va is None or log_buf_va_var is None or static_log_buf_va is None:
    raise gdb.GdbError("Could not resolve printk ring symbols from vmlinux")

log_buf_len_pa = kernel_va_to_pa(log_buf_len_va)
log_buf_var_pa = kernel_va_to_pa(log_buf_va_var)
static_log_buf_pa = kernel_va_to_pa(static_log_buf_va)

log_buf_len = read_pa_u32(log_buf_len_pa)
log_buf_ptr = read_pa_u64(log_buf_var_pa)
log_buf_pa = kernel_va_to_pa(log_buf_ptr)

gdb.write(f"[klog] log_buf_len VA=0x{log_buf_len_va:016x} PA=0x{log_buf_len_pa:08x} -> 0x{log_buf_len:x}\n")
gdb.write(f"[klog] log_buf     VA=0x{log_buf_va_var:016x} PA=0x{log_buf_var_pa:08x} -> 0x{log_buf_ptr:016x}\n")
gdb.write(f"[klog] __log_buf   VA=0x{static_log_buf_va:016x} PA=0x{static_log_buf_pa:08x}\n")

dump_pa = log_buf_pa
if not (0x80000000 <= dump_pa < 0x100000000):
    gdb.write(f"[klog] log_buf PA 0x{dump_pa:016x} out of DDR range, falling back to __log_buf\n")
    dump_pa = static_log_buf_pa

if not (0 < log_buf_len <= 0x200000):
    gdb.write(f"[klog] log_buf_len 0x{log_buf_len:x} invalid, falling back to 0x20000\n")
    log_buf_len = 0x20000

dump_len = min(log_buf_len, 0x40000)

gdb.write(f"[dump] Dumping {dump_len} bytes from PA 0x{dump_pa:x} -> {KLOG_BIN}\n")
gdb.execute(f"dump binary memory {KLOG_BIN} 0x{dump_pa:x} 0x{dump_pa + dump_len:x}")
gdb.write(f"[dump] Saved to {KLOG_BIN}\n")
gdb.execute(f"dump binary memory /tmp/klog_latest.bin 0x{dump_pa:x} 0x{dump_pa + dump_len:x}")

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
        "sdhci": False,
        "mmc0": False,
        "mmcblk": False,
        "arasan": False,
    }

    with open(LOG_FILE, "w") as f:
        for i, s in enumerate(strings):
            line = s.decode("ascii", errors="replace")
            f.write(f"{i:4d}: {line}\n")
            for key in milestones:
                if key.lower() in line.lower():
                    milestones[key] = True
            if i < 60 or i >= len(strings) - 20:
                gdb.write(f"  {i:4d}: {line[:120]}\n")
            elif i == 60:
                gdb.write(f"  ... ({len(strings) - 80} more strings) ...\n")

    gdb.write("\n[milestones]\n")
    for key, hit in milestones.items():
        status = "YES" if hit else "no"
        gdb.write(f"  {key:20s}: {status}\n")

    gdb.write(f"\n[files] klog binary: {KLOG_BIN}\n")
    gdb.write(f"[files] klog strings: {LOG_FILE}\n")

except Exception as err:
    gdb.write(f"[error] String extraction failed: {err}\n")

try:
    fw_data = open("/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.bin", "rb").read()
    cpio_off = fw_data.find(b"070701")
    if cpio_off >= 0:
        cpio_pa = 0x80000000 + cpio_off
        cpio_w0 = int(gdb.parse_and_eval(f"*(unsigned int*)0x{cpio_pa:x}"))
        cpio_w1 = int(gdb.parse_and_eval(f"*(unsigned int*)0x{cpio_pa + 4:x}"))
        expected_cpio = (cpio_w0 == 0x37303730 and (cpio_w1 & 0xFFFF) == 0x3130)
        gdb.write(f"\n[post-check] Initramfs magic @ PA 0x{cpio_pa:x}: 0x{cpio_w0:08x} 0x{cpio_w1:08x}")
        gdb.write(f" ({'OK' if expected_cpio else 'CORRUPTED!'})\n")
    else:
        gdb.write("\n[post-check] Could not find CPIO header in fw_payload.bin\n")
except Exception as err:
    gdb.write(f"[post-check] Initramfs read failed: {err}\n")

gdb.write("\n=== Boot + dump complete ===\n")
end
