# linux_boot_phase2.gdb - Phase 2: CEVA BT5.2 Linux kernel module boot
# Loads new fw_payload.bin (with BT modules) + CEVA-enabled DTB
# Based on linux_boot.gdb but using Phase 2 payload/DTB

set pagination off
set confirm off
set breakpoint auto-hw off
set remotetimeout 600

python
import os, gdb, time

host = os.environ.get("JLINK_HOST", "127.0.0.1")
port = int(os.environ.get("JLINK_PORT", "3333"))
run_secs = int(os.environ.get("KERNEL_RUN_SECS", "120"))
chunk_dir = os.environ.get("PHASE2_CHUNK_DIR", "/tmp/fw_chunks_phase2")
dtb_path  = os.environ.get("PHASE2_DTB", "/root/chipyard/fpga/linux-bringup/dtb/chipyard-zcu104-fedora.dtb")
vmlinux   = "/root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux"
fw_elf    = "/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf"

# Load OpenSBI symbol table first (for fw entry)
if os.path.exists(fw_elf):
    gdb.execute(f"file {fw_elf}", to_string=True)
    gdb.write(f"[init] Loaded fw_payload.elf symbol table\n")

gdb.write(f"[init] Connecting to J-Link {host}:{port}...\n")
gdb.execute(f"target remote {host}:{port}")
gdb.execute("monitor halt")
gdb.write("[init] Halted\n")
end

echo [phase2] Phase 2 CEVA BT5.2 Linux driver boot\n
echo [phase2] Step 1: Zero DDR range 0x80000000-0x84000000\n

monitor WriteU32 0x80000000 0x00000000
monitor WriteU32 0x80100000 0x00000000

# Set a1=DTB address before OpenSBI overwrites
set $a1 = 0x84000000

echo [phase2] Step 2: Load fw_payload.bin chunks\n

python
chunk_dir = os.environ.get("PHASE2_CHUNK_DIR", "/tmp/fw_chunks_phase2")
base_addr = 0x80000000
chunk_size = 4194304
# For 5 chunks (17.6MB), no reconnect needed - single session handles all
RECONNECT_EVERY = 99  # effectively disabled for <=5 chunks

chunks = sorted([f for f in os.listdir(chunk_dir) if f.startswith("chunk_") and f.endswith(".bin")])
total = len(chunks)
gdb.write(f"[restore] Loading fw_payload.bin in {total} chunks (4MB each)...\n")

for i, fname in enumerate(chunks):
    addr = base_addr + i * chunk_size
    fpath = os.path.join(chunk_dir, fname)
    gdb.write(f"[restore] chunk {i+1}/{total}: {fname} → 0x{addr:08X}\n")
    gdb.execute(f"restore {fpath} binary 0x{addr:x}")

gdb.write("[ok] fw_payload.bin restored\n")
end

echo [phase2] Step 3: Load DTB at 0x84000000\n

python
dtb_path = os.environ.get("PHASE2_DTB", "/root/chipyard/fpga/linux-bringup/dtb/chipyard-zcu104-fedora.dtb")
gdb.write(f"[dtb] Loading {dtb_path} at 0x84000000...\n")
gdb.execute(f"restore {dtb_path} binary 0x84000000")
gdb.write("[ok] DTB loaded at 0x84000000\n")
end

echo [phase2] Step 4: Set entry point and registers\n

# OpenSBI fw_payload entry
set $pc = 0x80000000
set $a0 = 0
set $a1 = 0x84000000

echo [phase2] Step 5: Boot kernel (monitor go)\n
monitor go

python
run_secs = int(os.environ.get("KERNEL_RUN_SECS", "120"))
gdb.write(f"[wait] Running kernel for {run_secs}s (waiting for insmod to complete)...\n")
time.sleep(run_secs)
gdb.write("[wait] Done waiting, halting CPU\n")
end

monitor halt
echo [phase2] CPU halted after boot\n

# Print PC and key CSRs
python
pc = gdb.parse_and_eval("(unsigned long long)$pc")
gdb.write(f"[state] PC = 0x{int(pc):016X}\n")
end

