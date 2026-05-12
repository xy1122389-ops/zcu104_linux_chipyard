# linux_boot_phase2_launch.gdb - Phase 2 launch session
# Loads fw_payload.bin + DTB, clears current-run evidence slots, and lets the kernel run.

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
fw_elf    = "/root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf"
vmlinux   = "/root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux"

if os.path.exists(fw_elf):
    gdb.execute(f"file {fw_elf}", to_string=True)
    gdb.write("[init] Loaded fw_payload.elf symbol table\n")

if os.path.exists(vmlinux):
    try:
        gdb.execute(f"add-symbol-file {vmlinux} 0", to_string=True)
        gdb.write("[init] Added vmlinux symbols for pre-boot evidence clears\n")
    except Exception as e:
        gdb.write(f"[init] add-symbol-file vmlinux failed: {e}\n")

gdb.write(f"[init] Connecting to J-Link {host}:{port}...\n")
gdb.execute(f"target remote {host}:{port}")
gdb.execute("monitor halt")
gdb.write("[init] Halted\n")
gdb.execute("monitor WriteCSR 0x180 0")
gdb.execute("monitor WriteCSR 0x7b0 0x4000F0C3")
gdb.write("[init] Reset satp and dcsr to known boot state\n")
end

echo [phase2] Phase 2 CEVA BT5.2 Linux driver boot\n
echo [phase2] Step 1: Zero DDR range 0x80000000-0x84000000\n

monitor WriteU32 0x80000000 0x00000000
monitor WriteU32 0x80100000 0x00000000

set $a1 = 0x84000000

echo [phase2] Step 2: Load fw_payload.bin chunks\n

python
chunk_dir = os.environ.get("PHASE2_CHUNK_DIR", "/tmp/fw_chunks_phase2")
base_addr = 0x80000000
chunk_size = 4194304

chunks = sorted([f for f in os.listdir(chunk_dir) if f.startswith("chunk_") and f.endswith(".bin")])
total = len(chunks)
gdb.write(f"[restore] Loading fw_payload.bin in {total} chunks (4MB each)...\n")

for i, fname in enumerate(chunks):
    addr = base_addr + i * chunk_size
    fpath = os.path.join(chunk_dir, fname)
    gdb.write(f"[restore] chunk {i+1}/{total}: {fname} -> 0x{addr:08X}\n")
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

set $pc = 0x80000000
set $a0 = 0
set $a1 = 0x84000000

echo [phase2] Step 4a: Clear init stage slot\n

monitor WriteU32 0x8F000000 0x00000000
monitor WriteU32 0x8F000004 0x00000000

python
zero_p3bd_path = "/tmp/phase2_zero_p3bd.bin"
if not os.path.exists(zero_p3bd_path) or os.path.getsize(zero_p3bd_path) != 0xA0:
    with open(zero_p3bd_path, "wb") as fh:
        fh.write(b"\x00" * 0xA0)
gdb.write("[phase2] Clearing P3BD breadcrumb slots at PA 0x8F000040\n")
gdb.execute(f"restore {zero_p3bd_path} binary 0x8f000040")
end

echo [phase2] Step 4b: Clear CEVA EM command/event slots\n

python
def va_to_pa(va):
    return (int(va) + 0x100200000) & 0xFFFFFFFFFFFFFFFF

zero_klog_path = "/tmp/phase2_zero_klog.bin"
if not os.path.exists(zero_klog_path) or os.path.getsize(zero_klog_path) != 0x20000:
    with open(zero_klog_path, "wb") as fh:
        fh.write(b"\x00" * 0x20000)

try:
    static_log_buf_sym_va = int(gdb.parse_and_eval("(unsigned long long)&__log_buf"))
    static_log_buf_sym_pa = va_to_pa(static_log_buf_sym_va)
    gdb.write(f"[phase2] Clearing __log_buf at PA 0x{static_log_buf_sym_pa:08X}\n")
    gdb.execute(f"restore {zero_klog_path} binary 0x{static_log_buf_sym_pa:x}")
except Exception as e:
    gdb.write(f"[phase2] __log_buf clear skipped: {e}\n")
end

monitor WriteU32 0x65000800 0x00000000
monitor WriteU32 0x65010100 0x00000000
monitor WriteU32 0x65010104 0x00000000
monitor WriteU32 0x65010108 0x00000000
monitor WriteU32 0x65010120 0x00000000
monitor WriteU32 0x65010124 0x00000000
monitor WriteU32 0x65010110 0x00000000
monitor WriteU32 0x65010114 0x00000000
monitor WriteU32 0x65010118 0x00000000
monitor WriteU32 0x65010160 0x00000000
monitor WriteU32 0x65010164 0x00000000
monitor WriteU32 0x65010168 0x00000000
monitor WriteU32 0x6501016C 0x00000000
monitor WriteU32 0x65010170 0x00000000
monitor WriteU32 0x65010174 0x00000000
monitor WriteU32 0x65010178 0x00000000
monitor WriteU32 0x6501017C 0x00000000
monitor WriteU32 0x65010180 0x00000000
monitor WriteU32 0x65010184 0x00000000
monitor WriteU32 0x65010188 0x00000000
monitor WriteU32 0x6501018C 0x00000000
monitor WriteU32 0x65010190 0x00000000
monitor WriteU32 0x65010194 0x00000000
monitor WriteU32 0x65010198 0x00000000
monitor WriteU32 0x6501019C 0x00000000
monitor WriteU32 0x650101A0 0x00000000
monitor WriteU32 0x650101A4 0x00000000
monitor WriteU32 0x650101A8 0x00000000
monitor WriteU32 0x650101AC 0x00000000
monitor WriteU32 0x650101B0 0x00000000
monitor WriteU32 0x650101B4 0x00000000
monitor WriteU32 0x650101B8 0x00000000
monitor WriteU32 0x650101BC 0x00000000
monitor WriteU32 0x650101C0 0x00000000
monitor WriteU32 0x650101C4 0x00000000
monitor WriteU32 0x650101C8 0x00000000
monitor WriteU32 0x650101CC 0x00000000
monitor WriteU32 0x650101D0 0x00000000
monitor WriteU32 0x650101D4 0x00000000
monitor WriteU32 0x650101D8 0x00000000
monitor WriteU32 0x650101DC 0x00000000
monitor WriteU32 0x650101E0 0x00000000
monitor WriteU32 0x65011000 0x00000000
monitor WriteU32 0x65014000 0x00000000
monitor WriteU32 0x6501FFFC 0x00000000

python
try:
    gdb.write("[phase2] Clearing Phase 2.5 DDR evidence scratch at 0x8FF00000\n")
    gdb.execute(f"restore {zero_klog_path} binary 0x8ff00000")
except Exception as e:
    gdb.write(f"[phase2] DDR evidence clear skipped: {e}\n")
end

python
run_secs = int(os.environ.get("KERNEL_RUN_SECS", "120"))
gdb.write("[phase2] Step 5: Boot kernel (monitor go)\n")
gdb.execute("monitor go")
gdb.write(f"[wait] Running kernel for {run_secs}s before capture session...\n")
time.sleep(run_secs)
gdb.write("[phase2] Launch window complete; ending launch session\n")
end
