set pagination off
set confirm off
set remotetimeout 60

file /root/chipyard/software/firemarshal/boards/default/firmware/opensbi/build/platform/generic/firmware/fw_payload.elf

python
import gdb, os, struct, time

host = os.environ.get("JLINK_HOST", "172.19.128.1")
port = int(os.environ.get("JLINK_PORT", "2331"))
gdb.execute(f"target remote {host}:{port}")
gdb.execute("monitor halt")
time.sleep(1)

def read_pa(pa, n=8):
    tmp = f"/tmp/_rd.bin"
    gdb.execute(f"dump binary memory {tmp} 0x{pa:x} 0x{pa+n:x}", to_string=True)
    with open(tmp, "rb") as f:
        data = f.read(n)
    return data

def u64(data, off=0):
    return struct.unpack_from("<Q", data, off)[0]

def u32(data, off=0):
    return struct.unpack_from("<I", data, off)[0]

# Known mapping: kernel VA 0xffffffff80XXXXXX → PA = VA - 0xffffffff80000000 + 0x80200000
KTEXT_OFF = 0x80200000 - 0xffffffff80000000  # = 0x0000000100200000 (mod 2^64)

def kva_to_pa(va):
    return (va + 0x0000000100200000) & 0xFFFFFFFFFFFFFFFF

# Read key variables
vars_to_read = {
    "log_buf": 0xffffffff80cbf368,
    "log_buf_len": 0xffffffff80cbf370,
    "__log_buf": 0xffffffff80cd0060,
    "saved_command_line": 0xffffffff80918468,
    "oops_count": 0xffffffff80cc0240,
    "jiffies_64": 0xffffffff80c00000,
}

for name, va in vars_to_read.items():
    pa = kva_to_pa(va)
    try:
        data = read_pa(pa, 8)
        val = u64(data)
        gdb.write(f"[var] {name:25s} VA=0x{va:x} PA=0x{pa:x} = 0x{val:016x}\n")
    except Exception as e:
        gdb.write(f"[var] {name:25s} ERROR: {e}\n")

# Direct mapping: VA 0xffffffd800000000 → PA 0x80000000
# So if log_buf points to direct map: PA = VA - 0xffffffd800000000 + 0x80000000
gdb.write("\n--- Reading log buffer ---\n")

log_buf_pa = kva_to_pa(0xffffffff80cbf368)
log_buf_data = read_pa(log_buf_pa, 8)
log_buf_ptr = u64(log_buf_data)
gdb.write(f"[klog] log_buf pointer = 0x{log_buf_ptr:016x}\n")

log_buf_len_pa = kva_to_pa(0xffffffff80cbf370)
log_buf_len_data = read_pa(log_buf_len_pa, 4)
log_buf_len = u32(log_buf_len_data)
gdb.write(f"[klog] log_buf_len = {log_buf_len} (0x{log_buf_len:x})\n")

# If log_buf is in direct mapping
if log_buf_ptr >= 0xffffffd800000000 and log_buf_ptr < 0xffffffd900000000:
    buf_pa = log_buf_ptr - 0xffffffd800000000 + 0x80000000
    gdb.write(f"[klog] log_buf is in direct map, PA = 0x{buf_pa:x}\n")
    dump_size = min(log_buf_len if log_buf_len > 0 else 131072, 262144)
    gdb.execute(f"dump binary memory /tmp/klog_direct.bin 0x{buf_pa:x} 0x{buf_pa + dump_size:x}")
    gdb.write(f"[klog] Dumped {dump_size} bytes\n")
elif log_buf_ptr >= 0xffffffff80000000:
    buf_pa = kva_to_pa(log_buf_ptr)
    gdb.write(f"[klog] log_buf is in kernel text/data, PA = 0x{buf_pa:x}\n")
    dump_size = min(log_buf_len if log_buf_len > 0 else 131072, 262144)
    gdb.execute(f"dump binary memory /tmp/klog_direct.bin 0x{buf_pa:x} 0x{buf_pa + dump_size:x}")
    gdb.write(f"[klog] Dumped {dump_size} bytes\n")
elif log_buf_ptr == 0:
    gdb.write("[klog] log_buf = NULL, dumping __log_buf area\n")
    logbuf_pa = kva_to_pa(0xffffffff80cd0060)
    gdb.execute(f"dump binary memory /tmp/klog_direct.bin 0x{logbuf_pa:x} 0x{logbuf_pa + 131072:x}")
    gdb.write(f"[klog] Dumped 128KB from __log_buf PA 0x{logbuf_pa:x}\n")
else:
    gdb.write(f"[klog] Unknown log_buf address space: 0x{log_buf_ptr:x}\n")
    # Try reading __log_buf anyway
    logbuf_pa = kva_to_pa(0xffffffff80cd0060)
    gdb.execute(f"dump binary memory /tmp/klog_direct.bin 0x{logbuf_pa:x} 0x{logbuf_pa + 131072:x}")
    gdb.write(f"[klog] Dumped 128KB from __log_buf PA\n")

# Also read saved_command_line
scl_pa = kva_to_pa(0xffffffff80918468)
scl_ptr_data = read_pa(scl_pa, 8)
scl_ptr = u64(scl_ptr_data)
gdb.write(f"\n[cmdline] saved_command_line ptr = 0x{scl_ptr:016x}\n")
if scl_ptr >= 0xffffffd800000000 and scl_ptr < 0xffffffd900000000:
    scl_buf_pa = scl_ptr - 0xffffffd800000000 + 0x80000000
    data = read_pa(scl_buf_pa, 256)
    nul = data.find(b'\x00')
    s = data[:nul].decode("ascii", errors="replace") if nul >= 0 else data[:256].hex()
    gdb.write(f"[cmdline] = \"{s}\"\n")
elif scl_ptr >= 0xffffffff80000000:
    scl_buf_pa = kva_to_pa(scl_ptr)
    data = read_pa(scl_buf_pa, 256)
    nul = data.find(b'\x00')
    s = data[:nul].decode("ascii", errors="replace") if nul >= 0 else data[:256].hex()
    gdb.write(f"[cmdline] = \"{s}\"\n")
elif scl_ptr == 0:
    gdb.write("[cmdline] NULL (kernel hasn't parsed yet?)\n")

# Dump a wider raw region for manual inspection
gdb.write("\n--- Dumping wider raw memory for analysis ---\n")
# Entire BSS/data area from 0x80c00000+0x200000 = 0x80e00000 onwards
gdb.execute("dump binary memory /tmp/kernel_data_region.bin 0x80e00000 0x81000000")
gdb.write("[raw] Dumped PA 0x80e00000 - 0x81000000 (2MB kernel data/BSS region)\n")

gdb.write("\n[done]\n")

end

quit