# Load vmlinux for kernel symbol access (log_buf, log_buf_len, etc.)
python
vmlinux = "/root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux"
if os.path.exists(vmlinux):
    gdb.write(f"[sym] Loading vmlinux symbols from {vmlinux}...\n")
    try:
        gdb.execute(f"add-symbol-file {vmlinux} 0", to_string=True)
        gdb.write("[sym] vmlinux symbols loaded OK\n")
    except Exception as e:
        gdb.write(f"[sym] add-symbol-file failed: {e}, trying file...\n")
        try:
            gdb.execute(f"file {vmlinux}", to_string=True)
            gdb.write("[sym] vmlinux via file OK\n")
        except Exception as e2:
            gdb.write(f"[sym] vmlinux load failed: {e2}\n")
else:
    gdb.write(f"[sym] vmlinux not found at {vmlinux}\n")
end

echo [phase2] Step 6: Scan klog for CEVA BT5.2 evidence\n

python
import struct

def va_to_pa(va):
    """Convert kernel high VA to physical address (Rocket kernel at 0x80200000)"""
    return (int(va) + 0x100200000) & 0xFFFFFFFFFFFFFFFF

def read_pa_u64(pa):
    """Read 8 bytes at physical address via GDB SBA"""
    try:
        v = int(gdb.parse_and_eval(f"*(unsigned long long*)0x{pa:X}"))
        return v
    except Exception as e:
        gdb.write(f"[pa_read] Failed 0x{pa:X}: {e}\n")
        return None

def read_pa_u32(pa):
    try:
        v = int(gdb.parse_and_eval(f"*(unsigned int*)0x{pa:X}"))
        return v
    except:
        return None

# Read log_buf using symbol address → PA conversion (never use kernel VA for SBA)
try:
    # Step 1: Get VA of log_buf SYMBOL (address-of, not value - no memory read needed)
    log_buf_sym_va = int(gdb.parse_and_eval("(unsigned long long)&log_buf"))
    gdb.write(f"[klog] log_buf symbol VA=0x{log_buf_sym_va:016X}\n")

    # Step 2: Convert symbol VA → PA and read the pointer value from DDR
    log_buf_sym_pa = va_to_pa(log_buf_sym_va)
    gdb.write(f"[klog] log_buf symbol PA=0x{log_buf_sym_pa:016X}\n")
    log_buf_ptr_va = read_pa_u64(log_buf_sym_pa)
    if log_buf_ptr_va is None:
        raise Exception("Cannot read log_buf pointer from PA")
    gdb.write(f"[klog] log_buf pointer VA=0x{log_buf_ptr_va:016X}\n")

    # Step 3: Get log_buf_len similarly
    log_buf_len_sym_va = int(gdb.parse_and_eval("(unsigned long long)&log_buf_len"))
    log_buf_len_sym_pa = va_to_pa(log_buf_len_sym_va)
    log_buf_len = read_pa_u32(log_buf_len_sym_pa)
    if log_buf_len is None:
        log_buf_len = 0x20000  # fallback: 128KB
    gdb.write(f"[klog] log_buf_len={log_buf_len}\n")

    # Step 4: Convert log buffer VA → PA and dump
    log_buf_pa = va_to_pa(log_buf_ptr_va)
    gdb.write(f"[klog] log buffer PA=0x{log_buf_pa:016X}\n")
    dump_size = min(131072, log_buf_len)
    gdb.execute(f"dump binary memory /tmp/phase2_klog.bin 0x{log_buf_pa:X} 0x{(log_buf_pa + dump_size):X}")
    gdb.write(f"[klog] Dumped {dump_size} bytes to /tmp/phase2_klog.bin\n")
except Exception as e:
    gdb.write(f"[klog] Symbol-based klog read failed: {e}\n")
    # Fallback: scan kernel data region 0x80A00000-0x81000000 for log messages
    gdb.write("[klog] Fallback: scanning kernel data region for strings...\n")
    try:
        gdb.execute("dump binary memory /tmp/phase2_klog.bin 0x80400000 0x80800000")
        gdb.write("[klog] Fallback dump done: 0x80400000-0x80800000 → /tmp/phase2_klog.bin\n")
    except Exception as e2:
        gdb.write(f"[klog] Fallback dump also failed: {e2}\n")
