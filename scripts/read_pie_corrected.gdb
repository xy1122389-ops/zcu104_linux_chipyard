set pagination off
set confirm off
set remotetimeout 60

target remote 172.19.128.1:12331
monitor halt

python
import gdb, struct

READER = 0x80038000

def cpu_ld(pa):
    gdb.execute(f"set $a0 = 0x{pa:x}")
    gdb.execute(f"set $pc = 0x{READER + 4:x}")
    gdb.execute(f"hbreak *0x{READER + 8:x}")
    gdb.execute("continue")
    val = int(gdb.parse_and_eval("$a1")) & 0xFFFFFFFFFFFFFFFF
    gdb.execute("delete breakpoints")
    return val

# The kernel is PIE-relocated by +0x200000 from vmlinux link addresses
# vmlinux GP = 0xffffffff80cbfa38, runtime GP = 0xffffffff80ebfa38
# offset = 0x200000
PIE_OFFSET = 0x200000

# vmlinux link VAs (from nm)
vmlinux_syms = {
    "log_buf":              0xffffffff80cbf368,
    "log_buf_len":          0xffffffff80cbf360,
    "__log_buf":            0xffffffff80cd0060,
    "saved_command_line":   0xffffffff80918468,
    "oops_count":           0xffffffff80cc0240,
    "jiffies_64":           0xffffffff80cbf3b0,
    "system_state":         0xffffffff80cc0038,
    "nr_threads":           0xffffffff80cc01ac,
    "init_task":            0xffffffff80c0d740,
    "boot_command_line":    0xffffffff80918460,
}

def runtime_va(link_va):
    return (link_va + PIE_OFFSET) & 0xFFFFFFFFFFFFFFFF

def va_to_pa(va):
    """For kernel image mapping: VA = PAGE_OFFSET + PA - load_PA
    PAGE_OFFSET = 0xffffffff80000000, load_PA = 0x80200000
    So PA = VA - 0xffffffff80000000 + 0x80200000
    But since runtime VA = link VA + PIE_OFFSET = link VA + 0x200000:
    PA = (link_va + 0x200000) - 0xffffffff80000000 + 0x80200000
       = link_va + 0x200000 + 0x80200000 (mod 2^64)
    Actually: PA = runtime_VA - PAGE_OFFSET + load_PA
            = (link_va + 0x200000) - 0xffffffff80000000 + 0x80200000
    """
    rva = runtime_va(va)
    return (rva - 0xffffffff80000000 + 0x80200000) & 0xFFFFFFFFFFFFFFFF

gdb.write("=" * 60 + "\n")
gdb.write("Kernel variables with PIE offset correction (+0x200000)\n")
gdb.write("=" * 60 + "\n\n")

for name, link_va in vmlinux_syms.items():
    rva = runtime_va(link_va)
    pa = va_to_pa(link_va)
    try:
        val = cpu_ld(pa)
        bval = val.to_bytes(8, "little")
        asc = "".join(chr(b) if 32 <= b < 127 else "." for b in bval)
        gdb.write(f"  {name:25s} linkVA=0x{link_va:x} runtimeVA=0x{rva:x} PA=0x{pa:x}\n")
        gdb.write(f"  {'':25s} val=0x{val:016x} [{asc}]\n")
    except Exception as e:
        gdb.write(f"  {name:25s} ERROR: {e}\n")
    gdb.write("\n")

# If log_buf has a valid pointer, follow it
log_buf_pa = va_to_pa(vmlinux_syms["log_buf"])
log_buf_val = cpu_ld(log_buf_pa)
gdb.write(f"\nlog_buf pointer = 0x{log_buf_val:x}\n")

if log_buf_val and log_buf_val > 0xffffffc000000000:
    # Convert log_buf VA to PA via linear mapping
    # Linear map: VA = 0xffffffd800000000 + PA
    if log_buf_val >= 0xffffffd800000000:
        buf_pa = (log_buf_val - 0xffffffd800000000) & 0xFFFFFFFFFFFFFFFF
    else:
        buf_pa = va_to_pa(log_buf_val - PIE_OFFSET)  # undo PIE offset to get link VA, then to PA
    
    gdb.write(f"Following log_buf: VA=0x{log_buf_val:x} -> PA=0x{buf_pa:x}\n")
    gdb.write("\nFirst 512 bytes of kernel log:\n")
    data = b""
    for off in range(0, 512, 8):
        try:
            w = cpu_ld(buf_pa + off)
            data += w.to_bytes(8, "little")
        except:
            break
    
    # Print hex + ascii
    for i in range(0, len(data), 16):
        c = data[i:i+16]
        h = " ".join(f"{b:02x}" for b in c)
        a = "".join(chr(b) if 32 <= b < 127 else "." for b in c)
        gdb.write(f"  {i:04x}: {h:48s} {a}\n")

# Read saved_command_line string (follow pointer)
saved_cl_pa = va_to_pa(vmlinux_syms["saved_command_line"])
saved_cl_val = cpu_ld(saved_cl_pa)
gdb.write(f"\nsaved_command_line pointer = 0x{saved_cl_val:x}\n")
if saved_cl_val and saved_cl_val > 0xffffffc000000000:
    if saved_cl_val >= 0xffffffd800000000:
        cl_pa = (saved_cl_val - 0xffffffd800000000) & 0xFFFFFFFFFFFFFFFF
    else:
        cl_pa = va_to_pa(saved_cl_val - PIE_OFFSET)
    
    gdb.write(f"Following: VA=0x{saved_cl_val:x} -> PA=0x{cl_pa:x}\n")
    data = b""
    for off in range(0, 256, 8):
        try:
            w = cpu_ld(cl_pa + off)
            data += w.to_bytes(8, "little")
        except:
            break
    # Find null terminator
    null_idx = data.find(b'\x00')
    if null_idx > 0:
        cmdline = data[:null_idx].decode('ascii', errors='replace')
        gdb.write(f"Command line: {cmdline}\n")
    else:
        gdb.write(f"Raw: {data[:64]}\n")

gdb.write("\n[done]\n")
end

quit
