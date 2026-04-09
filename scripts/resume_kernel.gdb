set pagination off
set confirm off
set remotetimeout 60

file /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf

python
import gdb, os, time, re, struct

host = os.environ.get("JLINK_HOST", "172.19.128.1")
port = int(os.environ.get("JLINK_PORT", "2331"))
gdb.execute(f"target remote {host}:{port}")

# Resume the kernel (it's currently halted)
gdb.write("[resume] Clearing triggers and resuming kernel...\n")
gdb.execute("monitor halt")
time.sleep(0.5)

# Clear hardware triggers
for i in range(2):
    gdb.execute(f"monitor WriteCSR 0x7a0 {i}")
    gdb.execute("monitor WriteCSR 0x7a1 0")
    gdb.execute("monitor WriteCSR 0x7a2 0")

# Set die_kernel_fault trigger on VA (not PA!) so it fires after MMU enable
die_kf_va = 0xffffffff8000687c
# tdata1: type=2, dmode=1, s=1, execute=1, action=1
# But we need to use VA. The trigger should match the VA that the CPU fetches.
# For SV39, the trigger in tdata2 needs the VA bits that CPU presents.
# However, J-Link WriteCSR might truncate to 32 bits...
# Let's use VA anyway: 0xffffffff8000687c
tdata1 = 0x2800000000001054
gdb.execute("monitor WriteCSR 0x7a0 0")
gdb.execute(f"monitor WriteCSR 0x7a2 0x{die_kf_va:x}")
gdb.execute(f"monitor WriteCSR 0x7a1 0x{tdata1:x}")

td2_out = gdb.execute("monitor ReadCSR 0x7a2", to_string=True).strip()
gdb.write(f"[trigger] tdata2 = {td2_out} (expect VA 0x{die_kf_va:x})\n")

# Resume
gdb.execute("monitor go")
run_secs = int(os.environ.get("KERNEL_RUN_SECS", "600"))
gdb.write(f"[resume] Kernel resumed. Waiting {run_secs}s...\n")

# Check every 60 seconds
for i in range(0, run_secs, 60):
    chunk = min(60, run_secs - i)
    time.sleep(chunk)
    elapsed = i + chunk
    gdb.write(f"[wait] {elapsed}/{run_secs}s elapsed\n")

gdb.write(f"[halt] Halting kernel after {run_secs}s...\n")
gdb.execute("monitor halt")
time.sleep(2)
try:
    gdb.execute("maintenance flush register-cache")
except:
    pass

pc = int(gdb.parse_and_eval("$pc")) & 0xFFFFFFFFFFFFFFFF
gdb.write(f"[state] PC = 0x{pc:016x}\n")

# Read CSRs
for name, num in [("sepc", 0x141), ("scause", 0x142), ("stval", 0x143),
                  ("satp", 0x180), ("mepc", 0x341), ("mcause", 0x342)]:
    out = gdb.execute(f"monitor ReadCSR 0x{num:x}", to_string=True).strip()
    gdb.write(f"[csr] {name:10s} = {out}\n")

gdb.execute("info reg pc ra sp gp tp a0 a1 a2")

# Read log_buf via SBA with page table walk
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

satp_out = gdb.execute("monitor ReadCSR 0x180", to_string=True)
m = re.search(r'(?:0x)?([0-9A-Fa-f]{8,16})', satp_out)
satp_val = int(m.group(1), 16) if m else 0
satp_ppn = satp_val & 0xFFFFFFFFFFF
root_pt = satp_ppn << 12

def va_to_pa(va):
    """SV39 page table walk"""
    # Extract only the lower 39 bits for SV39
    va39 = va & 0x7FFFFFFFFF
    vpn2 = (va39 >> 30) & 0x1FF
    vpn1 = (va39 >> 21) & 0x1FF
    vpn0 = (va39 >> 12) & 0x1FF
    pg_off = va39 & 0xFFF
    
    pte2 = read_pa_u64(root_pt + vpn2 * 8)
    if not (pte2 & 1):
        return None
    if pte2 & 0xE:
        return ((pte2 >> 10) << 30) | (va39 & 0x3FFFFFFF)
    
    l1 = (pte2 >> 10) << 12
    pte1 = read_pa_u64(l1 + vpn1 * 8)
    if not (pte1 & 1):
        return None
    if pte1 & 0xE:
        return ((pte1 >> 10) << 21) | (va39 & 0x1FFFFF)
    
    l0 = (pte1 >> 10) << 12
    pte0 = read_pa_u64(l0 + vpn0 * 8)
    if not (pte0 & 1):
        return None
    return ((pte0 >> 10) << 12) | pg_off

# Try to read log_buf
try:
    log_buf_pa = va_to_pa(0xffffffff80cbf368)
    if log_buf_pa:
        log_buf_ptr = read_pa_u64(log_buf_pa)
        gdb.write(f"\n[klog] log_buf (via walk) = 0x{log_buf_ptr:016x}\n")
        
        log_buf_len_pa = va_to_pa(0xffffffff80cbf370)
        if log_buf_len_pa:
            log_buf_len = read_pa_u32(log_buf_len_pa)
            gdb.write(f"[klog] log_buf_len = {log_buf_len}\n")
        
        if log_buf_ptr > 0xffffffc000000000:
            buf_pa = va_to_pa(log_buf_ptr)
            if buf_pa:
                dump_sz = min(log_buf_len if log_buf_len > 0 else 131072, 262144)
                gdb.execute(f"dump binary memory /tmp/klog_long_run.bin 0x{buf_pa:x} 0x{buf_pa + dump_sz:x}")
                gdb.write(f"[klog] Dumped {dump_sz} bytes from PA 0x{buf_pa:x}\n")
            else:
                gdb.write(f"[klog] Cannot translate log_buf VA 0x{log_buf_ptr:x}\n")
        elif log_buf_ptr == 0:
            gdb.write("[klog] log_buf still NULL\n")
    else:
        gdb.write("[klog] Cannot translate log_buf variable VA\n")
except Exception as e:
    gdb.write(f"[klog] Error: {e}\n")

# Also dump a raw block from where __log_buf should be
# Even if log_buf was reallocated, __log_buf might have contents from early boot
gdb.write("\n[raw] Dumping raw memory regions for analysis...\n")
gdb.execute("dump binary memory /tmp/klog_raw_0x80ed0000.bin 0x80ed0000 0x80f10000")
gdb.write("[raw] Dumped 0x80ed0000-0x80f10000 (128KB around __log_buf PA)\n")

# Check if saved_command_line is set
try:
    scl_pa = va_to_pa(0xffffffff80918468)
    if scl_pa:
        scl_ptr = read_pa_u64(scl_pa)
        gdb.write(f"\n[cmdline] saved_command_line = 0x{scl_ptr:016x}\n")
        if scl_ptr > 0xffffffc000000000:
            scl_buf_pa = va_to_pa(scl_ptr)
            if scl_buf_pa:
                data = b""
                for i in range(32):
                    w = read_pa_u64(scl_buf_pa + i*8)
                    data += w.to_bytes(8, "little")
                nul = data.find(b'\x00')
                s = data[:nul].decode("ascii", errors="replace") if nul >= 0 else data[:256].hex()
                gdb.write(f"[cmdline] = \"{s}\"\n")
except Exception as e:
    gdb.write(f"[cmdline] Error: {e}\n")

gdb.write("\n[done] Long run analysis complete\n")
end

quit