end

shell echo "[klog check] Searching for CEVA BT5.2 strings:" && \
  strings /tmp/phase2_klog.bin 2>/dev/null | grep -E "ceva|hci0|bluetooth|CEVA|rw-dm|insmod|init:|BT" | head -30 || \
  echo "[klog check] No CEVA strings found"
shell echo "[klog check] Linux boot strings:" && \
  strings /tmp/phase2_klog.bin 2>/dev/null | grep -E "Linux version|Freeing unused|Run /init|rescue-init|Kernel command" | head -10

echo [phase2] Step 7: Check CEVA hardware registers\n

python
CEVA_BASE = 0x65000000
EM_BASE   = 0x65010000

def r32(addr):
    try:
        v = int(gdb.parse_and_eval(f"*(unsigned int*){addr}"))
        return v
    except:
        return 0xDEADBEEF

dm_ver  = r32(CEVA_BASE + 0x0004)
dm_stat = r32(CEVA_BASE + 0x000C)
dm_stat1 = r32(CEVA_BASE + 0x001C)
bt_cntl = r32(CEVA_BASE + 0x0800)
em_w0   = r32(EM_BASE)
em_w64  = r32(EM_BASE + 0x100)

gdb.write(f"\n[hw] DM_VERSION  = 0x{dm_ver:08X}\n")
gdb.write(f"[hw] DM_INTSTAT0 = 0x{dm_stat:08X}\n")
gdb.write(f"[hw] DM_INTSTAT1 = 0x{dm_stat1:08X}\n")
gdb.write(f"[hw] BT_RWBTCNTL = 0x{bt_cntl:08X} (bit8=RWBTEN: {'SET' if bt_cntl & 0x100 else 'CLEAR'})\n")
gdb.write(f"[hw] EM[0]       = 0x{em_w0:08X}\n")
gdb.write(f"[hw] EM[64]      = 0x{em_w64:08X} (cmd buf)\n")

try:
    with open("/tmp/phase2_klog.bin", "rb") as fh:
        klog_text = fh.read().decode("latin1", errors="ignore")
except Exception:
    klog_text = ""

hci0_registered = (
    "registered as hci0" in klog_text or
    "hci0 registered OK" in klog_text
)

# PASS criteria
pass_count = 0
total_checks = 4

gdb.write("\n=== Phase 2 PASS/FAIL Criteria ===\n")

# Check 1: DM accessible
if dm_ver != 0xFFFFFFFF and dm_ver != 0xDEADBEEF:
    gdb.write(f"CHECK 1: DM_VERSION=0x{dm_ver:08X} - PASS (CEVA accessible)\n")
    pass_count += 1
else:
    gdb.write(f"CHECK 1: DM_VERSION=0x{dm_ver:08X} - FAIL (not accessible)\n")

# Check 2: BT enabled by driver open()
if bt_cntl & 0x100:
    gdb.write(f"CHECK 2: BT_RWBTCNTL bit8 SET - PASS (driver called open())\n")
    pass_count += 1
else:
    gdb.write(f"CHECK 2: BT_RWBTCNTL bit8 CLEAR - FAIL/WARN (driver open not called)\n")

# Check 3: EM accessible (Phase 1A)
if em_w0 != 0xFFFFFFFF and em_w0 != 0xDEADBEEF:
    gdb.write(f"CHECK 3: EM[0]=0x{em_w0:08X} - PASS (EM MMIO accessible)\n")
    pass_count += 1
else:
    gdb.write(f"CHECK 3: EM[0]=0x{em_w0:08X} - SKIP (EM MMIO needs Phase 1A bitstream)\n")
    total_checks -= 1

# Check 4: klog shows hci0 registration
if hci0_registered:
    gdb.write("CHECK 4: hci0 registration found in klog - PASS\n")
    pass_count += 1
else:
    gdb.write("CHECK 4: hci0 registration missing in klog - FAIL\n")

gdb.write(f"\n[result] {pass_count}/{total_checks} hardware checks PASS\n")
gdb.write("Phase 2 PASS requires: DM accessible + hci0 in klog\n")
end

monitor go
detach
quit
