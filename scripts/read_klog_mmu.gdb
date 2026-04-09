set pagination off
set confirm off
set remotetimeout 60

file /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf

python
import gdb, os, struct, time, re

host = os.environ.get("JLINK_HOST", "172.19.128.1")
port = int(os.environ.get("JLINK_PORT", "2331"))
gdb.execute(f"target remote {host}:{port}")
gdb.execute("monitor halt")
time.sleep(1)

# Read PA via SBA
def read_pa_u64(pa):
    tmp = f"/tmp/_rd_{pa:x}.bin"
    gdb.execute(f"dump binary memory {tmp} 0x{pa:x} 0x{pa+8:x}", to_string=True)
    with open(tmp, "rb") as f:
        return struct.unpack("<Q", f.read(8))[0]

def read_pa_u32(pa):
    tmp = f"/tmp/_rd_{pa:x}.bin"
    gdb.execute(f"dump binary memory {tmp} 0x{pa:x} 0x{pa+4:x}", to_string=True)
    with open(tmp, "rb") as f:
        return struct.unpack("<I", f.read(4))[0]

# SV39 page table walk
satp_out = gdb.execute("monitor ReadCSR 0x180", to_string=True)
m = re.search(r'(?:0x)?([0-9A-Fa-f]{8,16})', satp_out)
satp_val = int(m.group(1), 16) if m else None
gdb.write(f"[mmu] satp = 0x{satp_val:016x}\n")

satp_ppn = satp_val & 0xFFFFFFFFFFF
root_pt_pa = satp_ppn << 12
gdb.write(f"[mmu] root PT PA = 0x{root_pt_pa:x}\n")

def va_to_pa(va):
    vpn2 = (va >> 30) & 0x1FF
    vpn1 = (va >> 21) & 0x1FF
    vpn0 = (va >> 12) & 0x1FF
    pg_off = va & 0xFFF
    
    pte2 = read_pa_u64(root_pt_pa + vpn2 * 8)
    if not (pte2 & 1):
        raise Exception(f"L2 PTE invalid: 0x{pte2:x}")
    if pte2 & 0xE:  # 1GB leaf
        return ((pte2 >> 10) << 30) | (va & 0x3FFFFFFF)
    
    l1_pa = (pte2 >> 10) << 12
    pte1 = read_pa_u64(l1_pa + vpn1 * 8)
    if not (pte1 & 1):
        raise Exception(f"L1 PTE invalid: 0x{pte1:x}")
    if pte1 & 0xE:  # 2MB leaf
        return ((pte1 >> 10) << 21) | (va & 0x1FFFFF)
    
    l0_pa = (pte1 >> 10) << 12
    pte0 = read_pa_u64(l0_pa + vpn0 * 8)
    if not (pte0 & 1):
        raise Exception(f"L0 PTE invalid: 0x{pte0:x}")
    return ((pte0 >> 10) << 12) | pg_off

def read_va_u64(va):
    pa = va_to_pa(va)
    return read_pa_u64(pa)

def read_va_u32(va):
    pa = va_to_pa(va)
    return read_pa_u32(pa)

# Read log_buf pointer
log_buf_var_va = 0xffffffff80cbf368
try:
    log_buf_ptr = read_va_u64(log_buf_var_va)
    gdb.write(f"[klog] log_buf = 0x{log_buf_ptr:016x}\n")
except Exception as e:
    gdb.write(f"[klog] Cannot read log_buf: {e}\n")
    log_buf_ptr = 0

# Read log_buf_len
try:
    log_buf_len = read_va_u32(0xffffffff80cbf370)
    gdb.write(f"[klog] log_buf_len = {log_buf_len}\n")
except Exception as e:
    gdb.write(f"[klog] Cannot read log_buf_len: {e}\n")
    log_buf_len = 0

if log_buf_ptr > 0xffffffc000000000 and log_buf_len > 0:
    # log_buf was reallocated; translate its VA to PA
    try:
        log_buf_pa = va_to_pa(log_buf_ptr)
        gdb.write(f"[klog] log_buf PA = 0x{log_buf_pa:x}\n")
        dump_size = min(log_buf_len, 262144)
        klog_file = "/tmp/klog_mmu_walk.bin"
        gdb.execute(f"dump binary memory {klog_file} 0x{log_buf_pa:x} 0x{log_buf_pa + dump_size:x}")
        gdb.write(f"[klog] Dumped {dump_size} bytes to {klog_file}\n")
    except Exception as e:
        gdb.write(f"[klog] MMU walk failed for log_buf: {e}\n")
elif log_buf_ptr == 0:
    # log_buf not yet initialized; try __log_buf
    log_buf_var_va2 = 0xffffffff80ed0060  # __log_buf VA? No, this is the PA from vmlinux
    # __log_buf symbol VA
    gdb.write("[klog] log_buf = NULL, trying __log_buf via MMU\n")
    try:
        logbuf_va = 0xffffffff80cd0060  # Approximate - need to check
        logbuf_pa = va_to_pa(logbuf_va)
        gdb.write(f"[klog] __log_buf PA (via walk) = 0x{logbuf_pa:x}\n")
        klog_file = "/tmp/klog_mmu_walk.bin"
        gdb.execute(f"dump binary memory {klog_file} 0x{logbuf_pa:x} 0x{logbuf_pa + 131072:x}")
        gdb.write(f"[klog] Dumped 128KB from __log_buf\n")
    except Exception as e:
        gdb.write(f"[klog] __log_buf walk failed: {e}\n")

# Check sepc symbol
gdb.execute("symbol-file /root/chipyard/software/firemarshal/boards/default/linux-clean/vmlinux")

# Check what's at 0xffffffff80451770
sepc_va = 0xffffffff80451770
try:
    sepc_pa = va_to_pa(sepc_va)
    gdb.write(f"\n[sepc] VA 0x{sepc_va:x} -> PA 0x{sepc_pa:x}\n")
    # Read 32 bytes of code at that PA
    code_bytes = b""
    for i in range(4):
        w = read_pa_u64(sepc_pa + i*8)
        code_bytes += w.to_bytes(8, "little")
    gdb.write(f"[sepc] code: {code_bytes.hex()}\n")
except Exception as e:
    gdb.write(f"[sepc] walk failed: {e}\n")

# Also read PC-related info
pc = int(gdb.parse_and_eval("$pc")) & 0xFFFFFFFFFFFFFFFF
gdb.write(f"\n[state] PC = 0x{pc:016x}\n")

# Read saved_command_line via MMU
try:
    scl_ptr = read_va_u64(0xffffffff80918468)
    gdb.write(f"[cmdline] saved_command_line = 0x{scl_ptr:016x}\n")
    if scl_ptr > 0xffffffc000000000:
        scl_pa = va_to_pa(scl_ptr)
        data = b""
        for i in range(32):
            w = read_pa_u64(scl_pa + i*8)
            data += w.to_bytes(8, "little")
        nul = data.find(b'\x00')
        cmdline = data[:nul].decode("ascii", errors="replace") if nul >= 0 else data[:256].hex()
        gdb.write(f"[cmdline] = \"{cmdline}\"\n")
except Exception as e:
    gdb.write(f"[cmdline] Cannot read: {e}\n")

# Read oops_count via MMU
try:
    oops = read_va_u32(0xffffffff80cc0240)
    gdb.write(f"[oops] oops_count = {oops}\n")
except Exception as e:
    gdb.write(f"[oops] Cannot read: {e}\n")

end

quit
