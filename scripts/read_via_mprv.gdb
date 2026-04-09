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

pc = int(gdb.parse_and_eval("$pc")) & 0xFFFFFFFFFFFFFFFF
gdb.write(f"[state] PC=0x{pc:x}\n")

# Save registers
save_a0 = int(gdb.parse_and_eval("$a0")) & 0xFFFFFFFFFFFFFFFF
save_a1 = int(gdb.parse_and_eval("$a1")) & 0xFFFFFFFFFFFFFFFF
save_pc = pc

# Read current mstatus
mstatus_out = gdb.execute("monitor ReadCSR 0x300", to_string=True)
m = re.search(r'(?:0x)?([0-9A-Fa-f]{8,16})', mstatus_out)
mstatus = int(m.group(1), 16) if m else 0
gdb.write(f"[orig] mstatus=0x{mstatus:016x}\n")

# Strategy: write a tiny reader routine to the OpenSBI scratch area
# Use PA 0x80038000 (within OpenSBI but past the active handlers)
# This is within the payload we loaded, so SBA writes will work
# Then set MPRV=1, MPP=S, and execute it

READER = 0x80038000

# Reader routine (3 instructions):
# 0: fence.i          (0x0000100f) — ensure I-cache sees new code
# 4: ld a1, 0(a0)     (0x00053583) — load 8 bytes from VA in a0 (uses S-mode via MPRV)
# 8: ebreak           (0x00100073) — halt and return to debug
instrs = [0x0000100f, 0x00053583, 0x00100073]
for i, insn in enumerate(instrs):
    gdb.execute(f"set *(unsigned int*)0x{READER + i*4:x} = 0x{insn:08x}")

# Now we need to make the CPU fetch FROM this address.
# Set MPRV=1 and MPP=S (01) in mstatus
# ld with MPRV=1 and MPP=S will use S-mode address translation
# BUT: with MPRV=1 and MPP=S, instruction fetch STILL uses M-mode (no translation)
# Only loads/stores are affected by MPRV. Instruction fetch is always current mode.
# So the reader code at PA 0x80038000 can be fetched in M-mode directly.

new_mstatus = mstatus | (1 << 17)  # MPRV = 1
new_mstatus = (new_mstatus & ~(3 << 11)) | (1 << 11)  # MPP = 01 (S-mode)
gdb.write(f"[mstatus] Setting MPRV=1 MPP=S: 0x{new_mstatus:016x}\n")
gdb.execute(f"monitor WriteCSR 0x300 0x{new_mstatus:x}")

def read_kernel_u64(va):
    """Read 8 bytes from kernel VA using CPU ld with MPRV=1 MPP=S"""
    gdb.execute(f"set $a0 = 0x{va:x}")
    gdb.execute(f"set $pc = 0x{READER:x}")
    gdb.execute(f"hbreak *0x{READER + 8:x}")
    gdb.execute("continue")
    val = int(gdb.parse_and_eval("$a1")) & 0xFFFFFFFFFFFFFFFF
    gdb.execute("delete breakpoints")
    # MPRV may be cleared by ebreak entering debug mode, restore it
    gdb.execute(f"monitor WriteCSR 0x300 0x{new_mstatus:x}")
    return val

# First test: read a known value 
gdb.write("\n=== CPU ld tests (MPRV=1 MPP=S, through S-mode MMU) ===\n")

# Test 1: read log_buf
try:
    val = read_kernel_u64(0xffffffff80cbf368)
    gdb.write(f"[cpu] log_buf = 0x{val:016x}\n")
except Exception as e:
    gdb.write(f"[cpu] log_buf ERROR: {e}\n")

# Test 2: read log_buf_len (as u64, we'll mask to u32)
try:
    val = read_kernel_u64(0xffffffff80cbf360)
    gdb.write(f"[cpu] log_buf_len = 0x{val:016x} ({val & 0xFFFFFFFF})\n")
except Exception as e:
    gdb.write(f"[cpu] log_buf_len ERROR: {e}\n")

# Test 3: saved_command_line
try:
    val = read_kernel_u64(0xffffffff80918468)
    gdb.write(f"[cpu] saved_command_line = 0x{val:016x}\n")
except Exception as e:
    gdb.write(f"[cpu] saved_command_line ERROR: {e}\n")

# Test 4: oops_count  
try:
    val = read_kernel_u64(0xffffffff80cc0240)
    gdb.write(f"[cpu] oops_count = 0x{val:016x}\n")
except Exception as e:
    gdb.write(f"[cpu] oops_count ERROR: {e}\n")

# Test 5: read __log_buf (first 8 bytes)
try:
    val = read_kernel_u64(0xffffffff80cd0060)
    gdb.write(f"[cpu] __log_buf[0:8] = 0x{val:016x}\n")
except Exception as e:
    gdb.write(f"[cpu] __log_buf[0:8] ERROR: {e}\n")

# If log_buf is valid, try to read from it
log_buf_val = None
try:
    log_buf_val = read_kernel_u64(0xffffffff80cbf368)
except:
    pass

if log_buf_val and log_buf_val > 0xffffffc000000000:
    gdb.write(f"\n[klog] Reading first 512 bytes from log_buf=0x{log_buf_val:x}...\n")
    data = b""
    for off in range(0, 512, 8):
        try:
            w = read_kernel_u64(log_buf_val + off)
            data += w.to_bytes(8, "little")
        except:
            gdb.write(f"[klog] Read failed at offset {off}\n")
            break
    # Print as text (skip printk record headers, look for ASCII)
    text = ""
    for b in data:
        if 32 <= b < 127 or b == 10:
            text += chr(b)
        elif b == 0:
            text += ""
        else:
            text += "."
    gdb.write(f"[klog first 512B]:\n{text[:1000]}\n")

# If saved_command_line is valid, read it
scl_val = None
try:
    scl_val = read_kernel_u64(0xffffffff80918468)
except:
    pass

if scl_val and scl_val > 0xffffffc000000000:
    gdb.write(f"\n[cmdline] Reading string at 0x{scl_val:x}...\n")
    data = b""
    for off in range(0, 256, 8):
        try:
            w = read_kernel_u64(scl_val + off)
            data += w.to_bytes(8, "little")
        except:
            break
    nul = data.find(b'\x00')
    s = data[:nul].decode("ascii", errors="replace") if nul >= 0 else data[:256].hex()
    gdb.write(f"[cmdline] = \"{s}\"\n")

# Restore
gdb.write("\n[restore] Restoring registers...\n")
gdb.execute(f"set $a0 = 0x{save_a0:x}")
gdb.execute(f"set $a1 = 0x{save_a1:x}")
gdb.execute(f"set $pc = 0x{save_pc:x}")
gdb.execute(f"monitor WriteCSR 0x300 0x{mstatus:x}")
gdb.write("[restore] Done\n")

end

quit
