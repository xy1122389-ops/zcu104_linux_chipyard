set pagination off
set confirm off
set remotetimeout 60

python
import gdb, os, struct, time

host = os.environ.get("JLINK_HOST", "172.19.128.1")
port = int(os.environ.get("JLINK_PORT", "2331"))
gdb.write(f"[info] Connecting to {host}:{port}\n")
gdb.execute(f"target remote {host}:{port}")
gdb.execute("monitor halt")
time.sleep(1)

# Read 8 bytes from a physical address via SBA
def read_u64(pa):
    tmp = f"/tmp/_rd_{pa:x}.bin"
    gdb.execute(f"dump binary memory {tmp} 0x{pa:x} 0x{pa+8:x}", to_string=True)
    with open(tmp, "rb") as f:
        return struct.unpack("<Q", f.read(8))[0]

def read_u32(pa):
    tmp = f"/tmp/_rd_{pa:x}.bin"
    gdb.execute(f"dump binary memory {tmp} 0x{pa:x} 0x{pa+4:x}", to_string=True)
    with open(tmp, "rb") as f:
        return struct.unpack("<I", f.read(4))[0]

# log_buf VA = 0xffffffff80cbf368 → PA = 0x80ebf368
# log_buf_len VA = 0xffffffff80cbf370 → PA = 0x80ebf370
log_buf_ptr_pa = 0x80ebf368
log_buf_len_pa = 0x80ebf370

log_buf_va = read_u64(log_buf_ptr_pa)
log_buf_len = read_u32(log_buf_len_pa)
gdb.write(f"[klog] log_buf VA = 0x{log_buf_va:016x}\n")
gdb.write(f"[klog] log_buf_len = {log_buf_len} (0x{log_buf_len:x})\n")

# Convert log_buf VA to PA
# If it's in kernel linear mapping: PA = VA - 0xffffffff80000000 + 0x80200000
# If it's in direct mapping (0xffffffd800000000): PA = VA - 0xffffffd800000000 + 0x80000000
if log_buf_va >= 0xffffffd800000000 and log_buf_va < 0xffffffd900000000:
    log_buf_pa = log_buf_va - 0xffffffd800000000 + 0x80000000
elif log_buf_va >= 0xffffffff80000000:
    log_buf_pa = (log_buf_va - 0xffffffff80000000 + 0x80200000) & 0xFFFFFFFFFFFFFFFF
else:
    log_buf_pa = log_buf_va  # already PA or we don't know

gdb.write(f"[klog] log_buf PA = 0x{log_buf_pa:x}\n")

# Also check __log_buf PA = 0x80ed0060 (original buffer before possible realloc)
orig_log_buf_pa = 0x80ed0060

# Dump the main log buffer
dump_size = min(log_buf_len, 262144)  # 256KB max
if dump_size > 0 and log_buf_pa >= 0x80000000 and log_buf_pa < 0x90000000:
    klog_file = "/tmp/klog_via_sba.bin"
    gdb.execute(f"dump binary memory {klog_file} 0x{log_buf_pa:x} 0x{log_buf_pa + dump_size:x}")
    gdb.write(f"[klog] Dumped {dump_size} bytes from PA 0x{log_buf_pa:x} to {klog_file}\n")
else:
    gdb.write(f"[klog] log_buf PA seems invalid, trying __log_buf at 0x{orig_log_buf_pa:x}\n")
    klog_file = "/tmp/klog_via_sba.bin"
    gdb.execute(f"dump binary memory {klog_file} 0x{orig_log_buf_pa:x} 0x{orig_log_buf_pa + 131072:x}")
    gdb.write(f"[klog] Dumped 128KB from __log_buf PA 0x{orig_log_buf_pa:x}\n")

# Also try to understand what's at sepc
# sepc = 0xFFFFFFFF80451770 → PA = 0x80651770
sepc_pa = 0x80651770
gdb.write(f"\n[sepc] Dumping code at sepc PA 0x{sepc_pa:x}\n")
gdb.execute(f"x/16i 0x{sepc_pa}")

# Check mepc = 0xFFFFFFFF8045176C → PA = 0x8065176c
mepc_pa = 0x8065176c
gdb.write(f"\n[mepc] Code at mepc PA 0x{mepc_pa:x}\n")
gdb.execute(f"x/8i 0x{mepc_pa}")

# Read symbol info using vmlinux
gdb.write("\n[sym] Loading vmlinux symbols\n")
gdb.execute("symbol-file /root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux")
gdb.write(f"\n[sym] sepc = 0xFFFFFFFF80451770:\n")
try:
    gdb.execute("info symbol 0xFFFFFFFF80451770")
except:
    pass
gdb.write(f"\n[sym] mepc = 0xFFFFFFFF8045176C:\n")
try:
    gdb.execute("info symbol 0xFFFFFFFF8045176C")
except:
    pass

# Read PC
pc = int(gdb.parse_and_eval("$pc")) & 0xFFFFFFFFFFFFFFFF
gdb.write(f"\n[state] Current PC = 0x{pc:016x}\n")
gdb.execute("info reg pc ra sp gp tp a0 a1 a2")

end

quit
